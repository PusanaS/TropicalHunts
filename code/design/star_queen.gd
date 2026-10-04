extends Node2D
# STAR QUEEN: Level 2's boss, a huge starfruit queen floating high in the sunset sky.
# PLACEHOLDER look, drawn in code in BOOM's palette (the real one is Violeta's and BOOM's).
#
# Monster card
#   Moves:     floats high over the arena, out of reach of any jump, drifting after the player.
#   Notices:   nothing until the level calls start_fight() (or you hit her): then she rises up.
#   Attacks:   STARFALL: she tosses starfruits down near you, a zigzag ladder. Air Q them to bounce up
#              it (code/design/starfruit.gd); the last bounce throws you right at her.
#              COMET DIVE (warning: she slides to one side, glows, and a dotted line runs along the floor
#              for 0.8 s): she sweeps across the arena at foot height. Jump it, or COUNTER it.
#              Below half health: tosses faster, floats higher (one more bounce), dives there and back.
#   After:     a dive ends with her climbing back up.
#   Beaten by: up high: air Q (1, and you bounce off her for another go) or an AIR W SLAM onto her: she's
#              knocked out of the sky (3) and lies STUNNED 3 s, open to everything, a gallop flash too.
#              Countering her dive: 4, and she crashes, STUNNED.
#   Touch:     only her dive hurts.
#   Drops:     a burst of stars and juice when she's beaten.
#   Animations BOOM / Violeta will need: FLOAT, TOSS, DIVE_WINDUP, DIVE, CLIMB, HIT, KNOCKED_DOWN
#              (falling), STUNNED, RISE, DEFEAT
#
# The level: place her anywhere (she waits there, bobbing), set arena_left / arena_right (absolute x) and
# floor_y (the arena floor's absolute y), call start_fight() when the player comes in, and listen for
# boss_defeated(self) on the "level" group. Its HUD draws her name (boss_name) and hp / max_hp.

