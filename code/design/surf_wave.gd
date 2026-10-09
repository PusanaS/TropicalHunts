extends Node2D
# THE SURF RUN (level 1's opening, Morgan's idea): gallop through the long shallows and a wave builds up
# behind you. Keep galloping and it catches you up halfway through building: it picks you up on its face
# and keeps growing under you, carrying you up to the crest (you lean with the slope). Ride it to the end:
# it crashes into a wall too tall to jump and throws you up and over (or jump off the crest yourself,
# double jump and all). Stop galloping before it gets you and it dies down: go back and try again.
# Origin on the floor's top where the run starts; the wall stands `length` further right (the level builds
# it, `wall_height` tall). The floor under the run is named "Shallow..." so it's all water.
# PLACEHOLDER look, drawn in code in the day water colours.
# The sneak peek (Morgan's idea): once the wave is big, the river's watermelon shark (melon_shark.gd) slowly
# rises out of it until about 3/4 of it shows (the rest stays under the water, a line of foam where it breaks
# the surface), chasing you: at the crest bursting out of the
# face at you while the wave's behind you, then just behind your heels while you ride. It lunges and snaps
# its jaws now and then. It's only part of the picture: it can't touch you, and you meet it for real at the
# river.

const SPLASH := preload("res://sounds/WAVE_SOUND_universfield-water-splash-199583.mp3")
const Achievements := preload("res://code/design/achievements.gd")
const SPLASH_DB := -2.0
const SPLASH_SKIP := 0.17        # the file starts with near-silence
# plays as the wave starts to form: its 1.2 s swell matches the wave building, and it's loudest about
# when the wave catches you (Morgan's pick)
const FORM_SOUND := preload("res://sounds/dragon-studio-waves-crashing-397977.mp3")
const FORM_SOUND_DB := 0.0
const FORM_FADE := 0.4           # if the wave dies down, it fades out over this long
const MelonShark := preload("res://code/design/melon_shark.gd")
const PEEK_FROM := 90.0          # the shark shows once the wave's this tall...
const PEEK_FADE := 40.0          # ...fading in over this much more
const CHASE_GAP := 64.0          # it stays this far behind you (but never ahead of the crest)
const PEEK_RISE := 1.6           # it rises out of the water over this long once it shows...
const PEEK_SHOW := 0.75          # ...until this much of its body (and all its fin) is out
const PEEK_SNAP := 1.4           # it lunges and snaps its jaws this often
const PEEK_TINT := Color(0.85, 0.95, 1.0, 0.95)  # (a touch of water over it)

@export var length := 2400.0     # where the wall is, from here
@export var wall_height := 330.0
@export var left_wall := -100.0  # the start wall's face (local x): gallop left and the wave crashes into it
@export var build_time := 3.2    # seconds of galloping (then riding) to build the wave all the way up
								 # (was 2.4: Morgan wanted it to take a little longer to form)
@export var max_height := 210.0  # its crest at full size
@export var surf_speed := 560.0

const CATCH_AT := 0.5            # it catches you up once it's this built (then grows under you)
const RISE_TIME := 1.5           # being carried from the face up to the crest
const DECAY_TIME := 1.4          # stop galloping and it dies down over this long
const CRASH_GAP := 130.0         # it breaks this far before the wall, throwing its rider up and over
const BACK := 380.0              # the swell starts this far behind the crest
const SEAT := 16.0               # the rider ends up this far behind the crest
const JUMP_OFF := Vector2(380, -520)  # jumping off the crest yourself
const THROW_X := 300.0           # the crash throws the rider forward this fast, and up enough to clear the wall
const DUMP := Vector2(160, -260) # rolling left there's nothing to clear: the crash just dumps you back off the start wall
const RIDE_POSE := ["BRAKE", 1]  # leaning back, like on a board
# the water, deep to bright (the day palette, plus a pale tone for the sheen)
const C_DEEP := Color("1f5f78")
const C_SHADE := Color("2c7892")
const C_BODY := Color("3894b1")
const C_LIGHT := Color("72b8ce")
const C_PALE := Color("a9d8e3")
const C_FOAM := Color("ecdfdb")
const C_WHITE := Color(1, 1, 1)
# the Great Wave look (Morgan's reference image): navy body, light streaks along the curve, cool white foam
const GW_DEEP := Color("16294f")
const GW_NAVY := Color("1f4482")
const GW_BLUE := Color("2f63ad")
const GW_LIGHT := Color("6f9fd8")
const GW_PALE := Color("b9d3ef")
const GW_FOAM := Color("eef3fa")
# the surfboard under you while you ride (Morgan's idea): it pops up out of the water under your feet
# when the wave catches you, tilts with you, and tumbles off into the foam when you leave the wave.
# PLACEHOLDER art, in BOOM's palette.
const BOARD_LEN := 38.0
const BOARD_THICK := 3.0
const BOARD := Color("ecdfdb")         # the deck
const BOARD_RAIL := Color("b9a8a2")    # its edges and underside
const BOARD_STRIPE := Color("d36618")  # a stripe down the middle
const BOARD_FIN := Color("2e2a26")
const BOARD_POP := 0.15                # it rises out of the water under you over this long

enum Mode { CALM, BUILD, RIDE, FREE, CRASH }

