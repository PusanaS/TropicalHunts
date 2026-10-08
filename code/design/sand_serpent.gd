extends Node2D
# SNAKE FRUIT SERPENT (level 1's mine, Morgan's idea): a salak (the real "snake fruit": scaly reddish-brown
# skin, a pointy tip, creamy white flesh) that lives in pit sand. It snakes in and out of the sand around
# you and strikes, its neck stretching all the way to you. Q only knocks its head back; only W kills it
# (Morgan's call).
#
# Monster card (Snake fruit serpent)
#   Moves:     swims under the sand towards a spot beside you: a bulge ploughs along the surface with a
#              trail behind it, and now and then its back breaches in humps.
#   Attack:    bursts up in a sand geyser, rears and sways, hissing, tongue flicking. Then the tell:
#              it coils back, its eyes flash and its mouth opens, and it strikes, stretching all the way
#              to you.
#   After:     holds a moment, pulls back and dives, and comes up somewhere else.
#   Beaten by: W on its head (or neck) while it's up: any W kills it (the smash, the running W, the air
#              slam, the charged smash). Q doesn't hurt it: the blade clangs off its scales (the sound
#              of Q on the Pineapple's armour) and knocks its head back; it rears and strikes again
#              (after a few knocks it dives). It can't be countered.
#   Touch:     only the strike hurts.
#   Drops:     one juice drop (creamy snake-fruit flesh).
#   Animations BOOM / Violeta will need: SWIM (bulge + humps), EMERGE, REAR (sway + hiss), COIL (the
#              tell), STRIKE, RECOIL, HURT (repelled), STUNNED, DIVE, DIE (the body bursting, head first).
# A Node2D on the sand's top (y = the sand floor). It travels along under the sand within
# range_left..range_right (global x). It's drawn at z -1, so a quicksand over the sand (its sand is drawn
# at z 3) hides whatever is under the surface. Only one serpent strikes at a time.
# PLACEHOLDER art drawn in code (BOOM's style: flat colours, one shade each, whole pixels).

