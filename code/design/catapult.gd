extends Node2D
# THE SAND CATAPULT (level 1, Morgan's idea): a long plank lies hidden under the second half of the
# quicksand, balanced on a buried log, so you don't have to trudge all the way through. The level hangs a
# wall from the top just before it, so you trudge under it close to the sand and can't hop past.
# Halfway under that wall, the Big Pineapple (a cameo before the boss fight) leaps in from off-screen and
# hangs over the plank's far end, winding up a stomp. The moment you step out from under the wall onto the
# plank, it slams down: slow motion as it lands, your end flips up out of the sand and flings you way up
# into the sky, back to full speed as you sail over it and past the sand (Morgan's calls). Then it hops back
# off the way it came. Anything else standing on the plank when it lands is crushed or flung (take_hit).
# Origin: the pivot, on the sand's floor (the plank's middle). Hidden under the quicksand's sand, which is
# drawn in front of it (z 3). PLACEHOLDER: the plank is drawn in code, the Pineapple uses its own sheet.

enum Mode { BURIED, RISING, HANGING, DROPPING, SLAMMED, LEAVING, GONE }

const BOSS := preload("res://scene/design/fruit_boss.tscn")
const SLAM_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const SLAM_SOUND_DB := 0.0
const SLAM_SOUND_SKIP := 0.02        # the file starts with 20ms of silence

const LENGTH := 224.0                # the plank, end to end
const THICK := 9.0
const DEPTH := 2.0                   # its middle sits this far under the floor (all of it under the sand)
const TILT := deg_to_rad(24.0)       # how far it flips when the Pineapple lands (your end up)
const CLEAR := 20.0                  # it slams once you're this far onto the plank: out from under the wall
const FLING_ZONE := 0.6              # you're flung if you're on the near 60% of the plank when it lands
const RISE_TIME := 0.7               # the Pineapple's leap in, up to hang over the far end
const LEAP_FROM := Vector2(360, 0)   # it leaps from here (off-screen, past the far end)
const LEAP_BULGE := 150.0            # how far its leaps arc up over the straight line
const APEX := 90.0                   # it hangs this high over the far end (still on screen), winding up
const HANG_MAX := 4.0                # if you don't come, it stomps anyway after this long
const DROP_TIME := 0.22              # the stomp down onto the plank
const STAY := 0.6                    # it sits on the plank this long, then hops off
const LEAP_OUT := Vector2(520, -420) # where it hops off to, from its end of the plank (off-screen)
const LEAP_OUT_TIME := 0.9
const BOSS_FEET := Vector2(-64, -120)   # its 128x128 frame's top-left, from its feet
const LAND_AT := 30.0                # it lands this far in from the far end
# slow motion from the moment it lands: held, then eased back to full speed as you sail (real seconds)
const SLOW_SCALE := 0.12
const SLOW_HOLD := 0.5
const SLOW_EASE := 0.45
const WOOD := Color(0.55, 0.35, 0.18)
const WOOD_LIGHT := Color(0.69, 0.48, 0.26)
const WOOD_DARK := Color(0.38, 0.25, 0.13)
const NAIL := Color(0.13, 0.09, 0.06)
const SAND_BURST := [Color("efcf86"), Color("d39b4a"), Color("a8722f")]   # the quicksand's own colours

@export var trigger_at := -182.0          # the Pineapple comes when you're here (from the pivot): halfway under the wall
@export var fling := Vector2(220, -1350)  # way up (about 930px) and about 600px on: over it, past the sand
@export var fling_hold := 2.8             # no steering until you're down, so the arc goes where it's aimed

var player: CharacterBody2D = null
var _mode: Mode = Mode.BURIED
var _mode_t := 0.0
var _t := 0.0
var _angle := 0.0                    # the plank's tilt (positive: the far end down, your end up)
var _frames: SpriteFrames
var _boss_pos := Vector2.ZERO        # the Pineapple's feet (local)
var _boss_from := Vector2.ZERO
var _boss_to := Vector2.ZERO
var _flung := false
var _refling := false                # the frame after the fling: the quicksand weakens a jump out of it,
                                     # so the fling is put back the next frame
var _slow_from := -1.0               # real time the slow motion started (-1: not running it)
var _slam_sound := AudioStreamPlayer.new()


