extends StaticBody2D
# JELLY BED (Morgan's idea, 2026-10-09: "bounce up and down while travelling, speeding up with every
# bounce"): a long pool of mango jelly set into the jelly factory's floor (jelly_lab.gd), its top flush with
# the floor. You can't walk on jelly: touch it and it bounces you, and every bounce puts you up a speed level
# (walk, run, sprint, gallop) the way you're going, a little higher each time. So you come off it at a full
# gallop. Each bounce dents the jelly where you land and the dent wobbles out along it, with a squelch that
# rises in pitch, and a splash of jelly.
# Put it at the pool's left end, level with the floor, `length` long. Its name starts with "Board" so no
# grass grows on it. player.gd is untouched: it uses launch() and sets speed_level / hold_time, like the
# tutorial's locks.
# PLACEHOLDER look, drawn in code: the jelly in a glass tray, seen cut through: a glossy top, a shine just
# under it, bubbles and bits of fruit hanging in it, darker towards the bottom.

const DEPTH := 44.0                  # how deep the tray is
const STEP := 4.0                    # a spring on its surface every this far
const WAVE := 220.0                  # the surface: how fast a dent runs along it (px/s),
const TENSION := 40.0                # ...how hard it pulls back to flat,
const DAMP := 2.5                    # ...and how quickly it settles
const DENT := 320.0                  # how hard a bounce dents it (how fast its springs start down)
const BOUNCE_V := [0.0, 0.0, 380.0, 420.0, 460.0]     # how hard it throws you up, by the speed level it gives
const LAUNCH_HOLD := 0.18            # air steering waits this long after a bounce, so it throws you cleanly
const REST := 0.12                   # (game seconds) before it can bounce you again
const JELLY := Color(0.94, 0.56, 0.18, 0.92)
const JELLY_LIGHT := Color("f7c068")
const JELLY_DARK := Color(0.77, 0.4, 0.1, 0.95)
const BITS := Color("c4561a")
const TRAY := Color(0.85, 0.95, 1.0, 0.8)
const SQUELCH := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const SQUELCH_SKIP := 0.12
const SQUELCH_DB := -6.0

@export var length := 1160.0

var _h: PackedFloat32Array           # the surface's springs: how far down each is,
var _v: PackedFloat32Array           # ...and how fast it's moving
var _t := 0.0
var _rest := 0.0
var _player: CharacterBody2D = null
var _times := [0.0, 0.0, 0.5, 1.4, 2.5]   # the player's hold times for each speed level (read from player.gd)
var _speeds: Array = []
var _bits: Array = []                # [x, y, size, light] bubbles and fruit bits in it
var _squelch := AudioStreamPlayer.new()
var _quiet := false                  # nothing's moving: no need to work it out or redraw


func _ready():
	z_index = -45                    # over the lab's floor, behind you
	z_as_relative = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, 64)
	shape.shape = rect
	shape.position = Vector2(length / 2.0, 32)
	add_child(shape)
	var n := int(length / STEP) + 1
	_h.resize(n)
	_v.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in int(length / 14.0):
		_bits.append([rng.randf_range(4.0, length - 4.0), rng.randf_range(10.0, DEPTH - 6.0), rng.randi_range(1, 2), rng.randf() < 0.6])
	_squelch.stream = SQUELCH
	_squelch.volume_db = SQUELCH_DB
	_squelch.max_polyphony = 3
	add_child(_squelch)


func _find_player():
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if _player:
		var consts: Dictionary = _player.get_script().get_script_constant_map()
		_speeds = consts["SPEEDS"]
		_times = [0.0, 0.0, consts["TIME_TO_LEVEL_2"], consts["TIME_TO_LEVEL_3"], consts["TIME_TO_LEVEL_4"]]


func _physics_process(delta: float):
	_t += delta
	_rest -= delta
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	var px := _player.global_position.x - global_position.x
	var on_it := px >= 0.0 and px <= length and _player.is_on_floor() and absf(_player.global_position.y - global_position.y) < 3.0
	if on_it and _rest <= 0.0 and _player.is_physics_processing():
		_bounce(px)
	_springs(delta)
	if not _quiet or absf(px - length / 2.0) < length / 2.0 + 300.0:
		queue_redraw()


