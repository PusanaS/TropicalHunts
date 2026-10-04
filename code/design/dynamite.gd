extends Node2D
# THE DYNAMITE (level 1's mine, Morgan's idea): at the end of the underground tunnel a stash of TNT sits in
# a pit under a wooden grate, right under your feet. Its wick runs out through the grate, along the floor
# and up the dead-end wall to a frayed tip at waist height. Hit the tip with Q or W (or a charged W in
# reach) and it catches: the spark sputters back down the wick into the TNT, and the end of the tunnel goes
# up. The blast tears open the rock and earth above it (the "plug") and throws you out through the hole:
# very much rightwards, and up and out to the surface. Rubble then fills the crater behind you.
# Origin: the TNT, on the floor's top (global (6600, 320) in level 1). The plug and the rubble are this
# node's own bodies. mine_cave.gd (group "mine_cave") draws the earth around it: open_crater() when the plug
# goes, fill_crater() when the rubble comes.
# You can never be stuck down there: out of reach when it blows, you're thrown out the moment you step
# onto the end platform under the open crater.
# PLACEHOLDER art and effects drawn in code (BOOM's style: flat colours, one shade, whole pixels).

enum Mode { WAITING, BURNING, FIZZING, BLOWN }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const STRIKE_SOUND := preload("res://sounds/sword/sword_hit_metal_01.wav")    # the blade sparks off the wick tip
const STRIKE_SOUND_DB := -4.0
const SIZZLE_SOUND := preload("res://sounds/sword/sword_scrape_01.wav")       # quiet, pitched-up crackles while it burns
const SIZZLE_SOUND_DB := -16.0
const SIZZLE_EVERY := 0.16
const BOOM_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const BOOM_SOUND_DB := 0.0
const IMPACT_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const IMPACT_SOUND_DB := -2.0
const IMPACT_SOUND_SKIP := 0.02     # the file starts with 20ms of silence

# the layout, from the origin (the TNT on the floor). Global y 0 (the surface) is SURFACE_Y here.
const SURFACE_Y := -320.0
const CEILING_Y := -140.0           # the tunnel's ceiling (global y 180)
const PLUG_TOP := Rect2(-200, -320, 560, 180)    # the ground and earth over the tunnel's end (global x 6400..6960, y 0..180)
const PLUG_WALL := Rect2(100, -140, 260, 140)    # the dead-end wall (global x 6700..6960, y 180..320)
const RUBBLE := Rect2(-200, -320, 560, 320)      # what fills the crater afterwards
const WALL_X := 100.0               # the dead-end wall's face
const TIP := Vector2(92, -30)       # the wick's frayed end: what you hit
const STAR_ARM := Color(1.0, 0.96, 0.62)   # the twinkle on the wick's tip
const TIP_BOX := Rect2(-6, -8, 14, 16)           # around the tip
const PIT := Rect2(-46, 0, 112, 24) # the cutaway under the grate
const WICK := [Vector2(12, 7), Vector2(13, 3), Vector2(15, 0), Vector2(18, -2), Vector2(30, -2), Vector2(44, -1),
	Vector2(52, -3), Vector2(60, -2), Vector2(74, -1), Vector2(86, -2), Vector2(95, -3), Vector2(97, -9),
	Vector2(94, -15), Vector2(97, -21), Vector2(94, -27), TIP]   # from the TNT out to the tip
const BURN_SPEED := 90.0            # px a second along the wick (about 1.35s from the tip to the TNT)
const FIZZ_TIME := 0.25             # the bundle flashes this long before it goes
# the launch: straight up this fast, and across so you come down at land_x (on the surface)
const LAUNCH_VY := -1150.0
const LAUNCH_ZONE := Vector2(-220, 100)          # you're thrown if you're this far either side of the TNT (x)
const LATE_LAUNCH_X := -180.0       # out of reach when it blew: you're thrown once you step past here
# the blast throws fruit up with you (Morgan's idea): dizzy Mangos tumbling on arcs that each drift down past
# your chest one after another on the way up, right where your air Q reaches, for a combo in the sky
const MANGO := preload("res://scene/design/fruit_minion.tscn")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const SKY_FRUIT := 6
const SKY_CROSS := Vector2(0.3, 1.45)   # they pass you this long after the throw (game s), spread between
const SKY_AT := Vector2(26, -22)        # where they pass you: in front, at chest height
const SKY_DRIFT_X := Vector2(-80, 80)   # how they drift past you (relative to you, px/s): a little sideways...
const SKY_DRIFT_Y := Vector2(60, 140)   # ...and down, so each starts above you and drops past your front
# W in the air during the throw: a meteor slam, steered on to land_x where a pack of Mangos waits (Morgan's idea)
const METEOR_MAX := 1400.0          # the most it steers you sideways (px/s)
# when the slam opens up, time slows right down and a big W / SLAM! shows over your head, till you press W
# (then it snaps back to full speed for the slam) or you land (Morgan's call)
const SLAM_SLOW := 0.3
# W at the prompt: a scripted ground pound (Morgan's call): a quick somersault, then a dive straight into the
# pack waiting at land_x, landing as the slam's shockwave, with a beat of slow motion on the impact
const POUND_FLIP := 0.28             # the somersault (game seconds)
const POUND_SPEED := 950.0           # the dive (px/s, speeding up)
const SLAM_HOLD_MAX := 3.0           # real seconds: the slow motion never lasts longer than this
const PROMPT := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]   # the SLAM! text: fill, shade, light
const SLAM_FROM := 0.75             # ...but only for the last quarter of the throw: earlier, W does nothing and you
                                    # stay on your arc (Morgan's call: slamming early threw the flight away)
const PLAYER_HALF := 15.0           # the player's capsule: 30 wide, 40 tall
const PLAYER_H := 40.0
const CLEARANCE := 2.0
# slow motion as it blows: held, then eased back to full speed (real seconds)
const SLOW_SCALE := 0.15
const SLOW_HOLD := 0.35
const SLOW_EASE := 0.4
const FLASH_TIME := 0.3             # the white screen flash (real seconds)
const BOOM_LIGHT_TIME := 1.2
const DEBRIS_LIFE := 3.0
const Z_FX := 30                    # the fireball, smoke and debris: over the player and the world

