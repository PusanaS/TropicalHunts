extends Node2D
# CACTUS (Level 1): a prickly cactus in the quicksand, with a huddle of Mangos napping just behind it.
#   Touch:     pricks you (pushed back + red flash, like touching a Mango).
#   Breaking:  any hit breaks it: Q, W, the roll, the slams, or a charged smash that reaches it.
#   Then:      it bursts and fires a fan of its spikes away from you. Each spike flies in a low arc and
#              stabs the first enemy it meets (take_hit), so the nappers behind it get skewered.
#              Spikes that miss stick in the sand and fade.
#   Chain:     a spike that flies into another cactus bursts it too, firing on the same way, so breaking
#              the first one sets off the whole row (Morgan's idea). One spike is always aimed at the next
#              cactus (so the chain never fizzles) and one lobbed at each Mango napping up on a rock
#              pillar ahead (rock_pillar.gd); the rest fly in a fan, some lobbing high.
#   Palm:      the last cactus in the chain fires a volley on into the palm on the far bank
#              (palm_bridge.gd), which topples back across the sand as a bridge.
#   Camera:    while a chain runs, time slows and the view slides along with it (you stay on screen at its
#              edge), then it eases back once the last cactus has gone (Morgan's call). For the palm it goes
#              further: it follows the volley all the way there and rides the palm's fall back (chain_follow). Each Mango a spike
#              kills bursts into juice with a "+1" floating up.
#   Nappers:   the Mangos listed in `nappers`. While the cactus stands they doze facing away from it, with
#              "z"s drifting up, and only wake if you walk right up to them (the minion's own BEHIND_SIGHT).
#              Any the spikes miss wake with a start once the volley has passed.
# Place it with its feet on the floor (origin = bottom centre). PLACEHOLDER look, drawn in code.

signal shattered                                # it just broke

@export var nappers: Array[NodePath] = []       # Mangos dozing behind it
@export var spike_count := 14

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const BREAK_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const BREAK_SOUND_DB := 0.0
const BREAK_SOUND_SKIP := 0.12                  # the file starts with 0.12 s of silence
const VOLLEY_SOUND := preload("res://sounds/Q_HIT_54427377-sword-slash-476148.mp3")   # the spikes whooshing off
const VOLLEY_SOUND_DB := -4.0
const VOLLEY_SOUND_SKIP := 0.60                 # 0.6 s of silence first (as in player.gd)

const SIZE := Vector2i(32, 46)                  # the art, arms included
const HIT_BOX := Rect2(-14, -44, 28, 44)        # where the player's attacks break it
const TOUCH_BOX := Rect2(-6, -40, 12, 40)       # where it pricks the player (just the trunk)
const SPIKE_LEN := 7
const SPIKE_GRAVITY := 240.0
const SPIKE_RANGE := 420.0                      # spikes that fly this far without landing just vanish
const SPIKE_STICK_TIME := 1.6                   # a spike in the sand stays this long, then fades
const SPIKE_DAMAGE := 1                         # Mangos are one-shot
const CHAIN_RANGE := 320.0                      # the next cactus this far on (the way the spikes fly) is set off
												# for sure, by a spike aimed at it; so is any Mango up on a pillar