var player: CharacterBody2D = null
var _top := 4                    # the gallop's speed level
var _mode := Mode.CALM
var _mode_t := 0.0
var _charge := 0.0               # 0..1: how built up it is
var _front := 0.0                # the crest's x (in wave space: see _ws)
var _dir := 1.0                  # which way it rolls: 1 right (to the big wall), -1 left (back to the start, Morgan's call)
var _h := 0.0                    # its height
var _t := 0.0
var _ride := 0.0                 # seconds riding
var _catch_rel := Vector2.ZERO   # where the rider was, from the crest, when it caught them
var _drops := []                 # spray and mist: [pos (local), vel, life, mist?]
# THE CREST'S SPINDRIFT (the professor's idea, 2026-10-09): foam blown back off the top of the swell and the lip
# in a feathery plume, the way wind tears spray off a real wave's crest, plus little glints popping on the crest
var _spume := []                 # [pos (local), vel, life, starting life]
var _spume_acc := 0.0            # (part of a speck owed: they come out at a steady rate)
var _glints := []                # [x from the crest, life]
# THE WHITECAP (Morgan's call, 2026-10-09): the crest buried in churning foam bubbles, so you can't see its edge:
# each bubble rides along on the crest (x from the crest, so it moves with the wave), swells in and shrinks away
var _foam := []                  # [where along the outline (0..1), offset, radius, life, starting life, ring?]
var _foam_acc := 0.0
var _prev_front := 0.0
var _front_v := 0.0              # how fast the crest is moving (the plume keeps partly up with it)
var _boards := []                # surfboards tumbling away after you leave the wave: [pos (local), vel, angle, spin, life]
var _sprite: AnimatedSprite2D = null
var _sound := AudioStreamPlayer.new()
var _form_sound := AudioStreamPlayer.new()
var _form_fade: Tween = null
var _shark_art: Array = []       # melon_shark.gd's art: [mouth shut, half open, wide, shadow]
var _peek_x := 0.0               # where the shark is (wave space)
var _peek_on := false
var _peek_t := 0.0               # how long it's been showing
var _peek_rows: Array = []       # its art's width on each row: [first x, last x] (for the foam where it's cut)


func _ready():
	z_index = -1                 # behind the player
	process_physics_priority = 10    # after the player has moved this frame
	_sound.stream = SPLASH
	_sound.volume_db = SPLASH_DB
	add_child(_sound)
	_form_sound.stream = FORM_SOUND
	add_child(_form_sound)
	_shark_art = MelonShark.build_art()
	var img: Image = _shark_art[0].get_image()
	for y in img.get_height():
		var first := -1
		var last := -1
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				if first < 0:
					first = x
				last = x
		_peek_rows.append(Vector2i(first, last))


func _exit_tree():
	if _mode == Mode.RIDE and is_instance_valid(player):
		player.set_physics_process(true)
		if _sprite:
			_sprite.rotation = 0.0


func _physics_process(delta: float):
	_t += delta
	_mode_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		var speeds: Array = player.get_script().SPEEDS
		_top = speeds.size() - 1
		_sprite = player.get_node("AnimatedSprite2D")
	if Engine.time_scale == 0.0:
		return                   # time is stopped: the wave too
	var local := player.global_position - global_position
	if _mode == Mode.CALM and player.speed_level >= _top and absf(player.velocity.x) > 380.0:
		_dir = signf(player.velocity.x)              # a wave forms behind you whichever way you gallop
	var p := _ws(local)
	match _mode:
		Mode.CALM, Mode.BUILD:
			var galloping: bool = player.speed_level >= _top and player.velocity.x * _dir > 380.0 and p.x > -40.0 and p.x < _wall()
			if galloping:
				_charge = minf(_charge + delta / build_time, 1.0)
			else:
				_charge = maxf(_charge - delta / DECAY_TIME, 0.0)
			var was := _mode
			_mode = Mode.BUILD if _charge > 0.0 else Mode.CALM
			if was == Mode.CALM and _mode == Mode.BUILD:       # it starts to form, behind you
				_front = p.x - 260.0
				_form_sound_play()
			elif was == Mode.BUILD and _mode == Mode.CALM:     # it died down
				_form_sound_fade()
			# the crest chases you, closing the gap as it grows, until its face (just ahead of the crest)
			# reaches you
			var target := p.x - lerpf(260.0, _face() * 0.6, _ease(minf(_charge / CATCH_AT, 1.0)))
			_front = clampf(move_toward(_front, target, 900.0 * delta), 0.0, _wall() - CRASH_GAP)
			_h = max_height * _ease(_charge)
			if _charge >= CATCH_AT and p.x <= _front + _face() and p.x > _front - 20.0 and p.y > -30.0:
				_catch(p)
			elif _front >= _wall() - CRASH_GAP - 1.0 and _charge > 0.3:
				_crash(false)
		Mode.RIDE:
			_ride += delta
			_charge = minf(_charge + delta / build_time, 1.0)    # it keeps building under you
			_h = max_height * _ease(_charge)
			_front += surf_speed * delta
			# carried from where it caught you up the face to the crest, leaning with the water
			var k := _ease(clampf(_ride / RISE_TIME, 0.0, 1.0))
			var x := lerpf(_catch_rel.x, -SEAT, k)
			var surface := -_crest(_front + x)
			var settle := clampf(_ride / 0.25, 0.0, 1.0)            # no snap: ease onto the water first
			var y := lerpf(_catch_rel.y, surface, _ease(settle)) + roundf(sin(_t * 7.0) * 1.2) * k
			player.global_position = global_position + _ws(Vector2(_front + x, y))
			player.velocity = Vector2(surf_speed * _dir, 0)
			var slope := (_crest(_front + x + 3.0) - _crest(_front + x - 3.0)) / 6.0
			_sprite.rotation = clampf(-atan(slope) * 0.6, -0.55, 0.25) * _dir
			if k >= 0.6 and Input.is_action_just_pressed("ui_accept"):
				_release(Vector2(JUMP_OFF.x * _dir, JUMP_OFF.y))
				_mode = Mode.FREE
				_mode_t = 0.0
			elif _front >= _wall() - CRASH_GAP:
				if _dir > 0.0:
					# thrown up and over, from wherever on the wave you are
					var need := maxf(wall_height + 60.0 + y, 60.0)        # (y is negative: your height)
					_release(Vector2(THROW_X, -sqrt(2.0 * 980.0 * need)))
				else:
					_release(Vector2(-_dir * DUMP.x, DUMP.y))           # going left it doesn't help you: dumped
				_crash(true)
		Mode.FREE:                   # rolling on without a rider: it can pick you up again
			_front += surf_speed * delta
			if player.is_on_floor() and p.x >= _front - 30.0 and p.x <= _front + _face():
				_catch(p)
			elif _front >= _wall() - CRASH_GAP:
				_crash(false)
		Mode.CRASH:
			_h = max_height * _charge * maxf(0.0, 1.0 - _mode_t / 0.7)
			if _mode_t >= 2.2:
				_mode = Mode.CALM
				_mode_t = 0.0
				_charge = 0.0
				_front = 0.0
				_h = 0.0
	_update_peek(delta, p)
	_spray(delta)
	queue_redraw()