# BOOM's palette, plus the mine's woods and earths
const WOOD := Color(0.55, 0.35, 0.18)
const WOOD_LIGHT := Color(0.69, 0.48, 0.26)
const WOOD_DARK := Color(0.38, 0.25, 0.13)
const PIT_DARK := Color("231d1a")
const PIT_RIM := Color("3a302a")
const SCORCH := Color("120e0c")
const STICK := Color("c43a2a")
const STICK_SHADE := Color("8e2418")
const STICK_LIGHT := Color("e86a52")
const PAPER := Color("e8d8b0")
const ROPE := Color("c9a46a")
const FUSE := Color("c9a46a")
const FUSE_SHADE := Color("8e6a3c")
const ASH := Color("6e6a66")
const ASH_DARK := Color("4a4644")
const IRON := Color("6b6a72")
const IRON_LIGHT := Color("9c9ba4")
const SIGN_RED := Color("a8241c")
const BONE := Color("ecdfdb")
const SPARK := [Color(1, 1, 1), Color("fff3b0"), Color("ffcf4a"), Color("ff9a2e")]
const FIRE_CORE := Color("fff3b0")
const FIRE_MID := Color("ff9a2e")
const FIRE_RIM := Color("d8401c")
const SMOKE := [Color("4a4450"), Color("6b6470"), Color("8a8390")]
const EARTHS := [Color("4a3524"), Color("5e4430"), Color("6b5c4c"), Color("3d2a1c")]
const GRASS := Color("76964a")

@export var land_x := 7900.0        # where the throw comes down (global x, on the surface past the crater)

var player: CharacterBody2D = null
var _names: Array = []
var _mode: Mode = Mode.WAITING
var _mode_t := 0.0
var _t := 0.0
var _blast_t := -1.0                # game time it blew
var _path := PackedVector2Array()   # the wick, a point every pixel, from the TNT to the tip
var _burned := 0.0                  # how much of the wick has burned, from the tip
var _plugs: Array = []
var _launched := false
var _launch_at := 0.0
var _launch_v := Vector2.ZERO
var _throw_time := 0.0              # how long the throw takes, up and back down to the surface
var _sky: Array = []                # the thrown fruit still tumbling: [FruitMinion, spin, out in the open?]
var _sky_thrown := false
var _refling := false               # the frame after the throw: put it back (sand weakens a jump out of it)
var _filled := false
var _sizzle_t := 0.0
var _slow_from := -1.0              # real time the slow motion started (-1: not running it)
var _slam_hold := false             # the slow motion with the W / SLAM! prompt, as the slam opens up
var _slam_held := false             # (it only happens once)
var _slam_hold_from := 0.0
var _prompt: Node2D
var _pound := 0                     # the ground pound: 0 not happening, 1 the somersault, 2 the dive
var _pound_t := 0.0
var _pound_from := Vector2.ZERO
var _sprite: AnimatedSprite2D
var _flash_from := -1.0
var _boom_from := -1.0
var _sparks: Array = []             # [pos, vel, life, max life, size]
var _smoke: Array = []              # [pos, vel, radius, age, life] (age < 0: not started yet)
var _embers: Array = []             # [pos, vel, life, max life, size]
var _debris: Array = []             # [pos, vel, angle, spin, size, colour, age, grass top?]
var _fx: Node2D
var _spark_light: PointLight2D
var _tip_light: PointLight2D       # a little glow on the wick's star, so it stands out in the dark
var _boom_light: PointLight2D
var _flash: ColorRect
var _strike_sound := AudioStreamPlayer.new()
var _sizzle_sound := AudioStreamPlayer.new()
var _boom_sound := AudioStreamPlayer.new()
var _impact_sound := AudioStreamPlayer.new()


func _ready():
	z_index = -1                    # the stash, the wick and the props sit behind the player
	process_physics_priority = 20   # after the player and the quicksand (10) have moved this frame
	for r: Rect2 in [PLUG_TOP, PLUG_WALL]:
		_plugs.append(_body("WallMinePlugTop" if r == PLUG_TOP else "WallMinePlugWall", r))
	_build_wick()
	_fx = Node2D.new()
	_fx.z_as_relative = false
	_fx.z_index = Z_FX
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_spark_light = _light(Color(1.0, 0.75, 0.35), 0.9)
	_tip_light = _light(Color(1.0, 0.95, 0.7), 0.7)
	_tip_light.position = TIP + Vector2(0, -3)
	_tip_light.enabled = true
	_boom_light = _light(Color(1.0, 0.85, 0.55), 7.0)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_prompt = Node2D.new()
	_prompt.draw.connect(_draw_prompt)
	layer.add_child(_prompt)
	var sizzle := AudioStreamRandomizer.new()        # a different pitch each crackle
	sizzle.add_stream(-1, SIZZLE_SOUND)
	sizzle.random_pitch = 1.6
	for s: Array in [[_strike_sound, STRIKE_SOUND, STRIKE_SOUND_DB], [_sizzle_sound, sizzle, SIZZLE_SOUND_DB],
			[_boom_sound, BOOM_SOUND, BOOM_SOUND_DB], [_impact_sound, IMPACT_SOUND, IMPACT_SOUND_DB]]:
		s[0].stream = s[1]
		s[0].volume_db = s[2]
		add_child(s[0])
	_sizzle_sound.max_polyphony = 3
	_sizzle_sound.pitch_scale = 1.5