const AIM_SPEED := 420.0                        # (how fast those aimed spikes fly across)
const PALM_RANGE := 400.0                       # the last cactus fires on at a palm this far ahead
# galloping into it bursts it and stops you dead (a prick, you bounce off) so you stay and watch the chain;
# and till the chain fires, the Mangos in the desert are flash-proof, so a gallop can't flash past it
# (Morgan's call)
const GALLOP_REACH := 22.0
const PLAYER_HALF_WIDTH := 13.0
const DESERT_REACH := 640.0                     # the Mangos this far on from a standing cactus are flash-proof
# the chain camera: time slows and the view slides along to follow the chain, then lets go
const CHAIN_SLOW := 0.35
const CHAIN_HOLD := 0.9                         # real seconds after the last burst before it lets go
const CHAIN_LEAD := 40.0                        # the view leads the latest burst by this much
const PAN_MAX := 225.0                          # the most it slides: you stay on screen, at its edge
const FAR_MAX := 1000.0                         # (following the palm, it goes as far as it needs, you off screen)
const PAN_EASE := 6.0
const JuiceSpray := preload("res://code/design/juice_spray.gd")
const CinemaBars := preload("res://code/design/cinema_bars.gd")
const POP_LIFE := 0.9                           # a "+1" floats up this long (game time)
const POP_COLORS := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]
const SPIKE_PUSH := Vector2(140, -180)
const ENEMY_BOX := Rect2(-13, -26, 26, 26)      # about a Mango's body, from its feet
const WAKE_DELAY := 0.45                        # nappers the spikes missed wake this long after the burst
const DOZE_ANIM_SPEED := 0.35                   # a slow, drowsy idle
const PIECE := Vector2i(8, 9)                   # chunk size when it breaks
const PIECE_GRAVITY := 900.0
const PIECE_LIFE := 1.6
const SAND_Y := -4.0                            # the quicksand's surface stands this high over the floor
const Z_FX := 2                                 # spikes and chunks: in front of the player, behind the sand

const SKIN_LIGHT := Color("c8dc8e")

var player: CharacterBody2D = null
var _names: Array = []
var _broken := false
var _image: Image
var _texture: ImageTexture
var _spikes: Array = []                         # each: {"pos", "vel", "wait", "stuck", "age"}
var _pieces: Array = []                         # each: [Sprite2D, velocity, spin, age]
var _targets: Array = []                        # the enemies the spikes can hit
var _dozing: Array = []                         # nappers still asleep
var _wake_in := -1.0
var _wobble := 0.0                              # it shivers a moment after pricking you
var _t := 0.0
var _fx := Node2D.new()
var _break_sound := AudioStreamPlayer.new()
var _pops: Array = []                           # "+1"s floating up off the kills: [local pos, age]
# the chain camera is run by the cactus you broke yourself (the chain's first)
static var _chain_owner: Node = null
static var _chain_dir := 1.0
static var _front := 0.0                        # the latest cactus to burst (x)
static var _last_burst := 0.0                   # (real time)
static var _far := false                        # following the palm (chain_follow): no PAN_MAX, no lead
# you're held still from the moment the chain starts till the palm comes down (Morgan's call, 2026-10-08), so
# you watch it all. The palm lets go (release_player()); so does the chain ending, and FREEZE_MAX at most.
const FREEZE_MAX := 15.0                        # (real seconds)
static var _hold := false
var _held := false                              # (the chain's first cactus) it has you stopped right now
var _hold_since := 0.0
var _pan := 0.0
var _cam: Camera2D = null
var _cam_x := 0.0
var _last_real := 0.0
var _volley_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("cactus")                      # the others' spikes set it off
	z_index = -1                                # behind the player
	_fx.z_as_relative = false
	_fx.z_index = Z_FX
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_break_sound.stream = BREAK_SOUND
	_break_sound.volume_db = BREAK_SOUND_DB
	add_child(_break_sound)
	_volley_sound.stream = VOLLEY_SOUND
	_volley_sound.volume_db = VOLLEY_SOUND_DB
	_volley_sound.pitch_scale = 1.3
	add_child(_volley_sound)
	_build_art()
	for path in nappers:
		var m := get_node_or_null(path)
		if m:
			_dozing.append(m)


