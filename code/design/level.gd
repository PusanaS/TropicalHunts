extends Node2D
# A level (scene/design/level_1.tscn and on): the run's timer, checkpoints, falling into lava or off the
# world, the boss fight, the clear screen with your time and rank, and moving on to the next level.
# Its HUD is code/design/level_hud.gd. What the scene gives it (by name, next to it):
#   Checkpoints   Marker2D children: walking past one makes it where you come back to (a flag shows it)
#   Hints         Marker2D children with metadata "text": walking past one shows that tip once
#   KillZones     Marker2D children with metadata "size" (top left at the marker): falling into one (the sea
#                 under Level 2's boardwalk) sends you back to the last checkpoint
#   BossTrigger   Marker2D: walking past it starts the boss fight (and becomes the checkpoint)
#   BossGate      a tutorial_gate.gd with start_open on: it shuts behind you when the fight starts
#   boss_path     the boss (hp, max_hp, boss_name, and start_fight() if it has one)
# Lava: touching the lava over a StaticBody2D named "LavaBed..." sends you back to the last checkpoint, and
# so does falling below kill_y. The new bosses call boss_defeated() (group "level"); the Big Pineapple
# doesn't, so it also counts as beaten once it's out of health and its finisher is over (DEAD).

const Hud := preload("res://code/design/level_hud.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const LAVA_DEPTH := 24.0          # the living background fills this much above a LavaBed's top with lava
const CLEAR_DELAY := 2.0          # after the boss is beaten, LEVEL CLEAR comes up this much later

@export var level_number := 1
@export var level_name := "JUNGLE RUN"
@export_file("*.tscn") var next_scene := ""       # "" = the last level: THE END
@export var kill_y := 420.0                       # falling below this (world y) sends you back
@export var rank_times := Vector3(150, 210, 300)  # seconds: under x = rank S, under y = A, under z = B, else C
@export var boss_path: NodePath
@export var boss_title := ""                      # the name on its health bar ("" = its own boss_name)
@export var final_title := "THE END!"             # the clear screen's title when there's no next level

var player: CharacterBody2D
var hud: CanvasLayer
var _checkpoints: Array = []      # Marker2D, left to right
var _cp_index := -1
var _respawn_at := Vector2.ZERO
var _hints: Array = []            # Marker2D not shown yet
var _lava: Array = []             # Rect2 of the lava over each LavaBed, and of each kill zone (world)
var _boss: Node = null
var _trigger: Node2D = null
var _gate: Node = null
var _time := 0.0
var _timing := false
var _last_real := 0.0
var _fight := false
var _beaten_at := -1.0
var _cleared := false
var _enter_down := false
var _flags := Node2D.new()


func _ready():
	global_position = Vector2.ZERO       # the checkpoint flags are drawn in world space
	add_to_group("level")
	hud = Hud.new()
	add_child(hud)
	_flags.z_index = -1
	_flags.draw.connect(_draw_flags)
	add_child(_flags)
	var root := get_parent()
	var cps := root.get_node_or_null("Checkpoints")
	if cps:
		_checkpoints = cps.get_children().filter(func(n): return n is Marker2D)
		_checkpoints.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var hints := root.get_node_or_null("Hints")
	if hints:
		_hints = hints.get_children().filter(func(n): return n is Marker2D)
	_trigger = root.get_node_or_null("BossTrigger")
	_gate = root.get_node_or_null("BossGate")
	if not boss_path.is_empty():
		_boss = get_node_or_null(boss_path)
	var zones := root.get_node_or_null("KillZones")
	if zones:
		for z in zones.get_children():
			if z is Marker2D:
				_lava.append(Rect2(z.global_position, z.get_meta("size", Vector2(100, 100))))
	for body in root.find_children("LavaBed*", "StaticBody2D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape2D and cs.shape is RectangleShape2D:
				var size: Vector2 = cs.shape.size
				var r := Rect2(cs.global_position - size / 2.0, size)
				_lava.append(Rect2(r.position.x, r.position.y - LAVA_DEPTH, r.size.x, LAVA_DEPTH + r.size.y))
	_last_real = _now()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_respawn_at = player.global_position
		hud.intro(level_number, level_name)
		return

	# the timer runs on real time (hit-freezes and the flash's freeze don't stop it), from your first move
	var now := _now()
	if not _timing and not _cleared and player.velocity.length() > 1.0:
		_timing = true
	if _timing:
		_time += minf(now - _last_real, 0.1)
	_last_real = now
	hud.timer_text = _clock(_time)

	var at := player.global_position
	if Engine.time_scale == 0.0:
		return                            # time is stopped (the counter, the flash): nothing happens till it restarts
	while _cp_index + 1 < _checkpoints.size() and at.x >= _checkpoints[_cp_index + 1].global_position.x:
		_cp_index += 1
		_respawn_at = _checkpoints[_cp_index].global_position
		hud.checkpoint()
	for h in _hints.duplicate():
		if at.x >= h.global_position.x:
			_hints.erase(h)
			hud.toast(String(h.get_meta("text", "")))

	if at.y > kill_y:
		respawn_player()
	var bg := get_tree().get_first_node_in_group("living_background")
	if bg and bg.has_method("lava_at") and bg.lava_at(at + Vector2(0, -2)):
		respawn_player()                  # whatever the background draws as lava (PitBeds in the volcano too)
	else:
		for r in _lava:
			if r.has_point(at + Vector2(0, -2)):
				respawn_player()
				break

	if not _fight and _trigger and at.x >= _trigger.global_position.x:
		_start_fight()
	if _fight and _beaten_at < 0.0 and _boss_done():
		boss_defeated(_boss)
	if _beaten_at >= 0.0 and not _cleared and now - _beaten_at >= CLEAR_DELAY:
		_cleared = true
		_timing = false
		hud.final_title = final_title
		hud.clear(_clock(_time), _rank(), next_scene == "")


func _process(_delta):
	_flags.queue_redraw()
	if not _cleared or not hud.clear_ready() or next_scene == "":
		return
	var down := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	if down and not _enter_down:
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(next_scene)
	_enter_down = down


func _start_fight():
	_fight = true
	_respawn_at = _trigger.global_position
	if _gate and _gate.has_method("close"):
		_gate.close()
	if _boss:
		var n = _boss.get("boss_name")
		hud.boss_intro(_boss, boss_title if boss_title != "" else (String(n) if n != null else "BOSS"))
		if _boss.has_method("start_fight"):
			_boss.start_fight()


# the new bosses call this when they're beaten (group "level")
func boss_defeated(_who = null):
	if _beaten_at < 0.0:
		_beaten_at = _now()


# the Big Pineapple: out of health and done with (its finisher over, or dead)
func _boss_done() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	var hp = _boss.get("hp")
	if hp == null or hp > 0:
		return false
	var consts: Dictionary = _boss.get_script().get_script_constant_map()
	if not consts.has("State"):
		return false               # it says so itself (boss_defeated)
	var names: Array = consts["State"].keys()
	return names[_boss.state] == "DEAD"   # (FINISHED is the finisher still playing: it can still fail)


# fell in the lava or off the world: back to the last checkpoint (the clock keeps running)
func respawn_player():
	if _cleared or player == null:
		return
	hud.oops()
	player.velocity = Vector2.ZERO
	player.global_position = _respawn_at
	player.speed_level = 0
	player.hold_time = 0.0
	var states: Dictionary = player.get_script().State
	player._set_state(states["IDLE"])
	EnemyKit.protect_player(1.0)


func _clock(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]


func _rank() -> String:
	if _time < rank_times.x:
		return "S"
	if _time < rank_times.y:
		return "A"
	if _time < rank_times.z:
		return "B"
	return "C"


# a flag at each checkpoint: orange until you've reached it, then green
func _draw_flags():
	var t := _now()
	for i in _checkpoints.size():
		var base: Vector2 = _checkpoints[i].global_position.round()
		var done := i <= _cp_index
		var top := base.y - 30.0
		_flags.draw_rect(Rect2(base.x - 1, top, 3, 30), Pixel.INK)
		_flags.draw_rect(Rect2(base.x, top, 1, 30), Pixel.OFF_WHITE)
		_flags.draw_rect(Rect2(base.x - 2, top - 3, 5, 4), Pixel.INK)
		_flags.draw_rect(Rect2(base.x - 1, top - 2, 3, 2), Pixel.MUSTARD)
		var cols := [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE] if done else [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]
		for c in 10:
			var h := 7 - int(c * 0.65)
			var y := top + 1.0 + roundf(sin(t * 6.0 - c * 0.7) * c / 9.0 * 1.5) + floorf((7 - h) / 2.0)
			var x := base.x + 2.0 + c
			_flags.draw_rect(Rect2(x, y - 1, 1 if c < 9 else 2, h + 2), Pixel.INK)
			_flags.draw_rect(Rect2(x, y, 1, h), cols[0])
			_flags.draw_rect(Rect2(x, y, 1, 1), cols[2])
			_flags.draw_rect(Rect2(x, y + h - 1, 1, 1), cols[1])