func _ready():
	z_index = -1                     # behind the player, and under the quicksand's sand (z 3)
	process_physics_priority = 20    # after the player and the quicksand (10) have moved this frame
	_slam_sound.stream = SLAM_SOUND
	_slam_sound.volume_db = SLAM_SOUND_DB
	add_child(_slam_sound)
	_frames = _boss_frames()


# the Pineapple's sheet, read from its scene without making one
func _boss_frames() -> SpriteFrames:
	var state := BOSS.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != "Sprite":
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == "sprite_frames":
				return state.get_node_property_value(i, j)
	return null


func _physics_process(delta: float):
	_t += delta
	_mode_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
	if _refling:
		_refling = false
		player.velocity = fling + Vector2(0, player.get_gravity().y * delta)
	var near := -LENGTH / 2.0
	var far := Vector2(LENGTH / 2.0 - LAND_AT, 0.0)
	var feet := player.global_position - global_position
	var on_plank := feet.x >= near + CLEAR and feet.x <= near + LENGTH * FLING_ZONE
	match _mode:
		Mode.BURIED:
			if feet.x >= trigger_at and feet.x <= near + LENGTH * FLING_ZONE and absf(feet.y) < 12.0:
				_set_mode(Mode.RISING)
				_boss_from = far + LEAP_FROM
				_boss_to = far + Vector2(0, -APEX)
		Mode.RISING:
			var k := clampf(_mode_t / RISE_TIME, 0.0, 1.0)
			var e := 1.0 - (1.0 - k) * (1.0 - k)                      # slows into the top of its leap
			_boss_pos = _boss_from.lerp(_boss_to, e) + Vector2(0, -LEAP_BULGE * 4.0 * e * (1.0 - e))
			if k >= 1.0:
				_set_mode(Mode.HANGING)
		Mode.HANGING:
			# hangs there winding up, bobbing, till you're out from under the wall and on the plank
			_boss_pos = _boss_to + Vector2(0, roundf(sin(_t * 9.0) * 2.0))
			if on_plank or _mode_t >= HANG_MAX:
				_set_mode(Mode.DROPPING)
				_boss_from = _boss_pos
		Mode.DROPPING:
			var k := clampf(_mode_t / DROP_TIME, 0.0, 1.0)
			_boss_pos = _boss_from.lerp(far, k * k)                    # faster and faster
			if k >= 1.0:
				_slam(feet)
		Mode.SLAMMED:
			# the plank snaps over, overshoots a little and settles; the Pineapple rides its end down
			var k := clampf(_mode_t / 0.07, 0.0, 1.0)
			_angle = TILT * (1.0 - pow(1.0 - k, 3.0)) + sin(clampf(_mode_t - 0.07, 0.0, 0.5) * 30.0) * 0.04 * maxf(0.0, 1.0 - _mode_t * 2.0)
			_boss_pos = _end(1.0)
			if _mode_t >= STAY:
				_set_mode(Mode.LEAVING)
				_boss_from = _boss_pos
				_boss_to = _boss_pos + LEAP_OUT
		Mode.LEAVING:
			var k := clampf(_mode_t / LEAP_OUT_TIME, 0.0, 1.0)
			_boss_pos = _boss_from.lerp(_boss_to, k) + Vector2(0, -LEAP_BULGE * 4.0 * k * (1.0 - k))
			if k >= 1.0:
				_set_mode(Mode.GONE)
		Mode.GONE:
			# missed it (walked back, or wasn't on the plank): it sets itself again once you're back under the wall
			if not _flung and feet.x < trigger_at - 30.0:
				_angle = 0.0
				_set_mode(Mode.BURIED)
	queue_redraw()


func _set_mode(m: Mode):
	_mode = m
	_mode_t = 0.0


# where an end of the plank is now (side -1: your end, 1: where the Pineapple lands), on its top face
func _end(side: float) -> Vector2:
	var along := Vector2(cos(_angle), sin(_angle)) * side * (LENGTH / 2.0 - LAND_AT * (1.0 if side > 0.0 else 0.0))
	return Vector2(0, DEPTH) + along + Vector2(0, -THICK / 2.0).rotated(_angle)