func _spray(delta: float):
	if delta > 0.0:                                         # (clamped: the crest jumps when a wave re-forms)
		_front_v = lerpf(_front_v, clampf((_front - _prev_front) / delta, 0.0, 900.0), 0.3)
	_prev_front = _front
	if _h > 20.0 and _mode != Mode.CRASH:                  # spindrift: more, and further, as it grows
		_spume_acc += (90.0 + _h * 2.6) * clampf((_h - 20.0) / 30.0, 0.0, 1.0) * delta
		while _spume_acc >= 1.0:
			_spume_acc -= 1.0
			var at: Vector2
			if randf() < 0.75:                                 # off the top of the swell, most right at the crest
				var back := randf()
				var x := _front - back * back * (20.0 + _h * 0.3)
				at = Vector2(x, -_crest(x) - randf_range(3.0, 10.0))      # (from the top of the foam)
			else:                                              # off the top of the curling lip
				at = Vector2(_front + randf_range(0.0, _lip_radius()), -_h - randf_range(4.0, 10.0))
			var keep := randf_range(0.55, 0.85)               # it keeps up with the crest this much, so it trails back
			var vel := Vector2(_front_v * keep - randf_range(20.0, 70.0), -randf_range(45.0, 130.0))
			var life := randf_range(0.45, 0.95)
			_spume.append([at, vel, life, life])
		if randf() < delta * 8.0:                            # a glint on the crest
			_glints.append([-randf_range(0.0, 20.0 + _h * 0.25), 0.18])
	for sp in _spume:
		sp[1] *= maxf(1.0 - 1.6 * delta, 0.0)                 # air drag: it slows and falls behind
		sp[1].y += 70.0 * delta
		sp[0] += sp[1] * delta
		sp[2] -= delta
	_spume = _spume.filter(func(sp): return sp[2] > 0.0 and sp[0].y < 0.0)
	for g in _glints:
		g[1] -= delta
	_glints = _glints.filter(func(g): return g[1] > 0.0 and _h > 20.0)
	if _h > 15.0 and _mode != Mode.CRASH:                  # the whitecap: thick, and thicker as it grows
		var size := clampf(_h / max_height, 0.0, 1.0)
		_foam_acc += (140.0 + _h * 3.2) * clampf((_h - 15.0) / 25.0, 0.0, 1.0) * delta
		while _foam_acc >= 1.0:
			_foam_acc -= 1.0
			var life := randf_range(0.25, 0.6)
			_foam.append([randf(), Vector2(randf_range(-2.0, 2.0), randf_range(-10.0, -1.0)),
				randf_range(1.5, 3.2) * (0.75 + size * 0.6), life, life, randf() < 0.3])
	for f in _foam:
		f[1] += Vector2(-10.0, -16.0) * delta                 # churning back and up off the top
		f[3] -= delta
	_foam = _foam.filter(func(f): return f[3] > 0.0 and _h > 10.0)
	if _h > 30.0 and _mode != Mode.CRASH:
		var lip := _lip_tip()
		if randf() < delta * (24.0 + _h * 0.35):          # droplets thrown off the lip
			_drops.append([lip + Vector2(randf_range(-3, 3), randf_range(-3, 3)), Vector2(randf_range(80, 240), randf_range(-150, -30)), randf_range(0.4, 0.8), false])
		if randf() < delta * (14.0 + _h * 0.25):          # mist blown back off the crest
			_drops.append([Vector2(_front - randf_range(0, 30), -_h - randf_range(0, 4)), Vector2(randf_range(-120, -40), randf_range(-40, -10)), randf_range(0.5, 1.0), true])
	for d in _drops:
		d[0] += d[1] * delta
		if not d[3]:
			d[1].y += 520.0 * delta
		d[2] -= delta
	_drops = _drops.filter(func(d): return d[2] > 0.0 and d[0].y < 0.0)
	for b in _boards:
		b[1].y += 700.0 * delta
		b[0] += b[1] * delta
		b[2] += b[3] * delta
		b[4] -= delta
	_boards = _boards.filter(func(b): return b[4] > 0.0)


