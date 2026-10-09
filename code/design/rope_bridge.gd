extends StaticBody2D
# THE ROPE BRIDGE (Morgan's idea, 2026-10-09): Level 2, right after the coconut grove. A rickety rope bridge
# sagging across a chasm. As you near the far side it snaps, in slow motion: the planks ahead of you drop
# away (that half swings down and slaps against the far cliff), the bit you're on holds a moment longer, then
# swings down too, so you have to jump for the far side. Fall and you're back at the checkpoint before it,
# and the bridge is whole again.
# Put it at the near edge (its left end), level with the floor, and set `width` to the far edge. Its name
# starts with "Board" so no grass grows on it.
# PLACEHOLDER look, drawn in code: a wooden post at each end, a hand rope behind and one in front, a foot
# rope with planks along it (some cracked, some darker, all a little crooked) and ties between them, and the
# chasm's dark depths below. It sways, and the planks near you rattle as you cross.

const SLOW := 0.3                   # slow motion as it snaps
const SLOW_TIME := 1.8              # ...for this long at most (real seconds; it ends sooner once you land or fall)
const GRACE := 0.3                  # the bit you're standing on holds this long after the snap (game seconds)
const AHEAD := 30.0                 # it breaks this far ahead of you
const PITCH := 16.0                 # a plank every this far
const PLANK := Vector2(13, 4)
const HAND_Y := -26.0               # the hand ropes' height over the planks
const POST_H := 36.0
const SWING_TIME := 0.55            # a broken half swings down to hang against its cliff in this long (game s)
const LOOSE := 4                    # planks either side of the break that come loose and fall
const ROPE := Color("c9a46a")
const ROPE_DARK := Color("8a6a3a")
const WOOD := Color("8a5a32")
const WOOD_LIGHT := Color("a8743e")
const WOOD_DARK := Color("5e3a1e")
const DEPTHS := [Color("3a2433"), Color("30202c"), Color("281b25"), Color("21161f"), Color("1a1219")]
const SNAP_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const SNAP_SKIP := 0.02
const SNAP_DB := -4.0
const SLOWMO_SOUND := preload("res://sounds/MATRIX_freesound_community-the-matrix-trinity-jump-sound-fx-plain-single-77358_fast.wav")
const SLOWMO_DB := -6.0
const GROAN_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")
const GROAN_DB := -10.0

@export var width := 560.0
@export var sag := 32.0             # how far its middle hangs below its ends
@export var snap_from_end := 170.0  # it snaps when you're this far from the far end (sooner the faster you go)

var _planks: Array = []             # per plank: [along x, CollisionShape2D, cracked, dark, tilt, come loose]
var _snapped := false
var _snap_t := 0.0                  # game seconds since it snapped
var _break_x := 0.0
var _near_gone := false             # the near half has let go too
var _slow_until := -1.0             # real time
var _slowing := false
var _loose: Array = []              # [position, velocity, angle, spin] planks falling into the chasm
var _t := 0.0
var _player: CharacterBody2D = null
var _front := Node2D.new()          # the front hand rope, in front of the player
var _depths := Node2D.new()         # the chasm below, behind everything
var _snap_sound := AudioStreamPlayer.new()
var _slowmo_sound := AudioStreamPlayer.new()
var _groan_sound := AudioStreamPlayer.new()