enum State { IDLE, RISE, STARFALL, WINDUP, DIVE, CLIMB, FALLING, STUNNED, RECOVER, DEFEATED }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const Starfruit := preload("res://code/design/starfruit.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
# her hits: the fruit enemies' wet squelch
const HIT_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const HIT_SOUND_DB := 0.0
const HIT_SOUND_SKIP := 0.12      # the file starts with 0.12 s of silence
# the comet dive starting: the gallop's electric crackle, quieter
const DIVE_SOUND := preload("res://sounds/GALLOP_SOUND_freesound_community-electric-impact-37128.mp3")
const DIVE_SOUND_DB := -8.0
const DIVE_SOUND_SKIP := 0.042    # 44 ms of near-silence first
# crashing to the floor: the Pineapple's heavy impact
const CRASH_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRASH_SOUND_DB := -8.0
const CRASH_SOUND_SKIP := 0.02
# beaten: the boss finisher's final crash
const BURST_SOUND := preload("res://sounds/sword/sword_crash_01.wav")
const BURST_SOUND_DB := 0.0
const BURST_SOUND_SKIP := 0.03
# tossing a starfruit down
const TOSS_SOUND := preload("res://sounds/sword/sword_swoosh_02.wav")
const TOSS_SOUND_DB := -16.0

const LIGHT := ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2"]
const JUICE := Color(0.96, 0.82, 0.3)
const R_OUT := 22.0              # her star's points reach this far from her middle (44 px across)...
const R_IN := 10.0               # ...and the dips between them this far
const STEPS := 64                # her turn is drawn in this many steps (each one cached)
const HURT := Vector2(22, 22)    # half her hurt box
const RISE_TIME := 1.0
const DRIFT := 70.0              # she drifts after the player this fast...
const DRIFT_OFFSET := 70.0       # ...keeping this far off to one side of them
const HIGHER := 90.0             # below half health she floats this much higher (one more bounce)
const DROP_EVERY := [0.9, 0.6]   # starfall: a starfruit this often (full health / below half)
const DIVE_AFTER := [8.0, 5.5]   # seconds up there before she dives
const MAX_FRUIT := 4
const FIRST_RUNG := 205.0        # a ladder's first starfruit hangs this far over the floor (jump + double jump)
const RUNG_GAIN := 110.0         # each next one this much higher...
const RUNG_STEP := 90.0          # ...and this far across
const RUNG_HANG := [1.6, 1.2]    # how long it hangs still: the first of a ladder / the ones a bounce drops in
const REACH := 40.0              # a bounce that ends this close under her height throws you at her instead
const AIM_AT_HER := Vector2(24, 10)   # that throw puts the feet beside her and a little below her middle,
								 # where both an air Q and an air W slam connect
const HOLD_STILL := 0.9          # she stops drifting this long when a throw is aimed at her
const POGO := Vector2(90, -330)  # an air Q on her bounces you up off her for another go
const SLIDE_TIME := 0.45         # the comet dive: she slides to her starting side...
const TELEGRAPH := [0.8, 0.65]   # ...glows, with the dotted line along the floor, for this long...
const SWOOP_TIME := 0.3          # ...swoops down to foot height...
const DIVE_SPEED := [360.0, 440.0]   # ...and sweeps across
const TURN_TIME := 0.45          # below half health: a short glow at the far end, then back again
const DIVE_HEIGHT := 22.0        # her middle this far over the floor while diving and lying stunned
const DIVE_EDGE := 50.0          # she keeps this far in from the arena's sides
const CLIMB_TIME := 0.7
const FALL_ACCEL := 1600.0
const STUN_TIME := 3.0
const RECOVER_TIME := 1.0
const SLAM_DAMAGE := 3
const COUNTER_DAMAGE := 4
const FLASH_TIME := 0.08
const FLINCH_TIME := 0.25
const REPORT_AFTER := 1.4        # beaten: the level hears about it this long after she bursts
const CROWN := [
	"o....o....o",
	"mo..omo..om",
	"mmoommmoomm",
	"mmmmmrmmmmm",
	"ooooooooooo",
]

@export var max_hp := 24
@export var arena_left := -400.0
@export var arena_right := 400.0
@export var floor_y := 0.0
@export var sky_y := -260.0      # her hover height, from the floor (negative = up)
@export var boss_name := "STAR QUEEN"

var hp := 24
var state: State = State.IDLE
var state_time := 0.0
var player: CharacterBody2D = null

static var _cache := {}          # turn step -> her star's pixels

var _names: Array = []
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _t := 0.0
var _from := Vector2.ZERO        # where she was when this state started
var _home := Vector2.ZERO
var _up_time := 0.0
var _drop_timer := 0.0
var _rung_side := 1.0
var _hold_still := 0.0
var _flash := 0.0
var _flinch := 0.0
var _spin := 0.0                 # how far her star is turned
var _dive_from := 0.0
var _dive_to := 0.0
var _dive_dir := 1.0
var _dive_sub := 0               # 0 swooping down, 1 sweeping across, 2 turning at the far end
var _turn_t := 0.0
var _dive_hit := false           # this dive already hit the player: too late to counter it
var _second := false             # the dive back has happened
var _fall_v := 0.0
var _burst_done := false
var _reported := false
var _trail := []                 # where the dive has been (global), newest last
var _tosses := []                # starfruit throws to draw: [from, to, age]
var _bits := []                  # sparkles, dust and stars: [pos (global), vel, life, colour, gravity]
var _hit_sound: AudioStreamPlayer
var _dive_sound: AudioStreamPlayer
var _crash_sound: AudioStreamPlayer
var _burst_sound: AudioStreamPlayer
var _toss_sound: AudioStreamPlayer


func _ready():
	add_to_group("enemies")
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	var squelch := AudioStreamRandomizer.new()
	squelch.add_stream(-1, HIT_SOUND)
	squelch.random_pitch = 1.2
	_hit_sound = _sound(squelch, HIT_SOUND_DB)
	_dive_sound = _sound(DIVE_SOUND, DIVE_SOUND_DB)
	_crash_sound = _sound(CRASH_SOUND, CRASH_SOUND_DB)
	_crash_sound.pitch_scale = 0.85
	_burst_sound = _sound(BURST_SOUND, BURST_SOUND_DB)
	_toss_sound = _sound(TOSS_SOUND, TOSS_SOUND_DB)


func _sound(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.max_polyphony = 2
	add_child(p)
	return p


func start_fight():
	if state == State.IDLE:
		_set_state(State.RISE)


func is_alive() -> bool:
	return state != State.DEFEATED and hp > 0


# her comet dive can be countered, until it has hit the player
func is_counterable() -> bool:
	return state == State.DIVE and _dive_sub != 2 and not _dive_hit


func _phase() -> int:
	return 1 if hp * 2 <= max_hp else 0


func _hover_y() -> float:
	return floor_y + sky_y - (HIGHER if _phase() == 1 else 0.0)


func _set_state(s: State):
	state = s
	state_time = 0.0
	_from = global_position


func _hurtbox() -> Rect2:
	return Rect2(global_position - HURT, HURT * 2.0)


# ---------- every frame ----------
func _physics_process(delta: float):
	_t += delta
	state_time += delta
	_flash -= delta
	_flinch = maxf(_flinch - delta, 0.0)
	_hold_still = maxf(_hold_still - delta, 0.0)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player:
			_names = player.get_script().State.keys()
	if player and state not in [State.FALLING, State.DEFEATED]:
		_check_player_attack()
	match state:
		State.IDLE:
			global_position = _home + Vector2(0, roundf(sin(_t * 1.5) * 4.0))
			_sway(delta)
		State.RISE:
			var k := clampf(state_time / RISE_TIME, 0.0, 1.0)
			var to := Vector2(_clamp_x(_from.x), _hover_y())
			global_position = _from.lerp(to, _ease_in_out(k))
			_sway(delta)
			if k >= 1.0:
				_back_up()
		State.STARFALL:
			_starfall(delta)
		State.WINDUP:
			_windup(delta)
		State.DIVE:
			_dive(delta)
		State.CLIMB:
			var k := clampf(state_time / CLIMB_TIME, 0.0, 1.0)
			global_position = _from.lerp(Vector2(_from.x, _hover_y()), _ease_out(k))
			_sway(delta)
			if k >= 1.0:
				_back_up()
		State.FALLING:
			_fall_v += FALL_ACCEL * delta
			global_position.y += _fall_v * delta
			_spin += delta * 8.0
			if global_position.y >= floor_y - DIVE_HEIGHT:
				global_position.y = floor_y - DIVE_HEIGHT
				_crash(true)
		State.STUNNED:
			_spin = lerp_angle(_spin, 0.45, minf(delta * 8.0, 1.0))      # lying tipped over
			if state_time >= STUN_TIME:
				_set_state(State.RECOVER)
		State.RECOVER:
			var k := clampf(state_time / RECOVER_TIME, 0.0, 1.0)
			global_position = _from.lerp(Vector2(_from.x, _hover_y()), _ease_in_out(k))
			_sway(delta)
			if k >= 1.0:
				_back_up()
		State.DEFEATED:
			if not _burst_done and state_time >= 0.02:     # (after the freeze)
				_burst()
			if _burst_done and not _reported and state_time >= REPORT_AFTER:
				_reported = true
				get_tree().call_group("level", "boss_defeated", self)
	_update_effects(delta)
	queue_redraw()


func _sway(delta: float):
	_spin = lerp_angle(_spin, sin(_t * 1.6) * 0.12, minf(delta * 6.0, 1.0))


func _clamp_x(x: float) -> float:
	return clampf(x, arena_left + DIVE_EDGE, arena_right - DIVE_EDGE)


# up in the sky again: back to the starfall
func _back_up():
	_set_state(State.STARFALL)
	_up_time = 0.0
	_drop_timer = 0.6


# ---------- starfall ----------
func _starfall(delta: float):
	_up_time += delta
	_sway(delta)
	if player and _hold_still <= 0.0:
		var side := signf(global_position.x - player.global_position.x)
		if side == 0.0:
			side = 1.0
		var tx := _clamp_x(player.global_position.x + side * DRIFT_OFFSET)
		global_position.x = move_toward(global_position.x, tx, DRIFT * delta)
	global_position.y = move_toward(global_position.y, _hover_y() + sin(_t * 2.0) * 5.0, 120.0 * delta)
	if _flinch <= 0.0:
		_drop_timer -= delta
	if _drop_timer <= 0.0:
		_drop_timer = DROP_EVERY[_phase()]
		_drop_first_rung()
	if _up_time >= DIVE_AFTER[_phase()] and _hold_still <= 0.0:
		_start_dive()


func _fruit_count() -> int:
	var n := 0
	for c in get_children():
		if c.has_method("is_alive") and c.is_alive():
			n += 1
	return n


# the bottom of a ladder: a starfruit tossed down next to the player, just in reach of a double jump
func _drop_first_rung():
	if player == null or _fruit_count() >= MAX_FRUIT:
		return
	var x := clampf(player.global_position.x + _rung_side * 65.0, arena_left + 30.0, arena_right - 30.0)
	var f := _toss(Vector2(x, floor_y - FIRST_RUNG), RUNG_HANG[0])
	f.set_meta("side", _rung_side)
	_rung_side = -_rung_side


# a starfruit flung down to `at` (global), hanging there a moment before it falls. It stays put
# however she moves (top level).
func _toss(at: Vector2, hang: float) -> Node2D:
	var f: Node2D = Starfruit.new()
	f.mode = "fall"
	f.hang = hang
	f.top_level = true
	f.position = at
	add_child(f)
	f.sparkle_in()
	_tosses.append([global_position, at, 0.0])
	_toss_sound.play()
	return f


# one of her starfruits was hit with an air Q: where to throw the player (their feet). Up the ladder
# toward her, and once it's high enough, right at her.
func next_target(fruit: Node2D, p: Node2D):
	if state == State.DEFEATED:
		return null
	var me := global_position
	var hit := fruit.global_position
	if state == State.STARFALL and hit.y - RUNG_GAIN <= me.y + REACH:
		_hold_still = HOLD_STILL
		var dir := signf(me.x - p.global_position.x)
		if dir == 0.0:
			dir = 1.0
		return me + Vector2(-dir * AIM_AT_HER.x, AIM_AT_HER.y)
	var side := signf(me.x - hit.x)
	if absf(me.x - hit.x) < RUNG_STEP * 1.5:      # under her already: zigzag
		side = -float(fruit.get_meta("side", 1.0))
	if side == 0.0:
		side = 1.0
	var at := Vector2(clampf(hit.x + side * RUNG_STEP, arena_left + 30.0, arena_right - 30.0), hit.y - RUNG_GAIN)
	var next := _toss(at, RUNG_HANG[1])
	next.set_meta("side", side)
	return next.aim_point(p.global_position)


# ---------- the comet dive ----------
func _start_dive():
	var mid := (arena_left + arena_right) / 2.0
	var from_left := player == null or player.global_position.x > mid    # it comes from the far side
	_dive_from = arena_left + DIVE_EDGE if from_left else arena_right - DIVE_EDGE
	_dive_to = arena_right - DIVE_EDGE if from_left else arena_left + DIVE_EDGE
	_dive_dir = signf(_dive_to - _dive_from)
	_second = false
	_set_state(State.WINDUP)


func _windup(delta: float):
	if state_time < SLIDE_TIME:
		var k := state_time / SLIDE_TIME
		global_position = _from.lerp(Vector2(_dive_from, _hover_y()), _ease_in_out(k))
		_sway(delta)
		return
	_spin = lerp_angle(_spin, -_dive_dir * 0.3, minf(delta * 6.0, 1.0))   # rearing back
	if state_time >= SLIDE_TIME + TELEGRAPH[_phase()]:
		_set_state(State.DIVE)
		_dive_sub = 0
		_dive_hit = false
		_dive_sound.play(DIVE_SOUND_SKIP)


func _dive(delta: float):
	var low := floor_y - DIVE_HEIGHT
	match _dive_sub:
		0:      # swooping down, faster and faster
			var k := clampf(state_time / SWOOP_TIME, 0.0, 1.0)
			global_position = Vector2(lerpf(_from.x, _dive_from + _dive_dir * 60.0, k), lerpf(_from.y, low, k * k))
			if k >= 1.0:
				_dive_sub = 1
		1:      # sweeping across at foot height
			global_position.y = low
			global_position.x += _dive_dir * DIVE_SPEED[_phase()] * delta
			if (global_position.x - _dive_to) * _dive_dir >= 0.0:
				global_position.x = _dive_to
				if _phase() == 1 and not _second:
					_second = true
					_dive_sub = 2
					_turn_t = 0.0
				else:
					_set_state(State.CLIMB)
					return
		2:      # below half health: a short glow at the far end, then back the other way
			_turn_t += delta
			if _turn_t >= TURN_TIME:
				var was := _dive_from
				_dive_from = _dive_to
				_dive_to = was
				_dive_dir = -_dive_dir
				_dive_sub = 1
				_dive_hit = false
				_dive_sound.play(DIVE_SOUND_SKIP)
	if _dive_sub != 2:
		_spin += delta * 9.0 * _dive_dir           # spinning like a comet
		_trail.append(global_position)
		if _trail.size() > 16:
			_trail.pop_front()
		if player and not _dive_hit and EnemyKit.hurt_player(player, _hurtbox(), global_position.x):
			_dive_hit = true


# the counter caught her dive (code/counter_chain.gd calls this while time is stopped)
func countered(dir: int):
	if state == State.DEFEATED:
		return
	_hurt(COUNTER_DAMAGE, global_position.x - dir * 10.0)
	if state == State.DEFEATED:
		return
	global_position.y = floor_y - DIVE_HEIGHT
	_crash(false)           # (no shake: the counter shakes when time starts again)


# ---------- getting hit ----------
# same "new swing" rule as the fruit minion: a new state, or the same one restarted
func _check_player_attack():
	var ps: int = player.state
	var pt: float = player.state_time
	if ps != _last_state or pt < _last_time:
		_hit_this_swing = false
	_last_state = ps
	_last_time = pt
	if _hit_this_swing:
		return
	var hit := EnemyKit.player_attack_hitting(player, _names, _hurtbox())
	if hit.is_empty():
		return
	_hit_this_swing = true
	if state == State.IDLE:
		start_fight()
		return
	var move: String = _names[ps]
	var low := state in [State.STUNNED, State.RECOVER]
	if move == "DASH_ATTACK_HEAVY_SLAM" and not low and state != State.DIVE:
		_knock_down()
		return
	if move in LIGHT and not player.is_on_floor() and not low:
		_hurt(1, player.global_position.x)
		if state != State.DEFEATED:          # bounce up off her for another go
			var away := signf(player.global_position.x - global_position.x)
			if away == 0.0:
				away = -float(player.facing)
			player.launch(Vector2(away * POGO.x, POGO.y), 0.2)
		return
	_hurt(int(hit["damage"]), player.global_position.x)


# the flash, the charged smash, W waves
func take_hit(damage: int, push: Vector2):
	if state == State.IDLE:
		start_fight()
		return
	if state == State.DEFEATED:
		return
	var from_x := global_position.x - signf(push.x) * 10.0
	_hurt(damage, from_x)


func _hurt(damage: int, from_x: float):
	if hp <= 0 or state == State.DEFEATED:
		return
	hp = maxi(hp - damage, 0)
	_flash = FLASH_TIME
	_flinch = FLINCH_TIME
	_hit_sound.play(HIT_SOUND_SKIP)
	if damage >= 3:
		_spray(from_x, 0.9)
	EnemyKit.hitstop(get_tree(), 0.08 if damage >= 3 else 0.05)
	if hp <= 0:
		_defeat()


# an air W slam landed on her: out of the sky she goes
func _knock_down():
	_hurt(SLAM_DAMAGE, player.global_position.x)
	if state == State.DEFEATED:
		return
	_fall_v = 300.0
	_set_state(State.FALLING)


# hitting the floor: dust and stars, then she lies stunned
func _crash(shake: bool):
	_crash_sound.play(CRASH_SOUND_SKIP)
	if shake and player:
		player._shake(10.0, 0.3)
	var at := Vector2(global_position.x, floor_y)
	for i in 14:
		var side := 1.0 if i % 2 == 0 else -1.0
		_bits.append([at + Vector2(side * randf_range(4, 18), -1), Vector2(side * randf_range(40, 140), randf_range(-60, -10)),
			randf_range(0.3, 0.55), Pixel.PALE if i % 3 else Pixel.MUSTARD, 200.0])
	for i in 6:
		var d := Vector2.from_angle(-PI / 2.0 + randf_range(-1.0, 1.0))
		_bits.append([global_position, d * randf_range(60, 130), randf_range(0.3, 0.5), Pixel.WHITE, 0.0])
	_set_state(State.STUNNED)


func _defeat():
	if state == State.DEFEATED:
		return
	_set_state(State.DEFEATED)
	remove_from_group("enemies")
	EnemyKit.hitstop(get_tree(), 0.3)      # the moment before she bursts
	for c in get_children():               # her starfruits pop with her
		if c.has_method("cut_in_half") and c.is_alive():
			c.cut_in_half(1)


# beaten: a shower of stars and juice, all the way around
func _burst():
	_burst_done = true
	_burst_sound.play(BURST_SOUND_SKIP)
	if player:
		player._shake(16.0, 0.5)
	for i in 10:
		var aim := Vector2.from_angle(TAU * i / 10.0 + randf_range(-0.2, 0.2))
		_spray(global_position.x - aim.x * 10.0, 1.4, aim)
	for i in 56:
		var d := Vector2.from_angle(randf() * TAU)
		var colours := [Pixel.WHITE, Pixel.MUSTARD, Pixel.MUSTARD, Pixel.GREEN, Pixel.OFF_WHITE]
		_bits.append([global_position + d * randf_range(0, 14), d * randf_range(60, 260), randf_range(0.5, 1.2), colours[i % colours.size()], 60.0])


func _spray(from_x: float, power: float, aim := Vector2.ZERO):
	var s: Node2D = JuiceSpray.new()
	var side := signf(global_position.x - from_x)
	if side == 0.0:
		side = 1.0
	s.color = JUICE
	s.aim = aim if aim != Vector2.ZERO else Vector2(side, -0.35).normalized()
	s.power = power
	s.floor_y = floor_y
	s.position = get_parent().to_local(global_position + s.aim * 14.0)
	get_parent().add_child(s)


func _update_effects(delta: float):
	for b in _bits:
		b[0] += b[1] * delta
		b[1].y += float(b[4]) * delta
		b[1] *= 0.97
		b[2] -= delta
	_bits = _bits.filter(func(b): return b[2] > 0.0)
	for tt in _tosses:
		tt[2] += delta
	_tosses = _tosses.filter(func(tt): return tt[2] < 0.2)
	if state != State.DIVE and not _trail.is_empty() and int(_t * 60.0) % 2 == 0:
		_trail.pop_front()


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


# ---------- drawing ----------
func _star(step: int) -> Array:
	if not _cache.has(step):
		_cache[step] = Starfruit.star_pixels(R_OUT, R_IN, step * TAU / STEPS)
	return _cache[step]


func _draw():
	for tt in _tosses:                    # starfruits she just flung, a quick dotted streak
		var a: Vector2 = to_local(tt[0])
		var b: Vector2 = to_local(tt[1])
		var fade := 1.0 - float(tt[2]) / 0.2
		var n := int(a.distance_to(b) / 6.0)
		for k in n:
			draw_rect(Rect2(a.lerp(b, float(k) / maxf(n, 1)).round(), Vector2(1, 1)), Color(Pixel.MUSTARD, fade))
	for i in _trail.size():               # the comet's tail
		var k := float(i + 1) / float(_trail.size() + 1)
		var p: Vector2 = to_local(_trail[i]).round()
		draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 4)), Color(Pixel.MUSTARD, 0.35 * k))
		if i % 2 == 0:
			draw_rect(Rect2(p + Vector2(randi_range(-6, 6), randi_range(-6, 6)), Vector2(1, 1)), Color(Pixel.WHITE, k))
	if not _burst_done:
		_draw_glow()
		var jitter := Vector2(randi_range(-1, 1), 0) if _flinch > 0.0 or (state == State.WINDUP and state_time > SLIDE_TIME) else Vector2.ZERO
		var white := _flash > 0.0
		var step := posmod(int(roundf(_spin / TAU * STEPS)), STEPS)
		for px in _star(step):
			draw_rect(Rect2(px[0] + jitter, Vector2(1, 1)), Pixel.WHITE if white and px[1] != 0 else Starfruit.star_colour(px[1]))
		_draw_crown(jitter)
		_draw_face(jitter)
		if state == State.STUNNED:
			_draw_dizzy()
		_draw_telegraph()
	for b in _bits:
		var p: Vector2 = to_local(b[0]).round()
		draw_rect(Rect2(p, Vector2(1, 1)), Color(b[3], clampf(float(b[2]) * 3.0, 0.0, 1.0)))


