extends Node2D
# DRAGONFRUIT DRAKE: Level 3's boss (Volcano Heart). A dragon made of a dragonfruit, flying over the
# caldera. It flies, so it has no collision body: its origin is the middle of its body. Joins "enemies"
# and "boss"; the level HUD draws boss_name and a health bar from hp / max_hp.
# It waits, harmless, until the level calls start_fight(); when beaten it calls
# get_tree().call_group("level", "boss_defeated", self) once.
# The arena (the level's) is a basalt floor at floor_y between arena_left and arena_right, with two stone
# ledges about 90px up. PLACEHOLDER look, drawn in code; Violeta designs the real one, BOOM animates it.
#
# Monster card
#   Moves:     flies over the arena between attacks, drifting to stay on its side of you.
#   Attacks:   FIRE BREATH: swoops low to one side and breathes in, glowing (the warning), then a wall of
#                fire rolls along the floor across the arena. Jump it, or stand on a ledge.
#              DIVE BOMB: screeches and a red mark follows you on the ground, then locks (the warning),
#                and it dives at the mark. Q mid-dive COUNTERS it: 5 damage and it crashes, stunned
#                (head down, ~3s). Missed: it slams the floor (a shockwave rolls both ways: jump it)
#                and is dazed for a moment.
#              SUMMON: calls up to whelp_limit Dragonfruit Whelps, so a counter on its dive chains to them.
#   After:     stunned or dazed on the floor = the punish window (Q 1, W 3, charged smash and flash more).
#   In the air: air Q does 1; an air W slam landing on it does 3 and knocks it down for a moment.
#   Angry:     below half health it's faster, breathes twice and dives more.
#   Touch:     the fire, the shockwaves and the dive hurt; its body doesn't.
#   Drops:     bursts into juice when beaten.
#   Animations BOOM will need: FLY (wing flap), INHALE, BREATHE, SCREECH, DIVE (wings tucked), CRASH,
#              STUNNED (head down), SLAM, KNOCKED, SUMMON (roar), DIE

enum State { IDLE, TAKEOFF, HOVER, BREATH_WINDUP, BREATH, DIVE_WINDUP, DIVE, SLAMMED, CRASH, STUNNED,
	KNOCKED, SUMMON, DYING, DEAD }

@export_group("Look")
@export var juice_color := Color(0.86, 0.2, 0.52)

@export_group("Arena")
@export var arena_left := -400.0       # the arena's walls (absolute x)
@export var arena_right := 400.0
@export var floor_y := 0.0             # the arena's floor (absolute y)
@export var perch_height := 180.0      # how high over the floor it flies between attacks

@export_group("Stats")
@export var max_hp := 30
@export var whelp_limit := 2

