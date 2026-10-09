extends Node2D
# THE PIRATE SHIP (Morgan's pick, 2026-10-09: "if you can land it that would be siiiick"): while you're in
# level 2's coconut grove (from_x to to_x), a pirate ship sails along the horizon behind it, keeping pace with
# you, and shells you with coconut cannonballs.
#   Where (Morgan's call, 2026-10-09): the second half of the coconut run, an open beach with no palms or
#   coconuts so nothing takes your eye off it. It sails in from the left as you get there (appear_x), cruises,
#   fires from from_x to to_x, keeps you company till leave_x (the lab), then sails on ahead off to the right.
#   The shot: a cannon port on its side flashes, a puff of smoke, a distant boom. You watch the ball come all
#   the way (Morgan's call, 2026-10-09): a dot leaving the ship, it arcs up and comes at you, growing as it
#   closes in (slowly at first, then fast), spinning and trailing smoke, until it's a full-size coconut
#   slamming down. The far part of its flight passes behind the grove's palms, the near part in front of
#   everything (HANDOFF). Where it'll come down (where you'll be if you keep going: your speed x `flight`,
#   give or take), a shadow grows on the sand with a ring tightening round it, and a whistle rises. It bursts
#   in a sandy explosion: you're knocked back and dazed if you're in it (BLAST_R), coconuts in it smash, the
#   grass shakes and the screen with it.
#   Further along it fires two at a time, then three (VOLLEYS by how far along you are).
#   Some come in HIGH (Morgan's call, 2026-10-09: so jumping isn't always the answer, and can trick you): past
#   the first HIGH_FROM of the beach, HIGH_CHANCE of them burst in mid-air at jumping height (AIR_H) instead of
#   on the sand: jump and you're caught, stay down and they go off over your head. They glow red, and their
#   target ring hangs in the air where they'll burst, with a dotted line down to the sand.
#   Some come from BEHIND (BEHIND_CHANCE): out of the ship like the rest, but they hook out to the left, high,
#   and swing back in from behind to land, staying on screen (Morgan's call: they used to come in from off the
#   left edge, not from the ship).
# It's drawn far out on the sea (z -96: in front of the sea and the sun's glitter, behind the dune palms and
# everything in the grove), placed on screen each frame on the living background's horizon. Put it anywhere
# under Hazards.
# PLACEHOLDER art, drawn in code: a dark galleon silhouette lit along its top by the sunset, three masts of
# square sails catching the light, rigging, a Jolly Roger with a coconut skull, a wake, cannon ports.