func _physics_process(delta: float):
	_t += delta
	_wobble = move_toward(_wobble, 0.0, delta * 3.0)
	_update_spikes(delta)
	_update_pieces(delta)
	for pop: Array in _pops:
		pop[1] += delta
	_pops = _pops.filter(func(pop): return pop[1] < POP_LIFE)
	_keep_dozing()
	if _wake_in >= 0.0:
		_wake_in -= delta
		if _wake_in < 0.0:
			_wake_nappers()
	_fx.queue_redraw()
	if _broken:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	_flash_proof(true)
	if _galloping_into():
		var gdir := signf(global_position.x - player.global_position.x)
		_shatter(gdir)
		_stop_gallop(gdir)
		return
	if _hit_by_player():
		var dir := signf(global_position.x - player.global_position.x)
		_shatter(dir if dir != 0.0 else float(player.facing))
		return
	if EnemyKit.hurt_player(player, Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size), global_position.x):
		_wobble = 1.0
		queue_redraw()
	elif _wobble > 0.0:
		queue_redraw()


# galloping straight at it, about to touch it
func _galloping_into() -> bool:
	var top: int = player.get_script().SPEEDS.size() - 1
	var dir := signf(global_position.x - player.global_position.x)
	if player.speed_level < top or signf(player.velocity.x) != dir or absf(player.global_position.y - global_position.y) > 46.0:
		return false
	return absf(global_position.x - player.global_position.x) - HIT_BOX.size.x / 2.0 - PLAYER_HALF_WIDTH < GALLOP_REACH


# you galloped into it: the gallop's over (speed back to nothing), you bounce off it with a red prick
func _stop_gallop(dir: float):
	player.speed_level = 0
	player.hold_time = 0.0
	if player.has_method("bounce_back"):
		player.bounce_back(global_position.x, 170.0)
	player.modulate = Color(1, 0.35, 0.35)
	player.create_tween().tween_property(player, "modulate", Color.WHITE, 0.4)
	FruitMinion.play_hurt_sound(player)
	_wobble = 1.0


# the Mangos in the desert ahead: the flash skips them while this cactus stands (flash_proof)
func _flash_proof(on: bool):
	for e in get_tree().get_nodes_in_group("enemies"):
		if not ("flash_proof" in e) or not (e is Node2D):
			continue
		var d: float = e.global_position.x - global_position.x
		if d > -10.0 and d < DESERT_REACH:
			e.flash_proof = on


func _hit_by_player() -> bool:
	var box := Rect2(global_position + HIT_BOX.position, HIT_BOX.size)
	if not EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		return true
	# the charged smash hits everything in its reach (as in stone_wall.gd)
	if _names[player.state] != "CHARGED_SMASH":
		return false
	var d := player.global_position - global_position
	var radius: Vector2 = player.get_script().CHARGE_RADIUS
	var height: float = player.get_script().CHARGE_HEIGHT
	var reach := lerpf(radius.x, radius.y, player.charge) + HIT_BOX.size.x / 2.0
	return absf(d.x) <= reach and absf(d.y - HIT_BOX.get_center().y) <= height + HIT_BOX.size.y / 2.0


# ---------- the nappers ----------
# keeps them asleep: idle, facing away from the cactus, never turning round (their idle timer is held at 0).
# One that notices the player (or gets hit) leaves IDLE and is awake for good.
func _keep_dozing():
	var still: Array = []
	for m in _dozing:
		if not is_instance_valid(m):
			continue
		if m.state == FruitMinion.State.PATROL:      # just spawned: settle down
			m._set_state(FruitMinion.State.IDLE)
			m.sprite.speed_scale = DOZE_ANIM_SPEED
		if m.state != FruitMinion.State.IDLE:
			continue
		m.state_time = 0.0
		m.facing = 1 if m.global_position.x >= global_position.x else -1
		still.append(m)
	_dozing = still


# the spikes have flown: any napper they missed wakes with a start (hop + "!")
func _wake_nappers():
	for m in _dozing:
		if is_instance_valid(m) and m.state == FruitMinion.State.IDLE:
			m._set_state(FruitMinion.State.NOTICE)
	_dozing.clear()


# ---------- breaking ----------
# another cactus's spike flew into it: it bursts and fires on the same way (the chain reaction)
func spiked(dir: float):
	if not _broken:
		_shatter(dir)