# the face has caught up with the player: from here the wave carries them
func _catch(p: Vector2):
	_mode = Mode.RIDE
	_mode_t = 0.0
	_ride = 0.0
	_catch_rel = Vector2(clampf(p.x - _front, -SEAT, _face()), p.y)
	player.set_physics_process(false)
	_sprite.play(RIDE_POSE[0])
	_sprite.frame = mini(RIDE_POSE[1], _sprite.sprite_frames.get_frame_count(RIDE_POSE[0]) - 1)
	_sprite.pause()
	_sprite.flip_h = _dir < 0.0
	_sound.play(SPLASH_SKIP)
	var feet := _ws(to_local(player.global_position))            # the board pops up here in a splash
	for i in 12:
		_drops.append([feet + Vector2(randf_range(-18, 18), randf_range(-2, 2)), Vector2(randf_range(-80, 140), randf_range(-180, -40)), randf_range(0.3, 0.6), false])


func _form_sound_play():
	if _form_fade:
		_form_fade.kill()
	_form_sound.volume_db = FORM_SOUND_DB
	_form_sound.play()


func _form_sound_fade():
	if _form_fade:
		_form_fade.kill()
	_form_fade = create_tween()
	_form_fade.tween_property(_form_sound, "volume_db", -40.0, FORM_FADE)
	_form_fade.tween_callback(_form_sound.stop)


func _release(v: Vector2):
	var board := _board_pose()                                   # the board carries on without you, tumbling
	_boards.append([board[0], Vector2((surf_speed * 0.6 + randf_range(-40, 40)) * _dir, randf_range(-220, -120)), board[1], randf_range(-9.0, 9.0), 1.2, _dir])
	_sprite.rotation = 0.0
	player.set_physics_process(true)
	player.launch(v, 0.3)


func _crash(with_rider: bool):
	_mode = Mode.CRASH
	_mode_t = 0.0
	if with_rider and _dir > 0.0:                # it throws you over the big wall
		Achievements.unlock(get_tree(), "surf")
	_sound.play(SPLASH_SKIP)
	if player:
		player._shake(10.0 if with_rider else 6.0, 0.4)
	for i in 60:                 # it bursts up the wall in a tower of foam
		var x := _wall() - randf_range(0.0, 34.0)
		_drops.append([Vector2(x, -randf_range(0.0, _h)), Vector2(randf_range(-240, 20), randf_range(-360, -80)), randf_range(0.6, 1.2), false])
	for i in 20:
		_drops.append([Vector2(_wall() - randf_range(0, 60), -randf_range(10.0, _h)), Vector2(randf_range(-160, -40), randf_range(-60, -10)), randf_range(0.8, 1.4), true])


# the wave's own space, where it always rolls towards +x: going left, that's the run mirrored
# (this works both ways: wave space to local and back)
func _ws(p: Vector2) -> Vector2:
	return p if _dir > 0.0 else Vector2(length - p.x, p.y)


# where it crashes, in wave space: the big wall going right, the start wall going left
func _wall() -> float:
	return length if _dir > 0.0 else length - left_wall


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# the water's height above the floor at local x: a long swell up the back to a rounded crest, then a
# steep hollow face under the curl
func _crest(x: float) -> float:
	if _h <= 0.5:
		return 0.0
	var start := _front - BACK
	if x < start:
		return 0.0
	if x <= _front:
		var u := (x - start) / BACK
		return _h * (1.0 - pow(1.0 - u, 2.2)) * (0.97 + 0.03 * u)
	var f := (x - _front) / _face()
	return 0.0 if f >= 1.0 else _h * 0.9 * pow(1.0 - f, 1.6)


# how wide the steep front face is
func _face() -> float:
	return maxf(12.0, _h * 0.28)


func _lip_radius() -> float:
	return clampf(_h * 0.2, 5.0, 44.0)


# where the curl's tip hangs (local)
func _lip_tip() -> Vector2:
	var r := _lip_radius()
	var c := Vector2(_front + r * 0.3, -_h + r)
	return c + Vector2.from_angle(deg_to_rad(40.0)) * r


func _draw():
	if _dir < 0.0:
		draw_set_transform(Vector2(length, 0), 0.0, Vector2(-1, 1))   # rolling left: the same wave, mirrored
	if _h > 2.0:
		_draw_back()
		_draw_face()
		_draw_shark()
		if _h > 24.0:
			_draw_curl()
		_draw_foam()
		_draw_whitewater()
	_draw_drops()
	draw_set_transform(Vector2.ZERO)
	if _mode == Mode.RIDE and player and _sprite:
		var board := _board_pose()
		var pop := clampf(_mode_t / BOARD_POP, 0.0, 1.0)              # rising out of the water under you
		_draw_board(board[0] + Vector2(0, 6.0 * (1.0 - pop)).rotated(board[1]), board[1], pop, _dir)
	for b in _boards:
		_draw_board(b[0], b[2], clampf(b[4] / 0.4, 0.0, 1.0), b[5])