const Coconut := preload("res://code/design/coconut.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const BOOM_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const IMPACT_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const WHISTLE_SOUND := preload("res://sounds/sword/charge_riser_01.wav")
const HULL := Color("2d2142")
const HULL_DARK := Color("1c152b")
const RIM := Color("c86656")
const RIM_LIGHT := Color("f0a55a")
const SAIL := Color("f3c49a")
const SAIL_SHADE := Color("d8907a")
const ROPE := Color("3f2d55")
const FLAG := Color("1c152b")
const WAKE := Color("f8d8b0")
const FIRE := Color("ffcf4a")
const SMOKE := Color(0.85, 0.78, 0.8)
const SHADOW := Color(0.1, 0.05, 0.12)
const RING := Color("ff7a3a")
const RING_HOT := Color("ff3a2a")
const SAND := Color("e2b47a")
const BLAST_R := 36.0                # the explosion's reach (sideways) on the ground
const CRUISE_X := 330.0              # where it sails on screen (of the 480 across)
const IN_X := -110.0                 # it sails in from here, off the left edge (Morgan's call)
const OUT_X := 600.0                 # and sails off forward to here, off the right edge (not backing off: Morgan)
const ARC := 95.0                    # how high the ball's flight arcs on screen (px, at its middle)
const HANDOFF := 0.6                 # past this much of its flight it's in front of the grove (before: behind)
const NEAR_K := 1.35                 # it closes in slowly, then fast (its progress across the screen: t^NEAR_K)
const BALL_K := 1.35                 # the ball's full size, against a coconut's (bigger: easier to see)
const EMBER := Color("ffb02e")
const EMBER_HOT := Color("fff3b0")
const BOMB_TINT := Color(0.62, 0.55, 0.6)    # its shell, darker than the grove's coconuts'
const FUSE := Color("6b4a2a")
const WHISTLE_FROM := 4.3 - 0.55 * 1.6   # the whistle (4.3s, played at 1.6x) from here ends 0.55s on
const VOLLEYS := [[0.0, 1], [0.4, 2], [0.75, 3]]   # [how far through the grove, how many at a time]
const AIR_H := 64.0                  # a high one bursts this far over the sand (where a jump takes you)
const HIGH_FROM := 0.2               # past this much of the beach,
const HIGH_CHANCE := 0.3             # ...this many of them come in high
const BEHIND_CHANCE := 0.35          # and this many come from behind you (hooking out left, then back in)
const HOOK := Vector2(-220.0, 22.0)  # how far left of its spot a behind shot swings out (x), how high (y, on screen)
const AIR_RED := Color("ff4a3a")     # a high one's glow

@export var appear_x := 0.0          # it sails in once you're past here (Morgan's call: earlier, before the grove)
@export var from_x := 700.0          # the grove: it shells you while you're between these (world x)
@export var to_x := 4300.0
@export var interval := 1.8          # seconds between shots (a little off each time; Morgan's call: was 2.6)
@export var leave_x := -1.0          # it keeps you company, not firing, till here, then sails off (-1: to_x)
@export var flight := 1.25           # from the shot to the explosion

var _player: CharacterBody2D = null
var _bg: Node = null
var _sx := IN_X                      # where it is on screen (x)
var _t := 0.0
var _timer := 1.5
var _flash_t := -1.0                 # the cannon port flashing
var _port := 0
var _shots: Array = []               # {age, land (world), port (screen), spin}
var _smoke: Array = []               # puffs from the cannon: [screen pos, age, radius]
var _fx := Node2D.new()              # the shadows, the falling balls: in the grove (world)
var _snd := {}


func _ready():
	z_as_relative = false
	z_index = -96
	_fx.z_as_relative = false
	_fx.z_index = 4
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_fx.top_level = true
	for k in ["boom", "whistle", "impact", "crash"]:
		var s := AudioStreamPlayer.new()
		s.max_polyphony = 3
		add_child(s)
		_snd[k] = s


func _sound(k: String, stream: AudioStream, pitch: float, db: float, from := 0.0):
	var s: AudioStreamPlayer = _snd[k]
	s.stream = stream
	s.pitch_scale = pitch
	s.volume_db = db
	s.play(from)


func _physics_process(delta: float):
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		_bg = get_tree().get_first_node_in_group("living_background")
		if _player == null:
			return
	_t += delta
	var px := _player.global_position.x
	var active := px >= from_x and px <= to_x
	var leave := leave_x if leave_x >= 0.0 else to_x
	var target := CRUISE_X + sin(_t * 0.4) * 14.0
	if px < appear_x:
		target = IN_X - 30.0                          # (waiting off to the left)
	elif px > leave:
		target = OUT_X + 30.0                         # gone: sailing on ahead, off to the right
	_sx = move_toward(_sx, target, 130.0 * delta)
	if active and absf(_sx - CRUISE_X) < 80.0:       # (once it's sailed in)
		_timer -= delta
		if _timer <= 0.0:
			_timer = interval * randf_range(0.8, 1.2)
			_fire(clampf((px - from_x) / (to_x - from_x), 0.0, 1.0))
	_flash_t -= delta
	for p: Array in _smoke:
		p[1] += delta
		p[0] += Vector2(-8.0, -6.0) * delta
		p[2] += 6.0 * delta
	_smoke = _smoke.filter(func(p): return p[1] < 1.2)
	for sh: Dictionary in _shots:
		sh["age"] += delta
		if sh["age"] >= flight - 0.55 and not sh["whistled"]:
			sh["whistled"] = true
			_sound("whistle", WHISTLE_SOUND, 1.6, -5.0, WHISTLE_FROM)    # (its rising end, ending as it lands)
		if sh["age"] >= flight:
			_explode(sh["land"], bool(sh["high"]))
	_shots = _shots.filter(func(sh): return sh["age"] < flight)
	queue_redraw()
	_fx.queue_redraw()


func _process(_delta: float):
	if _player == null:
		return
	var horizon: float = _bg.get("_horizon") if _bg else 150.0
	var xf := get_viewport().get_canvas_transform()
	global_position = (xf.affine_inverse() * Vector2(roundf(_sx), roundf(horizon + 3.0 + sin(_t * 1.6) * 1.0))).round()


# a shot (or a few): the port flashes, smoke, a boom, and each ball's landing spot picked: where you'll be
func _fire(along: float):
	var count := 1
	for v: Array in VOLLEYS:
		if along >= v[0]:
			count = v[1]
	_port = randi() % 4
	_flash_t = 0.12
	_smoke.append([_port_screen(_port), 0.0, 3.0])
	_sound("boom", BOOM_SOUND, 0.55, -18.0)
	var ahead := _player.global_position.x + _player.velocity.x * flight
	for i in count:
		var x := ahead + (i - (count - 1) / 2.0) * 70.0 + randf_range(-25.0, 25.0)
		x = clampf(x, from_x - 100.0, to_x + 80.0)
		_shots.append({"age": -i * 0.12, "land": Vector2(x, _floor_at(x)), "port": _port,
			"spin": randf_range(-12.0, 12.0), "whistled": false,
			"high": along >= HIGH_FROM and randf() < HIGH_CHANCE,
			"behind": randf() < BEHIND_CHANCE})


# the floor's height at x (world): straight down from well above
func _floor_at(x: float) -> float:
	var y := _player.global_position.y
	var skip: Array[RID] = []
	for c in get_tree().get_nodes_in_group("coconut"):                # (the ground, not a coconut on it)
		if c is CollisionObject2D:
			skip.append(c.get_rid())
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, y - 300.0), Vector2(x, y + 400.0), 1, skip)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else y