# a bounce: up a speed level the way you're going, a little higher than the last
func _bounce(px: float):
	_rest = REST
	var top := _speeds.size() - 1
	var level := clampi(maxi(int(_player.speed_level) + 1, 2), 2, top)
	var dir := signf(_player.velocity.x) if absf(_player.velocity.x) > 10.0 else float(_player.facing)
	_player.launch(Vector2(dir * float(_speeds[level]), -float(BOUNCE_V[level])), LAUNCH_HOLD)
	_player.speed_level = level
	_player.hold_time = _times[level]
	var i := clampi(roundi(px / STEP), 0, _h.size() - 1)       # the dent where you landed
	for k in range(-2, 3):
		var j := i + k
		if j >= 0 and j < _h.size():
			_v[j] += DENT * (1.0 - absf(k) * 0.3)
	_quiet = false
	_squelch.pitch_scale = 0.8 + 0.18 * level
	_squelch.play(SQUELCH_SKIP)
	_splash(Vector2(px, 0), dir)
	if _player.has_method("_shake"):
		_player._shake(1.5 + level * 0.5, 0.08)


# the surface as a string of springs: each pulled by its neighbours (so a dent runs along it as a wobble),
# pulled back to flat, and settling. Its ends are held flat by the tray
func _springs(delta: float):
	if _quiet:
		return
	var c2 := WAVE * WAVE / (STEP * STEP)
	var n := _h.size()
	for i in n:
		var l := _h[i - 1] if i > 0 else 0.0
		var r := _h[i + 1] if i < n - 1 else 0.0
		_v[i] += (c2 * (l + r - 2.0 * _h[i]) - TENSION * _h[i] - DAMP * _v[i]) * delta
	var moving := false
	for i in n:
		_h[i] += _v[i] * delta
		if absf(_h[i]) > 0.05 or absf(_v[i]) > 0.5:
			moving = true
	_quiet = not moving


func _splash(at: Vector2, dir: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2(dir * 0.3, -1.0)
	p.spread = 55.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 150.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = JELLY_LIGHT
	p.position = at
	p.z_as_relative = false
	p.z_index = 3
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# the surface's height at x: its springs, and a slow, slight wobble
func _top(x: float) -> float:
	var f := clampf(x / STEP, 0.0, _h.size() - 1.001)
	var i := int(f)
	var h := lerpf(_h[i], _h[i + 1], f - i)
	return roundf(h + sin(_t * 2.2 + x * 0.045) * 0.6)


func _draw():
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x := maxf(floorf((view.position.x - global_position.x) / 2.0) * 2.0 - 2.0, 0.0)   # (only what's on screen)
	var x_end := minf(view.end.x - global_position.x + 2.0, length)
	while x < x_end:                                         # the jelly, in 2px columns
		var top := clampf(_top(x + 1.0), -6.0, DEPTH - 8.0)
		draw_rect(Rect2(x, top, 2, DEPTH - top), JELLY)
		draw_rect(Rect2(x, top, 2, 2), JELLY_LIGHT)           # its skin
		draw_rect(Rect2(x, top + 4.0, 2, 1), Color(1, 1, 1, 0.35))   # the shine just under it
		draw_rect(Rect2(x, DEPTH - 10.0, 2, 10), JELLY_DARK)
		x += 2.0
	for b: Array in _bits:                                   # bubbles and fruit bits hanging in it
		var by: float = b[1] + _top(b[0]) * 0.5
		draw_rect(Rect2(roundf(b[0]), roundf(by), b[2], b[2]), Color(1, 1, 1, 0.45) if b[3] else BITS)
	draw_rect(Rect2(-2, -1, 2, DEPTH + 3.0), TRAY)            # the glass tray
	draw_rect(Rect2(length, -1, 2, DEPTH + 3.0), TRAY)
	draw_rect(Rect2(-2, DEPTH, length + 4.0, 2), TRAY)