# a solid block of this node's own (the plug, the rubble): layer 1, like the level's ground
func _body(body_name: String, r: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name           # "Wall...": no grass grows on it
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = r.get_center()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	return body


# a soft round glow, for the burning spark and the blast (the mine is dark: mine_cave.gd)
func _light(color: Color, scale_: float) -> PointLight2D:
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
	var l := PointLight2D.new()
	l.texture = tex
	l.color = color
	l.texture_scale = scale_
	l.energy = 0.0
	l.enabled = false
	add_child(l)
	return l


# the wick as a point every pixel, so the burn creeps along it smoothly
func _build_wick():
	_path.append(WICK[0])
	for i in range(1, WICK.size()):
		var a: Vector2 = WICK[i - 1]
		var b: Vector2 = WICK[i]
		var n := maxi(1, int(ceilf(a.distance_to(b))))
		for k in range(1, n + 1):
			_path.append(a.lerp(b, float(k) / n))


func _wick_length() -> float:
	return float(_path.size() - 1)


# the burning point: `_burned` pixels in from the tip
func _burn_point() -> Vector2:
	var i := clampi(_path.size() - 1 - int(_burned), 0, _path.size() - 1)
	return _path[i]


func _physics_process(delta: float):
	_t += delta
	_mode_t += delta
	_update_particles(delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	if _refling:
		_refling = false
		player.velocity = _launch_v + Vector2(0, player.get_gravity().y * delta)
	_update_sky(delta)
	_update_pound(delta)
	_meteor(delta)
	match _mode:
		Mode.WAITING:
			_check_hit()
		Mode.BURNING:
			_burned += BURN_SPEED * delta
			var at := _burn_point()
			if randf() < delta * 40.0:                        # spits sparks...
				_spark(at, Vector2(randf_range(-60, 60), -randf_range(30, 120)), randf_range(0.15, 0.35))
			if randf() < delta * 14.0:                        # ...and little puffs of smoke
				_smoke.append([at + Vector2(0, -1), Vector2(randf_range(-6, 6), -randf_range(18, 34)), randf_range(1.5, 2.5), 0.0, randf_range(0.5, 0.9)])
			_sizzle_t -= delta
			if _sizzle_t <= 0.0:
				_sizzle_t = SIZZLE_EVERY
				_sizzle_sound.play()
			if _burned >= _wick_length():
				_set_mode(Mode.FIZZING)
				if player.has_method("_shake"):
					player._shake(2.0, FIZZ_TIME)
		Mode.FIZZING:
			if randf() < delta * 60.0:
				_spark(Vector2(randf_range(4, 30), randf_range(4, 12)), Vector2(randf_range(-50, 50), -randf_range(40, 140)), 0.3)
			if _mode_t >= FIZZ_TIME:
				_blast()
		Mode.BLOWN:
			if not _filled:
				# down here with the crater still open (out of reach when it blew, or fallen back in after a
				# throw): thrown out the moment you step under it, so you can never be stuck underground
				var feet := player.global_position - global_position
				if feet.x >= LATE_LAUNCH_X and feet.y > CEILING_Y and player.is_on_floor() \
						and (not _launched or _t - _launch_at > 0.3):
					_launch()
				elif _launched:
					# the rubble only comes once you're up and out (never while you're still down there)
					var out := player.global_position.y < global_position.y + SURFACE_Y - 20.0
					var inside := Rect2(global_position + RUBBLE.position, RUBBLE.size).has_point(player.global_position)
					if out and not inside:
						_fill()
	queue_redraw()
	_fx.queue_redraw()


func _set_mode(m: Mode):
	_mode = m
	_mode_t = 0.0


# ---------- lighting it ----------
func _check_hit():
	var tip := global_position + TIP
	var box := Rect2(tip + TIP_BOX.position, TIP_BOX.size)
	if not EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		_ignite()
		return
	if _names[player.state] == "CHARGED_SMASH":
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var charge: float = player.charge
		if absf(player.global_position.x - tip.x) <= lerpf(radius.x, radius.y, charge):
			_ignite()


func _ignite():
	_set_mode(Mode.BURNING)
	_burned = 0.0
	_strike_sound.play()
	EnemyKit.hitstop(get_tree(), 0.05)
	for i in 16:                                               # the blade throws sparks off the tip
		var dir := Vector2(-randf_range(0.3, 1.0), -randf_range(-0.4, 1.0)).normalized()
		_spark(TIP, dir * randf_range(90.0, 280.0), randf_range(0.25, 0.5))
	_spark_light.enabled = true
	get_tree().call_group("level_hud", "toast", "IT'S LIT!")


func _spark(at: Vector2, vel: Vector2, life: float):
	_sparks.append([at, vel, life, life, 2.0 if randf() < 0.2 else 1.0])


# ---------- the blast ----------
func _blast():
	_set_mode(Mode.BLOWN)
	_blast_t = _t
	for b: StaticBody2D in _plugs:                             # the ground above opens up
		b.queue_free()
	_plugs.clear()
	get_tree().call_group("mine_cave", "open_crater")
	_spark_light.enabled = false
	_boom_light.enabled = true
	_boom_from = _real()
	_flash_from = _real()
	_boom_sound.play()
	_impact_sound.play(IMPACT_SOUND_SKIP)
	if player.has_method("_shake"):
		player._shake(16.0, 0.5)
	get_tree().call_group("living_background", "burst", global_position + Vector2(WALL_X, SURFACE_Y), 7.0)
	_slow_from = _real()
	Engine.time_scale = SLOW_SCALE
	_spawn_blast_fx()
	var feet := player.global_position - global_position
	if feet.x >= LAUNCH_ZONE.x and feet.x <= LAUNCH_ZONE.y and feet.y > CEILING_Y:
		_launch()


# thrown up out of the crater, across to land_x: the vertical speed is fixed and the sideways speed makes
# it come down there. Clamped so the 40px-tall body clears the tunnel ceiling's end on the way up and the
# surface ground's edge on the way out.
func _launch():
	var p := player.global_position
	var g := player.get_gravity().y
	if g <= 0.0:                                               # never divide by a missing gravity below
		g = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var surface := global_position.y + SURFACE_Y
	var vy := LAUNCH_VY
	var h := p.y - surface                                     # how far below the surface you are
	var t := (-vy + sqrt(vy * vy - 2.0 * g * h)) / g           # up and back down to the surface
	var vx := (land_x - p.x) / t
	var lo := -INF
	var ceiling_edge := global_position.x + PLUG_TOP.position.x
	var rise_head := p.y - (global_position.y + CEILING_Y + PLAYER_H)   # feet this high: the head's above the ceiling
	if p.x - PLAYER_HALF < ceiling_edge + CLEARANCE and rise_head > 0.0:
		lo = (ceiling_edge + CLEARANCE + PLAYER_HALF - p.x) / _rise_time(vy, g, rise_head)
	var emerge_edge := global_position.x + PLUG_TOP.end.x
	var hi := (emerge_edge - CLEARANCE - PLAYER_HALF - p.x) / _rise_time(vy, g, h)
	vx = clampf(vx, lo, hi) if lo <= hi else hi
	_launch_v = Vector2(vx, vy)
	player.launch(_launch_v, t)
	_refling = true
	_launched = true
	_launch_at = _t
	_throw_time = t
	EnemyKit.protect_player(t + 0.5)
	if not _sky_thrown:
		_sky_thrown = true
		_throw_fruit(p, _launch_v)


# W pressed too early in the throw: the slam just started (one frame, no sound yet), so put you straight
# back on your arc, still coming down on land_x
func _resume_throw(since: float):
	var g: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var v := _launch_v + Vector2(0, g * since)                 # how fast the arc is going by now
	var left := maxf(_throw_time - since, 0.1)
	v.x = (land_x - player.global_position.x) / left
	player.launch(v, left)


# the fruit the blast throws up with you. You both fall the same way, so only the drift between you counts:
# each one starts where that drift brings it in front of your chest at its own moment
func _throw_fruit(from: Vector2, v: Vector2):
	var parent := (owner.get_node_or_null("Enemies") if owner else null) as Node2D
	if parent == null:
		parent = get_parent() as Node2D
	for i in SKY_FRUIT:
		var cross := lerpf(SKY_CROSS.x, SKY_CROSS.y, float(i) / maxf(SKY_FRUIT - 1.0, 1.0))
		var drift := Vector2(randf_range(SKY_DRIFT_X.x, SKY_DRIFT_X.y), randf_range(SKY_DRIFT_Y.x, SKY_DRIFT_Y.y))
		var m: FruitMinion = MANGO.instantiate()
		m.respawn_time = 0.0
		m.facing = -1
		m.position = parent.to_local(from + SKY_AT - drift * cross)
		parent.add_child(m)
		m.set_collision_mask_value(1, false)       # flies through the rock till it's up out in the open
		m._set_state(FruitMinion.State.HURT)       # knocked silly by the blast: it just flies
		m.sprite.play("DIZZY")
		m.velocity = v + drift
		_sky.append([m, randf_range(-12.0, 12.0) * (1.0 if i % 2 == 0 else -1.0), false])


# the thrown fruit tumble till they land; once they're up above the ground they collide again (so they land
# on it, and join the fight where you come down)
func _update_sky(delta: float):
	if _sky.is_empty():
		return
	var surface := global_position.y + SURFACE_Y
	for f: Array in _sky:
		var m = f[0]
		if not is_instance_valid(m) or m.hp <= 0:
			f[0] = null
			continue
		if not f[2] and m.global_position.y < surface - 6.0 and m.velocity.y > -900.0:
			f[2] = true
			m.set_collision_mask_value(1, true)
		if f[2] and m.is_on_floor():
			m.sprite.rotation = 0.0
			f[0] = null
			continue
		m.sprite.rotation += float(f[1]) * delta
	_sky = _sky.filter(func(f): return f[0] != null)


# W in the air during the throw: the slam drops you straight down, so steer it on to land_x instead, a
# meteor trailing embers into the pack waiting there. Too early in the throw it doesn't happen at all.
func _meteor(delta: float):
	var since := _t - _launch_at
	if not _launched or since > _throw_time + 0.5 or _names.is_empty():
		return
	if not _slam_held and since >= _throw_time * SLAM_FROM and not player.is_on_floor() \
			and _names[player.state] != "DASH_ATTACK_HEAVY_SLAM":
		_slam_held = true                                        # the slam opens up: slow motion, W / SLAM!
		_slam_hold = true
		_slam_hold_from = _real()
		Engine.time_scale = SLAM_SLOW
	if _names[player.state] != "DASH_ATTACK_HEAVY_SLAM":
		return
	if since < _throw_time * SLAM_FROM:
		_resume_throw(since)
		return
	var h := global_position.y + SURFACE_Y - player.global_position.y     # how high over the ground you are
	if h < 4.0:
		return
	var fall: float = player.get_script().DASH_HEAVY_SLAM_SPEED
	var vx := clampf((land_x - player.global_position.x) / maxf(h / fall, 0.05), -METEOR_MAX, METEOR_MAX)
	player.global_position.x += vx * delta
	var at := to_local(player.global_position + Vector2(0, -18))
	for i in 2:
		_embers.append([at + Vector2(randf_range(-6, 6), randf_range(-8, 8)), Vector2(-vx * 0.2 + randf_range(-40, 40), -randf_range(40, 140)), 0.35, 0.35, 2.0 if i == 0 else 1.0])


# how long the throw takes to rise `d` pixels
func _rise_time(vy: float, g: float, d: float) -> float:
	return (-vy - sqrt(maxf(vy * vy - 2.0 * g * d, 0.0))) / g


# the crater fills with rubble behind you, so there's no falling back in
func _fill():
	_filled = true
	call_deferred("_body", "WallMineRubble", RUBBLE)     # not mid-physics-step
	get_tree().call_group("mine_cave", "fill_crater")


func _spawn_blast_fx():
	var center := Vector2(10, -6)
	for i in 70:                                               # embers
		var dir := Vector2.from_angle(randf_range(-PI, 0.0) + randf_range(-0.3, 0.3))
		var life := randf_range(0.6, 1.4)
		_embers.append([center + dir * randf_range(0, 20), dir * randf_range(150, 520), life, life, 2.0 if randf() < 0.3 else 1.0])
	for i in 20:                                               # smoke billows up and out of the crater
		var at := center + Vector2(randf_range(-40, 80), randf_range(-60, 0))
		_smoke.append([at, Vector2(randf_range(10, 120), -randf_range(40, 160)), randf_range(10, 24), -randf_range(0.1, 0.5), randf_range(1.6, 2.8)])
	for i in 34:                                               # the plug flies: rock, earth and turf
		var r: Rect2 = PLUG_TOP if i < 24 else PLUG_WALL
		var at := Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		var turf := r == PLUG_TOP and at.y < SURFACE_Y + 20.0
		var close := clampf(1.0 - at.distance_to(center) / 400.0, 0.2, 1.0)
		_debris.append([at, Vector2(randf_range(60, 420), -randf_range(350, 950) * close), randf() * TAU, randf_range(-10, 10),
			Vector2(randf_range(3, 10), randf_range(3, 8)).round(), EARTHS[randi() % EARTHS.size()], 0.0, turf])
	for prop: Array in [[Vector2(-83, -7), Vector2(14, 14), WOOD], [Vector2(-83, -21), Vector2(14, 14), WOOD],   # crates
			[Vector2(-60, -8), Vector2(12, 16), WOOD_DARK], [Vector2(78, -72), Vector2(40, 24), WOOD_LIGHT]]:     # barrel, sign
		for k in 3:
			_debris.append([prop[0] + Vector2(randf_range(-4, 4), randf_range(-4, 4)), Vector2(randf_range(80, 360), -randf_range(250, 600)),
				randf() * TAU, randf_range(-12, 12), (prop[1] / 2.0).round(), prop[2], 0.0, false])
	_dust_rain()


# dust and grit shaken loose all along the tunnel's ceiling
func _dust_rain():
	var tunnel := Rect2(global_position.x - 1160.0, global_position.y + CEILING_Y, 960.0, 2.0)   # global x 5440..6400
	for k in 2:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = 140 if k == 0 else 40
		p.lifetime = 1.6
		p.explosiveness = 0.15
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = tunnel.size / 2.0
		p.direction = Vector2.DOWN
		p.spread = 10.0
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 20.0
		p.gravity = Vector2(0, 420 if k == 0 else 700)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 1.0 if k == 0 else 2.0
		p.color = EARTHS[1] if k == 0 else EARTHS[2]
		p.z_as_relative = false
		p.z_index = 5
		p.position = to_local(tunnel.get_center())
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


func _update_particles(delta: float):
	for s: Array in _sparks:
		s[0] += s[1] * delta
		s[1].y += 500.0 * delta
		s[2] -= delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	for e: Array in _embers:
		e[0] += e[1] * delta
		e[1] *= 1.0 - 1.5 * delta
		e[1].y += 300.0 * delta
		e[2] -= delta
	_embers = _embers.filter(func(e): return e[2] > 0.0)
	for s: Array in _smoke:
		s[3] += delta
		if s[3] < 0.0:
			continue
		s[0] += s[1] * delta
		s[1] *= 1.0 - 0.8 * delta
		s[2] += delta * 6.0
	_smoke = _smoke.filter(func(s): return s[3] < s[4])
	for d: Array in _debris:
		d[6] += delta
		d[1].y += 980.0 * delta
		d[0] += d[1] * delta
		d[2] += d[3] * delta
	_debris = _debris.filter(func(d): return d[6] < DEBRIS_LIFE)


# ---------- real time: the slow motion, the flash, the lights ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float):
	if _slam_hold:
		var slamming: bool = not _names.is_empty() and _names[player.state] == "DASH_ATTACK_HEAVY_SLAM"
		if Input.is_action_just_pressed("attack_heavy") or slamming:
			_start_pound()                                       # W at the prompt, whatever you were doing
		elif Engine.time_scale == 0.0 or player.is_on_floor() or _real() - _slam_hold_from > SLAM_HOLD_MAX:
			_slam_hold = false                                   # you landed without it: full speed
			if Engine.time_scale != 0.0:
				Engine.time_scale = 1.0
		else:
			Engine.time_scale = SLAM_SLOW                        # (hit-freezes reset it)
		_prompt.queue_redraw()
	if _slow_from >= 0.0:
		if Engine.time_scale == 0.0:     # the counter or the flash stopped time: they restart it themselves
			_slow_from = -1.0
		else:
			var t := _real() - _slow_from
			if t < SLOW_HOLD:
				Engine.time_scale = SLOW_SCALE
			elif t < SLOW_HOLD + SLOW_EASE:
				var k := (t - SLOW_HOLD) / SLOW_EASE
				Engine.time_scale = lerpf(SLOW_SCALE, 1.0, k * k)
			else:
				Engine.time_scale = 1.0
				_slow_from = -1.0
	if _flash_from >= 0.0:
		var k := clampf((_real() - _flash_from) / FLASH_TIME, 0.0, 1.0)
		_flash.color.a = 0.85 * (1.0 - k)
		if k >= 1.0:
			_flash_from = -1.0
	if _boom_from >= 0.0:
		var k := clampf((_real() - _boom_from) / BOOM_LIGHT_TIME, 0.0, 1.0)
		_boom_light.energy = 5.0 * pow(1.0 - k, 2.0)
		_boom_light.position = Vector2(30, -60)
		if k >= 1.0:
			_boom_from = -1.0
			_boom_light.enabled = false
	if _spark_light.enabled:
		_spark_light.position = _burn_point() if _mode == Mode.BURNING else Vector2(18, 6)
		_spark_light.energy = randf_range(0.8, 1.5)
	_tip_light.enabled = _mode == Mode.WAITING                    # the star's glow, pulsing with it
	if _tip_light.enabled:
		_tip_light.energy = 0.75 + 0.3 * sin(_t * 5.0) + (0.5 if fmod(_t, 1.1) < 0.2 else 0.0)


func _exit_tree():
	if _slow_from >= 0.0 or _slam_hold:   # removed mid-slow-motion (scene reload): never leave the game slowed
		Engine.time_scale = 1.0
	if _pound != 0 and is_instance_valid(player):   # removed mid-pound: give the player back
		player.set_physics_process(true)
		if _sprite:
			_sprite.rotation = 0.0


# ---------- the ground pound (W at the prompt) ----------
# it takes over from here: your own physics waits while you somersault and dive (like the surf ride)
func _start_pound():
	_slam_hold = false
	if Engine.time_scale != 0.0:
		Engine.time_scale = 1.0
	_pound = 1
	_pound_t = 0.0
	_pound_from = player.global_position
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_sprite.play("DOUBLE_JUMP")                                  # tucked up for the flip
	if player.has_method("play_swing_sound"):
		player.play_swing_sound(true)
	EnemyKit.protect_player(1.5)
	_prompt.queue_redraw()


func _update_pound(delta: float):
	if _pound == 0:
		return
	_pound_t += delta
	var ground := Vector2(land_x, global_position.y + SURFACE_Y)
	var dir := 1.0 if ground.x >= _pound_from.x else -1.0
	if _pound == 1:                                              # a hop up and on, one full somersault
		var k := clampf(_pound_t / POUND_FLIP, 0.0, 1.0)
		player.global_position = _pound_from + Vector2(dir * 26.0 * k, -22.0 * sin(PI * k))
		_sprite.rotation = dir * TAU * k * k * (3.0 - 2.0 * k)
		if k >= 1.0:
			_pound = 2
			_pound_t = 0.0
			_pound_from = player.global_position
			_sprite.rotation = dir * 0.35                         # leaning into the dive
			_sprite.play("JUMP_FALL")
	else:                                                        # the dive: faster and faster, trailing embers
		var travel := POUND_SPEED * _pound_t * (1.0 + _pound_t * 2.0)
		player.global_position = _pound_from.move_toward(ground, travel)
		var at := to_local(player.global_position + Vector2(0, -18))
		for i in 2:
			_embers.append([at + Vector2(randf_range(-6, 6), randf_range(-8, 8)), Vector2(-dir * randf_range(40, 140), -randf_range(60, 160)), 0.35, 0.35, 2.0 if i == 0 else 1.0])
		if player.global_position.distance_to(ground) < 1.0:
			_pound_impact(dir)


# it hits: you land as the slam's shockwave (the pack around you takes it), a big shake, a beat of slow motion
func _pound_impact(dir: float):
	_pound = 0
	_sprite.rotation = 0.0
	player.set_physics_process(true)
	player.velocity = Vector2.ZERO
	var states: Dictionary = player.get_script().State
	player._set_state(states["DASH_ATTACK_HEAVY_IMPACT"])
	player._shake(14.0, 0.45)
	get_tree().call_group("living_background", "burst", player.global_position, 7.0)
	var at := to_local(player.global_position)
	for i in 30:                                                 # a ring of embers and dirt bursting out
		var v := Vector2.from_angle(randf_range(PI, TAU)) * randf_range(120.0, 360.0)
		_embers.append([at + Vector2(randf_range(-10, 10), -2), v, randf_range(0.3, 0.6), 0.6, 2.0 if i % 3 == 0 else 1.0])
	_impact_sound.play(IMPACT_SOUND_SKIP)
	EnemyKit.protect_player(0.8)
	_slow_from = _real()                                          # the blast's slow-motion curve again, briefly


# a big W key over your head, acting out the press, with SLAM! under it (like the dam's Q / COUNTER!)
func _draw_prompt():
	if not _slam_hold or player == null:
		return
	var t := _real()
	var feet := get_viewport().get_canvas_transform() * player.global_position
	var bounce := roundf(sin(t * 10.0) * 2.0)
	var text_w := Pixel.width("SLAM!", 2)
	var text_y := feet.y - 58.0 + bounce
	_prompt.draw_set_transform(Vector2(roundf(feet.x - 13.0), text_y - 36.0), 0.0, Vector2(2, 2))
	Pixel.draw_key(_prompt, Vector2.ZERO, 13, "W", fmod(t, 0.4) < 0.15, true)
	_prompt.draw_set_transform(Vector2.ZERO)
	Pixel.draw_cells(_prompt, Pixel.cells("SLAM!", Vector2(roundf(feet.x - text_w / 2.0), text_y), 2), PROMPT)


# ---------- drawing: the stash, the wick and the props (behind the player) ----------
func _draw():
	if _mode == Mode.BLOWN:
		_draw_scorch()
		return
	_draw_props()
	_draw_stash()
	_draw_wick()


func _draw_stash():
	draw_rect(PIT, PIT_DARK)
	draw_rect(Rect2(PIT.position.x, PIT.position.y, 1, PIT.size.y), PIT_RIM)
	draw_rect(Rect2(PIT.end.x - 1.0, PIT.position.y, 1, PIT.size.y), PIT_RIM)
	draw_rect(Rect2(PIT.position.x, PIT.end.y - 1.0, PIT.size.x, 1), PIT_RIM)
	# a crate stencilled TNT
	var crate := Rect2(-42, 6, 30, 18)
	draw_rect(crate, WOOD)
	draw_rect(Rect2(crate.position, Vector2(crate.size.x, 1)), WOOD_LIGHT)
	draw_rect(Rect2(crate.position.x, crate.end.y - 2.0, crate.size.x, 2), WOOD_DARK)
	draw_rect(Rect2(crate.position.x, crate.position.y, 2, crate.size.y), WOOD_DARK)
	draw_rect(Rect2(crate.end.x - 2.0, crate.position.y, 2, crate.size.y), WOOD_DARK)
	for c in Pixel.cells("TNT", Vector2(-36, 11), 1):
		draw_rect(c[0], SIGN_RED)
	# a bundle of five sticks, roped together, fuses joined at the top
	for i in 5:
		var x := float(i * 6)
		draw_rect(Rect2(x, 7, 5, 16), STICK)
		draw_rect(Rect2(x, 7, 1, 16), STICK_LIGHT)
		draw_rect(Rect2(x + 4.0, 7, 1, 16), STICK_SHADE)
		draw_rect(Rect2(x, 7, 5, 1), PAPER)
	for y in [11.0, 19.0]:
		draw_rect(Rect2(-1, y, 31, 2), ROPE)
		draw_rect(Rect2(-1, y + 1.0, 31, 1), FUSE_SHADE)
	# loose sticks lying by it
	for i in 3:
		var r := Rect2(36, 18 - i * 5, 16 + (i % 2) * 6, 4)
		draw_rect(r, STICK)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), STICK_LIGHT)
		draw_rect(Rect2(r.end.x - 2.0, r.position.y, 2, r.size.y), PAPER)
	if _mode == Mode.FIZZING and int(_mode_t * 24.0) % 2 == 0:  # about to go: the bundle flashes
		draw_rect(Rect2(-1, 6, 31, 18), Color(1, 0.95, 0.7, 0.75))
	# the grate over it, flush with the floor
	var x := PIT.position.x
	while x < PIT.end.x:
		draw_rect(Rect2(x, 0, 4, 3), WOOD)
		draw_rect(Rect2(x, 0, 4, 1), WOOD_LIGHT)
		x += 7.0
	draw_rect(Rect2(PIT.position.x, 2, PIT.size.x, 1), WOOD_DARK)


