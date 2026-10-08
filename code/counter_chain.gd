extends Node2D
# The counter. player.gd's _try_counter spawns this when Q catches an enemy mid-lunge:
#   1. time stops (Engine.time_scale 0) and the world dims; the player stays lit
#   2. the player teleports through the lunging enemy to its far side and cuts it in half
#      (so the counter always teleports, even with a single enemy)
#   3. the player teleports next to each other enemy on screen, nearest first, and cuts it. "On screen"
#      grows as they go: wherever they land, enemies that come into view there join the chain (Morgan's call)
#   4. time starts again: every cut enemy falls apart at once, big shake
# Runs on real time. The cut halves hang in the air until time starts again.
# Enemies opt in with cut_in_half(dir, a, b): they split along the slash drawn from a to b. A boss can
# instead have countered(dir): it's only ever the first cut (the chain moves on to cuttable enemies). The COUNTER banner is drawn by the combo HUD ("combo_hud" group).

const EnemyKit := preload("res://code/design/enemy_kit.gd")

const FIRST_PAUSE := 0.18       # time stops for this long before the first cut
const NEXT_GAP := 0.14          # after a cut, before teleporting to the next enemy
const ARRIVE_PAUSE := 0.08      # after arriving, before cutting
const END_PAUSE := 0.3          # after the last cut, before time starts again
const SIDE_GAP := 22.0          # how far beside an enemy the player appears
# enemies in this group are chained at speed: one cut every frame, no pauses (the dam's flood of a hundred
# Mangos, Morgan's call). The first few cuts keep the normal pace, so the counter still reads.
const FAST_GROUP := "dam_flood"
const FAST_AFTER := 3
const FAST_CLANG_EVERY := 3     # at speed, a clang every few cuts (a hundred at once is just noise)
# the flood's rightmost few are kept for last and cut left to right, so the chain always ends on the right
# and you carry on that way (Morgan's call)
const FAST_LAST := 3
# enemies in this group are the next step even before they've been on screen, if they're within PATH_REACH
# of where you are: level 1's column staircase (MangoLedge1-4), so one counter always climbs every column
# (Morgan's call)
const PATH_GROUP := "counter_path"
const PATH_REACH := 300.0
const DIM := Color(0.208, 0.153, 0.357, 0.45)     # BOOM's indigo over the frozen world
const SLASH := Color(0.925, 0.875, 0.859)         # off-white
const SLASH_EDGE := Color(0.8, 0.678, 0.294)      # mustard
const GHOST := Color(0.447, 0.722, 0.808, 0.8)    # teal afterimage
const CUT_SOUND := preload("res://sounds/sword/sword_clash_02.wav")   # a clang on every cut
const CUT_SOUND_DB := -3.0
const CUT_SOUND_SKIP := 0.06    # skip the quiet lead-in, so the clang lands on the cut

var player: CharacterBody2D
var first: Node2D

var _psprite: AnimatedSprite2D
var _dim := Node2D.new()
var _views := []             # the screen when the counter started, plus the view from each landing:
                             # only enemies in one of them get chained
var _done := {}
var _cuts := 0
var _running := false
var _start := 0.0
var _resumed := -1.0
var _old_z := 0
var _slashes := []           # [from, to, start time]
var _streaks := []           # [from, to, start time]
var _ghosts := []            # [Sprite2D, start time]


func _ready():
	top_level = true
	global_position = Vector2.ZERO
	z_index = 40
	_dim.z_as_relative = false
	_dim.z_index = 30
	_dim.draw.connect(_draw_dim)
	add_child(_dim)
	_psprite = player.get_node("AnimatedSprite2D")
	_views = [_view_rect().grow(16.0)]
	_old_z = player.z_index
	player.z_index = 35          # above the dim
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.shake_time_left = 0.0 # a shake left running would jitter the whole freeze
	_start = _now()
	_running = true
	Engine.time_scale = 0.0
	# nothing can hurt you while it runs: you're teleported right up against each enemy, and their touch checks
	# still run with time stopped (it used to flash you red with the hurt sound, Morgan's bug report 2026-10-08)
	EnemyKit.protect_player(1.0)
	get_tree().call_group("combo_hud", "counter_start")
	_run()


func _exit_tree():
	if _running:                 # removed early (scene reload): never leave the game frozen
		Engine.time_scale = 1.0
		if is_instance_valid(player):
			player.set_physics_process(true)
			player.z_index = _old_z


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, true, false, true).timeout


func _run():
	await _wait(FIRST_PAUSE)
	var target := first
	if is_instance_valid(target):
		_teleport_to(target, true)         # through the lunging enemy: cut it from behind
		await _wait(ARRIVE_PAUSE)
	while target != null:
		_cut(target)
		if _fast(target):
			await get_tree().process_frame
		else:
			await _wait(NEXT_GAP)
		target = _next_target()
		if target != null:
			_teleport_to(target)
			if not _fast(target):
				await _wait(ARRIVE_PAUSE)
	await _wait(END_PAUSE)
	_resume()
	await _wait(0.4)
	queue_free()