# a cannon port on its side, on screen
func _port_screen(i: int) -> Vector2:
	return Vector2(roundf(_sx) - 14.0 + i * 8.0, roundf(get_global_transform_with_canvas().origin.y) - 3.0)


# high: an air burst (AIR_H up): no sand, a burst of red sparks, and it only catches you if you're up there
func _explode(land: Vector2, high := false):
	var at := land + Vector2(0, -AIR_H) if high else land
	_sound("impact", IMPACT_SOUND, randf_range(0.85, 1.0), -4.0, 0.02)
	_sound("crash", BOOM_SOUND, randf_range(0.9, 1.1), -8.0)
	if high:
		var sparks := _burst(at, 22, AIR_RED, 240.0, 0.5, 2.0)
		sparks.spread = 180.0
	else:
		_burst(at, 26, SAND, 220.0, 0.7, 3.0)                   # sand
	_burst(at, 10, Coconut.SHELL, 260.0, 0.8, 2.5)              # bits of shell
	_burst(at, 8, Color(1, 0.95, 0.75), 160.0, 0.25, 2.0)       # the flash
	var smoke := _burst(at, 10, SMOKE, 60.0, 1.0, 4.0)
	smoke.gravity = Vector2(0, -40)
	if _player.has_method("_shake"):
		var near := absf(_player.global_position.x - at.x) < 240.0
		_player._shake(6.0 if near else 2.0, 0.2)
	get_tree().call_group("living_background", "burst", land, 2.0 if high else 4.0)
	if high:                                                     # (well over a standing player's head)
		EnemyKit.hurt_player(_player, Rect2(at.x - BLAST_R, at.y - 36.0, BLAST_R * 2.0, 60.0), at.x)
		return
	EnemyKit.hurt_player(_player, Rect2(at.x - BLAST_R, at.y - 52.0, BLAST_R * 2.0, 56.0), at.x)
	for c in get_tree().get_nodes_in_group("coconut"):          # coconuts caught in it smash
		if c is Node2D and absf(c.global_position.x - at.x) < BLAST_R + 12.0 and absf(c.global_position.y - at.y) < 50.0:
			c.take_hit(3, Vector2.ZERO)
			c.take_hit(3, Vector2.ZERO)