# a twisted cord: tan where it's still to burn, grey ash behind the spark
func _draw_wick():
	var burn_i := _path.size() if _mode == Mode.WAITING else _path.size() - 1 - int(_burned)
	for i in _path.size():
		var p := _path[i].round()
		var burnt := i > burn_i
		var twist := int(i / 2.0) % 2 == 0
		var col := (ASH if twist else ASH_DARK) if burnt else (FUSE if twist else FUSE_SHADE)
		draw_rect(Rect2(p, Vector2(1, 2)), col)
	if _mode == Mode.WAITING:
		# the frayed tip, and a bright star shining on it so you spot it in the dark (Morgan wanted it brighter):
		# always there and pulsing, with a big flare now and then
		draw_rect(Rect2(TIP + Vector2(-1, -2), Vector2(1, 1)), FUSE)
		draw_rect(Rect2(TIP + Vector2(1, -2), Vector2(1, 1)), FUSE_SHADE)
		draw_rect(Rect2(TIP + Vector2(0, -3), Vector2(1, 1)), FUSE)
		var c := TIP + Vector2(0, -3)
		var flare := fmod(_t, 1.1) < 0.2
		var arm := 4.0 if flare else (2.0 if sin(_t * 5.0) > 0.0 else 1.0)
		draw_rect(Rect2(c + Vector2(-arm, 0), Vector2(arm * 2.0 + 1.0, 1)), STAR_ARM)
		draw_rect(Rect2(c + Vector2(0, -arm), Vector2(1, arm * 2.0 + 1.0)), STAR_ARM)
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_rect(Rect2(c + d * (2.0 if flare else 1.0), Vector2(1, 1)), Color(STAR_ARM, 0.9 if flare else 0.5))
		draw_rect(Rect2(c, Vector2(1, 1)), Color.WHITE)


