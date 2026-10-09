extends StaticBody2D
# THE PALM BRIDGE (level 1's quicksand desert, Morgan's call): a giant palm stands on the far bank of the
# desert, out of sight while you're at the near end. The last cactus in the chain fires a volley of spikes
# on across the sand into its trunk (cactus.gd), and the chain camera follows them all the way there.
# Thunk: it shudders, groans, snaps off at the foot and topples back across the sand towards you, the view
# riding along with it. On the way down it smashes the rock pillars (rock_pillar.gd) and squashes any Mango
# still under it, and the crown slams down just in front of where you started. It lies there as a bridge:
# its top is WIDTH over the sand, out of the quicksand's reach, so you can gallop all the way across.
# Place it at the palm's foot, on the far bank. It falls left (`fall_left`), or right.
# Its collision is made here, and only switched on once it's down: a ramp up through the crown, the trunk,
# and a ramp down over the stump. Name it "Sand..." so no grass grows on it. PLACEHOLDER art drawn in code.

signal fallen                                     # it just hit the ground

@export var fall_left := true

const Cactus := preload("res://code/design/cactus.gd")
const Achievements := preload("res://code/design/achievements.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const IMPACT_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const IMPACT_SKIP := 0.02                         # the file starts with 20ms of silence
const THUNK_DB := -10.0                           # a spike going in (played high)
const CRACK_DB := -3.0                            # the foot giving way (played low)
const CREAK_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")   # groaning as it goes over
const CREAK_DB := -6.0
const SLAM_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const SLAM_DB := 0.0

# its shape: nearly straight up from the foot, curving a little out over the sand towards the crown. All of
# it stays off to the side of the screen until the view comes over to it (the trunk is only 32px out from
# the foot at the top of the screen).
const LENGTH := 640.0                             # foot to crown
const SEGMENTS := 40
const FOOT_ANGLE := 86.0                          # degrees up from the ground, at the foot
const TOP_ANGLE := 66.0                           # and at the crown
const BEND := 300.0                               # how soon it goes from one to the other (pixels along it)
const WIDTH := 12.0                               # the trunk; lying down, its top is this high
const STUMP := 12.0                               # the root cone it snaps off
const LIE_AT := Vector2(10, -6)                   # where its foot ends up, lying (the trunk's middle line; x the way it falls)
const RAMP := 30.0                                # the slopes up onto each end
const RING_EVERY := 6.0                           # the rings round the trunk
# its fall
const SPIKE_HEIGHTS := [18.0, 28.0, 38.0]         # where the last cactus's volley goes in (over the ground)
const CREAK_TIME := 0.35                          # after the first spike, before the foot snaps
const FALL_TIME := 0.75
const BOUNCE_TIME := 0.3
const BOUNCE := 0.015
const LOOK_Y := -100.0                            # while it falls, the view follows the trunk where it crosses this height
const ENEMY_HEIGHT := 24.0                        # it squashes a Mango once it comes down this low over its feet
const BIT_GRAVITY := 600.0

const BARK := Color("9a6a3a")
const BARK_LIGHT := Color("c08a52")
const BARK_SHADE := Color("6a4424")
const RING := Color("5a3a1c")
const FROND_DARK := Color("526e36")
const NUT := Color("5a3a1c")
const NUT_LIGHT := Color("8a5a2e")
const SAND := Color("d39b4a")
const SAND_LIGHT := Color("efcf86")
const EARTH := Color("7a5a3a")

enum { STANDING, CREAKING, FALLING, BOUNCING, DOWN }

var player: CharacterBody2D = null
var _dir := -1.0                                  # the way it falls
var _state := STANDING
var _time := 0.0                                  # in this state
var _t := 0.0
var _k := 1.0                                     # its pose: 1 standing, 0 lying down
var _sway := 0.0                                  # it shudders when a spike goes in
var _pts := PackedVector2Array()                  # the trunk's middle line, foot to crown (local)
var _stuck: Array = []                            # spikes in the trunk: [distance along it, angle against it]
var _bits: Array = []                             # chips, splinters and coconuts flying: [pos, vel, colour, life, size]
var _fronds: Array = []                           # [angle off the trunk (degrees), length, shade]
var _shape := CollisionShape2D.new()
var _fx := Node2D.new()                           # dust, in front of the sand
var _thunk_sound := AudioStreamPlayer.new()
var _crack_sound := AudioStreamPlayer.new()
var _creak_sound := AudioStreamPlayer.new()
var _slam_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("palm_bridge")                   # the last cactus aims its volley at it
	_dir = -1.0 if fall_left else 1.0
	z_index = -2                                  # behind you, the Mangos and the cacti
	collision_layer = 1
	collision_mask = 0
	var tip := LIE_AT.x + LENGTH
	var poly := ConvexPolygonShape2D.new()
	poly.set_point_cloud(PackedVector2Array([Vector2((-RAMP - 4.0) * _dir, 1), Vector2(-4.0 * _dir, -WIDTH),
		Vector2((tip - 4.0) * _dir, -WIDTH), Vector2((tip + RAMP - 4.0) * _dir, 1)]))
	_shape.shape = poly
	_shape.disabled = true                        # nothing to stand on till it's down
	add_child(_shape)
	_fx.z_as_relative = false
	_fx.z_index = 4
	add_child(_fx)
	for pair in [[_thunk_sound, IMPACT_SOUND, THUNK_DB], [_crack_sound, IMPACT_SOUND, CRACK_DB],
			[_creak_sound, CREAK_SOUND, CREAK_DB], [_slam_sound, SLAM_SOUND, SLAM_DB]]:
		var s: AudioStreamPlayer = pair[0]
		s.stream = pair[1]
		s.volume_db = pair[2]
		add_child(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x)
	for i in 9:
		_fronds.append([lerpf(-170.0, 170.0, i / 8.0) + rng.randf_range(-8.0, 8.0), rng.randf_range(38.0, 52.0), i % 3])
	_pts = _trunk(_k)


func _physics_process(delta: float):
	_t += delta
	_time += delta
	_sway = move_toward(_sway, 0.0, delta * 2.5)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var moving := _sway > 0.0 or not _bits.is_empty()
	match _state:
		CREAKING:                                             # leaning over, shivering
			_k = 1.0 - 0.03 * _time / CREAK_TIME + 0.004 * sin(_t * 60.0)
			moving = true
			if _time >= CREAK_TIME:
				_snap()
		FALLING:                                              # slow to start, then faster and faster
			var u := minf(_time / FALL_TIME, 1.0)
			_k = 0.97 * (1.0 - pow(u, 2.2))
			moving = true
			_pts = _trunk(_k)
			_squash()
			if u >= 1.0:
				_slam()
		BOUNCING:                                             # a little hop off the ground, then still
			var u := minf(_time / BOUNCE_TIME, 1.0)
			_k = BOUNCE * sin(PI * u)
			moving = true
			if u >= 1.0:
				_k = 0.0
				_state = DOWN
	_pts = _trunk(_k + _sway * 0.02 * sin(_t * 30.0))
	if _state == CREAKING or _state == FALLING:               # the view rides along with it
		Cactus.chain_follow(_look_x())
	_update_bits(delta)
	if moving:
		queue_redraw()


# ---------- the trunk ----------
# its middle line, foot to crown (local), for a pose k (1 standing, 0 lying down): every bit of it leans k of
# the way it does standing, so it straightens out as it goes over
func _trunk(k: float) -> PackedVector2Array:
	var seg := LENGTH / SEGMENTS
	var p := Vector2(LIE_AT.x * _dir, LIE_AT.y).lerp(Vector2(0, -STUMP), clampf(k, 0.0, 1.0))
	var out := PackedVector2Array([p])
	for i in SEGMENTS:
		var s := (i + 0.5) * seg
		var a := deg_to_rad(TOP_ANGLE + (FOOT_ANGLE - TOP_ANGLE) * exp(-s / BEND)) * k
		p += Vector2(cos(a) * _dir, -sin(a)) * seg
		out.append(p)
	return out


func _point_at(s: float) -> Vector2:
	var seg := LENGTH / SEGMENTS
	var i := clampi(int(s / seg), 0, SEGMENTS - 1)
	return _pts[i].lerp(_pts[i + 1], clampf(s / seg - i, 0.0, 1.0))


func _angle_at(s: float) -> float:
	var i := clampi(int(s / (LENGTH / SEGMENTS)), 0, SEGMENTS - 1)
	return (_pts[i + 1] - _pts[i]).angle()


# the side of the trunk facing the ground it falls onto (the side the spikes come in from), at angle a
func _under(a: float) -> Vector2:
	var d := Vector2.from_angle(a)
	return Vector2(-d.y, d.x) * _dir


# how far along the trunk the point nearest p (local) is
func _along(p: Vector2) -> float:
	var seg := LENGTH / SEGMENTS
	var best := 0.0
	var best_d := INF
	for i in SEGMENTS:
		var q := Geometry2D.get_closest_point_to_segment(p, _pts[i], _pts[i + 1])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i * seg + q.distance_to(_pts[i])
	return best


# the middle line's height at x (local), or INF if the trunk isn't over x
func _y_at(x: float) -> float:
	for i in SEGMENTS:
		var a := _pts[i]
		var b := _pts[i + 1]
		if x >= minf(a.x, b.x) and x <= maxf(a.x, b.x):
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x)) if b.x != a.x else minf(a.y, b.y)
	return INF