# a pulsing ring of light around her; hot and fast while she winds up a dive
func _draw_glow():
	var hot := state == State.WINDUP and state_time > SLIDE_TIME or (state == State.DIVE and _dive_sub == 2)
	var speed := 12.0 if hot else 3.0
	var pulse := 0.5 + 0.5 * sin(_t * speed)
	for ring in 2:
		var r := 27.0 + ring * 3.0 + pulse
		var a := (0.55 + 0.4 * pulse if hot else 0.15 + 0.2 * pulse) * (1.0 - ring * 0.4)
		var col := Pixel.WHITE if hot and ring == 0 else Pixel.MUSTARD
		for i in 56:
			var p := (Vector2.from_angle(i * TAU / 56.0) * r).round()
			draw_rect(Rect2(p, Vector2(1, 1)), Color(col, a))


func _draw_crown(off: Vector2):
	var top_left := Vector2(-5, -R_OUT - 7) + off
	for row in CROWN.size():
		var line: String = CROWN[row]
		for col in line.length():
			var ch := line[col]
			if ch == ".":
				continue
			var c := Pixel.INK
			if ch == "m":
				c = Pixel.MUSTARD.lightened(0.2) if row < 3 else Pixel.MUSTARD
			elif ch == "r":
				c = Pixel.RED
			draw_rect(Rect2(top_left + Vector2(col, row), Vector2(1, 1)), c)