func _ready():
	z_index = -1                    # the planks behind the player's feet
	var n := int(width / PITCH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in n:
		var x := (i + 0.5) * width / n
		var shape := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = Vector2(x - width / n / 2.0, _curve(x - width / n / 2.0))
		seg.b = Vector2(x + width / n / 2.0, _curve(x + width / n / 2.0))
		shape.shape = seg
		add_child(shape)
		_planks.append([x, shape, rng.randf() < 0.18, rng.randf() < 0.25, rng.randf_range(-0.06, 0.06), false])
	_front.z_as_relative = false
	_front.z_index = 2
	_front.draw.connect(_draw_front)
	add_child(_front)
	_depths.z_as_relative = false
	_depths.z_index = -20
	_depths.draw.connect(_draw_depths)
	add_child(_depths)
	for p in [[_snap_sound, SNAP_SOUND, SNAP_DB], [_slowmo_sound, SLOWMO_SOUND, SLOWMO_DB], [_groan_sound, GROAN_SOUND, GROAN_DB]]:
		var s: AudioStreamPlayer = p[0]
		s.stream = p[1]
		s.volume_db = p[2]
		add_child(s)


func _exit_tree():
	if _slowing:
		Engine.time_scale = 1.0


# the sag: a parabola from one end to the other, `sag` down in the middle
func _curve(x: float) -> float:
	var u := clampf(x / width, 0.0, 1.0)
	return sag * 4.0 * u * (1.0 - u)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float):
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if _player == null:
			return
	var px := _player.global_position.x - global_position.x
	if not _snapped:
		var on_it := px > 0.0 and px < width and _player.is_on_floor() and absf(_player.global_position.y - global_position.y - _curve(px)) < 6.0
		var reach := snap_from_end + maxf(absf(_player.velocity.x) - 260.0, 0.0) * 0.35
		if on_it and px >= width - reach and _player.velocity.x >= 0.0:
			_snap(px)
	else:
		_snap_t += delta
		if not _near_gone and _snap_t >= GRACE:
			_near_gone = true                       # the bit you're on goes too
			for p: Array in _planks:
				if p[0] < _break_x:
					p[1].set_deferred("disabled", true)
			_snap_sound.pitch_scale = 1.9
			_snap_sound.play(SNAP_SKIP)
		# whole again once you're back on the near side (the checkpoint before it, after a fall)
		if _snap_t > 1.0 and px < -8.0 and _player.is_on_floor():
			_mend()
	for l: Array in _loose:
		l[1].y += 900.0 * delta
		l[0] += l[1] * delta
		l[2] += l[3] * delta
	_loose = _loose.filter(func(l): return l[0].y < 700.0)
	queue_redraw()
	_front.queue_redraw()


# real time: the slow motion (re-applied every frame, since hit-freezes reset it; never over a stop)
func _process(_delta: float):
	if not _slowing:
		return
	var done := _now() >= _slow_until
	if _player and is_instance_valid(_player):
		var px := _player.global_position.x - global_position.x
		if (_player.is_on_floor() and px > width + 2.0) or _player.global_position.y > global_position.y + 200.0:
			done = true                             # landed on the far side, or fell
	if done:
		_slowing = false
		if Engine.time_scale != 0.0:
			Engine.time_scale = 1.0
	elif Engine.time_scale != 0.0:
		Engine.time_scale = SLOW


func _snap(px: float):
	_snapped = true
	_snap_t = 0.0
	_near_gone = false
	_break_x = minf(px + AHEAD, width - PITCH)
	for p: Array in _planks:
		if p[0] >= _break_x:
			p[1].set_deferred("disabled", true)     # the planks ahead drop away at once
	var k := 0
	for p: Array in _planks:                        # a few just past the break come loose and tumble down
		if p[0] >= _break_x and k < LOOSE:          # (none on your side: that bit holds a moment)
			k += 1
			p[5] = true
			_loose.append([Vector2(p[0], _curve(p[0]) + PLANK.y / 2.0), Vector2(randf_range(-60.0, 60.0), randf_range(-140.0, -40.0)),
				p[4], randf_range(-9.0, 9.0)])
	_slowing = true
	_slow_until = _now() + SLOW_TIME
	Engine.time_scale = SLOW
	_snap_sound.pitch_scale = 1.6
	_snap_sound.play(SNAP_SKIP)
	_slowmo_sound.play()
	_groan_sound.pitch_scale = 1.8
	_groan_sound.play()
	_splinters(Vector2(_break_x, _curve(_break_x)))
	if _player.has_method("_shake"):
		_player._shake(5.0, 0.2)


# whole again (you fell, and you're back before it)
func _mend():
	_snapped = false
	_near_gone = false
	_loose.clear()
	for p: Array in _planks:
		p[1].set_deferred("disabled", false)
		p[5] = false


func _splinters(at: Vector2):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = WOOD_LIGHT
	p.position = at
	p.z_index = 3
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ---------- where everything is ----------
# a broken half swings down from its anchor: its shape turned about the anchor until its chord hangs
# straight down, speeding up as it falls, then knocking against the cliff and settling
func _turn(near: bool) -> float:
	var t := _snap_t - (GRACE if near else 0.0)
	if not _snapped or t <= 0.0:
		return 0.0
	var anchor := Vector2(0, 0) if near else Vector2(width, 0)
	var chord := Vector2(_break_x, _curve(_break_x)) - anchor
	var target := PI / 2.0 - chord.angle()
	target = wrapf(target, -PI, PI)
	var u := t / SWING_TIME
	var f := u * u if u < 1.0 else 1.0 - 0.1 * absf(sin((u - 1.0) * 9.0)) * exp(-(u - 1.0) * 3.0)
	return target * f