func _burst(at: Vector2, amount: int, col: Color, speed: float, life: float, size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 1.0
	p.scale_amount_max = size
	p.color = col
	p.z_as_relative = false
	p.z_index = 5
	get_parent().add_child(p)
	p.global_position = at + Vector2(0, -4)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# ---------- drawing ----------
# where a ball is on screen at u (0 leaving the ship, 1 landing), and how big: from the ship's port to just
# over its landing spot, closing in slowly then fast, arcing up on the way, growing as it nears
func _ball(sh: Dictionary, u: float) -> Array:
	u = clampf(u, 0.0, 1.0)
	var from := _port_screen(int(sh["port"]))
	var end := Vector2(0, -AIR_H) if sh["high"] else Vector2(0, -Coconut.RADIUS)
	var to: Vector2 = get_viewport().get_canvas_transform() * (Vector2(sh["land"]) + end)
	var p := pow(u, NEAR_K)
	var at: Vector2
	if sh["behind"]:
		# a hook: out of the ship, swinging out to the left and high (kept on screen), then back in from behind
		var hook := Vector2(clampf(minf(from.x, to.x) + HOOK.x, 24.0, 456.0), HOOK.y)
		at = from * (1.0 - p) * (1.0 - p) + hook * 2.0 * (1.0 - p) * p + to * p * p
	else:
		at = from.lerp(to, p) + Vector2(0, -ARC * sin(PI * u))
	return [at, lerpf(0.08, 1.0, u * u)]


# a ball at a screen spot, at a size: a dot while it's far, the coconut once it's near; smoke trailing it
# (made easy to see, Morgan's call, 2026-10-09: a glowing coconut bomb, not a dark dot): a fiery trail of
# embers into smoke, an orange halo pulsing round it, and close up a dark coconut with a lit fuse sparking
func _draw_ball(ci: CanvasItem, to_local_xf: Transform2D, sh: Dictionary, u: float):
	var b := _ball(sh, u)
	var k: float = b[1] * BALL_K
	var age: float = sh["age"]
	var flick := 0.5 + 0.5 * sin(age * 40.0)
	var glow: Color = AIR_RED if sh["high"] else EMBER            # (a high one glows red)
	for j in 7:                                                  # its trail: embers, then smoke
		var tb := _ball(sh, u - 0.03 * (j + 1))
		var tk := float(tb[1]) * BALL_K
		var tp: Vector2 = to_local_xf * Vector2(tb[0])
		if j < 3:
			ci.draw_circle(tp, maxf(1.0, (1.5 + 4.0 * tk) * (1.0 - j * 0.2)), Color(glow if j > 0 else EMBER_HOT, 0.85 - j * 0.2))
		else:
			ci.draw_circle(tp, (1.5 + 5.0 * tk) * (1.0 + (j - 3) * 0.3), Color(SMOKE, 0.45 - (j - 3) * 0.1))
	var at: Vector2 = to_local_xf * Vector2(b[0])
	ci.draw_circle(at, 3.0 + 16.0 * k, Color(glow, 0.18 + 0.12 * flick))            # its halo
	ci.draw_circle(at, 2.0 + 10.0 * k, Color(glow, 0.2 + 0.1 * flick))
	if k * Coconut.shell_size().x < 7.0:                         # far off: a glowing ember
		ci.draw_circle(at, maxf(1.5, k * Coconut.RADIUS), glow)
		ci.draw_rect(Rect2(at.round() - Vector2(0.5, 0.5), Vector2(1, 1)), EMBER_HOT)
		return
	ci.draw_set_transform(at, age * float(sh["spin"]), Vector2(k, k))
	Coconut.draw_shell(ci, false, BOMB_TINT)
	var top := Vector2(0, -Coconut.OVAL.y - 1.0)                 # the fuse, and its spark
	ci.draw_line(top, top + Vector2(3, -5), FUSE, 1.5)
	var sp := top + Vector2(3.5, -6.0)
	var arm := 1.5 + 2.0 * flick
	ci.draw_rect(Rect2(sp - Vector2(arm, 0.5), Vector2(arm * 2.0, 1)), EMBER_HOT)
	ci.draw_rect(Rect2(sp - Vector2(0.5, arm), Vector2(1, arm * 2.0)), EMBER_HOT)
	ci.draw_circle(sp, 1.5, EMBER)
	ci.draw_set_transform(Vector2.ZERO)


# the ship, far out on the sea (its waterline at 0, its bow to the right), its cannon smoke, and the balls
# while they're still far off (behind the grove)
func _draw():
	var xf_inv := get_global_transform_with_canvas().affine_inverse()
	for p: Array in _smoke:                                       # smoke from the port, drifting off
		var k: float = p[1] / 1.2
		draw_circle(xf_inv * p[0], p[2], Color(SMOKE, 0.6 * (1.0 - k)))
	for sh: Dictionary in _shots:
		var u: float = float(sh["age"]) / flight
		if u >= 0.0 and u < HANDOFF:
			_draw_ball(self, xf_inv, sh, u)
	# the wake, behind it
	for i in 6:
		var wx := -34.0 - i * 6.0 + fmod(_t * 10.0, 6.0)
		draw_rect(Rect2(roundf(wx), 1, 3, 1), Color(WAKE, 0.6 - i * 0.09))
	# the hull: a raised stern on the left, the deck, the bow rising to a bowsprit on the right
	for x in range(-30, 29):
		var top := -6.0
		if x < -20:
			top = -12.0
		elif x > 18:
			top = -6.0 - (x - 18) * 0.3
		var bottom := 1.0 - (maxf(0.0, -24.0 - x) + maxf(0.0, x - 20.0)) * 0.6
		draw_rect(Rect2(x, top, 1, bottom - top), HULL)
		draw_rect(Rect2(x, top, 1, 1), RIM)                       # lit along its top by the sunset
	draw_rect(Rect2(-30, -12, 10, 1), RIM_LIGHT)
	draw_line(Vector2(28, -9), Vector2(40, -13), HULL, 1.0)       # the bowsprit
	for i in 4:                                                   # cannon ports, one flashing as it fires
		var lit := _flash_t > 0.0 and i == _port
		draw_rect(Rect2(-14 + i * 8, -4, 3, 2), FIRE if lit else HULL_DARK)
	if _flash_t > 0.0:
		draw_circle(Vector2(-13 + _port * 8, -3), 4.0, Color(FIRE, 0.6))
	# masts and sails, catching the light
	for m: Array in [[-14.0, 28.0], [2.0, 36.0], [16.0, 26.0]]:
		var mx: float = m[0]
		var h: float = m[1]
		draw_rect(Rect2(mx, -6.0 - h, 1, h), HULL)
		for s in 2:
			var sy := -6.0 - h + 3.0 + s * (h * 0.42)
			var sh := h * 0.36
			var sw := 12.0 - s * 0.0 - (2.0 if mx > 10.0 else 0.0)
			var billow := 1.0 + sin(_t * 1.3 + mx) * 0.5
			draw_rect(Rect2(mx - sw / 2.0, sy, sw, sh), SAIL)
			draw_rect(Rect2(mx - sw / 2.0, sy + sh - 2.0, sw, 2), SAIL_SHADE)
			draw_rect(Rect2(mx + sw / 2.0, sy + 1.0, roundf(billow), sh - 2.0), SAIL_SHADE)
	# rigging, from the masts' tops to the bow and the stern
	draw_line(Vector2(2, -42), Vector2(40, -13), ROPE, 1.0)
	draw_line(Vector2(2, -42), Vector2(-30, -12), ROPE, 1.0)
	draw_line(Vector2(-14, -34), Vector2(-28, -12), ROPE, 1.0)
	# the Jolly Roger, waving, with a coconut skull
	for fy in 4:
		for fx in 7:
			var wave := roundf(sin(_t * 6.0 + fx * 0.8) * 0.6)
			draw_rect(Rect2(3 + fx, -47 + fy + wave, 1, 1), FLAG)
	draw_rect(Rect2(5, -46, 2, 2), WAKE)
	draw_rect(Rect2(8, -46, 1, 1), WAKE)


# in the grove: each ball's shadow on the sand (growing) with a ring tightening round it, and the ball itself
# once it's near (in front of everything)
func _draw_fx():
	var screen_to_world := get_viewport().get_canvas_transform().affine_inverse()
	for sh: Dictionary in _shots:
		var age: float = sh["age"]
		if age < 0.0:
			continue
		var land: Vector2 = sh["land"]
		var k := clampf(age / flight, 0.0, 1.0)
		var high: bool = sh["high"]
		var w := lerpf(8.0, 36.0, k) * (0.6 if high else 1.0)
		_fx.draw_rect(Rect2((land + Vector2(-w / 2.0, -2.0)).round(), Vector2(roundf(w), 3)), Color(SHADOW, lerpf(0.2, 0.6, k) * (0.6 if high else 1.0)))
		var r := lerpf(48.0, 16.0, k)
		var blink := 0.5 + 0.5 * sin(age * (10.0 + k * 30.0))
		if high:
			# a high one: its target hangs in the air where it'll burst (red rings), a dotted line to the sand
			var air := land + Vector2(0, -AIR_H)
			for y in range(int(air.y + r * 0.4), int(land.y), 4):
				_fx.draw_rect(Rect2(air.x, y, 1, 2), Color(RING_HOT, 0.5 * blink))
			_fx.draw_circle(air, r * 0.7, Color(RING_HOT, 0.1 + 0.1 * k))
			_fx.draw_arc(air, r * 0.7, 0.0, TAU, 32, Color(RING_HOT, (0.5 + 0.5 * k) * blink), 2.0)
			_fx.draw_arc(air, r * 0.4, 0.0, TAU, 24, Color(AIR_RED, (0.4 + 0.6 * k) * blink), 1.5)
		else:
			# the target on the sand (flattened rings, as if lying on it), tightening and blinking faster
			_fx.draw_set_transform(land + Vector2(0, -1), 0.0, Vector2(1.0, 0.3))
			_fx.draw_circle(Vector2.ZERO, r, Color(RING, 0.12 + 0.12 * k))
			_fx.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(RING, (0.5 + 0.5 * k) * blink), 2.0)
			_fx.draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 24, Color(RING_HOT, (0.4 + 0.6 * k) * blink), 1.5)
			_fx.draw_set_transform(Vector2.ZERO)
		if k >= HANDOFF:
			_draw_ball(_fx, screen_to_world, sh, k)