func _draw_props():
	var shake := Vector2(randf_range(-1, 1), 0).round() if _mode != Mode.WAITING else Vector2.ZERO
	# crates, a barrel and a pickaxe by the sand's edge
	for y in [-14.0, -28.0]:
		var c := Rect2(-90, y, 14, 14)
		draw_rect(c, WOOD)
		draw_rect(Rect2(c.position, Vector2(14, 1)), WOOD_LIGHT)
		draw_rect(Rect2(c.position.x, c.end.y - 1.0, 14, 1), WOOD_DARK)
		draw_rect(Rect2(c.position.x + 6.0, c.position.y, 2, 14), WOOD_DARK)
	var barrel := Rect2(-66, -16, 12, 16)
	draw_rect(barrel, WOOD_DARK)
	draw_rect(Rect2(barrel.position.x + 1.0, barrel.position.y, 10, 16), WOOD)
	for y in [-14.0, -4.0]:
		draw_rect(Rect2(barrel.position.x, y, 12, 2), IRON)
	draw_line(Vector2(-50, 0), Vector2(-58, -20), WOOD_LIGHT, 1.0)  # the pickaxe, leaning
	draw_rect(Rect2(-63, -22, 10, 2), IRON)
	draw_rect(Rect2(-63, -22, 2, 4), IRON_LIGHT)
	# a DANGER sign hanging on the dead-end wall, rattling once it's lit
	var top := Vector2(78, -92) + shake
	var board := Rect2(top + Vector2(-20, 8), Vector2(40, 24))
	draw_line(top, board.position + Vector2(3, 0), ROPE, 1.0)
	draw_line(top, Vector2(board.end.x - 3.0, board.position.y), ROPE, 1.0)
	draw_rect(Rect2(top - Vector2(1, 1), Vector2(2, 2)), IRON)
	draw_rect(board, WOOD_LIGHT)
	draw_rect(Rect2(board.position.x, board.end.y - 2.0, board.size.x, 2), WOOD_DARK)
	var skull := [".#####.", "#######", "#.###.#", "#######", ".##.##.", ".#.#.#."]
	for row in skull.size():
		var line: String = skull[row]
		for col in line.length():
			if line[col] == "#":
				draw_rect(Rect2(board.position + Vector2(16 + col, 2 + row), Vector2(1, 1)), BONE)
	for c in Pixel.cells("DANGER", board.position + Vector2(3, 10), 1):
		draw_rect(c[0], SIGN_RED)