# where the view looks while it falls (world x): the trunk where it crosses LOOK_Y, or the crown once it's
# lower than that
func _look_x() -> float:
	for i in SEGMENTS:
		var a := _pts[i]
		var b := _pts[i + 1]
		if b.y <= LOOK_Y:
			var f := clampf((LOOK_Y - a.y) / (b.y - a.y), 0.0, 1.0) if b.y != a.y else 0.0
			return global_position.x + lerpf(a.x, b.x, f)
	return global_position.x + _pts[SEGMENTS].x


# the top of what you stand on once it's down (local), or INF past its ends
func _top_y(x: float) -> float:
	var u := x * _dir                                         # (along the way it falls)
	var tip := LIE_AT.x + LENGTH
	if u < -RAMP - 4.0 or u > tip + RAMP - 4.0:
		return INF
	if u < -4.0:
		return lerpf(1.0, -WIDTH, (u + RAMP + 4.0) / RAMP)
	if u > tip - 4.0:
		return lerpf(-WIDTH, 1.0, (u - tip + 4.0) / RAMP)
	return -WIDTH


# ---------- the spikes ----------
# where the last cactus's i-th spike goes in (world): low on the trunk, on the side facing the sand. INF once
# it's past taking one.
func spike_point(i: int) -> Vector2:
	if _state > CREAKING:
		return Vector2.INF
	var h: float = SPIKE_HEIGHTS[i % SPIKE_HEIGHTS.size()]
	for j in SEGMENTS:
		var a := _pts[j]
		var b := _pts[j + 1]
		if b.y <= -h:
			var p := a.lerp(b, clampf((-h - a.y) / (b.y - a.y), 0.0, 1.0))
			return global_position + p + _under((b - a).angle()) * (WIDTH / 2.0 - 1.0)
	return Vector2.INF