const Pixel := preload("res://code/design/pixel_font.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Whelp := preload("res://code/design/dragon_whelp.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")

# the dragonfruit: magenta skin, green-tipped scale flaps, white flesh with black seeds
const MAGENTA := Color(0.86, 0.2, 0.52)
const MAGENTA_DARK := Color(0.6, 0.1, 0.36)
const PINK := Color(0.97, 0.56, 0.74)
const WING := Color(0.42, 0.08, 0.28)
const SCALE_GREEN := Color("76964a")
const SCALE_TIP := Color("a4bf68")
const EYE := Pixel.MUSTARD
const HORN := Pixel.PALE
const FIRE := [Pixel.RED, Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE]   # the flame's red tips in to its white-hot core
const DUST := [Color(0.38, 0.25, 0.13), Color(0.49, 0.43, 0.43)]

const BODY_HALF := 12.0                # from its middle to its claws: on the floor its middle is this high
const HURTBOX := Rect2(-20, -20, 54, 32)   # facing right (mirrored when it faces left)
const TOUCH_BOX := Rect2(-18, -14, 48, 26)
const MOUTH := Vector2(32, -9)         # facing right, from its middle
const HOVER_SPEED := 160.0
const IDLE_TIME := [1.1, 0.7]          # between attacks: normal, angry
const BREATH_LOW := 64.0               # how low over the floor it flies to breathe
const BREATH_EDGE := 70.0              # ...this far in from the arena's wall
const INHALE := [0.85, 0.7]            # the breath's warning: normal, angry
const BREATH_HOLD := 0.6               # it keeps breathing this long after (the last) wall goes out
const SECOND_BREATH := 0.7             # angry: the second wall this long after the first
const FIRE_SPEED := [240.0, 290.0]
const FIRE_SIZE := Vector2(24, 32)
const DIVE_WINDUP := [0.95, 0.8]       # the screech and the mark: follows you for the first 60%, then locks
const DIVE_SPEED := Vector2(250, 760)  # the dive speeds up from / to
const DIVE_ACCEL := 1600.0
const SLAM_DAZE := 1.0                 # missed: dazed this long
const STUN_TIME := 3.0                 # countered: head down on the floor this long
const COUNTER_DAMAGE := 5
const SHOCK_SPEED := 300.0             # the slam's shockwaves...
const SHOCK_RANGE := 240.0             # ...how far they roll
const SHOCK_SIZE := Vector2(20, 14)
const TAKEOFF_TIME := 0.8
const KNOCK_DROP := 50.0               # an air W slam knocks it this far down...
const KNOCK_TIME := 0.6                # ...and it wobbles this long
const SLAM_DAMAGE := 3                 # an air W slam landing on it
const SUMMON_TIME := 0.7
const SUMMON_COOLDOWN := 9.0
const HITSTOP := 0.06
const HITSTOP_HEAVY := 0.1
const DEATH_FREEZE := 0.4
const FLYING := [State.TAKEOFF, State.HOVER, State.BREATH_WINDUP, State.DIVE_WINDUP, State.SUMMON]

const SCREECH_SOUND := preload("res://sounds/sword/sword_scrape_01.wav")  # the dive's warning, pitched up
const SCREECH_SOUND_DB := -6.0
const SCREECH_PITCH := 1.35
const ROAR_PITCH := 0.7                # the same scrape, low: the fight starting, a summon
const BREATH_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")
const BREATH_SOUND_DB := -4.0
const SLAM_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const SLAM_SOUND_DB := -8.0
const SLAM_SOUND_SKIP := 0.02          # the file starts with 20ms of silence
const DAMAGE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const DAMAGE_SOUND_DB := 0.0
const DAMAGE_SOUND_SKIP := 0.12
const DEATH_SOUND := preload("res://sounds/sword/sword_crash_01.wav")
const DEATH_SOUND_DB := 0.0
const DEATH_SOUND_SKIP := 0.03

# the drawn frames, built once and shared: name -> {"map": {Vector2i: Color}, "runs": [[y, x, length, colour]]}
static var _frames := {}

var boss_name := "DRAGONFRUIT DRAKE"
var hp := 30
var state: State = State.IDLE
var state_time := 0.0
var facing := -1
var player: CharacterBody2D = null
var _names: Array = []
var _last_player_state := -1
var _last_player_time := 0.0
var _hit_this_swing := false
var _t := 0.0
var _home := Vector2.ZERO              # where it waits before the fight
var _from := Vector2.ZERO              # takeoff / knock: where the move started
var _hover_x := 0.0
var _angry := false
var _last_attacks := []
var _summon_ready_at := 0.0
var _summoned := false
var _whelps := []
var _arrived := -1.0                   # breath windup: when it got to its spot (-1 = still flying there)
var _side := 1.0                       # breath: which wall it breathes from
var _breaths_left := 0
var _next_breath := 0.0
var _landed := false                   # this dive already hit the player: too late to counter it
var _mark := Vector2.ZERO              # the dive's red mark (where it aims)
var _dive_dir := Vector2.DOWN
var _dive_speed := 0.0
var _crash_vel := Vector2.ZERO
var _flash := 0.0
var _walls := []                       # fire walls rolling along the floor: [x, dir, speed, age]
var _shocks := []                      # shockwaves: [x, dir, distance rolled]
var _streams := []                     # the breath from the mouth to where a wall started: [x, age]
var _defeated_sent := false
var _fx := Node2D.new()                # the fire, shockwaves and the mark, drawn in the world
var _sound := AudioStreamPlayer.new()
var _breath_sound := AudioStreamPlayer.new()
var _breath_fade: Tween
var _damage_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	_build_frames()
	_fx.top_level = true
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	add_child(_sound)
	_breath_sound.stream = BREATH_SOUND
	_breath_sound.volume_db = BREATH_SOUND_DB
	add_child(_breath_sound)
	var squelch := AudioStreamRandomizer.new()
	squelch.add_stream(-1, DAMAGE_SOUND)
	squelch.random_pitch = 1.2
	_damage_sound.stream = squelch
	_damage_sound.volume_db = DAMAGE_SOUND_DB
	_damage_sound.max_polyphony = 3
	add_child(_damage_sound)


# the level calls this when the player walks into the arena
func start_fight():
	if state != State.IDLE:
		return
	_play(SCREECH_SOUND, SCREECH_SOUND_DB, ROAR_PITCH)
	_shake(5.0, 0.3)
	_summon_ready_at = _t + 4.0
	_set_state(State.TAKEOFF)


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_names = player.get_script().State.keys()


func _set_state(s: State):
	state = s
	state_time = 0.0
	_from = global_position
	match s:
		State.HOVER:
			var side := signf(global_position.x - _player_x())
			if side == 0.0:
				side = 1.0
			_hover_x = _clamp_x(_player_x() + side * 150.0)
		State.BREATH_WINDUP:
			_arrived = -1.0
			_side = -1.0 if global_position.x < (arena_left + arena_right) / 2.0 else 1.0
			if absf(_player_x() - _breath_spot().x) < 120.0:
				_side = -_side                # don't breathe from right on top of the player
		State.BREATH:
			_breaths_left = 2 if _angry else 1
			_next_breath = 0.0
			_breath_fade_kill()
			_breath_sound.volume_db = BREATH_SOUND_DB
			_breath_sound.play()
		State.DIVE_WINDUP:
			_play(SCREECH_SOUND, SCREECH_SOUND_DB, SCREECH_PITCH)
			_mark = Vector2(_player_x(), _player_feet_y())
		State.DIVE:
			_landed = false
			_dive_speed = DIVE_SPEED.x
			var aim := _mark + Vector2(0, -BODY_HALF) - global_position
			if aim.y < 40.0:                  # always comes down to the floor
				aim.y = 40.0
			_dive_dir = aim.normalized()
			if absf(_dive_dir.x) > 0.05:
				facing = int(signf(_dive_dir.x))
		State.SUMMON:
			_summoned = false
			_summon_ready_at = _t + SUMMON_COOLDOWN
			_play(SCREECH_SOUND, SCREECH_SOUND_DB, ROAR_PITCH)


func _physics_process(delta: float):
	_t += delta
	state_time += delta
	_flash -= delta
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	_update_fire(delta)
	_update_shocks(delta)
	if state in [State.DYING, State.DEAD]:
		queue_redraw()
		_fx.queue_redraw()
		return
	if player and state != State.IDLE:
		_check_player_attack()
	match state:
		State.IDLE:
			global_position = _home + Vector2(0, sin(_t * 2.2) * 4.0)
		State.TAKEOFF:
			_state_takeoff()
		State.HOVER:
			_state_hover(delta)
		State.BREATH_WINDUP:
			_state_breath_windup(delta)
		State.BREATH:
			_state_breath()
		State.DIVE_WINDUP:
			_state_dive_windup(delta)
		State.DIVE:
			_state_dive(delta)
		State.SLAMMED:
			if state_time >= SLAM_DAZE:
				_set_state(State.TAKEOFF)
		State.CRASH:
			_state_crash(delta)
		State.STUNNED:
			if state_time >= STUN_TIME:
				_set_state(State.TAKEOFF)
		State.KNOCKED:
			_state_knocked()
		State.SUMMON:
			_state_summon(delta)
	queue_redraw()
	_fx.queue_redraw()


# ---------- helpers ----------
func _mult() -> float:
	return 1.3 if _angry else 1.0


func _hover_y() -> float:
	return floor_y - perch_height


func _player_x() -> float:
	return player.global_position.x if player else global_position.x


func _player_feet_y() -> float:
	return player.global_position.y if player and player.is_on_floor() else floor_y


func _clamp_x(x: float) -> float:
	return clampf(x, arena_left + 50.0, arena_right - 50.0)


func _face_player():
	if player and absf(_player_x() - global_position.x) > 4.0:
		facing = int(signf(_player_x() - global_position.x))


# flies towards a point; true once it's there
func _fly_to(target: Vector2, speed: float, delta: float) -> bool:
	global_position = global_position.move_toward(target, speed * delta)
	return global_position.distance_to(target) < 2.0


# a box facing the way it's facing, in the world
func _box(r: Rect2) -> Rect2:
	var x := r.position.x if facing > 0 else -r.position.x - r.size.x
	return Rect2(global_position + Vector2(x, r.position.y), r.size)


func _mouth() -> Vector2:
	return global_position + Vector2(MOUTH.x * facing, MOUTH.y)


func _breath_spot() -> Vector2:
	var x := arena_left + BREATH_EDGE if _side < 0.0 else arena_right - BREATH_EDGE
	return Vector2(x, floor_y - BREATH_LOW)


func _shake(strength: float, seconds: float):
	if player and player.has_method("_shake"):
		player._shake(strength, seconds)


func _play(stream: AudioStream, db: float, pitch := 1.0, skip := 0.0):
	_sound.stream = stream
	_sound.volume_db = db
	_sound.pitch_scale = pitch
	_sound.play(skip)


func _breath_fade_kill():
	if _breath_fade:
		_breath_fade.kill()


func _stop_breath_sound():
	if not _breath_sound.playing:
		return
	_breath_fade_kill()
	_breath_fade = create_tween()
	_breath_fade.tween_property(_breath_sound, "volume_db", -40.0, 0.4)
	_breath_fade.tween_callback(_breath_sound.stop)


# ---------- states ----------
func _state_takeoff():
	var k := clampf(state_time / TAKEOFF_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	global_position = _from.lerp(Vector2(_clamp_x(_from.x), _hover_y()), e)
	_face_player()
	if k >= 1.0:
		_set_state(State.HOVER)


func _state_hover(delta: float):
	_fly_to(Vector2(_hover_x, _hover_y() + sin(_t * 2.2) * 4.0), HOVER_SPEED * _mult(), delta)
	_face_player()
	if state_time >= IDLE_TIME[1 if _angry else 0]:
		_next_attack()


func _next_attack():
	_whelps = _whelps.filter(func(w): return is_instance_valid(w) and w.hp > 0)
	if _whelps.size() < whelp_limit and _t >= _summon_ready_at and randf() < 0.35:
		_set_state(State.SUMMON)
		return
	var pick := "dive" if randf() < (0.6 if _angry else 0.5) else "breath"
	if _last_attacks.size() >= 2 and _last_attacks[-1] == pick and _last_attacks[-2] == pick:
		pick = "breath" if pick == "dive" else "dive"     # never the same one three times running
	_last_attacks.append(pick)
	if _last_attacks.size() > 3:
		_last_attacks.pop_front()
	_set_state(State.DIVE_WINDUP if pick == "dive" else State.BREATH_WINDUP)


# swoops low to one side, then breathes in, glowing (the warning)
func _state_breath_windup(delta: float):
	facing = int(-_side)                     # towards the middle of the arena
	if _arrived < 0.0:
		if _fly_to(_breath_spot(), 300.0 * _mult(), delta) or state_time > 1.4:
			_arrived = state_time
		return
	if state_time - _arrived >= INHALE[1 if _angry else 0]:
		_set_state(State.BREATH)


func _state_breath():
	if _breaths_left > 0 and state_time >= _next_breath:
		_breaths_left -= 1
		_next_breath = state_time + SECOND_BREATH
		var start := clampf(_mouth().x + facing * 10.0, arena_left + 10.0, arena_right - 10.0)
		_walls.append([start, float(facing), FIRE_SPEED[1 if _angry else 0], 0.0])
		_streams.append([start, 0.0])
		_shake(4.0, 0.2)
	if _breaths_left == 0 and state_time >= _next_breath - SECOND_BREATH + BREATH_HOLD:
		_stop_breath_sound()
		_set_state(State.TAKEOFF)


# hovers over the player while the red mark follows them, then the mark locks
func _state_dive_windup(delta: float):
	var time: float = DIVE_WINDUP[1 if _angry else 0]
	if state_time < time * 0.6:
		_mark = Vector2(_player_x(), _player_feet_y())
	_fly_to(Vector2(_clamp_x(_mark.x), _hover_y() - 10.0), 260.0 * _mult(), delta)
	_face_player()
	if state_time >= time:
		_set_state(State.DIVE)


func _state_dive(delta: float):
	_dive_speed = minf(_dive_speed + DIVE_ACCEL * _mult() * delta, DIVE_SPEED.y * _mult())
	global_position += _dive_dir * _dive_speed * delta
	global_position.x = _clamp_x(global_position.x)
	if player and EnemyKit.hurt_player(player, _box(TOUCH_BOX), global_position.x):
		_landed = true
	if global_position.y >= floor_y - BODY_HALF:
		global_position.y = floor_y - BODY_HALF
		_slam()


# missed: it hits the floor, a shockwave rolls out both ways, and it's dazed for a moment
func _slam():
	_set_state(State.SLAMMED)
	_shocks.append([global_position.x, -1.0, 0.0])
	_shocks.append([global_position.x, 1.0, 0.0])
	_play(SLAM_SOUND, SLAM_SOUND_DB, 1.0, SLAM_SOUND_SKIP)
	_shake(10.0, 0.3)
	_burst_dust(Vector2(global_position.x, floor_y))
	get_tree().call_group("living_background", "burst", Vector2(global_position.x, floor_y), 5.0)


# countered: it tumbles out of the air and crashes, stunned
func _state_crash(delta: float):
	_crash_vel.y += 900.0 * delta
	global_position += _crash_vel * delta
	global_position.x = _clamp_x(global_position.x)
	if global_position.y >= floor_y - BODY_HALF:
		global_position.y = floor_y - BODY_HALF
		_set_state(State.STUNNED)
		_play(SLAM_SOUND, SLAM_SOUND_DB - 4.0, 1.0, SLAM_SOUND_SKIP)
		_shake(8.0, 0.25)
		_burst_dust(Vector2(global_position.x, floor_y))


# an air W slam landed on it: knocked down a little, wobbling
func _state_knocked():
	var k := clampf(state_time / 0.2, 0.0, 1.0)
	var low := minf(_from.y + KNOCK_DROP, floor_y - BODY_HALF - 30.0)
	global_position.y = lerpf(_from.y, low, 1.0 - (1.0 - k) * (1.0 - k))
	if state_time >= KNOCK_TIME:
		_set_state(State.HOVER)


func _state_summon(delta: float):
	_fly_to(Vector2(global_position.x, _hover_y() - 30.0), 200.0, delta)
	if not _summoned and state_time >= SUMMON_TIME * 0.6:
		_summoned = true
		_spawn_whelps()
	if state_time >= SUMMON_TIME:
		_set_state(State.HOVER)


func _spawn_whelps():
	_whelps = _whelps.filter(func(w): return is_instance_valid(w) and w.hp > 0)
	var room := whelp_limit - _whelps.size()
	for i in room:
		var w: Node2D = Whelp.new()
		w.respawn_time = 0.0
		w.patrol_range = 40.0
		var k := 0.5 if whelp_limit <= 1 else float(_whelps.size()) / (whelp_limit - 1)
		var at := Vector2(lerpf(arena_left + 100.0, arena_right - 100.0, k), floor_y - 150.0)
		w.position = get_parent().to_local(at)
		get_parent().add_child(w)
		_whelps.append(w)
		_burst_embers(at, 10)


# ---------- the fire and the shockwaves ----------
func _update_fire(delta: float):
	for w in _walls:
		w[0] += w[1] * w[2] * delta
		w[3] += delta
		if player:
			var r := Rect2(w[0] - FIRE_SIZE.x / 2.0, floor_y - FIRE_SIZE.y, FIRE_SIZE.x, FIRE_SIZE.y)
			EnemyKit.hurt_player(player, r, w[0] - w[1] * 30.0)     # pushed the way the fire's going
	_walls = _walls.filter(func(w): return w[0] > arena_left - 20.0 and w[0] < arena_right + 20.0)
	for s in _streams:
		s[1] += delta
	_streams = _streams.filter(func(s): return s[1] < 0.35)


func _update_shocks(delta: float):
	for s in _shocks:
		s[0] += s[1] * SHOCK_SPEED * delta
		s[2] += SHOCK_SPEED * delta
		if player:
			var r := Rect2(s[0] - SHOCK_SIZE.x / 2.0, floor_y - SHOCK_SIZE.y, SHOCK_SIZE.x, SHOCK_SIZE.y)
			EnemyKit.hurt_player(player, r, s[0] - s[1] * 20.0)
	_shocks = _shocks.filter(func(s): return s[2] < SHOCK_RANGE and s[0] > arena_left and s[0] < arena_right)


# ---------- getting hit ----------
func _check_player_attack():
	var ps: int = player.state
	var pt: float = player.state_time
	# a new state, or the same state restarted, is a new swing
	if ps != _last_player_state or pt < _last_player_time:
		_hit_this_swing = false
	_last_player_state = ps
	_last_player_time = pt
	if _hit_this_swing:
		return
	var hit := EnemyKit.player_attack_hitting(player, _names, _box(HURTBOX))
	if hit.is_empty():
		return
	_hit_this_swing = true
	if _names[ps] == "DASH_ATTACK_HEAVY_SLAM":      # an air W slam coming down on it
		var knock := state in FLYING
		take_hit(SLAM_DAMAGE, hit["push"])
		if knock and state in FLYING:
			_set_state(State.KNOCKED)
		return
	take_hit(hit["damage"], hit["push"])


func take_hit(damage: int, push: Vector2):
	if state in [State.IDLE, State.DYING, State.DEAD]:
		return
	hp -= damage
	_flash = 0.08
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	var side := signf(push.x)
	if side == 0.0:
		side = signf(global_position.x - _player_x())
	_spray(Vector2(side if side != 0.0 else 1.0, -0.35).normalized(), 1.0 + (damage - 1) * 0.4)
	EnemyKit.hitstop(get_tree(), HITSTOP_HEAVY if damage >= 3 else HITSTOP)
	if hp <= 0:
		_start_dying()
		return
	if not _angry and hp <= max_hp / 2.0:
		_angry = true                     # roars, and fights faster from now on
		_play(SCREECH_SOUND, SCREECH_SOUND_DB, ROAR_PITCH)


func is_alive() -> bool:
	return state not in [State.IDLE, State.DYING, State.DEAD] and hp > 0


# the player's counter catches it any time in the dive, until the dive has hit them
func is_counterable() -> bool:
	return state == State.DIVE and not _landed


# countered (code/counter_chain.gd, with time stopped): a big hit, and it tumbles out of the air
func countered(dir: int):
	if state != State.DIVE:
		return
	_landed = true
	hp -= COUNTER_DAMAGE
	_flash = 0.15
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	_spray(Vector2(dir, -0.35).normalized(), 1.8)
	_crash_vel = Vector2(dir * 90.0, -80.0)
	_set_state(State.CRASH)
	if hp <= 0:
		_start_dying()


func _spray(aim: Vector2, power: float):
	var s: Node2D = JuiceSpray.new()
	s.color = juice_color
	s.aim = aim
	s.power = power
	s.floor_y = floor_y
	s.position = get_parent().to_local(global_position + Vector2(aim.x * 20.0, -4.0))
	get_parent().add_child(s)


# beaten: everything freezes for a moment, then it bursts apart
func _start_dying():
	if state in [State.DYING, State.DEAD]:
		return
	hp = 0
	_set_state(State.DYING)
	_walls.clear()
	_shocks.clear()
	_streams.clear()
	_stop_breath_sound()
	EnemyKit.hitstop(get_tree(), DEATH_FREEZE)
	get_tree().create_timer(DEATH_FREEZE, true, false, true).timeout.connect(_burst_apart)


func _burst_apart():
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	for i in 12:
		_spray(Vector2.from_angle(TAU * i / 12.0 + randf_range(-0.2, 0.2)), 1.6)
	_burst_embers(global_position, 30)
	_fling_chunks()
	_play(DEATH_SOUND, DEATH_SOUND_DB, 1.0, DEATH_SOUND_SKIP)
	_shake(16.0, 0.5)
	get_tree().call_group("living_background", "burst", global_position, 7.0)
	for w in _whelps:                       # its whelps pop with it
		if is_instance_valid(w) and w.hp > 0:
			w.take_hit(1, Vector2.ZERO)
	get_tree().create_timer(1.2).timeout.connect(_send_defeated)


func _send_defeated():
	if _defeated_sent:
		return
	_defeated_sent = true
	get_tree().call_group("level", "boss_defeated", self)


# ---------- effects ----------
func _burst_embers(at: Vector2, amount: int):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 160.0
	p.gravity = Vector2(0, -60)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color_ramp = Gradient.new()
	p.color_ramp.set_color(0, Pixel.MUSTARD)
	p.color_ramp.set_color(1, Color(Pixel.RED, 0.0))
	p.z_index = 6
	p.position = get_parent().to_local(at)
	p.finished.connect(p.queue_free)
	get_parent().add_child(p)
	p.emitting = true


func _burst_dust(at: Vector2):
	for i in 2:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = 12
		p.lifetime = 0.6
		p.explosiveness = 1.0
		p.direction = Vector2.UP
		p.spread = 75.0
		p.initial_velocity_min = 60.0
		p.initial_velocity_max = 180.0
		p.gravity = Vector2(0, 600)
		p.scale_amount_min = 2.0
		p.scale_amount_max = 2.0
		p.color = DUST[i]
		p.z_index = 6
		p.position = get_parent().to_local(at)
		p.finished.connect(p.queue_free)
		get_parent().add_child(p)
		p.emitting = true


# beaten: the frame it was showing breaks into chunks that fly off, tumble and fade
func _fling_chunks():
	var map: Dictionary = _frames[_frame_name()]["map"]
	var sectors := []
	for i in 6:
		sectors.append([])
	for key in map:
		var p: Vector2i = key
		var center := Vector2(facing * (p.x + 0.5), p.y + 0.5)
		var sector := int(fposmod(center.angle() + randf_range(-0.15, 0.15), TAU) / TAU * 6.0) % 6
		sectors[sector].append([center, map[key]])
	for list in sectors:
		if list.is_empty():
			continue
		var c := Vector2.ZERO
		for px in list:
			c += px[0]
		c /= list.size()
		var chunk := Chunk.new()
		for px in list:
			chunk.pixels.append([px[0] - c - Vector2(0.5, 0.5), px[1]])
		chunk.vel = c.normalized() * randf_range(120.0, 220.0) + Vector2(0, -120.0)
		chunk.spin = randf_range(-6.0, 6.0)
		chunk.floor_y = floor_y
		get_parent().add_child(chunk)
		chunk.global_position = global_position + c


# a piece of the beaten drake: its pixels, flying, bouncing once, fading
class Chunk extends Node2D:
	var pixels := []                     # [offset, colour]
	var vel := Vector2.ZERO
	var spin := 0.0
	var floor_y := 0.0
	var _age := 0.0
	var _bounced := false

	func _physics_process(delta: float):
		_age += delta
		vel.y += 700.0 * delta
		position += vel * delta
		rotation += spin * delta
		if global_position.y >= floor_y - 4.0 and vel.y > 0.0 and not _bounced:
			_bounced = true
			vel = Vector2(vel.x * 0.5, -vel.y * 0.3)
			spin *= 0.4
		if _age > 0.9:
			modulate.a = maxf(0.0, 1.0 - (_age - 0.9) / 0.6)
		if _age > 1.5:
			queue_free()

	func _draw():
		for px in pixels:
			draw_rect(Rect2(px[0], Vector2(1, 1)), px[1])


# ---------- drawing ----------
func _frame_name() -> String:
	match state:
		State.DIVE:
			return "tuck"
		State.SLAMMED, State.CRASH, State.STUNNED, State.DYING, State.DEAD:
			return "down"
	var rate := 11.0 if _angry or state in [State.BREATH_WINDUP, State.DIVE_WINDUP, State.SUMMON] else 7.0
	return ["up", "mid", "down", "mid"][int(_t * rate) % 4]


# how it's tilted right now
func _tilt() -> float:
	match state:
		State.DIVE:
			return atan2(_dive_dir.y * facing, absf(_dive_dir.x))
		State.CRASH:
			return state_time * 7.0 * facing
		State.STUNNED, State.SLAMMED:
			return 0.45 * facing           # head down on the floor
		State.KNOCKED:
			return sin(state_time * 25.0) * 0.25 * (1.0 - clampf(state_time / KNOCK_TIME, 0.0, 1.0))
	return sin(_t * 2.0) * 0.05


func _glow() -> float:
	if state == State.BREATH:
		return 0.6
	if state == State.BREATH_WINDUP and _arrived >= 0.0:
		return clampf((state_time - _arrived) / INHALE[1 if _angry else 0], 0.0, 1.0) * 0.6
	return 0.0


func _draw():
	if state == State.DEAD:
		return
	var offset := Vector2.ZERO
	if (state == State.BREATH_WINDUP and _arrived >= 0.0) or state == State.SUMMON:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).round()
	var glow := _glow()
	var white := _flash > 0.0 or state == State.DYING
	draw_set_transform(offset, _tilt(), Vector2(facing, 1))
	for r in _frames[_frame_name()]["runs"]:
		var c: Color = r[3]
		if white and c != Pixel.INK:
			c = Pixel.WHITE
		elif glow > 0.0 and c != Pixel.INK:
			c = c.lerp(Pixel.ORANGE, glow * (0.7 + 0.3 * sin(_t * 30.0)))
		elif _angry and c == EYE:
			c = Pixel.ORANGE if int(_t * 6.0) % 2 == 0 else Pixel.RED
		draw_rect(Rect2(r[1], r[0], r[2], 1), c)
	if glow > 0.0:                         # fire in its open mouth
		for i in 6:
			var p := MOUTH + Vector2(-2 + i % 3, -1 + floori(i / 3.0))
			draw_rect(Rect2(p, Vector2(1, 1)), FIRE[1 + (i + int(_t * 20.0)) % 3])
	draw_set_transform(Vector2.ZERO)
	if state == State.STUNNED:             # dizzy stars over its head
		var head := Vector2(22.0 * facing, -12.0).rotated(_tilt())
		for i in 3:
			var a := state_time * 6.0 + i * TAU / 3.0
			var p := (head + Vector2(cos(a) * 12.0, -10.0 + sin(a) * 3.0)).round()
			draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Pixel.MUSTARD)
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Pixel.MUSTARD)
			draw_rect(Rect2(p, Vector2(1, 1)), Pixel.OFF_WHITE)


