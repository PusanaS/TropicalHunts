extends Node2D
# THE MINE CART (level 1, Morgan's idea): just past the gate, a rusty mine cart waits on rails at the
# mouth of a mine. Touch it (or jump at it) and you're bundled in, and it's off: down the rails into the
# dark, faster and faster, ploughing through the Mangos standing on the track. Juice everywhere: it bursts
# out of them, stains the rails and the tunnel wall, and splatters the cart itself. Sparks fly off the
# wheels on the steep part. At the bottom it slams into the buffer stop and flips end over end: you're
# thrown on into the underground quicksand, and the cart breaks apart behind you. Single use.
# Origin: (4960, 0) in level 1; the rails below are relative to it. Draws the rails, the buffer stop, the
# timber mine mouth (MINE sign, lantern) and the cart. mine_cave.gd draws the tunnel around it.
# PLACEHOLDER art drawn in code (BOOM's style: flat colours, one shade each). The Mangos use their own sheet.

enum Mode { PARKED, HOPPING, RIDING, FLIPPING, DONE }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Achievements := preload("res://code/design/achievements.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const MANGO := preload("res://scene/design/fruit_minion.tscn")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
# the wheels grinding on the rails (Morgan's pick). The file swells in, grinds steadily from 0.1 to 1.45 s,
# then fades: only that steady part is looped, by two players taking turns with a crossfade (no pulse)
const WAGON_SOUND := preload("res://sounds/WAGON_spinopel-grinding-sound-of-a-railway-wheels-545715.mp3")
const WAGON_DB := Vector2(-14.0, -2.0)      # quiet when slow, loud flat out
const WAGON_PITCH := Vector2(0.85, 1.2)
const WAGON_LOOP_FROM := 0.12               # each turn starts here in the file...
const WAGON_LOOP_TO := 1.45                 # ...and the next takes over before this
const WAGON_FADE := 0.25                    # the crossfade between turns (real seconds)
const WAGON_OUT := 0.12                     # how fast it cuts out at the crash
const SPLAT_SOUNDS := [preload("res://sounds/sword/sword_hit_flesh_02.wav"), preload("res://sounds/sword/sword_hit_flesh_04.wav"),
	preload("res://sounds/sword/sword_hit_flesh_06.wav")]   # a Mango going under the wheels
const SPLAT_SOUND_DB := -2.0
const CLANG_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")   # the cart hitting the buffer
const CLANG_SOUND_DB := -4.0
const CLANG_SOUND_SKIP := 0.02       # the file starts with 20ms of silence
const CRASH_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const CRASH_SOUND_DB := 0.0

# the track, relative to the origin (global = these + (4960, 0)): flat at the mouth, steep down, then a long
# straight along the bottom (Morgan wanted the ride longer there) through the barricades to the buffer
const RAILS := [Vector2(10, 0), Vector2(80, 0), Vector2(125, 6), Vector2(170, 22), Vector2(480, 286),
	Vector2(520, 312), Vector2(560, 320), Vector2(1208, 320)]
const PARK := 30.0                   # the cart waits this far along the rails (x 5000)
const VICTIMS := [250.0, 300.0, 345.0, 390.0, 435.0, 480.0, 530.0, 620.0, 672.0,
	760.0, 820.0, 870.0, 990.0, 1030.0, 1140.0, 1175.0]   # Mangos on the track (distance along it)
# wooden barricades across the straight at the bottom: the cart smashes straight through them (Morgan's idea)
const BARRICADES := [924.0, 1074.0, 1224.0]   # distance along the track (x 5785, 5935, 6085: between the supports)
const BARRICADE_SLOW := 0.95        # each one takes a little speed off
const CRACK_SOUND_DB := -6.0        # the heavy impact again, quieter and at a random pitch
const GRAB := 28.0                   # you're bundled in this close to the cart...
const GRAB_ABOVE := 130.0            # ...even jumping over it
const HOP_TIME := 0.22
const START_SPEED := 180.0
const GRAVITY := 980.0
const TOP_SPEED := 760.0
const PUSH := 220.0                  # on the flat at the top, it gets going
const DRAG := 40.0
const PANIC_AT := 140.0              # a Mango sees the cart coming this far off ("!")
const HIT_AT := 14.0                 # the cart's nose, from its middle
const HIT_SLOW := 0.96               # each Mango takes a little speed off
const SEAT := Vector2(-2, -10)       # the rider's feet in the cart (forward, down)
const CART_HALF := 16.0
const RIDE_POSE := ["BRAKE", 1]      # braced, leaning back (like the surf ride)
const THROW := Vector2(380, -300)    # the crash throws you on into the sand (lands around x 6390)
const THROW_HOLD := 0.35
const GROUND_Y := 320.0              # the bottom floor
const SAND_X := 1300.0               # the underground quicksand starts here (x 6260)
const BUFFER_X := 1208.0
const MOUTH := Vector2(80, 180)      # the timber frame's posts, round the tunnel mouth in the mountain (x 5040..5140)
const MOUTH_TOP := -80.0            # (the mouth itself is 72 tall)
# slow motion as it hits the buffer: held, then eased back to full speed (real seconds)
const SLOW_SCALE := 0.25
const SLOW_HOLD := 0.25
const SLOW_EASE := 0.25
const MAX_STAINS := 180
const MAX_SPLATS := 70
const DEBRIS_LIFE := 6.0

const IRON := Color("6b4a3a")        # rusty iron
const IRON_SHADE := Color("4a3128")
const IRON_RIM := Color("9c7d68")
const RUST := Color("b5652e")
const RUST_DARK := Color("8a4a22")
const RIVET := Color("2e211b")
const WHEEL := Color("35322f")
const WHEEL_RIM := Color("5e5852")
const SPOKE := Color("8a8178")
const STEEL := Color("8a8f99")
const STEEL_SHADE := Color("5d626b")
const WOOD := Color(0.55, 0.35, 0.18)
const WOOD_LIGHT := Color(0.69, 0.48, 0.26)
const WOOD_DARK := Color(0.38, 0.25, 0.13)
const ROPE := Color(0.82, 0.74, 0.55)
const STRIPE_RED := Color("b3261e")
const STRIPE_WHITE := Color("ecdfdb")
const LAMP := Color("ffd27a")
const LAMP_LIGHT := Color("ffd9a0")
const SPARKS := [Color("fffbe6"), Color("ffe27a"), Color("f6b13c")]
const SAND := [Color("efcf86"), Color("d39b4a"), Color("a8722f")]   # the quicksand's own colours
const DUST := Color("8c8577")
const RUBBLE := [Color("6e6250"), Color("564c40"), Color("4d321a")]   # the caved-in mouth: stones and earth
const SIGN_TEXT := [Color("8d0e0e"), Color("5a0808"), Color("b3261e")]   # fill, shade, light
const RUST_SPOTS := [Rect2(-10, -18, 3, 2), Rect2(5, -21, 2, 2), Rect2(9, -13, 3, 1), Rect2(-4, -12, 2, 2), Rect2(-14, -22, 2, 1)]

var player: CharacterBody2D = null
var _sprite: AnimatedSprite2D = null
var _mode: Mode = Mode.PARKED
var _mode_t := 0.0
var _t := 0.0
var _sealed := false                 # the mouth caved in behind you once the cart crashed
var _blocked_ach := false            # you walked back up the shaft to the rubble (WRONG WAY BRO)
var _shame_ach := false              # ...and then all the way back down again (THE WALK OF SHAME)
var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()     # distance along the track at each point
var _len := 0.0
var _d := PARK                       # the cart's place along the track
var _speed := 0.0
var _wheel := 0.0                    # how far the wheels have turned (radians)
var _cart_pos := Vector2.ZERO        # where the cart is drawn (local): on the rails, or flying after the crash
var _cart_angle := 0.0
var _cart_vel := Vector2.ZERO
var _cart_spin := 0.0
var _jolt := Vector2.ZERO            # the rattle this frame
var _hop_from := Vector2.ZERO
var _victims: Array = []             # [Mango, distance along the track, panicked?, hit?]
var _stains: Array = []              # [pos (local), size, colour, drip] on the rails and the tunnel wall
var _splats: Array = []              # [pos (in the cart), colour] juice on the cart's side
var _sparks: Array = []              # [pos, vel, life, colour]
var _streaks: Array = []             # [pos, dir, length, life]
var _debris: Array = []              # [pos, vel, angle, spin, size, wheel?, age, colour]
var _slow_from := -1.0               # real time the slow motion started (-1: not running it)
var _back := Node2D.new()            # rails, buffer, stains, the mine mouth: behind you
var _front := Node2D.new()           # the cart and its wreck: in front of you (you sit inside it)
var _fx := Node2D.new()              # sparks and speed lines
var _lamp := PointLight2D.new()      # the cart's headlamp (only lit underground)
var _wagon: Array[AudioStreamPlayer] = [AudioStreamPlayer.new(), AudioStreamPlayer.new()]
var _wagon_cur := 0                  # the one playing (the other takes over at each crossfade)
var _wagon_on := false
var _wagon_xfade := -1.0             # real time a crossfade started (-1: none)
var _wagon_out := -1.0               # real time the fade-out started (-1: none)
var _splat := AudioStreamPlayer.new()
var _clang := AudioStreamPlayer.new()
var _crack := AudioStreamPlayer.new()   # a barricade going
var _barricades: Array = []           # [distance, broken?]
var _crash_sound := AudioStreamPlayer.new()


func _ready():
	for p: Vector2 in RAILS:
		_pts.append(p)
	_cum.append(0.0)
	for i in range(1, _pts.size()):
		_cum.append(_cum[i - 1] + _pts[i - 1].distance_to(_pts[i]))
	_len = _cum[_cum.size() - 1]
	_cart_pos = _point_at(_d)
	_cart_angle = _angle_at(_d)
	for layer: Array in [[_back, -1, _draw_back], [_front, 1, _draw_front], [_fx, 4, _draw_fx]]:
		var n: Node2D = layer[0]
		n.z_index = layer[1]
		n.draw.connect(layer[2])
		add_child(n)
	for w: AudioStreamPlayer in _wagon:
		w.stream = WAGON_SOUND
		add_child(w)
	var squelch := AudioStreamRandomizer.new()
	for s: AudioStream in SPLAT_SOUNDS:
		squelch.add_stream(-1, s)
	squelch.random_pitch = 1.25
	_splat.stream = squelch
	_splat.volume_db = SPLAT_SOUND_DB
	_splat.max_polyphony = 4
	add_child(_splat)
	_clang.stream = CLANG_SOUND
	_clang.volume_db = CLANG_SOUND_DB
	add_child(_clang)
	_crack.stream = CLANG_SOUND
	_crack.volume_db = CRACK_SOUND_DB
	_crack.max_polyphony = 3
	add_child(_crack)
	for d: float in BARRICADES:
		_barricades.append([d, false])
	_crash_sound.stream = CRASH_SOUND
	_crash_sound.volume_db = CRASH_SOUND_DB
	add_child(_crash_sound)
	_lamp.texture = _light_texture()
	_lamp.color = LAMP_LIGHT
	_lamp.texture_scale = 2.2
	_lamp.energy = 0.0
	add_child(_lamp)
	_spawn_victims.call_deferred()   # the Enemies node may still be setting up its own children


# a soft round light
static func _light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


# Mangos standing on the track, frozen in place (no physics) until the cart comes for them
func _spawn_victims():
	var parent := (owner.get_node_or_null("Enemies") if owner else null) as Node2D
	if parent == null:
		parent = get_parent() as Node2D
	for d: float in VICTIMS:
		var m: FruitMinion = MANGO.instantiate()
		m.respawn_time = 0.0
		m.facing = -1
		m.position = parent.to_local(to_global(_point_at(d)))
		m.rotation = _angle_at(d)    # standing square on the rails
		parent.add_child(m)
		m.set_physics_process(false)
		m._set_state(FruitMinion.State.IDLE)
		m.sprite.flip_h = true       # facing up the track, at the cart
		_victims.append([m, d, false, false])


# ---------- the track ----------
func _point_at(d: float) -> Vector2:
	d = clampf(d, 0.0, _len)
	for i in range(1, _pts.size()):
		if d <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			return _pts[i - 1].lerp(_pts[i], (d - _cum[i - 1]) / maxf(seg, 0.001))
	return _pts[_pts.size() - 1]


# the track's slope here, smoothed over the corners
func _angle_at(d: float) -> float:
	return (_point_at(d + 8.0) - _point_at(d - 8.0)).angle()


func _physics_process(delta: float):
	_t += delta
	_mode_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if _sealed and not _blocked_ach:      # back up the shaft against the cave-in (Morgan's call, 2026-10-09)
		var p := player.global_position
		if p.x < global_position.x + MOUTH.y + 24.0 and p.y > 0.0 and p.y < 80.0:
			_blocked_ach = true
			Achievements.unlock(get_tree(), "mine_back")
	elif _blocked_ach and not _shame_ach:  # back down to the bottom of the shaft, where the slope meets the floor
		var p := player.global_position
		if p.y > 300.0 and p.x > global_position.x + 520.0 and player.is_on_floor():
			_shame_ach = true
			Achievements.unlock(get_tree(), "shame")
	match _mode:
		Mode.PARKED:
			var c := to_global(_cart_pos)
			var dx := player.global_position.x - c.x
			var dy := player.global_position.y - c.y
			if absf(dx) < GRAB and dy > -GRAB_ABOVE and dy < 20.0:
				_grab()
		Mode.HOPPING:
			# a quick hop up and over the side into the cart
			var k := clampf(_mode_t / HOP_TIME, 0.0, 1.0)
			var seat := to_global(_cart_pos + SEAT.rotated(_cart_angle))
			player.global_position = _hop_from.lerp(seat, k) + Vector2(0, -24.0 * 4.0 * k * (1.0 - k))
			if k >= 1.0:
				_mode = Mode.RIDING
				_mode_t = 0.0
				_wagon_start()
		Mode.RIDING:
			_ride(delta)
		Mode.FLIPPING:
			# the cart rears up over the buffer and flips end over end, till it comes down
			_cart_vel.y += GRAVITY * delta
			_cart_pos += _cart_vel * delta
			_cart_angle += _cart_spin * delta
			if _cart_pos.y >= GROUND_Y - 8.0 and _cart_vel.y > 0.0:
				_shatter()
	if _mode == Mode.HOPPING or _mode == Mode.RIDING:
		for v: Array in _victims:
			if not v[2] and _d + PANIC_AT >= float(v[1]) and is_instance_valid(v[0]):
				v[2] = true
				v[0]._set_state(FruitMinion.State.NOTICE)     # "!"
	_update_bits(delta)
	# the headlamp: lit only underground (on the surface it would just be a bright blob)
	var depth := clampf((to_global(_cart_pos).y - 40.0) / 120.0, 0.0, 1.0)
	_lamp.energy = 0.0 if _mode == Mode.DONE else depth * (1.1 + sin(_t * 31.0) * 0.05)
	_lamp.position = _cart_pos + Vector2.from_angle(_cart_angle) * 46.0 + Vector2(0, -16).rotated(_cart_angle)
	_back.queue_redraw()
	_front.queue_redraw()
	_fx.queue_redraw()


func _grab():
	_mode = Mode.HOPPING
	_mode_t = 0.0
	_hop_from = player.global_position
	_speed = maxf(absf(player.velocity.x), START_SPEED)
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.facing = 1
	_sprite.play(RIDE_POSE[0])
	_sprite.frame = mini(RIDE_POSE[1], _sprite.sprite_frames.get_frame_count(RIDE_POSE[0]) - 1)
	_sprite.pause()
	_sprite.flip_h = false


func _ride(delta: float):
	var ang := _angle_at(_d)
	var accel := GRAVITY * sin(ang) - DRAG
	if _d < 80.0:
		accel += PUSH                # the flat top: it gets going
	_speed = clampf(_speed + accel * delta, 120.0, TOP_SPEED)
	_d += _speed * delta
	_wheel += _speed / 4.0 * delta
	var k := _speed / TOP_SPEED
	_jolt = (Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * k * 1.4).round()
	_cart_pos = _point_at(_d)
	_cart_angle = ang
	var dir := Vector2.from_angle(ang)
	# carry the rider, leaning with the track
	player.global_position = to_global(_cart_pos + SEAT.rotated(ang) + _jolt)
	player.velocity = dir * _speed
	_sprite.rotation = ang * 0.8
	# everything on the track goes under the wheels
	for v: Array in _victims:
		if not v[3] and _d + HIT_AT >= float(v[1]):
			_smash(v, dir)
	for b: Array in _barricades:
		if not b[1] and _d + HIT_AT >= float(b[0]):
			_break_barricade(b, dir)
	# sparks off the wheels where it's steep and fast
	if ang > 0.3 and randf() < delta * 60.0 * k:
		for wx in [-9.0, 9.0]:
			var at: Vector2 = _cart_pos + Vector2(wx, 0).rotated(ang)
			for i in 2:
				var back := -dir * randf_range(60.0, 220.0) + Vector2(randf_range(-40.0, 40.0), -randf_range(20.0, 140.0))
				_sparks.append([at, back, randf_range(0.15, 0.4), SPARKS.pick_random()])
	# speed lines streaming past
	if _speed > 380.0 and randf() < delta * 40.0 * k:
		var side := Vector2(0, randf_range(-60.0, 6.0)).rotated(ang)
		_streaks.append([_cart_pos + side + dir * randf_range(-10.0, 60.0), dir, randf_range(10.0, 26.0) * k, 0.18])
	if _d + CART_HALF >= _len - 1.0:
		_crash()


# a Mango goes under the cart: juice bursts out, stains the rails and the wall, splatters the cart
func _smash(v: Array, dir: Vector2):
	v[3] = true
	var m = v[0]
	if not is_instance_valid(m):
		return
	var feet: Vector2 = m.global_position
	var juice: Color = m.juice_color
	m.take_hit(99, dir * 420.0 + Vector2(0, -260))
	var spray: Node2D = JuiceSpray.new()
	spray.color = juice
	spray.aim = (dir + Vector2(0, -0.8)).normalized()
	spray.power = 1.5
	spray.floor_y = feet.y + 2.0
	spray.position = get_parent().to_local(feet + Vector2(0, -12))
	get_parent().add_child(spray)
	var here := to_local(feet)
	var up := dir.rotated(-PI / 2.0)
	var tones := [juice, juice.darkened(0.25), juice.lightened(0.25), juice.lightened(0.55)]
	for i in 8:                      # puddles and pulp along the rails ahead
		_stain(here + dir * randf_range(-6.0, 36.0) + up * randf_range(0.0, 3.0), randi_range(1, 3), tones.pick_random(), 0)
	for i in 7:                      # sprayed up the tunnel wall, dripping
		_stain(here + up * randf_range(14.0, 80.0) + dir * randf_range(-10.0, 50.0), randi_range(1, 4), tones.pick_random(), randi_range(0, 6))
	for i in 7:                      # and all over the cart's side
		_splats.append([Vector2(randi_range(2, 16), randi_range(-24, -10)), tones.pick_random()])
	while _splats.size() > MAX_SPLATS:
		_splats.pop_front()
	EnemyKit.hitstop(get_tree(), 0.03)
	if player.has_method("_shake"):
		player._shake(5.0, 0.12)
	_splat.play()
	_speed *= HIT_SLOW


# the cart bursts through a barricade: boards and posts fly on ahead, splinters and dust, a crack and a jolt
func _break_barricade(b: Array, dir: Vector2):
	b[1] = true
	var at := _point_at(float(b[0]))
	var base := dir * _speed * 0.7
	for by in [-54.0, -40.0, -26.0, -12.0]:                       # the boards
		_debris.append([at + Vector2(randf_range(-4.0, 4.0), by), base + Vector2(randf_range(-60.0, 160.0), -randf_range(80.0, 320.0)),
			randf() * TAU, randf_range(-16.0, 16.0), Vector2(26, 5), false, 0.0, WOOD])
	for px in [-9.0, 9.0]:                                         # the posts, snapped
		_debris.append([at + Vector2(px, -40.0), base * 0.6 + Vector2(randf_range(-40.0, 80.0), -randf_range(120.0, 260.0)),
			randf() * TAU, randf_range(-10.0, 10.0), Vector2(4, 30), false, 0.0, WOOD_DARK])
	_debris.append([at + Vector2(0, -60.0), base + Vector2(randf_range(0.0, 100.0), -randf_range(200.0, 360.0)),
		randf() * TAU, randf_range(-18.0, 18.0), Vector2(26, 6), false, 0.0, STRIPE_RED])   # the warning board
	_burst(at + Vector2(0, -30.0), [WOOD_LIGHT, WOOD, WOOD_DARK], (dir + Vector2(0, -0.4)).normalized(), 1.4)
	_burst(at + Vector2(0, -4.0), [DUST], Vector2(0, -1), 0.8)
	EnemyKit.hitstop(get_tree(), 0.045)
	if player.has_method("_shake"):
		player._shake(8.0, 0.15)
	_crack.pitch_scale = randf_range(0.9, 1.15)
	_crack.play(CLANG_SOUND_SKIP)
	_speed *= BARRICADE_SLOW


# a barricade standing across the track: two posts, boards nailed across, an X brace, a striped board on top
func _draw_barricade(c: Node2D, at: Vector2):
	for px in [-11.0, 7.0]:
		c.draw_rect(Rect2(at.x + px, at.y - 62.0, 4, 62), WOOD_DARK)
		c.draw_rect(Rect2(at.x + px, at.y - 62.0, 1, 62), WOOD)
	for by in [-54.0, -40.0, -26.0, -12.0]:
		c.draw_rect(Rect2(at.x - 14.0, at.y + by, 28, 6), WOOD)
		c.draw_rect(Rect2(at.x - 14.0, at.y + by, 28, 1), WOOD_LIGHT)
		c.draw_rect(Rect2(at.x - 14.0, at.y + by + 5.0, 28, 1), WOOD_DARK)
		c.draw_rect(Rect2(at.x - 10.0, at.y + by + 2.0, 1, 1), IRON_SHADE)   # nails
		c.draw_rect(Rect2(at.x + 9.0, at.y + by + 2.0, 1, 1), IRON_SHADE)
	c.draw_line(at + Vector2(-12, -50), at + Vector2(12, -10), WOOD_DARK, 2.0)
	c.draw_line(at + Vector2(12, -50), at + Vector2(-12, -10), WOOD_DARK, 2.0)
	for i in 7:
		c.draw_rect(Rect2(at.x - 14.0 + i * 4.0, at.y - 62.0, 4, 6), STRIPE_RED if i % 2 == 0 else STRIPE_WHITE)


func _stain(pos: Vector2, size: int, color: Color, drip: int):
	_stains.append([pos.round(), size, color, drip])
	while _stains.size() > MAX_STAINS:
		_stains.pop_front()


# the bottom: it slams into the buffer, you fly on into the sand, it flips
func _crash():
	_mode = Mode.FLIPPING
	_mode_t = 0.0
	_wagon_out = _real()
	_clang.play(CLANG_SOUND_SKIP)
	_crash_sound.play()
	if player.has_method("_shake"):
		player._shake(12.0, 0.45)
	_release()
	_cart_vel = Vector2(_speed * 0.35, -300.0)
	_cart_spin = 11.0
	var buffer := Vector2(BUFFER_X, GROUND_Y - 10.0)
	for i in 26:
		_sparks.append([buffer, Vector2(-randf_range(40.0, 260.0), -randf_range(60.0, 320.0)), randf_range(0.2, 0.6), SPARKS.pick_random()])
	_burst(buffer, [DUST, WOOD_LIGHT, WOOD_DARK], Vector2(-0.4, -1), 1.0)
	get_tree().call_group("living_background", "burst", to_global(buffer), 5.0)
	_slow_from = _real()             # slow motion as it hits (re-applied in _process: hit-freezes reset it)
	Engine.time_scale = SLOW_SCALE
	_seal_mouth.call_deferred()


# the crash brings the tunnel mouth down behind you: rubble fills it (the mountain blocks the way over)
func _seal_mouth():
	_sealed = true
	var body := StaticBody2D.new()
	body.name = "WallMineMouthRubble"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(MOUTH.y - MOUTH.x, 64.0)
	shape.shape = rect
	shape.position = Vector2((MOUTH.x + MOUTH.y) / 2.0, 32.0)
	body.add_child(shape)
	add_child(body)


func _release():
	if _sprite:
		_sprite.rotation = 0.0
		_sprite.play()
	player.set_physics_process(true)
	player.launch(THROW, THROW_HOLD)


# the cart hits the ground and breaks up: side panels and the frame tumble, the wheels roll off into the sand
func _shatter():
	_mode = Mode.DONE
	var at := _cart_pos
	var base := _cart_vel * 0.4
	for p: Array in [[Vector2(14, 5), IRON], [Vector2(14, 5), RUST_DARK], [Vector2(10, 4), IRON_SHADE], [Vector2(12, 3), IRON_RIM], [Vector2(24, 2), IRON_SHADE]]:
		_debris.append([at + Vector2(randf_range(-8.0, 8.0), -randf_range(4.0, 14.0)), base + Vector2(randf_range(-160.0, 200.0), -randf_range(120.0, 300.0)),
			randf() * TAU, randf_range(-14.0, 14.0), p[0], false, 0.0, p[1]])
	for wx in [-1.0, 1.0]:
		_debris.append([at + Vector2(wx * 9.0, -4.0), base + Vector2(randf_range(120.0, 240.0), -randf_range(100.0, 220.0)), 0.0, 0.0, Vector2(4, 4), true, 0.0, WHEEL])
	_burst(at, SAND, Vector2(0.2, -1), 1.6)
	_burst(at, [DUST], Vector2(0, -1), 1.0)
	if player.has_method("_shake"):
		player._shake(6.0, 0.2)


func _burst(at: Vector2, colors: Array, dir: Vector2, power: float):
	for color: Color in colors:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = int(14 * power)
		p.lifetime = 0.8
		p.explosiveness = 1.0
		p.gravity = Vector2(0, 700)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.0
		p.color = color
		p.z_as_relative = false
		p.z_index = 4                # in front of the sand and the player
		p.position = at
		p.direction = dir
		p.spread = 45.0
		p.initial_velocity_min = 100.0 * power
		p.initial_velocity_max = 280.0 * power
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


# sparks, speed lines and the wreck
func _update_bits(delta: float):
	for s: Array in _sparks:
		s[1].y += 600.0 * delta
		s[0] += s[1] * delta
		s[2] -= delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	for s: Array in _streaks:
		s[0] -= s[1] * _speed * 0.2 * delta
		s[3] -= delta
	_streaks = _streaks.filter(func(s): return s[3] > 0.0)
	for p: Array in _debris:
		p[6] += delta
		p[1].y += 900.0 * delta
		p[0] += p[1] * delta
		var rest := 4.0 if p[5] else minf(p[4].x, p[4].y) / 2.0
		var grounded := false
		if p[0].y >= GROUND_Y - rest and p[1].y >= 0.0:
			p[0].y = GROUND_Y - rest
			p[1].y *= -0.3
			p[1].x *= 0.85 if p[5] else 0.6
			p[3] *= 0.5
			grounded = absf(p[1].y) < 40.0
			if grounded and p[0].x > SAND_X:
				p[0].y += 1.0                       # into the quicksand (its sand hides what sinks)
		if p[5]:
			p[2] += p[1].x / 4.0 * delta            # the wheels roll
			if grounded:
				p[1].x = move_toward(p[1].x, 0.0, 120.0 * delta)
		else:
			p[2] += p[3] * delta
	_debris = _debris.filter(func(p): return p[6] < DEBRIS_LIFE)


# ---------- slow motion (real time) ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float):
	_update_wagon()
	if _slow_from < 0.0:
		return
	if Engine.time_scale == 0.0:         # the counter or the flash stopped time: they restart it themselves
		_slow_from = -1.0
		return
	var t := _real() - _slow_from
	if t < SLOW_HOLD:
		Engine.time_scale = SLOW_SCALE
	elif t < SLOW_HOLD + SLOW_EASE:
		var k := (t - SLOW_HOLD) / SLOW_EASE
		Engine.time_scale = lerpf(SLOW_SCALE, 1.0, k * k)
	else:
		Engine.time_scale = 1.0
		_slow_from = -1.0


# ---------- the wheels' grinding loop (real time, so slow motion doesn't stretch the crossfades) ----------
func _wagon_start():
	_wagon_on = true
	_wagon_cur = 0
	_wagon_xfade = -1.0
	_wagon_out = -1.0
	_wagon[0].volume_db = WAGON_DB.x            # (no loud first frame before _process sets it)
	_wagon[0].pitch_scale = WAGON_PITCH.x
	_wagon[0].play(WAGON_LOOP_FROM)


func _update_wagon():
	if not _wagon_on:
		return
	var now := _real()
	var k := clampf(_speed / TOP_SPEED, 0.0, 1.0)
	var level := db_to_linear(lerpf(WAGON_DB.x, WAGON_DB.y, k))
	var pitch := lerpf(WAGON_PITCH.x, WAGON_PITCH.y, k)
	if _wagon_out >= 0.0:
		var left := 1.0 - clampf((now - _wagon_out) / WAGON_OUT, 0.0, 1.0)
		if left <= 0.0:
			for w: AudioStreamPlayer in _wagon:
				w.stop()
			_wagon_on = false
			return
		level *= left
	var cur := _wagon[_wagon_cur]
	var nxt := _wagon[1 - _wagon_cur]
	if _wagon_xfade < 0.0:
		# the crossfade takes WAGON_FADE real seconds, which is WAGON_FADE * pitch of the file
		if not cur.playing or cur.get_playback_position() >= WAGON_LOOP_TO - WAGON_FADE * pitch:
			nxt.play(WAGON_LOOP_FROM)
			_wagon_xfade = now
	var gain_cur := 1.0
	var gain_nxt := 0.0
	if _wagon_xfade >= 0.0:
		var f := clampf((now - _wagon_xfade) / WAGON_FADE, 0.0, 1.0)
		gain_cur = cos(f * PI / 2.0)                 # equal power: no dip in the middle
		gain_nxt = sin(f * PI / 2.0)
		if f >= 1.0:
			cur.stop()
			_wagon_cur = 1 - _wagon_cur
			_wagon_xfade = -1.0
	for pair: Array in [[cur, gain_cur], [nxt, gain_nxt]]:
		var w: AudioStreamPlayer = pair[0]
		w.pitch_scale = pitch
		w.volume_db = linear_to_db(maxf(level * float(pair[1]), 0.0001))


func _exit_tree():
	if (_mode == Mode.HOPPING or _mode == Mode.RIDING) and is_instance_valid(player):
		player.set_physics_process(true)  # removed mid-ride (scene reload): give the player back
		if _sprite:
			_sprite.rotation = 0.0
	if _slow_from >= 0.0:
		Engine.time_scale = 1.0


# ---------- drawing ----------
func _draw_back():
	var c := _back
	# sleepers under the track, then the rail on top (a light top edge, a dark underside)
	var d := 0.0
	while d <= _len:
		c.draw_set_transform(_point_at(d), _angle_at(d))
		c.draw_rect(Rect2(-2, 0, 4, 3), WOOD_DARK)
		c.draw_rect(Rect2(-2, 0, 4, 1), WOOD)
		d += 10.0
	c.draw_set_transform(Vector2.ZERO)
	for i in range(1, _pts.size()):
		c.draw_line(_pts[i - 1] + Vector2(0, -1), _pts[i] + Vector2(0, -1), STEEL, 1.0)
		c.draw_line(_pts[i - 1], _pts[i], STEEL_SHADE, 1.0)
	# the buffer stop at the bottom: a block striped red and white, an iron plate on its face
	for i in 6:
		c.draw_rect(Rect2(BUFFER_X, GROUND_Y - 18.0 + i * 3.0, 12, 3), STRIPE_RED if i % 2 == 0 else STRIPE_WHITE)
	c.draw_rect(Rect2(BUFFER_X + 10.0, GROUND_Y - 18.0, 2, 18), WOOD_DARK)
	c.draw_rect(Rect2(BUFFER_X - 2.0, GROUND_Y - 14.0, 2, 10), IRON_SHADE)
	for b: Array in _barricades:
		if not b[1]:
			_draw_barricade(c, _point_at(float(b[0])))
	# the juice: puddles on the track, splashes up the wall dripping down
	for s: Array in _stains:
		var p: Vector2 = s[0]
		var size: int = s[1]
		c.draw_rect(Rect2(p, Vector2(size, maxi(1, size - 1))), s[2])
		if s[3] > 0:
			c.draw_rect(Rect2(p + Vector2(0, size), Vector2(1, s[3])), s[2])
	_draw_mouth(c)


# the timber frame over the mine's mouth, with its sign and a lantern
func _draw_mouth(c: Node2D):
	if _sealed:                                                     # caved in: stones and earth fill the tunnel mouth
		c.draw_rect(Rect2(MOUTH.x, MOUTH_TOP + 8.0, MOUTH.y - MOUTH.x, 64.0 - MOUTH_TOP - 8.0), RUBBLE[2])
		var rng := RandomNumberGenerator.new()
		rng.seed = 5040
		for i in 46:
			var bw := float(rng.randi_range(8, 22))
			var r := Rect2(roundf(rng.randf_range(MOUTH.x - 2.0, MOUTH.y - bw + 2.0)), roundf(rng.randf_range(MOUTH_TOP + 8.0, 52.0)), bw, float(rng.randi_range(6, 12)))
			c.draw_rect(r, RUBBLE[rng.randi() % 2])
			c.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), RUBBLE[2])
		c.draw_line(Vector2(MOUTH.x + 6.0, -24.0), Vector2(MOUTH.y - 10.0, -34.0), WOOD_DARK, 3.0)   # a fallen beam
	for x: float in [MOUTH.x, MOUTH.y]:
		c.draw_rect(Rect2(x - 4.0, MOUTH_TOP, 8, -MOUTH_TOP), WOOD)
		c.draw_rect(Rect2(x - 4.0, MOUTH_TOP, 1, -MOUTH_TOP), WOOD_LIGHT)
		c.draw_rect(Rect2(x + 2.0, MOUTH_TOP, 2, -MOUTH_TOP), WOOD_DARK)
		for y in range(int(MOUTH_TOP) + 14, 0, 22):                    # rings in the timber
			c.draw_rect(Rect2(x - 4.0, y, 8, 1), WOOD_DARK)
	c.draw_line(Vector2(MOUTH.x + 4.0, -36.0), Vector2(MOUTH.x + 30.0, MOUTH_TOP + 2.0), WOOD_DARK, 3.0)   # braces
	c.draw_line(Vector2(MOUTH.y - 4.0, -36.0), Vector2(MOUTH.y - 30.0, MOUTH_TOP + 2.0), WOOD_DARK, 3.0)
	c.draw_rect(Rect2(MOUTH.x - 10.0, MOUTH_TOP - 8.0, MOUTH.y - MOUTH.x + 20.0, 9), WOOD)          # the lintel
	c.draw_rect(Rect2(MOUTH.x - 10.0, MOUTH_TOP - 8.0, MOUTH.y - MOUTH.x + 20.0, 1), WOOD_LIGHT)
	c.draw_rect(Rect2(MOUTH.x - 10.0, MOUTH_TOP, MOUTH.y - MOUTH.x + 20.0, 1), WOOD_DARK)
	for x: float in [MOUTH.x - 10.0, MOUTH.y + 7.0]:
		c.draw_rect(Rect2(x, MOUTH_TOP - 8.0, 3, 9), WOOD_DARK)                                  # log ends
	# the sign, hung on two ropes, creaking a little
	var mid := (MOUTH.x + MOUTH.y) / 2.0
	var swing := roundf(sin(_t * 1.7) * 1.0)
	c.draw_line(Vector2(mid - 14.0, MOUTH_TOP + 1.0), Vector2(mid - 14.0 + swing, MOUTH_TOP + 9.0), ROPE, 1.0)
	c.draw_line(Vector2(mid + 14.0, MOUTH_TOP + 1.0), Vector2(mid + 14.0 + swing, MOUTH_TOP + 9.0), ROPE, 1.0)
	var board := Rect2(mid - 18.0 + swing, MOUTH_TOP + 9.0, 36, 14)
	c.draw_rect(board.grow(1.0), WOOD_DARK)
	c.draw_rect(board, WOOD_LIGHT)
	c.draw_rect(Rect2(board.position.x, board.end.y - 2.0, board.size.x, 2), WOOD)
	var w := Pixel.width("MINE", 1)
	Pixel.draw_cells(c, Pixel.cells("MINE", Vector2(roundf(mid - w / 2.0) + swing, board.position.y + 3.0), 1), SIGN_TEXT)
	# a lantern on a chain by the left post
	var lx := MOUTH.x + 18.0
	c.draw_line(Vector2(lx, MOUTH_TOP + 1.0), Vector2(lx, MOUTH_TOP + 7.0), RIVET, 1.0)
	c.draw_rect(Rect2(lx - 3.0, MOUTH_TOP + 7.0, 7, 9), IRON_SHADE)
	c.draw_rect(Rect2(lx - 2.0, MOUTH_TOP + 9.0, 5, 5), LAMP if sin(_t * 23.0) > -0.6 else LAMP.darkened(0.15))
	c.draw_rect(Rect2(lx - 1.0, MOUTH_TOP + 10.0, 1, 2), Color.WHITE)