func _shatter(dir: float):
	_broken = true
	_flash_proof(false)                         # the chain's going: the flash can have them again
	if _chain_owner == null or not is_instance_valid(_chain_owner):
		_chain_owner = self                     # this one starts the chain: it runs the camera
		_chain_dir = dir
		_far = false
		_front = global_position.x
		_last_real = _real()
		_hold = true                            # ...and holds you still till the palm's down
		_hold_since = _last_real
	elif (global_position.x - _front) * _chain_dir > 0.0:
		_front = global_position.x
	_last_burst = _real()
	var top_left := Vector2(-SIZE.x / 2.0, -SIZE.y)
	for y in range(0, SIZE.y, PIECE.y):
		for x in range(0, SIZE.x, PIECE.x):
			var region := Rect2i(x, y, mini(PIECE.x, SIZE.x - x), mini(PIECE.y, SIZE.y - y))
			if not _image.get_region(region).is_invisible():
				_piece(Rect2(region), top_left, dir)
	_targets = get_tree().get_nodes_in_group("enemies")
	_fire_spikes(dir)
	_burst(Vector2(dir * 4.0, -24.0), SKIN_LIGHT, 16, Vector2(dir, -0.6), 160.0)     # sap
	_burst(Vector2(0, -4.0), Color("d39b4a"), 12, Vector2.UP, 90.0)                    # sand
	_break_sound.play(BREAK_SOUND_SKIP)
	_volley_sound.play(VOLLEY_SOUND_SKIP)
	EnemyKit.hitstop(get_tree(), 0.06)
	if player:
		player._shake(6.0, 0.25)
	get_tree().call_group("living_background", "burst", global_position, 3.0)
	_wake_in = WAKE_DELAY
	shattered.emit()
	queue_redraw()


# most spikes fly low and nearly flat, at Mango height, so they skewer whatever is behind it; the rest lob
# up, some of them high, for the Mangos napping up on the rock pillars
func _fire_spikes(dir: float):
	for i in spike_count:
		var band := 0 if i < int(spike_count * 0.6) else (1 if i < int(spike_count * 0.85) else 2)
		var h: float = [randf_range(6.0, 24.0), randf_range(26.0, 40.0), randf_range(30.0, 44.0)][band]
		var angle := deg_to_rad(float([randf_range(-7.0, 4.0), randf_range(-32.0, -14.0), randf_range(-52.0, -38.0)][band]))
		var speed: float = [randf_range(380.0, 470.0), randf_range(300.0, 380.0), randf_range(330.0, 400.0)][band]
		_spikes.append({
			"pos": Vector2(dir * randf_range(2.0, 7.0), -h),
			"vel": Vector2(dir * cos(angle), sin(angle)) * speed,
			"wait": randf_range(0.0, 0.12),          # a ripple, not one flat line
			"stuck": false,
			"age": 0.0,
		})
	# the chain never fizzles: one spike aimed at the next cactus (passing over anything in the way), and
	# one lobbed at each Mango napping up on a pillar ahead
	var next := _next_cactus(dir)
	if next:
		_aimed_spike(next.global_position + Vector2(0, -22.0), dir, true)
	var lobbed := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if lobbed >= 3 or not (e is Node2D) or ("hp" in e and e.hp <= 0):
			continue
		var d: Vector2 = e.global_position - global_position
		if d.x * dir > 0.0 and absf(d.x) < CHAIN_RANGE and d.y < -30.0:
			_aimed_spike(e.global_position + Vector2(0, -12.0), dir, false)
			lobbed += 1
	# the last cactus in the chain fires a volley on into the palm on the far bank, if there is one
	# (palm_bridge.gd): it brings it down. The view follows the first spike there.
	if next == null:
		for palm in get_tree().get_nodes_in_group("palm_bridge"):
			var d: float = (palm.global_position.x - global_position.x) * dir
			if d <= 0.0 or d > PALM_RANGE:
				continue
			for i in 3:
				var at: Vector2 = palm.spike_point(i)
				if at.is_finite():
					_aimed_spike(at, dir, false, palm, 0.04 + i * 0.07)