# the fire walls, the breath, the shockwaves, the dive's mark and the embers it breathes in (world space)
func _draw_fx():
	for w in _walls:
		_draw_fire(w[0], float(w[3]))
	for s in _streams:
		var a := _mouth()
		var b := Vector2(s[0], floor_y - 4.0)
		var steps := maxi(int(a.distance_to(b) / 2.0), 1)
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps).round()
			var size := 2.0 + 2.0 * float(k) / steps
			_fx.draw_rect(Rect2(p - Vector2(size, size) / 2.0, Vector2(size, size)), FIRE[(k + int(_t * 24.0)) % 3])
	for s in _shocks:
		_draw_shock(s[0], s[1], s[2])
	if state == State.DIVE_WINDUP or (state == State.DIVE and global_position.y < _mark.y - 30.0):
		_draw_mark()
	if state == State.BREATH_WINDUP and _arrived >= 0.0:
		var m := _mouth()
		for i in 10:
			var k := fposmod(_t * 2.0 + i / 10.0, 1.0)
			var p := (m + Vector2.from_angle(i * 2.4) * 46.0 * (1.0 - k)).round()
			_fx.draw_rect(Rect2(p, Vector2(1, 1)), Color(FIRE[i % 3], k))


# a wall of fire: flickering flame columns, red at the bottom up to white-hot tips
func _draw_fire(x: float, age: float):
	var alpha := clampf(age / 0.1, 0.0, 1.0)
	for c in int(FIRE_SIZE.x):
		var edge := 1.0 - absf(c - FIRE_SIZE.x / 2.0 + 0.5) / (FIRE_SIZE.x / 2.0) * 0.6
		var flick := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 18.0 + c * 0.9 + x * 0.05))
		var h := roundf(FIRE_SIZE.y * flick * edge)
		var px := roundf(x - FIRE_SIZE.x / 2.0 + c)
		var bands := [h, h * 0.7, h * 0.4, h * 0.15]     # red to the tip, hotter towards the base
		for i in 4:
			var bh: float = roundf(bands[i])
			if bh > 0.0:
				_fx.draw_rect(Rect2(px, floor_y - bh, 1, bh), Color(FIRE[i], alpha))
	for i in 4:                             # embers flicking up off it
		var k := fposmod(_t * 1.5 + i * 0.27 + x * 0.01, 1.0)
		var p := Vector2(x + sin(_t * 7.0 + i) * 8.0, floor_y - FIRE_SIZE.y - k * 24.0).round()
		_fx.draw_rect(Rect2(p, Vector2(1, 1)), Color(Pixel.MUSTARD, alpha * (1.0 - k)))