# a point on the bridge (at x along it, lifted `up` off the planks), where it is now
func _at(x: float, up := 0.0) -> Vector2:
	var p := Vector2(x, _curve(x) + up)
	if not _snapped:
		var u := x / width
		p.y += sin(_t * 1.6) * 1.0 * 4.0 * u * (1.0 - u)        # a gentle sway
		return p
	var near := x < _break_x
	var anchor := Vector2(0, 0) if near else Vector2(width, 0)
	return anchor + (p - anchor).rotated(_turn(near))


# ---------- drawing ----------
func _draw():
	_draw_posts()
	_draw_hand_rope(-1.0)                                       # the hand rope behind
	var px := (_player.global_position.x - global_position.x) if _player and is_instance_valid(_player) else -999.0
	for i in _planks.size():
		var p: Array = _planks[i]
		var x: float = p[0]
		if p[5]:
			continue                                            # (it's come loose: drawn falling below)
		var a := _at(x - PLANK.x / 2.0, PLANK.y / 2.0)          # (its top on the walkable line)
		var b := _at(x + PLANK.x / 2.0, PLANK.y / 2.0)
		var mid := (a + b) / 2.0
		var ang := (b - a).angle() + float(p[4])
		if not _snapped and absf(x - px) < 28.0:
			ang += sin(_t * 30.0 + i) * 0.07                   # rattling under you
		_plank(mid, ang, p[2], p[3])
		if i % 2 == 0:                                          # the ties up to the hand rope
			var top := _at(x, HAND_Y)
			draw_line(mid.round(), top.round(), ROPE_DARK, 1.0)
	for l: Array in _loose:
		_plank(l[0], l[2], false, false)
	_draw_foot_rope()


func _plank(at: Vector2, ang: float, cracked: bool, dark: bool):
	draw_set_transform(at.round(), ang)
	draw_rect(Rect2(-PLANK / 2.0, PLANK), WOOD_DARK if dark else WOOD)
	draw_rect(Rect2(-PLANK.x / 2.0, -PLANK.y / 2.0, PLANK.x, 1), WOOD_LIGHT)
	draw_rect(Rect2(-PLANK.x / 2.0, PLANK.y / 2.0 - 1.0, PLANK.x, 1), WOOD_DARK)
	if cracked:
		draw_rect(Rect2(-1, -PLANK.y / 2.0, 1, PLANK.y), WOOD_DARK)
	draw_set_transform(Vector2.ZERO)


func _draw_posts():
	for x in [0.0, width]:
		draw_rect(Rect2(x - 2.0, -POST_H, 4, POST_H + 6.0), WOOD_DARK)
		draw_rect(Rect2(x - 2.0, -POST_H, 1, POST_H + 6.0), WOOD)
		draw_rect(Rect2(x - 3.0, HAND_Y - 2.0, 6, 3), ROPE)          # the rope wrapped round it
		draw_rect(Rect2(x - 3.0, -3.0, 6, 3), ROPE)


func _draw_foot_rope():
	var pts := PackedVector2Array()
	var steps := 40
	for side in 2:                                              # (each half separately once it's snapped)
		pts.clear()
		for s in steps + 1:
			var x := width * float(s) / steps
			if _snapped and ((side == 0) != (x < _break_x)):
				continue
			if not _snapped and side == 1:
				break
			pts.append(_at(x, PLANK.y).round())
		if pts.size() >= 2:
			draw_polyline(pts, ROPE_DARK, 1.0)


func _draw_hand_rope(depth: float):
	var ci: CanvasItem = self if depth < 0.0 else _front
	var lift := HAND_Y + (0.0 if depth < 0.0 else 6.0)        # (the front one hangs a little lower)
	var col := ROPE_DARK if depth < 0.0 else ROPE
	var steps := 40
	for side in 2:
		var pts := PackedVector2Array()
		for s in steps + 1:
			var x := width * float(s) / steps
			if _snapped and ((side == 0) != (x < _break_x)):
				continue
			if not _snapped and side == 1:
				break
			var p := _at(x, lift)
			if not _snapped:
				var u := x / width
				p.y += sag * 0.15 * 4.0 * u * (1.0 - u)            # (hand ropes sag a touch more)
			pts.append(p.round())
		if pts.size() >= 2:
			ci.draw_polyline(pts, col, 1.0)


func _draw_front():
	_draw_hand_rope(1.0)


# the chasm under it: dark bands going down, between its cliffs
func _draw_depths():
	var band := 520.0 / DEPTHS.size()
	for i in DEPTHS.size():
		_depths.draw_rect(Rect2(0, 64.0 + i * band, width, band + 1.0), DEPTHS[i])
	_depths.draw_rect(Rect2(0, 0, width, 64.0), DEPTHS[0].lightened(0.06))