func _process(_delta):
	if _running:
		Engine.time_scale = 0.0  # hit-freezes elsewhere reset it: keep the world stopped
		EnemyKit.protect_player(0.5)
	var now := _now()
	for g in _ghosts:
		var ghost: Sprite2D = g[0]
		ghost.modulate.a = GHOST.a * (1.0 - clampf((now - g[1]) / 0.35, 0.0, 1.0))
	for g in _ghosts.filter(func(g): return now - g[1] >= 0.35):
		g[0].queue_free()
	_ghosts = _ghosts.filter(func(g): return now - g[1] < 0.35)
	queue_redraw()
	_dim.queue_redraw()


func _cut(e: Node2D):
	if not is_instance_valid(e):
		return
	var dir := signf(e.global_position.x - player.global_position.x)
	if dir == 0.0:
		dir = float(player.facing)
	player.facing = int(dir)
	_psprite.flip_h = dir < 0.0
	_pose("ATTACK_LIGHT_2" if _cuts % 2 == 0 else "ATTACK_LIGHT_1", 2)
	_done[e.get_instance_id()] = true
	var mid := e.global_position + Vector2(0, -11)
	var tilt := Vector2(dir * 14.0, -9.0 if _cuts % 2 == 0 else 9.0)    # the diagonal alternates
	_slashes.append([mid - tilt, mid + tilt, _now()])
	if e.has_method("cut_in_half"):
		e.cut_in_half(int(dir), mid - tilt, mid + tilt)    # it splits along this same slash
	elif e.has_method("countered"):
		e.countered(int(dir))        # a boss: it takes the counter its own way (damage, a crash, a stun)
	if not _fast(e) or _cuts % FAST_CLANG_EVERY == 0:
		_clang()
	_cuts += 1
	get_tree().call_group("combo_hud", "counter_cut", _cuts)


# this enemy is chained at speed (it's part of the dam's flood, and the chain is under way)
func _fast(e: Node2D) -> bool:
	return _cuts >= FAST_AFTER and is_instance_valid(e) and e.is_in_group(FAST_GROUP)


# each clang gets its own player in the level, so its ring isn't cut off when the counter ends
func _clang():
	var s := AudioStreamPlayer.new()
	s.stream = CUT_SOUND
	s.volume_db = CUT_SOUND_DB
	get_parent().add_child(s)
	s.finished.connect(s.queue_free)
	s.play(CUT_SOUND_SKIP)


# the nearest enemy that can be cut, has been on screen during the counter, and isn't cut yet
func _next_target() -> Node2D:
	var found: Array = []
	var flood: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not e.has_method("cut_in_half") or _done.has(e.get_instance_id()):
			continue
		var hp = e.get("hp")
		if hp != null and hp <= 0:
			continue
		if not _in_views(e.global_position) and not (e.is_in_group(PATH_GROUP) \
				and player.global_position.distance_to(e.global_position) <= PATH_REACH):
			continue
		found.append(e)
		if e.is_in_group(FAST_GROUP):
			flood.append(e)
	if found.is_empty():
		return null
	# the dam's flood: its rightmost few wait till last, then go left to right, ending furthest right
	# (worked out again every cut, since each landing can bring more into view)
	if not flood.is_empty():
		flood.sort_custom(func(a: Node2D, b: Node2D): return a.global_position.x < b.global_position.x)
		var last := flood.slice(maxi(flood.size() - FAST_LAST, 0))
		if found.size() <= last.size():
			return last[0]
		found = found.filter(func(e): return not last.has(e))
	var best: Node2D = null
	var best_d := INF
	for e: Node2D in found:
		var d := player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


# a plain loop, not a lambda: a big chain (the dam's flood) asks this for every enemy on every cut
func _in_views(p: Vector2) -> bool:
	for v: Rect2 in _views:
		if v.has_point(p):
			return true
	return false


# through = arrive on the enemy's far side (the first cut), else on the side we're coming from
func _teleport_to(e: Node2D, through := false):
	var from := player.global_position
	var at := e.global_position
	var side := signf(from.x - at.x)            # arrive on the side we're coming from...
	if side == 0.0:
		side = -float(player.facing)
	if through:
		side = -side
	var gap := maxf(SIDE_GAP, _body_reach(e) + 10.0)   # big enemies: land clear of their body
	var spot := at + Vector2(side * gap, 0)
	if _blocked(at, spot, e):                   # ...unless there's a wall there
		spot = at - Vector2(side * gap, 0)
	_ghost()
	_streaks.append([from + Vector2(0, -20), spot + Vector2(0, -20), _now()])
	player.global_position = spot
	_views.append(_view_around_player())    # whatever's in view from here can be chained next
	if at.x != spot.x:
		player.facing = int(signf(at.x - spot.x))
	_psprite.flip_h = player.facing < 0
	_pose("ATTACK_LIGHT_1", 0)