# after: a blackened hole where the stash was, embers glowing in it for a while
func _draw_scorch():
	draw_rect(PIT, SCORCH)
	draw_rect(Rect2(PIT.position.x, 0, 5, 3), WOOD_DARK)        # stubs of the grate
	draw_rect(Rect2(PIT.end.x - 6.0, 0, 6, 2), WOOD_DARK)
	var glow := 1.0 - clampf((_t - _blast_t) / 4.0, 0.0, 1.0)
	if glow > 0.0:
		for i in 9:
			var p := Vector2(PIT.position.x + 6.0 + fmod(i * 23.0, PIT.size.x - 12.0), 6.0 + fmod(i * 7.0, 16.0))
			if fmod(_t * 3.0 + i * 0.37, 1.0) < 0.7:
				draw_rect(Rect2(p, Vector2(1, 1)), Color(SPARK[3], glow))


# ---------- drawing: the fire, smoke, sparks and debris (over everything) ----------
func _draw_fx():
	for s: Array in _smoke:
		if s[3] < 0.0:
			continue
		var a := 1.0 - clampf(s[3] / s[4], 0.0, 1.0)
		var at: Vector2 = s[0]
		var r: float = s[2]
		_disk(_fx, at, r, Color(SMOKE[0], 0.85 * a))
		_disk(_fx, at + Vector2(-r * 0.2, -r * 0.2), r * 0.7, Color(SMOKE[1], 0.85 * a))
		_disk(_fx, at + Vector2(-r * 0.35, -r * 0.4), r * 0.35, Color(SMOKE[2], 0.85 * a))
	if _blast_t >= 0.0:
		var age := _t - _blast_t
		if age < 1.0:
			_draw_fireball(age)
		if age < 0.5:
			var ring_a := 1.0 - age / 0.5
			_ring(_fx, Vector2(10, -6), minf(20.0 + 700.0 * age, 380.0), 3.0, Color(FIRE_CORE, ring_a))
	for e: Array in _embers:
		var k: float = e[2] / e[3]
		if randf() < 0.15:
			continue                                          # embers flicker
		var col: Color = SPARK[1] if k > 0.6 else (SPARK[2] if k > 0.3 else SPARK[3])
		_fx.draw_rect(Rect2(e[0].round(), Vector2(e[4], e[4])), col)
	for s: Array in _sparks:
		var k: float = s[2] / s[3]
		_fx.draw_rect(Rect2(s[0].round(), Vector2(s[4], s[4])), SPARK[mini(3, int((1.0 - k) * 4.0))])
	if _mode == Mode.BURNING:                                 # the spark itself, sputtering
		var at := _burn_point().round()
		var big := randf() < 0.5
		_fx.draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), SPARK[1])
		_fx.draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 3)), SPARK[1])
		if big:
			_fx.draw_rect(Rect2(at + Vector2(-2, 0), Vector2(5, 1)), Color(SPARK[2], 0.8))
			_fx.draw_rect(Rect2(at + Vector2(0, -2), Vector2(1, 5)), Color(SPARK[2], 0.8))
		_fx.draw_rect(Rect2(at, Vector2(1, 1)), SPARK[0])
	for d: Array in _debris:
		var a := 1.0 - clampf((float(d[6]) - (DEBRIS_LIFE - 0.5)) / 0.5, 0.0, 1.0)
		var s: Vector2 = d[4]
		var col: Color = d[5]
		_fx.draw_set_transform(d[0], d[2])
		_fx.draw_rect(Rect2(-s / 2.0, s), Color(col, a))
		_fx.draw_rect(Rect2(Vector2(-s.x / 2.0, s.y / 2.0 - 1.0), Vector2(s.x, 1)), Color(col.darkened(0.3), a))
		if d[7]:
			_fx.draw_rect(Rect2(-s / 2.0, Vector2(s.x, 2)), Color(GRASS, a))
	_fx.draw_set_transform(Vector2.ZERO)