# the shark follows you along the top of the wave: CHASE_GAP behind you, but no further forward than the
# crest (so while the wave's still behind you, it's up at the crest, nose out of the face at you)
func _update_peek(delta: float, p: Vector2):
	if _h < PEEK_FROM:
		_peek_on = false
		_peek_t = 0.0
		return
	var target := clampf(p.x - CHASE_GAP, _front - BACK * 0.5, _front - 6.0)
	if not _peek_on:
		_peek_on = true
		_peek_x = target
	_peek_t += delta
	_peek_x = move_toward(_peek_x, target, 500.0 * delta)


# the sneak peek: the shark rising out of the water, only its top showing (fin, back, eye, the top of its
# jaws), tilting with the water, lunging and snapping. The art is cut off at the surface (in its own tilted
# frame, so the cut follows the slope), with foam along the cut.
func _draw_shark():
	var a := clampf((_h - PEEK_FROM) / PEEK_FADE, 0.0, 1.0)
	if a <= 0.0 or _shark_art.is_empty() or not _peek_on:
		return
	var mid := Vector2(MelonShark.MID)
	var body_top := mid.y - 10.0 * MelonShark.K                    # (the art's body, under the fin)
	var body_bottom := mid.y + 8.5 * MelonShark.K
	var rise := clampf(_peek_t / PEEK_RISE, 0.0, 1.0)
	rise = 1.0 - (1.0 - rise) * (1.0 - rise)                         # slowing as it comes up
	var cut := lerpf(0.0, body_top + PEEK_SHOW * (body_bottom - body_top), rise) + sin(_t * 5.0) * 1.5
	var rows := clampi(int(roundf(cut)), 0, _peek_rows.size() - 1)
	var snap := fmod(_t, PEEK_SNAP)
	var x := _peek_x + 14.0 * sin(PI * clampf(snap / 0.3, 0.0, 1.0))      # it lunges as it snaps
	var y := -_crest(x) - (rows - mid.y)                           # the cut sits on the surface
	var slope := (_crest(x + 6.0) - _crest(x - 6.0)) / 12.0
	var tilt := clampf(-atan(slope) * 0.7, -0.5, 0.3)
	var mouth := 2 if snap < 0.2 else (1 if snap < 0.32 else 0)
	var origin := Vector2(x, y) if _dir > 0.0 else Vector2(length - x, y)
	draw_set_transform(origin.round(), tilt * _dir, Vector2(_dir, 1))
	if rows > 0:
		var w := float(MelonShark.IMG.x)
		draw_texture_rect_region(_shark_art[mouth], Rect2(-mid, Vector2(w, rows)), Rect2(0, 0, w, rows),
			Color(PEEK_TINT, PEEK_TINT.a * a))
	var span: Vector2i = _peek_rows[rows]
	if span.x >= 0:                                                # foam where it breaks the surface
		for fx in range(span.x - 4, span.y + 5):
			var lift := 1.0 if posmod(fx + int(_t * 12.0), 5) == 0 else 0.0
			draw_rect(Rect2(fx - mid.x, rows - mid.y - 1.0 - lift, 1, 2), Color(GW_FOAM if posmod(fx, 3) else GW_PALE, a))
	if _dir < 0.0:                                     # back to the wave's own (mirrored) drawing
		draw_set_transform(Vector2(length, 0), 0.0, Vector2(-1, 1))
	else:
		draw_set_transform(Vector2.ZERO)


# THE WHOLE TOP OUTLINE IN FOAM (Morgan's call, 2026-10-09: so you can't see the wave's border anywhere):
# the outline runs from the back of the swell up over the crest and round the curl to its tip (or down the
# face while it's too small to curl). A rim of foam clumps every few pixels along all of it, each churning a
# little (pulsing, jiggling), so there's never a gap: small at the far back, biggest at the crest and the lip,
# tapering to the tip. Then the swelling, popping bubbles (_foam) anywhere along it on top.
const RIM_STEP := 3.0            # a clump this often along the outline (pixels)


# the outline's length in its two parts: [back of the swell (to the crest), the curl (or the face)]
func _outline_lengths(g: Array) -> Array:
	var back := BACK + _h * 0.9
	var lip: float = g[1] * 3.2 if _h > 24.0 else _face() + _h * 0.9
	return [back, lip]


# a point along the outline, t 0 (the back of the swell) .. 1 (the curl's tip): [point, how big the foam is there]
func _outline(t: float, g: Array, lens: Array) -> Array:
	var split: float = lens[0] / (lens[0] + lens[1])
	if t <= split:
		var u := t / maxf(split, 0.001)
		var x := floorf(_front - BACK + u * BACK)
		return [Vector2(x, -roundf(_crest(x))), 0.35 + 0.65 * u * u]
	var s := (t - split) / maxf(1.0 - split, 0.001)
	if _h > 24.0:
		return [_curl_edge(s, g), 1.0 - 0.45 * s]
	var fx := floorf(_front) + roundf(s * _face())
	return [Vector2(fx, -roundf(_crest(fx))), 1.0 - 0.5 * s]