enum State { SWIM, EMERGE, REAR, STRIKE, HOLD, RECOIL, REPELLED, STUNNED, DIVE, DYING, DEAD, DRAG }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const NoDamagePop := preload("res://code/design/no_damage_pop.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
const JuiceDrop := preload("res://code/design/juice_drop.gd")
# every hit: a wet squelch, a different pitch each time (like the minion's)
const HIT_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const HIT_SOUND_DB := 0.0
const HIT_SOUND_SKIP := 0.12          # the file starts with 0.12 s of silence
const KILL_SOUND := preload("res://sounds/sword/sword_hit_flesh_03.wav")
const KILL_SOUND_DB := -3.0
const KILL_SOUND_SKIP := 0.025        # the file swells in over 40ms; start partway in
# Q clanging off its scales: the same as Q on the Pineapple's armour (fruit_boss.gd)
const CLANG_SOUND := preload("res://sounds/sword/sword_clash_06.wav")
const CLANG_SOUND_DB := -6.0
const CLANG_SOUND_SKIP := 0.012
# bursting up out of the sand: the water splash, quiet and pitched down so it reads as sand
const SAND_SOUND := preload("res://sounds/WAVE_SOUND_universfield-water-splash-199583.mp3")
const SAND_SOUND_DB := -12.0
const SAND_SOUND_SKIP := 0.17

# timing (seconds) and reach (pixels)
const SWIM_SPEED := 130.0
const EMERGE_TIME := 0.22
const SWAY_TIME := 0.3                # rearing up, swaying and hissing...
const COIL_TIME := 0.38               # ...then the tell: coils back, eyes flash, mouth opens
const STRIKE_TIME := 0.16
const HOLD_TIME := 0.14               # stretched out after the strike (still counterable)
const RECOIL_TIME := 0.28
# its bite drags you down (Morgan's call, 2026-10-08): it hauls you straight back to where its body comes out of
# the sand, then pulls you right under. You're back at the last checkpoint (OOPS!), and on the juice clock it
# costs PENALTY seconds (a red "-5s" flies off to the countdown).
const DRAG_TIME := 0.32
const DRAG_TO := Vector2(0, -12)      # the head gets here with you (just over its root)...
const PULL_TIME := 0.4                # ...then pulls you down under the sand
const PENALTY := 5.0
const REPEL_TIME := 0.35              # knocked back by a hit, then it dives
# Q's knock: the head whips way back and up, chin in the air, overshoots, wobbles dazed, then comes again
# (Morgan wanted it to really knock the head back)
const KNOCK_BACK := Vector2(64, -34)  # how far the head is thrown (away from you, and up)
const KNOCK_TIME := 0.6
const STUN_TIME := 0.9                # flopped on the sand after a parry it lived through
const DIVE_TIME := 0.25
const RESURFACE := 0.7                # under the sand this long after an attack before it comes up again
const RESURFACE_HURT := 1.2           # ...and this long after being hit
const STRIKE_GAP := 0.45              # between any two serpents' attacks (real seconds)
const STRIKE_REACH := 220.0          # its neck stretches all the way to you (Morgan's call): it follows you as it strikes
const KNOCKS := 3                    # Q knocks its head back this many times, then it dives and comes up elsewhere
# the swings that kill it (any W); everything else (Q) only knocks its head back
const KILLING_SWINGS := ["ATTACK_HEAVY_SMASH", "DASH_ATTACK_HEAVY_SLAM", "DASH_ATTACK_HEAVY_IMPACT", "CHARGED_SMASH"]
const EMERGE_DIST := Vector2(60, 100) # it comes up this far in front of or behind you
const MIN_EMERGE_GAP := 48.0          # never right under you
const NEAR_Y := 60.0                  # you have to be about level with the sand for it to come at you
const REAR_HEIGHT := 34.0             # the head reared up (low enough for a Q to reach)
const HUMP_TIME := 0.6
const POP_EVERY := 0.05               # dying: a piece of it bursts this often, head first

# shape
const SEGMENTS := 15                  # body pieces from the sand to the head
const ENTRY := Vector2(0, 10)         # where the body goes into the sand (local: under the surface)
const TUCKED := Vector2(0, 16)        # the head under the sand
const SURFACE := -5.0                 # the sand's top edge, drawn by the quicksand (local y)
const HEAD_BOX := Rect2(-9, -8, 18, 16)
const PLAYER_BODY := Vector2(0, -20)  # it strikes at the middle of you

# colours
const SKIN := Color("7a3b1f")
const SKIN_SHADE := Color("54260f")
const SCALE_LIGHT := Color("b0663a")
const BELLY := Color("e9d8a6")
const EYE := Color("f2c22e")
const PUPIL := Color("1d0f08")
const TONGUE := Color("c2282b")
const MOUTH := Color("5a1410")
const FLESH := Color("f3ead0")
const STAR := Color("ccad4b")
const SAND_TOP := Color("efcf86")     # the quicksand's own colours
const SAND := Color("d39b4a")
const SAND_SHADE := Color("a8722f")
const SAND_SWIRL := Color("f6e2ad")

@export var range_left := 5680.0      # global x it stays within (the sand)
@export var range_right := 6480.0
@export var max_hp := 2
@export var juice_color := Color(0.95, 0.91, 0.76)   # creamy snake-fruit flesh

static var _striker := 0              # the serpent attacking right now (instance id; 0 = none)
static var _next_strike_at := 0.0     # real time the next one may come up

var hp := 2
var state: State = State.SWIM
var state_time := 0.0
var player: CharacterBody2D = null
var body_half_width := 10.0           # counter_chain.gd lands this far beside it
var _names: Array = []
var _dir := -1.0                      # which way it faces: towards you
var _head := TUCKED                   # the head (local)
var _head_from := Vector2.ZERO        # where the current move started
var _strike_to := Vector2.ZERO
var _repel_to := Vector2.ZERO
var _aimed := false
var _landed := false                  # this strike already hit you: too late to counter it
var _dragging := false                # it has you in its jaws
var _target_x := 0.0
var _target_for := 0.0                # where you were when that target was picked
var _swim_dir := 1.0
var _wait := 0.0                      # time left under the sand before it may come up
var _dive_wait := RESURFACE
var _flash := 0.0
var _hump_t := -1.0                   # a hump breaching: its age (-1 = none)
var _next_hump := 1.0
var _trail: Array = []                # [global x, age]
var _trail_tick := 0.0
var _bits: Array = []                 # scales, juice and sand: [local pos, vel, size, colour, life, gravity]
var _geyser := 0.0                    # a sand column bursting up (fades)
var _popped := 0
var _pop_t := 0.0
var _pop_dir := 1.0
var _splat := 0.0                     # dead: the puddle it leaves on the sand (fades)
var _t := 0.0
var _last_player_state := -1
var _last_player_time := 0.0
var _hit_this_swing := false
var _light := PointLight2D.new()
var _hit_sound := AudioStreamPlayer.new()
var _clang := AudioStreamPlayer.new()
var _knocked := false                 # Q knocked its head back: it rears and strikes again
var _knocks := 0
var _knock_dir := 1.0               # which way Q knocked its head (away from you)
var _kill_sound := AudioStreamPlayer.new()
var _sand_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")           # other code finds enemies here and calls take_hit(damage, push)
	z_index = -1                      # under the quicksand's sand (z 3): it hides whatever is below the surface
	hp = max_hp
	_target_x = global_position.x
	_wait = randf_range(0.3, 1.0)
	var squelch := AudioStreamRandomizer.new()
	squelch.add_stream(-1, HIT_SOUND)
	squelch.random_pitch = 1.3
	squelch.random_volume_offset_db = 2.0
	_hit_sound.stream = squelch
	_hit_sound.volume_db = HIT_SOUND_DB
	_hit_sound.max_polyphony = 3
	add_child(_hit_sound)
	_clang.stream = CLANG_SOUND
	_clang.volume_db = CLANG_SOUND_DB
	add_child(_clang)
	_kill_sound.stream = KILL_SOUND
	_kill_sound.volume_db = KILL_SOUND_DB
	add_child(_kill_sound)
	_sand_sound.stream = SAND_SOUND
	_sand_sound.volume_db = SAND_SOUND_DB
	_sand_sound.pitch_scale = 0.75
	add_child(_sand_sound)
	# a faint glow around its eyes (the mine is dark)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_light.texture = tex
	_light.color = Color(1.0, 0.82, 0.35)
	_light.energy = 0.6
	_light.texture_scale = 0.6
	_light.enabled = false
	add_child(_light)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _set_state(s: State):
	state = s
	state_time = 0.0


func _physics_process(delta: float):
	_t += delta
	state_time += delta
	_flash = maxf(_flash - delta, 0.0)
	_geyser = maxf(_geyser - delta * 4.0, 0.0)
	_update_bits(delta)
	for tr: Array in _trail:
		tr[1] += delta
	_trail = _trail.filter(func(tr): return tr[1] < 0.6)
	if state == State.DEAD:
		_splat = maxf(_splat - delta * 0.25, 0.0)
		queue_redraw()
		if _splat <= 0.0 and _bits.is_empty() and _trail.is_empty():
			set_physics_process(false)                    # all gone: nothing left to move or draw
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player:
			_names = player.get_script().State.keys()
	if player and state != State.DYING:
		_check_player_attack()
	match state:
		State.SWIM:
			_swim(delta)
		State.EMERGE:
			_face_player()
			var k := clampf(state_time / EMERGE_TIME, 0.0, 1.0)
			_head = TUCKED.lerp(_rest(), 1.0 - pow(1.0 - k, 3.0))
			if k >= 1.0:
				_aimed = false
				_knocks = 0
				_set_state(State.REAR)
		State.REAR:
			_rear(delta)
		State.STRIKE:
			_strike_to = _aim()                                   # it follows you all the way in
			var k := clampf(state_time / STRIKE_TIME, 0.0, 1.0)
			var e := 1.0 - (1.0 - k) * (1.0 - k)
			_head = _head_from.lerp(_strike_to, e) + Vector2(0, -14.0 * sin(PI * k))   # a curved lunge
			_bite()
			if k >= 1.0:
				_set_state(State.HOLD)
		State.HOLD:
			_head = _strike_to + Vector2(0, roundf(sin(_t * 30.0)))
			_bite()
			if state_time >= HOLD_TIME:
				_head_from = _head
				_set_state(State.RECOIL)
		State.DRAG:                                           # hauling you back to its root, then right under
			if state_time < DRAG_TIME:
				var k := state_time / DRAG_TIME
				_head = _head_from.lerp(DRAG_TO, k * k * (3.0 - 2.0 * k))
			else:
				var k := clampf((state_time - DRAG_TIME) / PULL_TIME, 0.0, 1.0)
				_head = DRAG_TO.lerp(TUCKED + Vector2(0, 24), k * k)
				if randf() < delta * 30.0:
					_burst_sand(0.3)
			if player and is_instance_valid(player):
				player.global_position = global_position + _head - PLAYER_BODY
			if state_time >= DRAG_TIME + PULL_TIME:
				_end_drag()
		State.RECOIL:
			var k := clampf(state_time / RECOIL_TIME, 0.0, 1.0)
			_head = _head_from.lerp(_rest(), 1.0 - pow(1.0 - k, 2.0))
			if k >= 1.0:
				_dive(RESURFACE)
		State.REPELLED:
			var k := clampf(state_time / (KNOCK_TIME if _knocked else REPEL_TIME), 0.0, 1.0)
			if _knocked:
				# whipped back hard (overshooting), then it sags back a little and wobbles, dazed
				var snap := clampf(state_time / 0.14, 0.0, 1.0)
				var back := 1.0 + 2.7 * pow(snap - 1.0, 3.0) + 1.7 * pow(snap - 1.0, 2.0)
				var sag := 0.25 * clampf((state_time - 0.14) / (KNOCK_TIME - 0.14), 0.0, 1.0)
				_head = _head_from.lerp(_repel_to, back - sag) + Vector2(sin(state_time * 38.0) * 3.0 * (1.0 - k), 0)
			else:
				_head = _head_from.lerp(_repel_to, 1.0 - pow(1.0 - k, 3.0)) + Vector2(sin(state_time * 60.0) * 2.0 * (1.0 - k), 0)
			if k >= 1.0:
				if _knocked and _knocks < KNOCKS:              # knocked back by Q: it comes at you again
					_knocked = false
					_aimed = false
					_set_state(State.REAR)
				else:
					_knocked = false
					_dive(RESURFACE_HURT)
		State.STUNNED:
			var k := clampf(state_time / 0.2, 0.0, 1.0)
			_head = _head_from.lerp(Vector2(_dir * 30.0, SURFACE - 3.0), k * k)          # flopped on the sand
			if state_time >= STUN_TIME:
				_dive(RESURFACE_HURT)
		State.DIVE:
			var k := clampf(state_time / DIVE_TIME, 0.0, 1.0)
			_head = _head_from.lerp(TUCKED, k * k)
			if k >= 1.0:
				_set_state(State.SWIM)
				_wait = _dive_wait
				_pick_target()
		State.DYING:
			_pop_t += delta
			while _pop_t >= POP_EVERY and _popped <= SEGMENTS:
				_pop_t -= POP_EVERY
				_pop_next()
			_head = _head.lerp(Vector2(_head.x, SURFACE), minf(1.0, delta * 3.0))      # what's left slumps
			if _popped > SEGMENTS:
				_set_state(State.DEAD)
				_splat = 1.0
	_light.enabled = _exposed()
	_light.position = _head + Vector2(_dir * 2.0, -2.0)
	queue_redraw()


# ---------- moving under the sand ----------
func _swim(delta: float):
	_head = _head.lerp(TUCKED, minf(1.0, delta * 10.0))
	_wait -= delta
	var near := _player_near()
	if near and absf(player.global_position.x - _target_for) > 60.0:
		_pick_target()                                    # you've moved on: go round to where you are now
	elif not near and absf(_target_x - global_position.x) < 4.0:
		_target_x = randf_range(range_left, range_right)  # nobody about: cruise around
	var dx := _target_x - global_position.x
	var step := SWIM_SPEED * delta
	global_position.x += clampf(dx, -step, step)
	var moving := absf(dx) > 6.0
	if moving:
		_swim_dir = signf(dx)
		_trail_tick -= delta
		if _trail_tick <= 0.0:
			_trail_tick = 0.05
			_trail.append([global_position.x, 0.0])
		if randf() < delta * 14.0:                         # sand flicked up by the bulge
			_bit(Vector2(randf_range(-5, 5), SURFACE - 2.0), Vector2(-_swim_dir * randf_range(20, 60), -randf_range(40, 110)),
				1.0, [SAND_TOP, SAND, SAND_SWIRL].pick_random(), randf_range(0.3, 0.5), 400.0)
		if _hump_t < 0.0:
			_next_hump -= delta
			if _next_hump <= 0.0:
				_hump_t = 0.0
	if _hump_t >= 0.0:
		_hump_t += delta
		if _hump_t >= HUMP_TIME:
			_hump_t = -1.0
			_next_hump = randf_range(0.9, 1.8)
	if near and _wait <= 0.0 and not moving and _can_strike():
		if absf(player.global_position.x - global_position.x) < MIN_EMERGE_GAP:
			_pick_target()
		else:
			_striker = get_instance_id()
			_face_player()
			_set_state(State.EMERGE)
			_burst_sand(1.0)


func _player_near() -> bool:
	if player == null:
		return false
	var p := player.global_position
	return p.x > range_left - 80.0 and p.x < range_right + 80.0 and absf(p.y - global_position.y) < NEAR_Y


# a spot beside you, mostly in front (the way you're heading), inside its range. Ones already ahead stay
# ahead; ones behind often swim round to the front (Morgan wanted more of them in front of him)
func _pick_target():
	if player == null:
		return
	var px := player.global_position.x
	var side := 1.0 if randf() < 0.65 else -1.0
	if global_position.x > px + 20.0 and randf() < 0.85:
		side = 1.0
	var x := px + side * randf_range(EMERGE_DIST.x, EMERGE_DIST.y)
	if x < range_left or x > range_right:
		x = px - side * randf_range(EMERGE_DIST.x, EMERGE_DIST.y)
	_target_x = clampf(x, range_left, range_right)
	_target_for = px


func _can_strike() -> bool:
	var free := _striker == 0 or _striker == get_instance_id() or not is_instance_id_valid(_striker)
	return free and _now() >= _next_strike_at


func _release_strike():
	if _striker == get_instance_id():
		_striker = 0
		_next_strike_at = _now() + STRIKE_GAP


# ---------- up out of the sand ----------
# reared up facing you, swaying
func _rest() -> Vector2:
	return Vector2(_dir * 12.0 + sin(_t * 7.0) * 3.0, -REAR_HEIGHT + sin(_t * 5.0) * 1.5)


func _face_player():
	if player and absf(player.global_position.x - global_position.x) > 4.0:
		_dir = signf(player.global_position.x - global_position.x)


func _rear(delta: float):
	if state_time < SWAY_TIME:
		_face_player()
		_head = _head.lerp(_rest(), minf(1.0, delta * 12.0))
		return
	if not _aimed:                                        # the tell starts: it marks where you are now
		_aimed = true
		_strike_to = _aim()
	var k := clampf((state_time - SWAY_TIME) / COIL_TIME, 0.0, 1.0)
	var coil := Vector2(-_dir * 8.0, -REAR_HEIGHT + 7.0) + Vector2(randf_range(-1.0, 1.0) * k, 0)   # trembling
	_head = _head.lerp(coil, minf(1.0, delta * 14.0))
	if state_time >= SWAY_TIME + COIL_TIME:
		_head_from = _head
		_landed = false
		_set_state(State.STRIKE)


# where it strikes: the middle of you, as far as its neck stretches
func _aim() -> Vector2:
	var at := to_local(player.global_position + PLAYER_BODY) if player else Vector2(_dir * 60.0, -20.0)
	var from := Vector2(0, SURFACE)
	var v := at - from
	if v.length() > STRIKE_REACH:
		v = v.normalized() * STRIKE_REACH
	var to := from + v
	to.y = minf(to.y, SURFACE - 8.0)
	return to


# the strike reaching you: it grabs you and drags you down
func _bite():
	if _landed or player == null:
		return
	if EnemyKit.hurt_player(player, _head_rect(), global_position.x + _head.x):
		_landed = true
		player.velocity = Vector2.ZERO
		var states: Dictionary = player.get_script().State
		player._set_state(states["JUMP_FALL"])          # (flailing)
		player.set_physics_process(false)
		_dragging = true
		_head_from = _head
		_set_state(State.DRAG)


# you've gone under: the sand closes over you, you're sent back to the checkpoint (minus PENALTY seconds on the
# juice clock), and it dives
func _end_drag():
	_dragging = false
	_burst_sand(1.0)
	if player and is_instance_valid(player):
		player.velocity = Vector2.ZERO
		player.set_physics_process(true)
		var states: Dictionary = player.get_script().State
		player._set_state(states["IDLE"])
		player._shake(6.0, 0.25)
		get_tree().call_group("level", "juice_penalty", PENALTY, global_position + Vector2(0, -30))
		if get_tree().get_first_node_in_group("level"):
			get_tree().call_group("level", "respawn_player")
		else:                                             # (no level here: you're spat back out)
			player.global_position = global_position + Vector2(0, -4)
	_dive(RESURFACE)


func _exit_tree():
	if _dragging and player and is_instance_valid(player):   # removed mid-drag: give you back
		player.set_physics_process(true)


func _dive(wait: float):
	_release_strike()
	_dive_wait = wait
	_head_from = _head
	_set_state(State.DIVE)
	_burst_sand(0.5)


# ---------- getting hit ----------
func _exposed() -> bool:
	return state in [State.EMERGE, State.REAR, State.STRIKE, State.HOLD, State.RECOIL, State.STUNNED]


func _check_player_attack():
	var ps: int = player.state
	var pt: float = player.state_time
	# a new state, or the same state restarted, is a new swing
	if ps != _last_player_state or pt < _last_player_time:
		_hit_this_swing = false
	_last_player_state = ps
	_last_player_time = pt
	if _hit_this_swing or not _exposed():
		return
	var box := _hurt_rect()
	var hit := EnemyKit.player_attack_hitting(player, _names, box)
	var heavy := false
	if hit.is_empty():
		if _names[ps] != "CHARGED_SMASH" or pt > 0.2:
			return
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var charge: float = player.charge
		if absf(box.get_center().x - player.global_position.x) > lerpf(radius.x, radius.y, charge):
			return
		heavy = true
	else:
		heavy = _names[ps] in KILLING_SWINGS
	_hit_this_swing = true
	var dir := signf(box.get_center().x - player.global_position.x)
	if dir == 0.0:
		dir = float(player.facing)
	_struck(dir, heavy)


# a hit on its head. W kills it. Q doesn't hurt it: the blade clangs off its scales and knocks its head
# back, and it rears and strikes again (Morgan's call)
func _struck(dir: float, heavy: bool):
	_flash = 0.08
	if heavy:
		_hit_sound.play(HIT_SOUND_SKIP)
		_spill(_head, Vector2(dir, -0.6), 1.4)
		EnemyKit.hitstop(get_tree(), 0.08)
		if player and player.has_method("_shake"):
			player._shake(4.0, 0.12)
		_kill(dir, 1.3)
		return
	_knock(dir)


# knocked back without a scratch: a clang off its scales, sparks, and its head whips way back, chin up
func _knock(dir: float):
	_clang.play(CLANG_SOUND_SKIP)
	NoDamagePop.show_on(self, global_position + _head + Vector2(0, -16))   # it doesn't hurt it: say so
	EnemyKit.hitstop(get_tree(), 0.06)
	if player and player.has_method("_shake"):
		player._shake(3.0, 0.12)
	_knocked = true
	_knocks += 1
	_knock_dir = dir
	_flash = 0.1
	_head_from = _head
	_repel_to = _head + Vector2(dir * KNOCK_BACK.x, KNOCK_BACK.y)
	_repel_to.y = minf(_repel_to.y, SURFACE - 12.0)
	for i in 10:                                          # sparks off its scales
		var v := Vector2(dir, -0.6).normalized().rotated(randf_range(-0.9, 0.9)) * randf_range(120.0, 280.0)
		_bit(_head, v, 1.0, [Color.WHITE, STAR, Color(1, 0.95, 0.7)].pick_random(), randf_range(0.15, 0.3), 300.0)
	_set_state(State.REPELLED)


# other code hitting it (waves, crushes...): a W-sized hit (3+) kills it, anything lighter only knocks it
func take_hit(damage: int, push: Vector2):
	if not is_alive():
		return
	var dir := signf(push.x) if push.x != 0.0 else -_dir
	_flash = 0.08
	if damage >= 3:
		_hit_sound.play(HIT_SOUND_SKIP)
		_spill(_head if _exposed() else Vector2(0, SURFACE), Vector2(dir, -0.6), 1.0)
		_kill(dir, 1.0)
	elif _exposed():
		_knock(dir)


func is_alive() -> bool:
	return hp > 0 and state != State.DYING and state != State.DEAD


# it can't be countered: Q never kills it (Morgan's call), so Q as it strikes just knocks it back
func is_counterable() -> bool:
	return false


# killed by the counter (counter_chain.gd calls this: it has no cut_in_half)
func countered(dir: int):
	if not is_alive():
		return
	hp = 0
	_kill(float(dir), 1.6)


func _kill(dir: float, power: float):
	hp = 0
	_pop_dir = dir
	_release_strike()
	_set_state(State.DYING)
	_popped = 0
	_pop_t = POP_EVERY                                    # the head goes at once
	_kill_sound.play(KILL_SOUND_SKIP)
	var spray: Node2D = JuiceSpray.new()
	spray.color = juice_color
	spray.aim = Vector2(dir, -0.5).normalized()
	spray.power = power
	spray.floor_y = global_position.y + SURFACE
	spray.position = get_parent().to_local(to_global(_head))
	get_parent().add_child(spray)
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = "Snake fruit"
	drop.color = juice_color
	drop.position = get_parent().to_local(to_global(_head + Vector2(0, -6)))
	get_parent().add_child.call_deferred(drop)


# dying: the head bursts, then the body, piece by piece down into the sand
func _pop_next():
	var pts := _body_points()
	var i := SEGMENTS - _popped
	_popped += 1
	var p: Vector2 = pts[i]
	if p.y > SURFACE:
		return                                            # under the sand: nothing to see
	_spill(p, Vector2(_pop_dir * 0.4, -1.0), 0.8 if i < SEGMENTS else 1.3)
	if i % 4 == 0 and i > 0:
		var spray: Node2D = JuiceSpray.new()
		spray.color = juice_color
		spray.aim = Vector2(randf_range(-0.6, 0.6), -1.0).normalized()
		spray.power = 0.5
		spray.floor_y = global_position.y + SURFACE
		spray.position = get_parent().to_local(to_global(p))
		get_parent().add_child(spray)
		_hit_sound.play(HIT_SOUND_SKIP)


# creamy juice and bits of scaly skin flying out of a hit
func _spill(at: Vector2, aim: Vector2, power: float):
	for i in int(14 * power):
		var v := aim.normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(70.0, 220.0) * power
		_bit(at, v, float(randi_range(1, 2)), [FLESH, juice_color, juice_color.darkened(0.15)].pick_random(), randf_range(0.4, 0.8), 700.0)
	for i in int(5 * power):
		var v := aim.normalized().rotated(randf_range(-1.0, 1.0)) * randf_range(60.0, 180.0)
		_bit(at, v, 2.0, [SKIN, SKIN_SHADE, SCALE_LIGHT].pick_random(), randf_range(0.6, 1.0), 800.0)


func _burst_sand(power: float):
	_geyser = power
	_sand_sound.play(SAND_SOUND_SKIP)
	for i in int(26 * power):
		var v := Vector2(randf_range(-0.45, 0.45), -1.0).normalized() * randf_range(140.0, 330.0) * power
		_bit(Vector2(randf_range(-4, 4), SURFACE), v, float(randi_range(1, 2)), [SAND_TOP, SAND, SAND_SHADE, SAND_SWIRL].pick_random(),
			randf_range(0.4, 0.75), 720.0)


func _bit(at: Vector2, vel: Vector2, size: float, color: Color, life: float, gravity: float):
	_bits.append([at, vel, size, color, life, gravity])


func _update_bits(delta: float):
	for b: Array in _bits:
		b[1].y += float(b[5]) * delta
		b[0] += b[1] * delta
		b[4] -= delta
		if b[0].y > SURFACE and b[1].y > 0.0:            # lands on the sand and sinks in
			b[4] = minf(float(b[4]), 0.05)
	_bits = _bits.filter(func(b): return b[4] > 0.0)


# ---------- shape ----------
# the body from where it goes into the sand to the head: a curve, so the neck bends like a snake's
func _body_points() -> Array:
	var c := Vector2(_head.x * 0.15 - _dir * 10.0, minf(_head.y * 0.6, -2.0))
	var pts := []
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		pts.append(ENTRY * (1.0 - t) * (1.0 - t) + c * 2.0 * (1.0 - t) * t + _head * t * t)
	return pts


func _radius(i: int) -> float:
	var t := float(i) / SEGMENTS
	return 5.0 + 2.0 * sin(PI * t * 0.9)


# where its head and neck are (global), for the player's hits
func _hurt_rect() -> Rect2:
	var r := _head_rect()
	var pts := _body_points()
	for i in range(SEGMENTS - 3, SEGMENTS):
		var p: Vector2 = to_global(pts[i])
		var rad := _radius(i)
		r = r.merge(Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
	return r


func _head_rect() -> Rect2:
	return Rect2(to_global(_head) + HEAD_BOX.position, HEAD_BOX.size)


# ---------- drawing ----------
func _c(col: Color) -> Color:
	return Color.WHITE if _flash > 0.0 else col


func _draw():
	# the trail it ploughs along the surface
	for tr: Array in _trail:
		var a := 1.0 - float(tr[1]) / 0.6
		var x := roundf(float(tr[0]) - global_position.x)
		draw_rect(Rect2(x - 2.0, SURFACE - 1.0, 4, 1), Color(SAND_SWIRL, a))
	if state == State.DEAD:
		if _splat > 0.0:                                  # a creamy puddle on the sand
			draw_rect(Rect2(-13, SURFACE - 1.0, 26, 2), Color(juice_color, _splat))
			draw_rect(Rect2(-8, SURFACE - 2.0, 14, 1), Color(FLESH, _splat))
		_draw_bits()
		return
	if state == State.SWIM:
		_draw_bulge()
		if _hump_t >= 0.0:
			_draw_hump()
	else:
		draw_rect(Rect2(-6, SURFACE - 1.0, 12, 2), SAND_SHADE)    # the hole it comes out of
		_draw_body()
	if _geyser > 0.0:                                     # the sand column bursting up
		var h := roundf(34.0 * _geyser)
		draw_rect(Rect2(-4, SURFACE - h, 8, h), Color(SAND, _geyser))
		draw_rect(Rect2(-2, SURFACE - h - 3.0, 4, 3), Color(SAND_TOP, _geyser))
	if state == State.STUNNED or (state == State.REPELLED and _knocked and state_time > 0.1):   # dizzy stars
		for i in 3:
			var a := _t * 6.0 + TAU * i / 3.0
			draw_rect(Rect2((_head + Vector2(cos(a) * 9.0, -10.0 + sin(a) * 3.0)).round(), Vector2(2, 2)), STAR)
	_draw_bits()


# the bulge it pushes along under the sand
func _draw_bulge():
	var w := 14.0
	draw_rect(Rect2(-w / 2.0, SURFACE - 2.0, w, 2), SAND)
	draw_rect(Rect2(-w / 2.0 + 2.0, SURFACE - 3.0, w - 4.0, 1), SAND_TOP)
	draw_rect(Rect2(-2, SURFACE - 4.0, 4, 1), SAND_SWIRL)
	draw_rect(Rect2(-_swim_dir * (w / 2.0 + 2.0) - 1.0, SURFACE - 1.0, 3, 1), SAND_SHADE)


# its back breaching in a hump behind the bulge, then sliding back under
func _draw_hump():
	var k := _hump_t / HUMP_TIME
	var height := 16.0 * sin(PI * k)
	for i in 8:
		var u := float(i) / 7.0
		var p := Vector2(-_swim_dir * (38.0 * (1.0 - u) + 4.0), 6.0 - sin(PI * u) * height).round()
		_draw_segment(p, Vector2(_swim_dir, 0), 5.5, -_swim_dir)


func _draw_body():
	var pts := _body_points()
	var last := SEGMENTS if state != State.DYING else SEGMENTS - maxi(0, _popped - 1)
	for i in last:
		var p: Vector2 = pts[i]
		var along: Vector2 = (pts[mini(i + 1, SEGMENTS)] - p)
		if along.length() < 0.01:
			along = Vector2(0, -1)
		_draw_segment(p.round(), along.normalized(), _radius(i), _dir)
	if state != State.DYING or _popped == 0:
		_draw_head()


# one piece of body: shade under it, skin, a belly stripe on its front and a scale on its back
func _draw_segment(p: Vector2, along: Vector2, r: float, face: float):
	var normal := Vector2(-along.y, along.x) * face       # towards its belly
	if normal.length() < 0.01:
		normal = Vector2(face, 0)
	draw_circle(p + Vector2(0, 1), r, _c(SKIN_SHADE))
	draw_circle(p, r - 1.0, _c(SKIN))
	draw_circle((p + normal * (r - 2.5)).round(), 2.0, _c(BELLY))
	var back := (p - normal * (r - 2.0)).round()          # a triangular scale, pointing back along the body
	var tip := (back - along * 2.0).round()
	draw_rect(Rect2(tip, Vector2(1, 1)), _c(SCALE_LIGHT))
	draw_rect(Rect2((back + Vector2(-along.y, along.x)).round(), Vector2(1, 1)), _c(SCALE_LIGHT))
	draw_rect(Rect2((back - Vector2(-along.y, along.x)).round(), Vector2(1, 1)), _c(SCALE_LIGHT))


# the head: a salak's teardrop with its pointy tip as the snout, slit-pupil eyes, a forked tongue
func _draw_head():
	var h := _head.round()
	var look := Vector2(_dir, 0.2)
	if state == State.STRIKE or state == State.HOLD:
		look = _strike_to - _head_from
	elif state == State.STUNNED:
		look = Vector2(_dir, 0.6)
	elif state == State.REPELLED and _knocked:            # chin in the air, slowly turning back to you
		var k := clampf(state_time / KNOCK_TIME, 0.0, 1.0)
		var to_you := to_local(player.global_position + PLAYER_BODY) - _head if player else Vector2(-_knock_dir, 0)
		look = Vector2(-_knock_dir * 0.35, -1.0).lerp(to_you.normalized(), k * k)
	elif player and state != State.DYING:
		look = to_local(player.global_position + PLAYER_BODY) - _head
	if look.length() < 0.01:
		look = Vector2(_dir, 0)
	var fwd := look.normalized()
	var up := Vector2(fwd.y, -fwd.x) if fwd.x >= 0.0 else Vector2(-fwd.y, fwd.x)   # its top stays up
	var coiling := state == State.REAR and state_time > SWAY_TIME
	var open := coiling or state == State.STRIKE or state == State.HOLD
	# a point on the head: a forward, u up
	var at := func(a: float, u: float) -> Vector2:
		return (h + fwd * a + up * u).round()
	var outline: Array[Vector2] = [Vector2(10, 0), Vector2(6, 3.5), Vector2(1, 5.5), Vector2(-3, 5.5), Vector2(-6, 3.5),
		Vector2(-7.5, 0), Vector2(-6, -3.5), Vector2(-3, -5.5), Vector2(1, -5.5), Vector2(6, -3.5)]
	var shade := PackedVector2Array()
	var skin := PackedVector2Array()
	for o in outline:
		shade.append(at.call(o.x, o.y - 1.0))
		skin.append(at.call(o.x - 0.5, o.y))
	_poly(shade, _c(SKIN_SHADE))
	_poly(skin, _c(SKIN))
	for row in 3:                                         # rows of little scales, like the fruit's skin
		for col in 3:
			var p: Vector2 = at.call(-4.0 + col * 3.5 + row * 0.8, 3.5 - row * 2.5)
			draw_rect(Rect2(p, Vector2(1, 1)), _c(SCALE_LIGHT))
	if open:                                              # the mouth: creamy flesh inside, a dark rim
		var gape := 3.5 if state != State.REAR else 2.0
		var mouth := PackedVector2Array([at.call(11.0, 0.5), at.call(2.0, -0.5), at.call(10.0, -gape)])
		_poly(mouth, _c(MOUTH))
		var inner := PackedVector2Array([at.call(9.0, 0.0), at.call(3.5, -0.5), at.call(8.5, -gape + 1.0)])
		_poly(inner, _c(FLESH))
	if open or fmod(_t + get_instance_id() % 7 * 0.13, 0.7) < 0.15:   # the tongue flicks out
		var base: Vector2 = at.call(10.0, -1.0 if open else 0.0)
		var tip := (base + fwd * (6.0 if open else 4.0)).round()
		draw_line(base, tip, _c(TONGUE), 1.0)
		draw_rect(Rect2((tip + fwd + up).round(), Vector2(1, 1)), _c(TONGUE))
		draw_rect(Rect2((tip + fwd - up).round(), Vector2(1, 1)), _c(TONGUE))
	# the eye: yellow with a slit pupil; it flashes white as it coils to strike
	var eye: Vector2 = at.call(3.5, 2.5)
	var flashing := coiling and fmod(state_time, 0.1) < 0.05
	draw_rect(Rect2(eye - Vector2(1, 1), Vector2(3, 3)), _c(Color.WHITE if flashing else EYE))
	if state != State.STUNNED:
		draw_rect(Rect2(eye + Vector2(0, -1), Vector2(1, 3)), _c(PUPIL))
	else:
		draw_rect(Rect2(eye - Vector2(1, 0), Vector2(3, 1)), _c(PUPIL))   # eyes squeezed shut


# a filled shape, skipped if rounding to whole pixels squashed it flat (Godot can't fill that, and says so
# every frame)
func _poly(pts: PackedVector2Array, col: Color):
	var area := 0.0
	for i in pts.size():
		area += pts[i].cross(pts[(i + 1) % pts.size()])
	if absf(area) >= 1.0:
		draw_colored_polygon(pts, col)


func _draw_bits():
	for b: Array in _bits:
		var s: float = b[2]
		draw_rect(Rect2((b[0] as Vector2).round(), Vector2(s, s)), b[3])
