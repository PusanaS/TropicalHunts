extends Node2D
# "Breaking the sound barrier": the moment the player reaches full speed (the gallop, player.gd's top
# speed level), a sonic boom goes off behind them: two shock rings, speed lines, a burst of dust and
# a screen shake, with the gallop sound. While the gallop lasts, thin speed lines trail behind. It
# fires again only after slowing down.
# Drop this node into any level (like LiveReload). It only watches the player; player.gd is untouched.
# PLACEHOLDER effects.

@export var trail := true                 # speed lines behind the player while galloping

const RING_TIME := 0.3
const RING_SIZE := Vector2(30, 48)        # how big a shock ring gets (half-width, half-height)
const RING_DRIFT := 24.0                  # rings drift back this far as they grow
const SECOND_RING_DELAY := 0.07
const BODY_Y := -20.0                     # the player's middle, from their feet
const BOOM_LINES := 7
const TRAIL_EVERY := 0.05
const SHAKE := Vector2(6, 0.25)           # strength, seconds
const WHITE := Color(1.0, 0.97, 0.9)
const DUST := Color(0.93, 0.87, 0.86)
const GALLOP_SOUND := preload("res://sounds/GALLOP_SOUND_freesound_community-electric-impact-37128.mp3")
const SOUND_DB := 0.0                     # gallop sound volume
const SOUND_SKIP := 0.042                 # the file starts with 44ms of near-silence; skip it so the hit lands with the boom

var player: CharacterBody2D = null
var _sound := AudioStreamPlayer.new()
var _top_level := 4                       # full speed = the last entry in player.gd's SPEEDS
var _last_level := 0
var _trail_timer := 0.0
var _rings: Array = []                    # each: {"pos", "dir", "age", "delay"}


func _ready():
	z_index = 5
	_sound.stream = GALLOP_SOUND
	_sound.volume_db = SOUND_DB
	add_child(_sound)


func _process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		var speeds: Array = player.get_script().SPEEDS
		_top_level = speeds.size() - 1
	var level: int = player.speed_level
	if level >= _top_level and _last_level < _top_level and player.is_on_floor():
		_boom()
	_last_level = level
	if trail and level >= _top_level:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = TRAIL_EVERY
			_speed_line(randf_range(-36.0, -4.0), randf_range(18.0, 34.0), 1.0, 0.12)
	_age_rings(delta)


func _boom():
	var dir := float(player.facing)
	var center := player.global_position + Vector2(-dir * 10.0, BODY_Y)
	_rings.append({"pos": center, "dir": dir, "age": 0.0, "delay": 0.0})
	_rings.append({"pos": center + Vector2(-dir * 12.0, 0), "dir": dir, "age": 0.0, "delay": SECOND_RING_DELAY})
	for i in BOOM_LINES:
		_speed_line(randf_range(-40.0, 0.0), randf_range(40.0, 80.0), 2.0, 0.25)
	_dust(dir)
	_sound.play(SOUND_SKIP)               # restarts it if a gallop starts again before it ends
	if player.has_method("_shake"):
		player._shake(SHAKE.x, SHAKE.y)


func _age_rings(delta: float):
	var alive: Array = []
	for r: Dictionary in _rings:
		r["age"] = float(r["age"]) + delta
		if float(r["age"]) < float(r["delay"]) + RING_TIME:
			alive.append(r)
	_rings = alive
	queue_redraw()


# each shock ring is the back half of an ellipse, growing and drifting back as it fades
func _draw():
	for r: Dictionary in _rings:
		var age: float = r["age"]
		var delay: float = r["delay"]
		if age < delay:
			continue
		var t := clampf((age - delay) / RING_TIME, 0.0, 1.0)
		var grow := 1.0 - (1.0 - t) * (1.0 - t)          # fast, then slowing
		var dir: float = r["dir"]
		var pos: Vector2 = r["pos"]
		var c := to_local(pos) + Vector2(-dir * RING_DRIFT * grow, 0)
		var size := RING_SIZE * (0.15 + 0.85 * grow)
		var pts := PackedVector2Array()
		for i in 17:
			var a := lerpf(PI * 0.5, PI * 1.5, i / 16.0)
			pts.append(c + Vector2(cos(a) * size.x * dir, sin(a) * size.y))
		var color := Color(WHITE, 1.0 - t)
		draw_polyline(pts, color, lerpf(4.0, 1.0, t))
		if delay == 0.0 and t < 0.25:
			draw_circle(c, 10.0 * (1.0 - t * 4.0), Color(WHITE, 0.9))   # the flash at the break


# a horizontal streak behind the player that stays put in the world and fades
func _speed_line(y: float, length: float, width: float, fade: float):
	var back := -float(player.facing)
	var start := player.global_position + Vector2(back * 8.0, y)
	var line := Line2D.new()
	line.points = PackedVector2Array([to_local(start), to_local(start + Vector2(back * length, 0))])
	line.width = width
	line.default_color = WHITE
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, fade)
	tw.tween_callback(line.queue_free)


func _dust(dir: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector2(-dir, -0.6)
	p.spread = 30.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2(0, 400)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 2.0
	p.color = DUST
	p.position = to_local(player.global_position + Vector2(-dir * 6.0, -2.0))
	p.finished.connect(p.queue_free)
	add_child(p)
	p.emitting = true