# layered pixel disks billowing out and up towards the crater, then darkening into smoke
func _draw_fireball(age: float):
	var grow := clampf(age / 0.35, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - grow, 3.0)
	var fade := clampf((age - 0.35) / 0.65, 0.0, 1.0)
	var center := Vector2(10, -6) + Vector2(30, -70) * e
	var r := (30.0 + 110.0 * e) * (1.0 - 0.35 * fade)
	var rim := FIRE_RIM.lerp(SMOKE[0], fade)
	var mid := FIRE_MID.lerp(SMOKE[1], fade)
	var core := FIRE_CORE.lerp(FIRE_MID, fade)
	var alpha := 1.0 - fade * fade
	_disk(_fx, center, r, Color(rim, alpha))
	for i in 9:                                               # billowing lobes round the edge
		var ang := TAU * i / 9.0 + age * 1.5
		var lobe := r * 0.38 * (0.8 + 0.2 * sin(i * 3.0 + age * 20.0))
		_disk(_fx, center + Vector2.from_angle(ang) * r * 0.75, lobe, Color(rim, alpha))
	_disk(_fx, center + Vector2(0, -r * 0.08), r * 0.78, Color(mid, alpha))
	_disk(_fx, center + Vector2(0, -r * 0.12), r * 0.5 * (1.0 - fade), Color(core, alpha))
	if age < 0.1:
		_disk(_fx, center, r * 0.3, Color(1, 1, 1, 1.0 - age / 0.1))