# a spike has gone into the trunk at `at` (world), flying along `vel`: thunk. The first one starts it going over.
func thunk(at: Vector2, vel: Vector2):
	if _state > CREAKING:
		return
	var s := _along(at - global_position)
	_stuck.append([s, vel.angle() - _angle_at(s)])
	_sway = 1.0
	for i in 6:                                               # bark chips
		_bits.append([at - global_position, Vector2(-signf(vel.x) * randf_range(20.0, 90.0), randf_range(-90.0, 30.0)),
			BARK_LIGHT if i % 2 == 0 else BARK_SHADE, randf_range(0.4, 0.7), 2.0])
	_thunk_sound.pitch_scale = randf_range(1.5, 1.8)
	_thunk_sound.play(IMPACT_SKIP)
	Cactus.chain_follow(global_position.x)                    # the view settles on it
	if player:
		player._shake(2.0, 0.1)
	if _state == STANDING:
		_state = CREAKING
		_time = 0.0
		_creak_sound.pitch_scale = 1.2
		_creak_sound.play()
	queue_redraw()


# ---------- the fall ----------
# the foot gives way: a crack, splinters, and over it goes
func _snap():
	_state = FALLING
	_time = 0.0
	_crack_sound.pitch_scale = 0.85
	_crack_sound.play(IMPACT_SKIP)
	for i in 14:                                              # splinters, flying back off the way it falls
		_bits.append([Vector2(randf_range(-6.0, 6.0), -STUMP - randf_range(0.0, 4.0)),
			Vector2(-_dir * randf_range(-60.0, 150.0), randf_range(-220.0, -60.0)),
			Pixel.PALE if i % 3 else Pixel.OFF_WHITE, randf_range(0.5, 0.9), 2.0 if i % 2 else 3.0])
	if player:
		player._shake(4.0, 0.2)