func _draw_foam():
	if _h <= 10.0:
		return
	var g := _curl_geom()
	var lens := _outline_lengths(g)
	var grow := 0.75 + clampf(_h / max_height, 0.0, 1.0) * 0.6
	var total: float = lens[0] + lens[1]
	var n := int(total / RIM_STEP)
	var shade: Array = []
	var tops: Array = []
	for i in n + 1:                                          # the rim
		var pt := _outline(float(i) / n, g, lens)
		var p: Vector2 = pt[0]
		if p.y > -1.0:
			continue                                         # (no foam on the flat water behind it)
		var r: float = (1.5 + 2.4 * float(pt[1])) * grow * (0.78 + 0.22 * sin(_t * 7.0 + i * 1.9))
		var jig := Vector2(sin(_t * 5.0 + i * 2.3), cos(_t * 6.0 + i * 1.1))
		var at := (p + jig - Vector2(0, r * 0.35)).round()                  # on the edge: hides it
		var up := (p - jig - Vector2(0, r * 1.35)).round()                  # and piled up above it (Morgan's call)
		shade.append([at + Vector2(1, 1), r])
		shade.append([up + Vector2(1, 1), r * 0.8])
		tops.append([at, r, i])
		tops.append([up, r * 0.8, i + 3])
	for b in shade:                                          # (all the shade first, so no clump's shade lands on
		_blob(b[0], b[1], GW_PALE)                           # top of the one next to it)
	for b in tops:
		_blob(b[0], b[1], C_WHITE if posmod(int(b[2]) * 5 + int(_t * 6.0), 7) == 0 else GW_FOAM)
	for f in _foam:                                          # the bubbles: swell in, shrink away
		var pt := _outline(f[0], g, lens)
		var p: Vector2 = pt[0]
		if p.y > -1.0:
			continue
		var k: float = 1.0 - f[3] / f[4]                     # 0 new .. 1 gone
		var r: float = f[2] * sqrt(sin(k * PI)) * (0.5 + 0.5 * float(pt[1]))
		if r < 0.6:
			continue
		var at: Vector2 = (p + (f[1] as Vector2)).round()
		if f[5] and r >= 1.5:                                # an open bubble
			var rr := roundf(r)
			draw_rect(Rect2(at + Vector2(-rr, -rr), Vector2(rr * 2.0 + 1.0, 1)), C_WHITE)
			draw_rect(Rect2(at + Vector2(-rr, rr), Vector2(rr * 2.0 + 1.0, 1)), GW_PALE)
			draw_rect(Rect2(at + Vector2(-rr, -rr), Vector2(1, rr * 2.0 + 1.0)), GW_FOAM)
			draw_rect(Rect2(at + Vector2(rr, -rr), Vector2(1, rr * 2.0 + 1.0)), GW_FOAM)
		else:                                                # a clump: pale shade under, white on top
			_blob(at + Vector2(1, 1), r, GW_PALE)
			_blob(at, r, GW_FOAM if posmod(int(f[0] * 997.0), 4) > 0 else C_WHITE)


func _draw_drops():
	for sp in _spume:                                       # spindrift: foam specks fading to mist, a faint streak
		var k: float = sp[2] / sp[3]                         # back toward the crest they came off
		var at: Vector2 = (sp[0] as Vector2).round()
		var alpha := clampf(k * 1.4, 0.0, 0.9)
		var size := 2.0 if k > 0.65 else 1.0
		draw_rect(Rect2(at, Vector2(size, size)), Color(GW_FOAM if k > 0.45 else GW_PALE, alpha))
		if k > 0.3:
			draw_rect(Rect2(at + Vector2(size, 0), Vector2(2, 1)), Color(GW_PALE, alpha * 0.45))
	for g in _glints:                                       # glints: a little white cross on the crest
		var x := floorf(_front) + roundf(g[0])
		var at := Vector2(x, -roundf(_crest(x)) - 2.0)
		var alpha: float = clampf(g[1] / 0.18 * 1.5, 0.0, 1.0)
		draw_rect(Rect2(at, Vector2(1, 1)), Color(C_WHITE, alpha))
		if g[1] > 0.06:
			for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_rect(Rect2(at + off, Vector2(1, 1)), Color(GW_PALE, alpha * 0.7))
	for d in _drops:
		var p: Vector2 = d[0]
		var life: float = d[2]
		if d[3]:                     # mist: soft, fading
			draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(GW_PALE, clampf(life * 0.8, 0.0, 0.7)))
		else:                        # spray: big drops shrink as they fall
			var size := 3.0 if life > 0.6 else (2.0 if life > 0.3 else 1.0)
			var tone := GW_FOAM if posmod(int(p.x) + int(p.y), 3) > 0 else C_WHITE
			draw_rect(Rect2(p.round(), Vector2(size, size)), Color(tone, clampf(life * 3.0, 0.0, 1.0)))


# where the rider's feet are and how they lean (the sprite turns about its own centre): [local pos, angle]
func _board_pose() -> Array:
	var pivot := player.global_position + _sprite.position
	var feet := pivot + Vector2(0, -_sprite.position.y).rotated(_sprite.rotation)
	return [to_local(feet), _sprite.rotation]