# a spike that comes down right on `at` (world): flat across, falling just as it gets there. One at the palm
# (`catcher`) goes into its trunk there.
func _aimed_spike(at: Vector2, dir: float, chain: bool, catcher: Node = null, wait := 0.04):
	var from := Vector2(dir * 4.0, -20.0)
	var to := at - global_position
	var vx := dir * AIM_SPEED
	var t := maxf(absf((to.x - from.x) / vx), 0.05)
	var vy := (to.y - from.y - 0.5 * SPIKE_GRAVITY * t * t) / t
	var spike := {"pos": from, "vel": Vector2(vx, vy), "wait": wait, "stuck": false, "age": 0.0, "chain": chain}
	if catcher:
		spike["catcher"] = catcher
		spike["at"] = at
		spike["flight"] = t
		spike["lead"] = not _spikes.any(func(o): return o.has("catcher"))   # the view follows the first one
	_spikes.append(spike)


# the nearest cactus still standing ahead (the way the spikes fly), within CHAIN_RANGE
func _next_cactus(dir: float) -> Node2D:
	var best: Node2D = null
	var best_d := CHAIN_RANGE
	for c in get_tree().get_nodes_in_group("cactus"):
		if c == self or c._broken:
			continue
		var d: float = (c.global_position.x - global_position.x) * dir
		if d > 0.0 and d < best_d:
			best_d = d
			best = c
	return best


func _update_spikes(delta: float):
	var alive: Array = []
	for s: Dictionary in _spikes:
		if s["wait"] > 0.0:
			s["wait"] -= delta
			alive.append(s)
			continue
		s["age"] += delta
		if s["stuck"]:
			if s["age"] < SPIKE_STICK_TIME:
				alive.append(s)
			continue
		var vel: Vector2 = s["vel"]
		vel.y += SPIKE_GRAVITY * delta
		var pos: Vector2 = s["pos"] + vel * delta
		s["vel"] = vel
		s["pos"] = pos
		if s.has("catcher"):                         # flying at the palm: it goes into the trunk when it gets there
			var catcher: Object = s["catcher"]
			if s["age"] >= s["flight"]:
				if is_instance_valid(catcher):
					catcher.thunk(s["at"], vel)
				continue
			if s["lead"]:
				chain_follow(global_position.x + pos.x)
			alive.append(s)
			continue
		if _stab(global_position + pos, signf(vel.x), s.get("chain", false)):
			continue                                 # it's in the Mango now
		if pos.y >= SAND_Y + 3.0:                    # tip buried in the sand: it sticks there at its angle
			s["pos"] = Vector2(pos.x, SAND_Y + 3.0)
			s["stuck"] = true
			s["age"] = 0.0
		elif absf(pos.x) > SPIKE_RANGE:
			continue
		alive.append(s)
	_spikes = alive


# a Mango the spikes just killed: it bursts into juice, and a "+1" floats up off it
func _juice_pop(e: Node2D, dir: float):
	var spray: Node2D = JuiceSpray.new()
	spray.color = e.juice_color if "juice_color" in e else Color(0.91, 0.54, 0.13)
	spray.aim = Vector2(dir, -0.9).normalized()
	spray.power = 1.2
	spray.floor_y = e.global_position.y + 2.0
	spray.check_ground = true                       # (a Mango up on a rock pillar: no puddles in mid-air)
	spray.position = get_parent().to_local(e.global_position + Vector2(0, -12))
	get_parent().add_child(spray)
	_pops.append([to_local(e.global_position + Vector2(0, -34)), 0.0])


# ---------- the chain camera (real time) ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