# while it comes down: any Mango it reaches is squashed, any rock pillar it reaches is smashed
func _squash():
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not ("hp" in e) or e.hp <= 0 or not e.has_method("take_hit"):
			continue
		var p: Vector2 = e.global_position - global_position
		var y := _y_at(p.x)
		if y != INF and y + WIDTH / 2.0 >= p.y - ENEMY_HEIGHT:
			e.take_hit(99, Vector2(_dir * 40.0, -80.0))
			if e.hp <= 0:
				_juice_pop(e)
	for r in get_tree().get_nodes_in_group("rock_pillar"):
		var p: Vector2 = r.global_position - global_position
		var y := _y_at(p.x)
		if y != INF and not r.crumbled and y + WIDTH / 2.0 >= p.y - r.height:
			r.crumble(_dir)


# down: a slam that shakes everything, sand thrown up all along it, the coconuts bouncing off, and now you
# can stand on it
func _slam():
	_state = BOUNCING
	_time = 0.0
	Achievements.unlock(get_tree(), "timber")
	_k = 0.0
	_pts = _trunk(0.0)
	_squash()
	_shape.set_deferred("disabled", false)
	_lift_player()
	_creak_sound.stop()
	_slam_sound.play()
	_crack_sound.pitch_scale = 0.7
	_crack_sound.play(IMPACT_SKIP)
	EnemyKit.hitstop(get_tree(), 0.08)
	if player:
		player._shake(10.0, 0.45)
	var tip := LIE_AT.x + LENGTH
	var u := 16.0
	while u < tip:                                            # sand (earth at the ends, off the sand)
		var on_sand := u > 40.0 and u < tip - 40.0
		_burst(Vector2(u * _dir, -4.0), SAND if on_sand else EARTH, 8, 110.0)
		if on_sand and int(u) % 3 == 0:
			_burst(Vector2((u + 12.0) * _dir, -4.0), SAND_LIGHT, 5, 70.0)
		u += 36.0
	for i in 3:                                               # the coconuts bounce off, on the way it fell
		_bits.append([_pts[SEGMENTS] + Vector2(i * 4.0 - 4.0, -2.0), Vector2(_dir * randf_range(40.0, 160.0), randf_range(-240.0, -140.0)),
			NUT, 1.4, 5.0])
	for at in [0.0, tip * 0.5, tip]:
		get_tree().call_group("living_background", "burst", global_position + Vector2(at * _dir, 0), 3.0)
	Cactus.chain_follow(global_position.x + _pts[SEGMENTS].x)  # hold the view on the crown a moment
	Cactus.release_player()                                   # and you can move again
	fallen.emit()
	queue_redraw()