# a surfboard, its deck at `pos` (where the feet stand), nose kicked up at the front (facing: 1 right, -1 left)
func _draw_board(pos: Vector2, angle: float, a: float, facing := 1.0):
	if a <= 0.0:
		return
	var half := BOARD_LEN / 2.0
	draw_set_transform(pos.round(), angle, Vector2(facing, 1))
	draw_rect(Rect2(-half, 0, BOARD_LEN - 6.0, BOARD_THICK), Color(BOARD, a))
	draw_rect(Rect2(half - 6.0, -1, 4, BOARD_THICK), Color(BOARD, a))           # the nose rising...
	draw_rect(Rect2(half - 2.0, -2, 2, 2), Color(BOARD, a))                      # ...to its tip
	draw_rect(Rect2(-half, BOARD_THICK - 1.0, BOARD_LEN - 4.0, 1), Color(BOARD_RAIL, a))
	draw_rect(Rect2(-half, 0, 1, BOARD_THICK), Color(BOARD_RAIL, a))             # the squared tail
	draw_rect(Rect2(-half + 3.0, 1, BOARD_LEN - 12.0, 1), Color(BOARD_STRIPE, a))
	draw_rect(Rect2(-half + 3.0, BOARD_THICK, 3, 3), Color(BOARD_FIN, a))        # the fin under the tail
	draw_set_transform(Vector2.ZERO)


# a cheap repeatable "random" number 0..999 for a pixel, for foam speckles that don't flicker
func _hash(x: int, y: int) -> int:
	return posmod((x * 73856093) ^ (y * 19349663), 1000)


# the back of the wave: blue bands that follow the curve (light just under the foam, navy, deep at the
# base, dithered where they meet), brush-stroke streaks along the curve (near-white high up, bluer
# lower), and a lumpy white foam cap thickening toward the crest
func _draw_back():
	var start := _front - BACK
	var x := floorf(start)                                  # whole pixels: the columns don't shimmer as it moves
	while x <= _front:
		var hgt := roundf(_crest(x))
		if hgt >= 1.0:
			var u := (x - start) / BACK
			var top := -hgt
			var ix := int(x)
			var light_end := top + roundf(hgt * 0.1)
			var deep_start := -roundf(hgt * 0.38)
			draw_rect(Rect2(x, top, 1, hgt), GW_NAVY)
			draw_rect(Rect2(x, top, 1, light_end - top), GW_BLUE)
			draw_rect(Rect2(x, deep_start, 1, -deep_start), GW_DEEP)
			if ix % 2 == 0:                                       # dithered seams between the bands
				draw_rect(Rect2(x, light_end, 1, 1), GW_BLUE)
				draw_rect(Rect2(x, deep_start - 1.0, 1, 1), GW_DEEP)
			var d := 4.0
			var k := 0
			while d < hgt * 0.8:
				var wig := roundf(sin(x * 0.08 + k * 1.7 + _t * 1.6) * 1.5)
				var drift := int(_t * 25.0) * (1 if k % 2 == 0 else -1)
				if posmod(ix + k * 37 + drift, 23) < 14:          # broken, like brush strokes
					var tone := GW_PALE if k < 2 else (GW_LIGHT if k < 5 else GW_BLUE)
					draw_rect(Rect2(x, top + d + wig, 1, 2.0 if k < 3 else 1.0), tone)
				d += 5.0 + k * 1.5
				k += 1
			var foam := 0.0 if u < 0.55 else roundf((u - 0.55) / 0.45 * (8.0 + _h * 0.09))
			if foam > 0.0:
				var bump := roundf(absf(sin(x * 0.35 + _t * 3.0)) * minf(foam, 3.0))
				draw_rect(Rect2(x, top - bump, 1, foam + bump), GW_FOAM)
				if _hash(ix, int(_t * 8.0)) < 300:                # light-blue specks in the foam
					draw_rect(Rect2(x, top + 1.0 + posmod(ix * 7 + int(_t * 6.0), maxi(int(foam) - 1, 1)), 1, 1), GW_LIGHT)
				draw_rect(Rect2(x, top + foam, 1, 1), GW_PALE)
				if u > 0.8 and posmod(ix, 7) == 0:                # cauliflower clumps along the crest
					_blob(Vector2(x, top - bump - 1.0), 2.0 + (u - 0.8) * 12.0, GW_FOAM)
			else:
				draw_rect(Rect2(x, top, 1, 1), GW_LIGHT)
		x += 1.0


# the face under the curl: dark and hollow, with streaks of water pulled up it
func _draw_face():
	var face := _face()
	var x := floorf(_front) + 1.0
	while x < _front + face:
		var hgt := roundf(_crest(x))
		if hgt >= 1.0:
			var top := -hgt
			draw_rect(Rect2(x, top, 1, hgt), GW_DEEP)
			draw_rect(Rect2(x, -roundf(hgt * 0.3), 1, roundf(hgt * 0.3)), GW_NAVY)
			if int(x) % 3 == 0 and hgt > 12.0:
				var sy := -fmod(_t * 90.0 + x * 7.0, hgt - 8.0) - 4.0
				draw_rect(Rect2(x, roundf(sy), 1, 4), GW_BLUE)
				draw_rect(Rect2(x, roundf(sy), 1, 1), GW_LIGHT)
		x += 1.0


# the curl: a hooked lip thrown forward over the face (open underneath, like the reference), thick at
# the crest and tapering, white on top and blue underneath, with rows of claw-like talons hanging off
# it and a split tip
# the curl's circle: [centre, radius, thickness]. Low enough that the top of its foam lines up with the crest's
# foam, so it blends into the wave; on whole pixels so the whole lip moves as one (it shimmered when each blob
# rounded on its own)
func _curl_geom() -> Array:
	var r := roundf(_lip_radius() * 1.5)
	var thick := roundf(8.0 + r * 0.5)
	return [Vector2(_front + r * 0.2, -_h + r * 0.927 + thick * 0.72 - 8.0).round(), r, thick]