# the cactus that started the chain slows time and slides the view along after it, keeping you on screen;
# once the last one's gone, the view eases back and time speeds up again
func _process(_delta: float):
	if _chain_owner != self:
		return
	var now := _real()
	var dt := minf(now - _last_real, 0.05)
	_last_real = now
	if player == null or not is_instance_valid(player):
		return
	if _cam == null:
		_cam = player.get_node_or_null("Camera2D") as Camera2D
		if _cam == null:
			return
		_cam_x = _cam.position.x
	_hold_player(now)
	var holding := now - _last_burst < CHAIN_HOLD
	var target := 0.0
	if holding:
		var lead := 0.0 if _far else CHAIN_LEAD
		var ahead := (_front + lead * _chain_dir - player.global_position.x) * _chain_dir
		target = clampf(ahead, 0.0, FAR_MAX if _far else PAN_MAX) * _chain_dir
		if _far:                                # you're off screen: nothing can hurt you meanwhile
			EnemyKit.protect_player(0.3)
	if Engine.time_scale != 0.0:                # (the counter or the flash own time while it's stopped)
		Engine.time_scale = CHAIN_SLOW if holding else minf(Engine.time_scale + dt * 2.5, 1.0)
	_pan = lerpf(_pan, target, 1.0 - exp(-PAN_EASE * dt))
	_cam.position.x = _cam_x + roundf(_pan)
	if not holding and absf(_pan) < 0.5 and Engine.time_scale >= 1.0:
		_end_chain()


# held still: once you're on the ground, your controls stop (your physics is paused, as in the counter) and you
# stand idle, safe from anything that comes at you. Let go when release_player() (or FREEZE_MAX) says so.
func _hold_player(now: float):
	if _hold and now - _hold_since > FREEZE_MAX:
		_hold = false
	if _hold and not _held and player.is_on_floor():
		_held = true
		player.velocity = Vector2.ZERO
		player.speed_level = 0
		player.hold_time = 0.0
		var states: Dictionary = player.get_script().State
		player._set_state(states["IDLE"])
		player.set_physics_process(false)
		CinemaBars.set_on(get_tree(), true)          # a cutscene now: the black bars slide in
	elif _held and not _hold:
		_let_go()
	if _held:
		EnemyKit.protect_player(0.3)


func _let_go():
	if _held and player and is_instance_valid(player):
		player.set_physics_process(true)
	if _held:
		CinemaBars.set_on(get_tree(), false)
	_held = false


# the palm's down (palm_bridge.gd): you can move again
static func release_player():
	_hold = false


# the view follows x (world), however far from you that takes it, and the slow motion holds: the volley flying
# to the palm, then the palm itself as it falls (palm_bridge.gd)
static func chain_follow(x: float):
	_front = x
	_far = true
	_last_burst = Time.get_ticks_msec() / 1000.0


func _end_chain():
	if _cam and is_instance_valid(_cam):
		_cam.position.x = _cam_x
	if Engine.time_scale != 0.0:
		Engine.time_scale = 1.0
	_chain_owner = null
	_far = false
	_hold = false
	_let_go()


func _exit_tree():
	if _chain_owner == self:                    # removed mid-chain (scene reload): put the camera and time back
		_end_chain()


# the spike's tip at `tip` (world): the first living enemy it touches takes the hit, or a cactus it flies
# into bursts. A chain spike passes over the Mangos: it's only after the next cactus.
func _stab(tip: Vector2, dir: float, chain_only := false) -> bool:
	for c in get_tree().get_nodes_in_group("cactus"):
		if c == self or c._broken:
			continue
		if Rect2(c.global_position + HIT_BOX.position, HIT_BOX.size).has_point(tip):
			c.spiked(dir)
			return true
	if chain_only:
		return false
	for e in _targets:
		if not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		if e.has_method("is_alive") and not e.is_alive() and not ("flash_proof" in e and e.flash_proof):
			continue                             # (flash-proof Mangos are still alive to the spikes)
		if "hp" in e and e.hp <= 0:
			continue
		if not Rect2(e.global_position + ENEMY_BOX.position, ENEMY_BOX.size).has_point(tip):
			continue
		e.take_hit(SPIKE_DAMAGE, Vector2(dir * SPIKE_PUSH.x, SPIKE_PUSH.y))
		if "hp" in e and e.hp <= 0:
			_juice_pop(e, dir)
		return true
	return false