# you were right where it came down: you end up standing on it
func _lift_player():
	if player == null or not is_instance_valid(player):
		return
	var p := player.global_position - global_position
	var top := _top_y(p.x)
	if top != INF and p.y > top - 1.0 and p.y < 30.0:
		player.global_position.y = global_position.y + top
		player.velocity.y = minf(player.velocity.y, 0.0)


# a Mango it squashed: it bursts into juice (no "+1" floating up any more, as with the cactus spikes)
func _juice_pop(e: Node2D):
	var spray: Node2D = JuiceSpray.new()
	spray.color = e.juice_color if "juice_color" in e else Color(0.91, 0.54, 0.13)
	spray.aim = Vector2(_dir * 0.3, -1.0).normalized()
	spray.power = 1.4
	spray.floor_y = e.global_position.y + 2.0
	spray.check_ground = true                       # (a Mango up on a rock pillar: no puddles in mid-air)
	spray.position = get_parent().to_local(e.global_position + Vector2(0, -8))
	get_parent().add_child(spray)


func _burst(at: Vector2, color: Color, amount: int, speed: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 40.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.position = at
	p.finished.connect(p.queue_free)
	_fx.add_child(p)
	p.emitting = true


func _update_bits(delta: float):
	for b: Array in _bits:
		b[1].y += BIT_GRAVITY * delta
		b[0] += b[1] * delta
		b[3] -= delta
		if b[0].y > -4.0 and b[1].y > 0.0:                    # bounce off the ground (or the sand)
			b[0].y = -4.0
			b[1] = Vector2(b[1].x * 0.5, -b[1].y * 0.3)
	_bits = _bits.filter(func(b): return b[3] > 0.0)


# ---------- drawing ----------
func _draw():
	_draw_root()
	var broken := _state >= FALLING
	var n := _pts.size()
	var ups := PackedVector2Array()                           # each point's top side (lying down)
	for i in n:
		ups.append(-_under((_pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)]).angle()))
	var lit := PackedVector2Array()
	var shade := PackedVector2Array()
	for i in n:
		lit.append(_pts[i] + ups[i] * (WIDTH / 2.0 - 2.0))
		shade.append(_pts[i] - ups[i] * (WIDTH / 2.0 - 2.5))
	draw_polyline(_pts, Pixel.INK, WIDTH + 2.0)
	draw_polyline(_pts, BARK, WIDTH)
	draw_polyline(lit, BARK_LIGHT, 2.0)
	draw_polyline(shade, BARK_SHADE, 3.0)
	var s := RING_EVERY * 0.5
	while s < LENGTH - 4.0:                                   # rings round the trunk
		var p := _point_at(s)
		var up := -_under(_angle_at(s))
		draw_line((p + up * (WIDTH / 2.0 - 1.0)).round(), (p - up * (WIDTH / 2.0 - 1.0)).round(), RING, 1.0)
		s += RING_EVERY
	if not broken:
		for i in _stuck.size():                               # its foot cracking, a crack for every spike
			_draw_crack(5.0 + i * 5.0, i)
	else:                                                     # the splintered end where it snapped
		var foot := _pts[0]
		var along := Vector2.from_angle(_angle_at(0.0))
		var up := -_under(_angle_at(0.0))
		for j in 6:
			var q := foot + up * (j * 2.0 - 5.0) - along * float(j % 3)
			draw_rect(Rect2(q.round(), Vector2(2, 2)), Pixel.PALE if j % 2 else Pixel.OFF_WHITE)
	for st: Array in _stuck:                                  # the spikes sticking out of it
		var at: float = st[0]
		var dir := Vector2.from_angle(_angle_at(at) + float(st[1]))
		_draw_spike(_point_at(at) + _under(_angle_at(at)) * (WIDTH / 2.0 - 1.0), dir)
	_draw_crown(_pts[n - 1], (_pts[n - 1] - _pts[n - 2]).angle())
	for b: Array in _bits:
		var c: Color = b[2]
		draw_rect(Rect2((b[0] as Vector2).round(), Vector2(b[4], b[4])), Color(c, clampf(float(b[3]) * 4.0, 0.0, 1.0)))