# how far an enemy's body reaches sideways from its position (the further side): from its hurtbox
# (_hurtbox() or a HURTBOX const), else its collision shape, else a body_half_width property, else 12
func _body_reach(e: Node2D) -> float:
	var r := Rect2()
	if e.has_method("_hurtbox"):
		var g: Rect2 = e._hurtbox()
		r = Rect2(g.position - e.global_position, g.size)
	elif e.get_script() != null:
		var consts: Dictionary = e.get_script().get_script_constant_map()
		if consts.has("HURTBOX") and consts["HURTBOX"] is Rect2:
			r = consts["HURTBOX"]
	if r.size.x > 0.0:
		return maxf(absf(r.position.x), absf(r.end.x))
	for c in e.get_children():
		if c is CollisionShape2D and c.shape != null:
			var s: Shape2D = c.shape
			if s is RectangleShape2D:
				return (s as RectangleShape2D).size.x / 2.0
			if s is CapsuleShape2D:
				return (s as CapsuleShape2D).radius
			if s is CircleShape2D:
				return (s as CircleShape2D).radius
	var hw = e.get("body_half_width")
	if hw != null:
		return float(hw)
	return 12.0


func _blocked(a: Vector2, b: Vector2, e: Node2D) -> bool:
	var exclude: Array[RID] = [player.get_rid()]
	if e is CollisionObject2D:
		exclude.append(e.get_rid())
	var q := PhysicsRayQueryParameters2D.create(a + Vector2(0, -10), b + Vector2(0, -10), 1, exclude)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# a frozen pose: time is stopped, so the frame stays put
func _pose(anim: String, frame: int):
	_psprite.play(anim)
	_psprite.frame = mini(frame, _psprite.sprite_frames.get_frame_count(anim) - 1)


# a teal copy of the player's current frame left behind, fading out
func _ghost():
	var tex := _psprite.sprite_frames.get_frame_texture(_psprite.animation, _psprite.frame)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.texture = tex
	g.centered = _psprite.centered
	g.offset = _psprite.offset
	g.flip_h = _psprite.flip_h
	g.modulate = GHOST
	g.z_as_relative = false
	g.z_index = 34
	add_child(g)
	g.global_position = _psprite.global_position
	_ghosts.append([g, _now()])


func _resume():
	_running = false
	_resumed = _now()
	Engine.time_scale = 1.0
	player.z_index = _old_z
	player.set_physics_process(true)
	var states: Dictionary = player.get_script().State
	player._set_state(states["IDLE"] if player.is_on_floor() else states["JUMP_FALL"])
	player._shake(12.0, 0.3)
	EnemyKit.protect_player(0.6)
	get_tree().call_group("combo_hud", "counter_end")


# the screen as it will be around the player where they are now (the camera follows them there)
func _view_around_player() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var center := player.global_position + Vector2(0, -72)
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		size /= cam.zoom
		center = cam.global_position
	return Rect2(center - size / 2.0, size).grow(16.0)


func _view_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(player.global_position - size / 2.0, size)
	size /= cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size)


func _draw():
	var now := _now()
	var fade := 1.0 if _resumed < 0.0 else 1.0 - clampf((now - _resumed) / 0.25, 0.0, 1.0)
	for s in _slashes:
		if fade <= 0.0:
			break
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var tip := a.lerp(b, clampf((now - s[2]) / 0.06, 0.0, 1.0))    # the cut draws in from one end
		draw_line(a, tip, SLASH_EDGE, 4.0 * fade)
		draw_line(a, tip, SLASH, 2.0 * fade)
		if now - s[2] < 0.12:           # a small star where the blade went through
			var c := a.lerp(b, 0.5).round()
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				for k in range(2, 6):
					draw_rect(Rect2(c + d * k, Vector2(1, 1)), SLASH)
	for s in _streaks:
		var k := clampf((now - s[2]) / 0.2, 0.0, 1.0)
		if k < 1.0:
			draw_line(s[0], s[1], SLASH, 2.0 * (1.0 - k))


func _draw_dim():
	var now := _now()
	var a := clampf((now - _start) / 0.08, 0.0, 1.0)
	if _resumed >= 0.0:
		a = 1.0 - clampf((now - _resumed) / 0.15, 0.0, 1.0)
	if a > 0.0:
		_dim.draw_rect(_view_rect().grow(8.0), Color(DIM, DIM.a * a))