func _piece(region: Rect2, top_left: Vector2, dir: float):
	var piece := Sprite2D.new()
	piece.texture = _texture
	piece.region_enabled = true
	piece.region_rect = region
	_fx.add_child(piece)
	piece.position = top_left + region.position + region.size / 2.0
	var high := 1.0 - region.position.y / SIZE.y                # the top flies higher
	var vel := Vector2(dir * randf_range(30.0, 160.0) + randf_range(-40.0, 40.0), -randf_range(80.0, 220.0) * (0.5 + high))
	_pieces.append([piece, vel, randf_range(-12.0, 12.0), 0.0])


# chunks fly, spin, bounce and settle half into the sand, then fade
func _update_pieces(delta: float):
	var alive: Array = []
	for p: Array in _pieces:
		var piece: Sprite2D = p[0]
		var vel: Vector2 = p[1]
		var spin: float = p[2]
		var age: float = float(p[3]) + delta
		vel.y += PIECE_GRAVITY * delta
		var pos := piece.position + vel * delta
		if pos.y > SAND_Y + 2.0 and vel.y > 0.0:
			pos.y = SAND_Y + 2.0
			vel = Vector2(vel.x * 0.4, -vel.y * 0.25)
			spin *= 0.4
		piece.position = pos
		piece.rotation += spin * delta
		if age > PIECE_LIFE - 0.4:
			piece.modulate.a = maxf(0.0, (PIECE_LIFE - age) / 0.4)
		if age >= PIECE_LIFE:
			piece.queue_free()
			continue
		p[1] = vel
		p[2] = spin
		p[3] = age
		alive.append(p)
	_pieces = alive