# a shockwave: a hump of rubble and dust with a glowing crack under it
func _draw_shock(x: float, dir: float, rolled: float):
	var fade := 1.0 - clampf(rolled / SHOCK_RANGE, 0.0, 1.0)
	for c in int(SHOCK_SIZE.x):
		var h := roundf(SHOCK_SIZE.y * sin(c / SHOCK_SIZE.x * PI) * (0.7 + 0.3 * fade))
		var px := roundf(x - dir * (SHOCK_SIZE.x / 2.0 - c))
		if h > 0.0:
			_fx.draw_rect(Rect2(px, floor_y - h, 1, h), Color(DUST[c % 2], fade))
	_fx.draw_rect(Rect2(roundf(x - SHOCK_SIZE.x / 2.0), floor_y - 1.0, SHOCK_SIZE.x, 1), Color(Pixel.ORANGE, fade))


# the dive's red mark: a ring on the ground with a cross, blinking faster once it's locked on
func _draw_mark():
	var time: float = DIVE_WINDUP[1 if _angry else 0]
	var locked := state == State.DIVE or state_time >= time * 0.6
	var on := int(_t * (14.0 if locked else 6.0)) % 2 == 0
	var a := 1.0 if on else 0.45
	for i in 20:
		var p := (_mark + Vector2(cos(i * TAU / 20.0) * 18.0, sin(i * TAU / 20.0) * 4.0 - 2.0)).round()
		_fx.draw_rect(Rect2(p, Vector2(2, 1)), Color(Pixel.RED, a))
	_fx.draw_rect(Rect2(_mark.x - 6.0, _mark.y - 2.0, 13, 1), Color(Pixel.ORANGE, a))
	_fx.draw_rect(Rect2(_mark.x, _mark.y - 5.0, 1, 7), Color(Pixel.ORANGE, a))
	if locked:
		_fx.draw_rect(Rect2(_mark.x - 1.0, _mark.y - 3.0, 3, 3), Color(Pixel.WHITE, a))