# her face stays upright whatever her star is doing
func _draw_face(off: Vector2):
	var eyes := [Vector2(-6, -3) + off, Vector2(4, -3) + off]
	var hurt := _flinch > 0.0 or _flash > 0.0
	if state == State.STUNNED:            # x x
		for e in eyes:
			for k in 3:
				draw_rect(Rect2(e + Vector2(k, k), Vector2(1, 1)), Pixel.INK)
				draw_rect(Rect2(e + Vector2(2 - k, k), Vector2(1, 1)), Pixel.INK)
	elif hurt:                            # > <
		for i in 2:
			var e: Vector2 = eyes[i]
			var flip := i == 1
			for k in 3:
				var x := (1 - absi(k - 1)) if not flip else absi(k - 1)
				draw_rect(Rect2(e + Vector2(x, k), Vector2(1, 1)), Pixel.INK)
	else:
		for e in eyes:
			draw_rect(Rect2(e, Vector2(2, 3)), Pixel.INK)
			draw_rect(Rect2(e, Vector2(1, 1)), Pixel.WHITE)
	var angry := state == State.WINDUP or state == State.DIVE
	if angry:                             # brows, slanting in
		draw_rect(Rect2(eyes[0] + Vector2(-1, -2), Vector2(2, 1)), Pixel.INK)
		draw_rect(Rect2(eyes[0] + Vector2(1, -1), Vector2(1, 1)), Pixel.INK)
		draw_rect(Rect2(eyes[1] + Vector2(1, -2), Vector2(2, 1)), Pixel.INK)
		draw_rect(Rect2(eyes[1] + Vector2(0, -1), Vector2(1, 1)), Pixel.INK)
	var m := Vector2(-2, 3) + off
	if angry or hurt:                     # an open mouth
		draw_rect(Rect2(m + Vector2(1, 0), Vector2(3, 2)), Pixel.INK)
	elif state == State.STUNNED:          # a wobbly line
		for k in 5:
			draw_rect(Rect2(m + Vector2(k, k % 2), Vector2(1, 1)), Pixel.INK)
	else:                                 # a smile
		draw_rect(Rect2(m, Vector2(1, 1)), Pixel.INK)
		draw_rect(Rect2(m + Vector2(4, 0), Vector2(1, 1)), Pixel.INK)
		draw_rect(Rect2(m + Vector2(1, 1), Vector2(3, 1)), Pixel.INK)