# a filled circle made of whole-pixel rows
func _disk(n: CanvasItem, c: Vector2, r: float, col: Color):
	if r < 0.5 or col.a <= 0.0:
		return
	var cx := roundf(c.x)
	var cy := roundf(c.y)
	var ri := int(r)
	for dy in range(-ri, ri + 1):
		var half := floorf(sqrt(maxf(r * r - dy * dy, 0.0)))
		n.draw_rect(Rect2(cx - half, cy + dy, half * 2.0 + 1.0, 1), col)


# a ring `w` pixels thick, made of whole-pixel rows
func _ring(n: CanvasItem, c: Vector2, r: float, w: float, col: Color):
	if col.a <= 0.0:
		return
	var cx := roundf(c.x)
	var cy := roundf(c.y)
	var inner := maxf(r - w, 0.0)
	for dy in range(-int(r), int(r) + 1):
		var outer := floorf(sqrt(maxf(r * r - dy * dy, 0.0)))
		var hole := floorf(sqrt(maxf(inner * inner - dy * dy, 0.0))) if absf(dy) < inner else -1.0
		n.draw_rect(Rect2(cx - outer, cy + dy, outer - hole, 1), col)
		n.draw_rect(Rect2(cx + hole + 1.0, cy + dy, outer - hole, 1), col)