# ---------- the placeholder art, built from shapes into pixels (helpers from dragon_whelp.gd) ----------
func _build_frames():
	if not _frames.is_empty():
		return
	# wings behind the body: [polygon, bone tips]
	var wings := {
		"up": [[Vector2(-8, -6), Vector2(6, -8), Vector2(10, -20), Vector2(4, -30), Vector2(-6, -34),
			Vector2(-16, -28), Vector2(-22, -22), Vector2(-14, -12)], [Vector2(4, -30), Vector2(-6, -34), Vector2(-22, -22)]],
		"mid": [[Vector2(-8, -6), Vector2(6, -8), Vector2(4, -16), Vector2(-6, -22), Vector2(-18, -25),
			Vector2(-28, -18), Vector2(-18, -10)], [Vector2(-6, -22), Vector2(-18, -25), Vector2(-28, -18)]],
		"down": [[Vector2(-8, -4), Vector2(6, -6), Vector2(4, 4), Vector2(-6, 10), Vector2(-18, 12),
			Vector2(-28, 6), Vector2(-18, -1)], [Vector2(-6, 10), Vector2(-18, 12), Vector2(-28, 6)]],
		"tuck": [[Vector2(-8, -6), Vector2(6, -8), Vector2(-4, -14), Vector2(-20, -14), Vector2(-30, -8),
			Vector2(-16, -4)], [Vector2(-20, -14), Vector2(-30, -8)]],
	}
	for frame_name in wings:
		var map := {}
		var wing: Array = wings[frame_name]
		Whelp.fill_poly(map, PackedVector2Array(wing[0]), WING)
		for tip in wing[1]:
			Whelp.draw_line_px(map, Vector2(0, -8), tip, MAGENTA_DARK)
		# the tail, thick to thin, with a green spade at the end
		for seg in [[Vector2(-14, 2), 4.0], [Vector2(-19, 4), 3.4], [Vector2(-24, 6), 2.8], [Vector2(-29, 7), 2.2], [Vector2(-33, 8), 1.6]]:
			Whelp.fill_ellipse(map, seg[0], Vector2(seg[1], seg[1]), MAGENTA)
		Whelp.fill_poly(map, PackedVector2Array([Vector2(-33, 5), Vector2(-41, 6), Vector2(-34, 11)]), SCALE_GREEN)
		# the body: magenta, darker underneath, a highlight on top; white flesh and black seeds on the belly
		var body := {}
		Whelp.fill_ellipse(body, Vector2.ZERO, Vector2(16, 10), MAGENTA)
		for key in body:
			var p: Vector2i = key
			var c := MAGENTA
			if p.y >= 5:
				c = MAGENTA_DARK
			elif p.y <= -6 and p.x <= 4:
				c = PINK
			var belly := Vector2((p.x - 3.0) / 13.0, (p.y - 4.0) / 6.0)
			if p.y >= 1 and belly.length_squared() <= 1.0:
				c = Pixel.OFF_WHITE
				if (p.x * 7 + p.y * 13) % 11 == 0:
					c = Pixel.INK
			map[p] = c
		# green-tipped scale flaps along its back
		for k in 7:
			var a := lerpf(PI * 1.08, PI * 1.92, k / 6.0)
			var base := Vector2(cos(a) * 15.0, sin(a) * 9.0)
			var out := Vector2(cos(a), sin(a))
			var p := Vector2i(roundi(base.x), roundi(base.y))
			map[p] = SCALE_GREEN
			map[p + Vector2i(roundi(out.x - 1.0), roundi(out.y))] = SCALE_GREEN
			map[p + Vector2i(roundi(out.x * 2.0 - 1.0), roundi(out.y * 2.0))] = SCALE_TIP
		# the neck and head: snout, a dark jaw, a glowing eye under a heavy brow, two swept-back horns
		for seg in [[Vector2(13, -4), 5.0], [Vector2(16, -7), 4.5], [Vector2(19, -10), 4.0]]:
			Whelp.fill_ellipse(map, seg[0], Vector2(seg[1], seg[1]), MAGENTA)
		Whelp.fill_ellipse(map, Vector2(22, -12), Vector2(7, 5), MAGENTA)
		Whelp.fill_ellipse(map, Vector2(29, -10), Vector2(4.5, 3.2), MAGENTA)
		for key in map.keys():
			var p: Vector2i = key
			if p.x >= 17 and p.y >= -9 and map[p] == MAGENTA:
				map[p] = MAGENTA_DARK
		Whelp.draw_line_px(map, Vector2(24, -8), Vector2(33, -9), Pixel.INK)
		map[Vector2i(31, -12)] = Pixel.INK
		map[Vector2i(23, -14)] = EYE
		map[Vector2i(24, -14)] = EYE
		for p in [Vector2i(22, -16), Vector2i(23, -16), Vector2i(24, -15), Vector2i(25, -15)]:
			map[p] = MAGENTA_DARK
		Whelp.draw_line_px(map, Vector2(19, -16), Vector2(13, -22), HORN)
		Whelp.draw_line_px(map, Vector2(20, -16), Vector2(14, -22), HORN)
		Whelp.draw_line_px(map, Vector2(13, -22), Vector2(11, -23), HORN)
		Whelp.draw_line_px(map, Vector2(23, -17), Vector2(19, -23), HORN)
		map[Vector2i(18, -16)] = SCALE_GREEN
		map[Vector2i(17, -17)] = SCALE_TIP
		# claws tucked under the belly
		for p in [Vector2i(6, 10), Vector2i(7, 11), Vector2i(-6, 10), Vector2i(-5, 11)]:
			map[p] = MAGENTA_DARK
		Whelp.outline(map, Pixel.INK)
		_frames[frame_name] = {"map": map, "runs": Whelp.runs(map)}