func _draw_dizzy():
	for i in 3:
		var a := _t * 6.0 + i * TAU / 3.0
		var p := Vector2(cos(a) * 14.0, -R_OUT - 12.0 + sin(a) * 3.0).round()
		draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Pixel.MUSTARD)
		draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Pixel.MUSTARD)
		draw_rect(Rect2(p, Vector2(1, 1)), Pixel.WHITE)


# the dive's warning: a dotted line along the floor where she'll sweep, marching the way she'll go
func _draw_telegraph():
	var from_x := 0.0
	var to_x := 0.0
	if state == State.WINDUP and state_time > SLIDE_TIME:
		from_x = _dive_from
		to_x = _dive_to
	elif state == State.DIVE and _dive_sub == 2:
		from_x = _dive_to
		to_x = _dive_from
	else:
		return
	var y := floor_y - DIVE_HEIGHT - global_position.y
	var dir := signf(to_x - from_x)
	var blink := 0.55 + 0.45 * sin(_t * 14.0)
	var march := fmod(_t * 60.0, 7.0)
	var length := absf(to_x - from_x)
	var d := march
	var i := 0
	while d <= length:
		var x := from_x + dir * d - global_position.x
		draw_rect(Rect2(Vector2(x, y).round() - Vector2(1, 1), Vector2(2, 2)), Color(Pixel.ORANGE if i % 2 == 0 else Pixel.WHITE, blink))
		d += 7.0
		i += 1
	# an arrowhead at the far end
	var tip := Vector2(to_x - global_position.x, y).round()
	for k in 4:
		draw_rect(Rect2(tip + Vector2(-dir * k, -k), Vector2(1, 1)), Color(Pixel.ORANGE, blink))
		draw_rect(Rect2(tip + Vector2(-dir * k, k), Vector2(1, 1)), Color(Pixel.ORANGE, blink))