# a point along the curl's outer edge, s 0 (where it leaves the swell) .. 1 (its tip)
func _curl_edge(s: float, g: Array) -> Vector2:
	var out := Vector2.from_angle(deg_to_rad(lerpf(-112.0, 70.0, s)))
	var w: float = g[2] * (1.0 - 0.55 * s)
	return g[0] + out * (g[1] * (1.0 - 0.15 * s) + w * 0.55)


func _draw_curl():
	var g := _curl_geom()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var thick: float = g[2]
	var steps := 44
	for i in steps + 1:
		var s := float(i) / steps
		var a := deg_to_rad(lerpf(-112.0, 70.0, s))
		var rad := r * (1.0 - 0.15 * s)
		var w := thick * (1.0 - 0.55 * s)
		var out := Vector2.from_angle(a)
		var p := c + out * rad
		# the underside is the same navy as the wave's body, with the same brush streaks running along
		# the curl, so the body flows straight into the lip
		_blob(p - out * w * 0.6, w * 0.55, GW_NAVY)
		var along := out.orthogonal()
		if posmod(i + int(_t * 12.0), 5) < 2:
			var q := (p - out * w * 0.5).round()
			draw_line(q, q + along * 3.0, GW_PALE, 1.0)
		if posmod(i + 2 + int(_t * 12.0), 5) < 2:
			var q2 := (p - out * w * 0.85).round()
			draw_line(q2, q2 + along * 3.0, GW_LIGHT, 1.0)
		_blob(p, w * 0.55, GW_FOAM)
		if posmod(i, 3) == 0:                                      # fluffy clumps on the outer edge
			_blob(p + out * w * 0.45, w * 0.3, GW_FOAM)
		if s > 0.3 and i % 3 == 0:                                 # talons: big outer ones, smaller inner ones
			_claw(p + out * w * 0.5, out.rotated(0.45), 6.0 + w * 0.6, i)
			if s > 0.5:
				_claw(p - out * w * 0.2, out.rotated(0.9), 4.0 + w * 0.35, i + 17)
	# the tip splits into three talons
	var tip_a := deg_to_rad(70.0)
	var tip := c + Vector2.from_angle(tip_a) * r * 0.85
	for k in 3:
		_claw(tip, Vector2.from_angle(tip_a + 0.2 + k * 0.4), 8.0 + thick * 0.3, 40 + k)


# one claw-like foam talon: reaches out, then hooks down; they twitch
func _claw(root: Vector2, dir: Vector2, reach: float, i: int):
	var n := int(reach * (0.85 + 0.15 * sin(_t * 8.0 + i)))
	for j in n:
		var k := float(j) / maxf(n - 1, 1)
		var q := root + dir * j * 1.1 + Vector2(0, j * j * 0.09)     # reaches out, then hooks down
		var sz := 3.0 if k < 0.35 else (2.0 if k < 0.75 else 1.0)
		draw_rect(Rect2(q.round(), Vector2(sz, sz)), GW_FOAM if j < n - 1 else C_WHITE)
		if sz > 1.0 and j % 3 == 1:
			draw_rect(Rect2(q.round() + Vector2(1, 1), Vector2(1, 1)), GW_LIGHT)


# a small pixel blob (two crossed rects), for foam and the lip
func _blob(at: Vector2, radius: float, color: Color):
	if radius < 1.5:
		draw_rect(Rect2(at.round(), Vector2(2, 2)), color)
		return
	var rr := roundf(radius)
	var r2 := roundf(radius * 0.6)
	draw_rect(Rect2((at - Vector2(rr, r2)).round(), Vector2(rr * 2.0, r2 * 2.0)), color)
	draw_rect(Rect2((at - Vector2(r2, rr)).round(), Vector2(r2 * 2.0, rr * 2.0)), color)


# churning whitewater where the curl comes down: clumps of foam blobs with blue specks, and a foamy
# wake behind the swell
func _draw_whitewater():
	var face := _face()
	var fh := 4.0 + _h * 0.06
	var x := floorf(_front) - 4.0
	while x < _front + face + 26.0:
		var top := -2.0 - roundf(absf(sin(x * 0.45 + _t * 11.0)) * 1.5)
		draw_rect(Rect2(x, top, 1, -top), GW_FOAM)
		x += 1.0
	for i in 12:
		var bx := _front - 2.0 + i * (face + 28.0) / 12.0 + sin(_t * 6.0 + i) * 3.0
		var rad := 2.5 + absf(sin(i * 2.3)) * (2.0 + _h * 0.02)
		var by := -fh * 0.6 - rad * 0.6 - absf(sin(_t * 9.0 + i * 1.3)) * 3.0
		_blob(Vector2(bx, by), rad, GW_FOAM)
		_blob(Vector2(bx + 1.0, by + 1.0), 1.0, GW_LIGHT)
	x = floorf(_front - BACK)
	while x < _front - BACK + 50.0:
		var wh := roundf(1.0 + sin(x * 0.3 - _t * 6.0) * 1.0)
		if wh > 0.0:
			draw_rect(Rect2(x, -wh, 1, wh), GW_FOAM)
		x += 1.0
