extends Node2D
# The Thunderclap flash, seen (the professor's idea: show the kills). player.gd's _flash_strike works out
# where the flash ends and who's in the way, then this takes over:
#   1. time stops and the player dashes through them on real time, leaving yellow afterimages. Passing
#      each enemy, they swing, the slash appears across it and it flashes white, and the dash catches
#      on it for a split second: cut, cut, cut.
#   2. they land in a follow-through pose and hold it for a beat.
#   3. time starts again and the enemies drop in order, nearest first, a moment apart: those that can be
#      cut (the fruit minion) split in two along their slash, the rest take the flash's hit. Sparks and a
#      jolt each, a big shake on the last. The player keeps galloping.
# player.flashing is true while its hits land, so a target can tell a hit came from the flash.

const DASH_TIME := 0.15          # the dash through them, from start to end (not counting the catches)
const CUT_HOLD := 0.04           # the dash catches on each enemy it cuts for this long
const HOLD := 0.22               # at the end, the pose holds this long before time starts again
const HIT_STEP := 0.07           # then the hits land this far apart
const PASS := 6.0                # an enemy is cut once the player is this far past its middle
const GHOST_EVERY := 12.0        # an afterimage every this many pixels of the dash
const GHOST_LIFE := 0.3
const SLASH_HALF := Vector2(14, 8)   # half of each slash (from its middle), leaning up the way you went
const SLASH_WIDTH := Vector2(3, 1)   # yellow edge, white core (Morgan: a bit thinner than 4 / 2)
const STREAK_WIDTH := Vector2(4, 2)  # the lightning streak along the path
const SLASH := Color(1.0, 0.95, 0.45)    # the flash's yellow
const CORE := Color(1, 1, 1)
const GHOST := Color(1.0, 0.92, 0.45, 0.7)
const CUT_POSES := ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2"]   # the swing alternates on each cut, like the counter's
const DASH_POSE := ["GALLOP", 1]
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const CUT_SOUND := preload("res://sounds/sword/sword_hit_flesh_01.wav")   # the fruit minion's kill sound
const CUT_SOUND_DB := -3.0
const CUT_SOUND_SKIP := 0.025

var player: CharacterBody2D
var targets: Array = []          # nearest first
var from := Vector2.ZERO         # where the flash starts and ends (the player's feet)
var to := Vector2.ZERO
var damage := 3
var push := Vector2.ZERO

var _psprite: AnimatedSprite2D
var _old_anim := ""
var _old_frame := 0
var _frozen := true
var _start := 0.0
var _resumed := -1.0
var _slashes := []               # [from, to, start time], one per target (empty until it's cut)
var _mods := []                  # each target's modulate before it flashed white
var _ghosts := []                # [Sprite2D, start time]
var _last_ghost_x := 0.0
var _cuts := 0


func _ready():
	top_level = true
	global_position = Vector2.ZERO
	z_index = 40
	_start = _now()
	Engine.time_scale = 0.0
	player.set_physics_process(false)    # (it still ticks at time scale 0: keys pressed now would act)
	player.shake_time_left = 0.0         # a shake left running would jitter the whole freeze
	# the dash goes through them over several frames: touching them mustn't hurt
	EnemyKit.protect_player(DASH_TIME + CUT_HOLD * targets.size() + HOLD + HIT_STEP * targets.size() + 0.3)
	_psprite = player.get_node("AnimatedSprite2D")
	_old_anim = _psprite.animation
	_old_frame = _psprite.frame
	_pose(DASH_POSE[0], DASH_POSE[1])
	_last_ghost_x = from.x
	for e in targets:
		_slashes.append([])
		_mods.append(e.modulate)
	_run()


func _exit_tree():
	if _frozen:                          # removed early (scene reload): never leave the game frozen
		Engine.time_scale = 1.0
		if is_instance_valid(player):
			player.set_physics_process(true)
	if is_instance_valid(player):
		player.flashing = false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, true, false, true).timeout


func _run():
	var facing := float(player.facing)
	var dash := 0.0                      # real seconds of dashing so far (the catches don't count)
	var last := _now()
	while true:
		await get_tree().process_frame
		var now := _now()
		dash += now - last
		last = now
		var k := clampf(dash / DASH_TIME, 0.0, 1.0)
		var x := lerpf(from.x, to.x, 1.0 - (1.0 - k) * (1.0 - k))    # fast off the mark, easing into the pose
		# cut each enemy as you go past it, and catch on it for a moment
		while _cuts < targets.size() and (x - _target_x(_cuts)) * facing >= PASS:
			var at := _target_x(_cuts) + facing * PASS
			_move_to(at)
			_cut(_cuts, facing)
			_cuts += 1
			await _wait(CUT_HOLD)
			last = _now()
		_move_to(x)
		if k >= 1.0:
			break
	while _cuts < targets.size():         # (anything the dash ended short of still gets its slash)
		_cut(_cuts, facing)
		_cuts += 1
	get_tree().call_group("living_background", "cut_path", from.x, to.x, from.y, facing)
	await _wait(HOLD)

	_frozen = false
	_resumed = _now()
	Engine.time_scale = 1.0
	player.set_physics_process(true)     # still galloping: its velocity was kept
	if is_instance_valid(_psprite):
		_psprite.play(_old_anim)
		_psprite.frame = _old_frame
	_sparks(player.global_position + Vector2(0, -20))
	for i in targets.size():
		var e = targets[i]
		if is_instance_valid(e):
			e.modulate = _mods[i]
			if _alive(e):
				_land(e, _slashes[i], i == targets.size() - 1)
		await _wait(HIT_STEP)
	await _wait(0.4)
	queue_free()