func _slam(feet: Vector2):
	_set_mode(Mode.SLAMMED)
	_slam_sound.play(SLAM_SOUND_SKIP)
	if player.has_method("_shake"):
		player._shake(12.0, 0.35)
	var near := -LENGTH / 2.0
	if feet.x >= near - 10.0 and feet.x <= near + LENGTH * FLING_ZONE and feet.y > -120.0:
		_flung = true
		_refling = true
		player.launch(fling, fling_hold)
	# whatever else is on the plank: crushed at its end, flung off the near end
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not e.has_method("take_hit"):
			continue
		var hp = e.get("hp")
		if hp != null and hp <= 0:
			continue
		var at: Vector2 = e.global_position - global_position
		if absf(at.x) <= LENGTH / 2.0 and absf(at.y) < 40.0:
			e.take_hit(99, Vector2(fling.x, fling.y * 0.7) if at.x < 0.0 else Vector2(80, -200))
	_sand_burst(Vector2(near, 0), Vector2(0.3, -1), 1.0)
	_sand_burst(Vector2(LENGTH / 2.0 - LAND_AT, 0), Vector2(0, -1), 1.6)
	get_tree().call_group("living_background", "burst", global_position, 4.0)
	_slow_from = _real()             # slow motion as it lands (hit-freezes from the crushed ones would end it,
	Engine.time_scale = SLOW_SCALE   # so _process keeps it going)


# ---------- slow motion (real time) ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


# held right as it lands, then eased back to full speed as you sail
func _process(_delta: float):
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


func _exit_tree():
	if _slow_from >= 0.0:                # removed mid-slow-motion (scene reload): never leave the game slowed
		Engine.time_scale = 1.0


func _sand_burst(at: Vector2, dir: Vector2, power: float):
	for color: Color in SAND_BURST:
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
		p.position = at + Vector2(0, -4)
		p.direction = dir
		p.spread = 40.0
		p.initial_velocity_min = 120.0 * power
		p.initial_velocity_max = 300.0 * power
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


func _draw():
	_draw_plank()
	if _mode != Mode.BURIED and _mode != Mode.GONE and _frames:
		_draw_boss()


# two long boards nailed across, pivoting on a log (all of it under the sand until it flips)
func _draw_plank():
	draw_circle(Vector2(0, DEPTH + THICK), 7.0, WOOD_DARK)                     # the log it balances on
	draw_set_transform(Vector2(0, DEPTH), _angle)
	var r := Rect2(-LENGTH / 2.0, -THICK / 2.0, LENGTH, THICK)
	draw_rect(r, WOOD)
	draw_rect(Rect2(r.position, Vector2(LENGTH, 1)), WOOD_LIGHT)
	draw_rect(Rect2(r.position.x, -0.5, LENGTH, 1), WOOD_DARK)                # the seam between the boards
	draw_rect(Rect2(r.position.x, r.end.y - 2.0, LENGTH, 2), WOOD_DARK)
	var x := r.position.x + 10.0
	while x < r.end.x - 4.0:                                                  # cross battens with nails
		draw_rect(Rect2(x, r.position.y, 3, THICK), WOOD_DARK)
		draw_rect(Rect2(x + 1, r.position.y + 2, 1, 1), NAIL)
		draw_rect(Rect2(x + 1, r.end.y - 3, 1, 1), NAIL)
		x += 36.0
	draw_set_transform(Vector2.ZERO)


func _draw_boss():
	var anim := "IDLE_0"
	match _mode:
		Mode.RISING, Mode.LEAVING, Mode.DROPPING:
			anim = "JUMP_0"
		Mode.HANGING:
			anim = "STOMP_WINDUP_0"
		Mode.SLAMMED:
			anim = "LAND_0" if _mode_t < 0.3 else "IDLE_0"
	if not _frames.has_animation(anim):
		anim = "IDLE_0"
	var once := anim != "IDLE_0"                                              # play through, then hold the last frame
	var n := _frames.get_frame_count(anim)
	var f := int((_mode_t if once else _t) * _frames.get_animation_speed(anim))
	f = mini(f, n - 1) if once else f % n
	if _mode == Mode.DROPPING:
		f = n - 1
	var face := -1.0 if _mode != Mode.LEAVING else 1.0                       # facing you, then off away
	draw_set_transform(_boss_pos.round(), 0.0, Vector2(face, 1))
	draw_texture(_frames.get_frame_texture(anim, f), BOSS_FEET)
	draw_set_transform(Vector2.ZERO)