func _burst(offset: Vector2, color: Color, amount: int, direction: Vector2, speed: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = direction
	p.spread = 50.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.position = offset
	p.finished.connect(p.queue_free)
	_fx.add_child(p)
	p.emitting = true


# ---------- drawing ----------
# a saguaro: a ribbed trunk with a flower on top and two arms, outlined in BOOM's indigo, with pale spines
# poking out of the outline. Drawn once into a texture so the chunks can be cut from it.
func _build_art():
	var body: Array[Rect2i] = [
		Rect2i(10, 4, 12, 42), Rect2i(11, 3, 10, 1), Rect2i(12, 2, 8, 1),       # trunk
		Rect2i(3, 24, 8, 6), Rect2i(3, 13, 6, 12), Rect2i(4, 12, 4, 1),         # left arm
		Rect2i(21, 18, 8, 6), Rect2i(23, 7, 6, 12), Rect2i(24, 6, 4, 1),        # right arm
	]
	var inside := func(x: int, y: int) -> bool:
		for r in body:
			if r.has_point(Vector2i(x, y)):
				return true
		return false
	_image = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var spines: Array[Vector2i] = []
	for y in SIZE.y:
		for x in SIZE.x:
			if not inside.call(x, y):
				continue
			var open: Array[Vector2i] = []
			for n: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not inside.call(x + n.x, y + n.y):
					open.append(n)
			var col := Pixel.GREEN
			if not open.is_empty():
				col = Pixel.INK
				if (x * 7 + y * 3) % 5 == 0 and y < SIZE.y - 6:      # a spine every few pixels, not in the sand
					spines.append(Vector2i(x, y) + open[0])
			elif not inside.call(x - 2, y):
				col = SKIN_LIGHT                                   # lit left edge
			elif not inside.call(x + 2, y) or x % 3 == 1:
				col = Pixel.GREEN_DARK                             # shaded right edge and the ribs
				if x % 3 == 1 and y % 5 == 0:
					col = Pixel.PALE                               # a tuft on the rib
			_image.set_pixelv(Vector2i(x, y), col)
	for s in spines:
		if s.x >= 0 and s.x < SIZE.x and s.y >= 0 and _image.get_pixelv(s).a == 0.0:
			_image.set_pixelv(s, Pixel.OFF_WHITE)
	# the flower on top
	for x in range(13, 19):
		_image.set_pixel(x, 1, Pixel.MUSTARD if x == 15 or x == 16 else Pixel.ORANGE)
	_image.set_pixel(14, 0, Pixel.RUST)
	_image.set_pixel(17, 0, Pixel.RUST)
	_texture = ImageTexture.create_from_image(_image)


func _draw():
	if _broken:
		return
	var shiver := roundf(sin(_t * 70.0) * _wobble * 1.5)
	draw_texture(_texture, Vector2(-SIZE.x / 2.0 + shiver, -SIZE.y))


# spikes in flight (with a faint streak) or stuck in the sand, and the nappers' "z"s
func _draw_fx():
	for pop: Array in _pops:                    # "+1": floating up, fading out at the end
		var k: float = pop[1] / POP_LIFE
		var at: Vector2 = pop[0] + Vector2(-5, -roundf(26.0 * (1.0 - (1.0 - k) * (1.0 - k))))
		Pixel.draw_cells(_fx, Pixel.cells("+1", at.round(), 1), POP_COLORS, 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0))
	for s: Dictionary in _spikes:
		if s["wait"] > 0.0:
			continue
		var a := 1.0
		if s["stuck"]:
			a = clampf((SPIKE_STICK_TIME - s["age"]) / 0.4, 0.0, 1.0)
		_draw_spike(s["pos"], (s["vel"] as Vector2).normalized(), a, not s["stuck"])
	for i in _dozing.size():
		var m: Node2D = _dozing[i]
		if not is_instance_valid(m):
			continue
		var head := _fx.to_local(m.global_position) + Vector2(m.facing * 4.0, -30.0)
		for k in 2:
			var phase := fmod(_t * 0.5 + k * 0.5 + i * 0.37, 1.0)
			var p := head + Vector2(m.facing * (phase * 8.0 + sin(phase * TAU) * 2.0), -phase * 16.0)
			_draw_z(p.floor(), 3 if phase < 0.5 else 4, sin(phase * PI))


func _draw_spike(tip: Vector2, dir: Vector2, a: float, flying: bool):
	if flying:
		for i in range(SPIKE_LEN, SPIKE_LEN + 8):
			var fade := 1.0 - float(i - SPIKE_LEN) / 8.0
			_fx.draw_rect(Rect2((tip - dir * i).floor(), Vector2.ONE), Color(Pixel.OFF_WHITE, 0.3 * a * fade))
	for i in SPIKE_LEN:                              # a dark underside so it reads against the sky
		_fx.draw_rect(Rect2((tip - dir * i).floor() + Vector2(0, 1), Vector2.ONE), Color(Pixel.INK, 0.8 * a))
	for i in SPIKE_LEN:
		var col: Color = Pixel.WHITE if i == 0 else (Pixel.PALE if i < SPIKE_LEN - 2 else Pixel.BROWN)
		_fx.draw_rect(Rect2((tip - dir * i).floor(), Vector2.ONE), Color(col, a))


# a little n x n "z", outlined
func _draw_z(p: Vector2, n: int, a: float):
	var cells: Array[Vector2] = []
	for i in n:
		cells.append(p + Vector2(i, 0))
		cells.append(p + Vector2(i, n - 1))
	for r in range(1, n - 1):
		cells.append(p + Vector2(n - 1 - r, r))
	for c in cells:
		_fx.draw_rect(Rect2(c - Vector2.ONE, Vector2(3, 3)), Color(Pixel.INK, a))
	for c in cells:
		_fx.draw_rect(Rect2(c, Vector2.ONE), Color(Pixel.OFF_WHITE, a))