func _target_x(i: int) -> float:
	var e = targets[i]
	return e.global_position.x if is_instance_valid(e) else from.x


func _move_to(x: float):
	player.global_position.x = x
	while absf(x - _last_ghost_x) >= GHOST_EVERY:
		_last_ghost_x += signf(x - _last_ghost_x) * GHOST_EVERY
		_ghost(_last_ghost_x)


# passing an enemy: a swing, its slash, a white flash and a sword sound
func _cut(i: int, facing: float):
	var e = targets[i]
	if not is_instance_valid(e):
		return
	_pose(CUT_POSES[i % 2], 2)
	var mid: Vector2 = e.global_position + Vector2(0, -12)
	var half := Vector2(facing * SLASH_HALF.x, -SLASH_HALF.y if i % 2 == 0 else SLASH_HALF.y)
	_slashes[i] = [mid - half, mid + half, _now()]
	e.modulate = Color(3, 3, 3)
	player.play_swing_sound(false)


func _pose(anim: String, frame: int):
	_psprite.play(anim)
	_psprite.frame = mini(frame, _psprite.sprite_frames.get_frame_count(anim) - 1)


# a yellow copy of the player's current frame left behind at x, fading out
func _ghost(x: float):
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
	g.global_position = Vector2(x, _psprite.global_position.y)
	_ghosts.append([g, _now()])


func _alive(e: Node) -> bool:
	if e.has_method("is_alive"):
		return e.is_alive()
	var hp = e.get("hp")
	return hp == null or hp > 0


func _land(e: Node2D, slash: Array, last: bool):
	var at := e.global_position + Vector2(0, -12)
	var hp = e.get("hp")
	player.flashing = true
	if e.has_method("cut_in_half") and not slash.is_empty() and (hp == null or hp <= damage):
		e.cut_in_half(player.facing, slash[0], slash[1])    # it splits along the slash you saw
		_cut_sound()
	elif e.has_method("take_hit"):
		e.take_hit(damage, push)
	player.flashing = false
	_sparks(at)
	if last:
		player._shake(16.0, 0.35)
	else:
		player._shake(5.0, 0.12)


# each cut gets its own sound player in the level, so it isn't cut off when this node goes
func _cut_sound():
	var s := AudioStreamPlayer.new()
	s.stream = CUT_SOUND
	s.volume_db = CUT_SOUND_DB
	get_parent().add_child(s)
	s.finished.connect(s.queue_free)
	s.play(CUT_SOUND_SKIP)


func _sparks(at: Vector2):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.3
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = SLASH
	p.z_index = 41
	p.finished.connect(p.queue_free)
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true


func _process(_delta):
	if _frozen:
		Engine.time_scale = 0.0          # hit-freezes elsewhere reset it: keep the world stopped
	var now := _now()
	for g in _ghosts:
		var ghost: Sprite2D = g[0]
		ghost.modulate.a = GHOST.a * (1.0 - clampf((now - float(g[1])) / GHOST_LIFE, 0.0, 1.0))
	for g in _ghosts.filter(func(g): return now - g[1] >= GHOST_LIFE):
		g[0].queue_free()
	_ghosts = _ghosts.filter(func(g): return now - g[1] < GHOST_LIFE)
	queue_redraw()


func _view_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(player.global_position - size / 2.0, size)
	size /= cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size)


func _draw():
	var now := _now()
	# a flash of light the moment it starts
	var flash := 1.0 - clampf((now - _start) / 0.12, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(_view_rect().grow(8.0), Color(1.0, 0.97, 0.8, 0.3 * flash))
	var fade := 1.0 if _resumed < 0.0 else 1.0 - clampf((now - _resumed) / 0.25, 0.0, 1.0)
	if fade <= 0.0:
		return
	# the lightning streak, following the player along the path
	var a := from + Vector2(0, -20)
	var b := Vector2(player.global_position.x, from.y - 20)
	draw_line(a, b, Color(SLASH, 0.8 * fade), STREAK_WIDTH.x)
	draw_line(a, b, Color(CORE, 0.8 * fade), STREAK_WIDTH.y)
	for s in _slashes:
		if s.is_empty():
			continue
		var s0: Vector2 = s[0]
		var s1: Vector2 = s[1]
		var tip := s0.lerp(s1, clampf((now - float(s[2])) / 0.04, 0.0, 1.0))    # each slash draws in from one end
		draw_line(s0, tip, Color(SLASH, fade), SLASH_WIDTH.x)
		draw_line(s0, tip, Color(CORE, fade), SLASH_WIDTH.y)
		if now - float(s[2]) < 0.1:          # a small star where the blade went through
			var c := s0.lerp(s1, 0.5).round()
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				for k in range(2, 5):
					draw_rect(Rect2(c + d * k, Vector2(1, 1)), CORE)