# the root cone at its foot (it stays when the trunk snaps off), roots spreading into the ground
func _draw_root():
	for r in [[Vector2(-6, -6), Vector2(-26, 0)], [Vector2(-4, -3), Vector2(-16, 0)], [Vector2(6, -6), Vector2(25, 0)], [Vector2(4, -3), Vector2(14, 0)]]:
		draw_line(r[0], r[1], Pixel.INK, 4.0)
		draw_line(r[0], r[1], BARK_SHADE, 2.0)
	var cone := PackedVector2Array([Vector2(-20, 0), Vector2(-11, -4), Vector2(-7, -9), Vector2(-6, -STUMP),
		Vector2(6, -STUMP), Vector2(7, -9), Vector2(11, -4), Vector2(20, 0)])
	draw_colored_polygon(cone, BARK_SHADE)
	draw_polyline(cone, Pixel.INK, 1.0)
	draw_line(Vector2(-5, -STUMP + 2.0), Vector2(-9, -2), BARK, 1.0)
	if _state >= FALLING:                                     # the jagged top where the trunk snapped off
		for i in 6:
			var h := 1.0 + float((i * 5) % 3)
			draw_rect(Rect2(-6.0 + i * 2.0, -STUMP - h, 2, h + 1.0), Pixel.PALE if i % 2 else Pixel.OFF_WHITE)


# a crack across the trunk at s along it, zigzagging
func _draw_crack(s: float, i: int):
	var p := _point_at(s)
	var along := Vector2.from_angle(_angle_at(s))
	var up := along.orthogonal()
	var w := WIDTH / 2.0 - 1.0
	var flip := 1.0 if i % 2 == 0 else -1.0
	draw_polyline(PackedVector2Array([p + up * w * flip, p + up * 2.0 * flip + along * 2.0, p - up * 1.0 * flip - along * 1.0,
		p - up * w * flip + along * 2.0]), Pixel.INK, 1.0)


# a cactus spike stuck in the trunk: its tip in the wood at `at`, the rest sticking out back along `dir`
func _draw_spike(at: Vector2, dir: Vector2):
	for i in range(1, 6):
		draw_rect(Rect2((at - dir * i).floor() + Vector2(0, 1), Vector2.ONE), Color(Pixel.INK, 0.8))
	for i in range(1, 6):
		draw_rect(Rect2((at - dir * i).floor(), Vector2.ONE), Pixel.PALE if i < 4 else Pixel.BROWN)


# the crown: fronds all round, drooping at the tips (lying flat on the ground once it's down), and coconuts
func _draw_crown(c: Vector2, dir: float):
	for f: Array in _fronds:
		var a := dir + deg_to_rad(float(f[0]))
		var length: float = f[1]
		var col: Color = [FROND_DARK, Pixel.GREEN_DARK, Pixel.GREEN][f[2]]
		var out := Vector2.from_angle(a)
		var prev := c
		var j := 2.0
		while j < length:
			var q := j / length
			var p := c + out * j + Vector2(0, q * q * 16.0)
			p.y = minf(p.y, -1.0)                             # the ground
			draw_line(prev.round(), p.round(), col, 2.0)
			if int(j) % 4 == 0 and j < length - 2.0:             # leaflets hanging off both sides
				for side in [-1.0, 1.0]:
					var e: Vector2 = p + out.orthogonal() * side * 5.0 * (1.0 - q * 0.5) + Vector2(0, 3)
					e.y = minf(e.y, 0.0)
					draw_line(p.round(), e.round(), col.darkened(0.15) if side > 0.0 else col, 1.0)
			prev = p
			j += 2.0
	if _state < BOUNCING:                                     # (they bounce off when it lands)
		for i in 3:
			var nut := c + Vector2(i * 4.0 - 4.0, 3.0 + float(i % 2))
			draw_circle(nut, 3.0, Pixel.INK)
			draw_circle(nut, 2.0, NUT)
			draw_rect(Rect2(nut + Vector2(-1, -1), Vector2.ONE), NUT_LIGHT)