func _draw_front():
	if _mode != Mode.DONE:
		_front.draw_set_transform(_cart_pos + _jolt, _cart_angle)
		_draw_cart(_front)
		_front.draw_set_transform(Vector2.ZERO)
	for p: Array in _debris:
		var a := 1.0 - clampf((float(p[6]) - (DEBRIS_LIFE - 1.2)) / 1.2, 0.0, 1.0)
		_front.draw_set_transform(p[0], p[2])
		if p[5]:
			_draw_wheel(_front, Vector2.ZERO, 0.0, a)
		else:
			var s: Vector2 = p[4]
			var col: Color = p[7]
			_front.draw_rect(Rect2(-s / 2.0, s), Color(col, a))
			var wood := col == WOOD or col == WOOD_DARK or col == STRIPE_RED     # a barricade's boards and posts
			_front.draw_rect(Rect2(-s.x / 2.0, -s.y / 2.0, s.x, 1), Color(WOOD_LIGHT if wood else IRON_RIM, a))
			if not wood:
				_front.draw_rect(Rect2(-1, -s.y / 2.0 + 1.0, 2, 1), Color(RUST, a))
	_front.draw_set_transform(Vector2.ZERO)


# the cart, in its own frame: forward is +x, the rails at y 0
func _draw_cart(c: Node2D):
	for wx in [-9.0, 9.0]:
		_draw_wheel(c, Vector2(wx, -4), _wheel, 1.0)
	c.draw_rect(Rect2(-12, -8, 24, 2), IRON_SHADE)                                                # the axle frame
	c.draw_colored_polygon(PackedVector2Array([Vector2(-16, -24), Vector2(16, -24), Vector2(13, -9), Vector2(-13, -9)]), IRON)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-14.5, -14), Vector2(14.5, -14), Vector2(13, -9), Vector2(-13, -9)]), IRON_SHADE)
	c.draw_rect(Rect2(-15.5, -20, 31, 1), IRON_SHADE)                                             # iron straps
	for r: Rect2 in RUST_SPOTS:
		c.draw_rect(r, RUST if int(r.position.x) % 2 == 0 else RUST_DARK)
	for x in [-12, -6, 0, 6, 12]:                                                                 # rivets
		c.draw_rect(Rect2(x, -21, 1, 1), RIVET)
		c.draw_rect(Rect2(x, -22, 1, 1), IRON_RIM)
	c.draw_rect(Rect2(-17, -26, 34, 2), IRON_RIM)                                                 # the rim
	c.draw_rect(Rect2(-16, -24, 32, 1), IRON_SHADE)
	c.draw_rect(Rect2(15, -23, 3, 3), LAMP)                                                        # the headlamp
	c.draw_rect(Rect2(17, -23, 1, 1), Color.WHITE)
	for s: Array in _splats:                                                                       # juice all over it
		var p: Vector2 = s[0]
		c.draw_rect(Rect2(p, Vector2(1, 1)), s[1])
		if int(p.x + p.y) % 3 == 0:
			c.draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 2)), s[1])


func _draw_wheel(c: Node2D, at: Vector2, turn: float, a: float):
	c.draw_circle(at, 4.0, Color(WHEEL, a))
	c.draw_arc(at, 3.5, 0.0, TAU, 12, Color(WHEEL_RIM, a), 1.0)
	for i in 3:
		c.draw_line(at, at + Vector2.from_angle(turn + i * TAU / 3.0) * 3.0, Color(SPOKE, a), 1.0)
	c.draw_rect(Rect2(at - Vector2(0.5, 0.5), Vector2(1, 1)), Color(RIVET, a))


func _draw_fx():
	for s: Array in _sparks:
		var p: Vector2 = s[0]
		_fx.draw_rect(Rect2(p.round(), Vector2(1, 1)), s[3])
		_fx.draw_rect(Rect2((p - s[1] * 0.012).round(), Vector2(1, 1)), Color(s[3], 0.5))    # a short trail
	for s: Array in _streaks:
		var p: Vector2 = s[0]
		var dir: Vector2 = s[1]
		_fx.draw_line(p, p - dir * float(s[2]), Color(1, 1, 1, clampf(float(s[3]) / 0.18, 0.0, 1.0) * 0.6), 1.0)
