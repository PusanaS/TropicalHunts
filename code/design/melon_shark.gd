extends Node2D
# THE WATERMELON SHARK (level 1's river, Morgan's call): a shark made of a watermelon, its rind striped green,
# its mouth red flesh with black seeds for teeth. It owns the deep water of one basin, and you can't get
# across while it's there.
#   In the water:  only its fin shows, circling out in the basin (`IDLE_FROM_EDGE` from the end you're nearest),
#                  so you can get into the water. Once you're in, it gives you `FIRST_GRACE` before it strikes.
#                  It can't be hurt in the water: a hit (or the flash) just makes it dive.
#   Its attack:    wade in, or jump out over its water, and it lines up: its fin sinks, bubbles rise and a "!"
#                  pops up (the tell; it hardly waits if you're in the air). Then it bursts out of the water at
#                  you, jaws wide. If it bites, it throws you back out onto the bank you came in from (`throw_to`).
#   No counter:    it's immune to the counter (Morgan's call: is_counterable is always false).
#   Hit it:        Q clangs off its rind with the Pineapple's armour clang and sparks, and never hurts it.
#                  Hit it as it leaps at you and it's knocked spinning back into the water, away from you (further
#                  for a W). It's not dazed: it comes straight back (Morgan's call). The moment it's away is your
#                  chance to charge W and drain the basin (living_background.gd).
#   Stranded:      wherever the water under it is drained, it flops about on the dry bed, gasping. It's
#                  helpless, but only a W kills it (Q still clangs off), bursting it in a big spray of juice,
#                  rind and seeds. If the water comes back first (waterfall.gd), it's back in business.
#   Relentless (Morgan's call: as strong as the sand serpent): it's big (1.5x, its back and fin out of the
#                  water), strikes from as far as the serpent does (`STRIKE_REACH` 220), hunts you down fast, curves
#                  after you in the air (`HOMING`), and is back for another go almost at once (`COOLDOWN`).
# Put it in the basin, anywhere: it finds the water. range_left / range_right: where it swims.
# PLACEHOLDER art drawn in code. Animations BOOM and Violeta would need: SWIM (fin above the water), TELL (the
# fin sinking), LEAP (jaws wide), BITE, FLUNG (spinning), FLOP (stranded), DIE.

@export var range_left := 9716.0
@export var range_right := 10390.0
@export var throw_to := Vector2(9640, 0)          # where a bite throws you (your feet): the bank you came in from
@export var max_hp := 3

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const NoDamagePop := preload("res://code/design/no_damage_pop.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const SPLASH_SOUND := preload("res://sounds/WATER_FOOTSTEP_freesound_community-splash-6213.mp3")
const SPLASH_DB := -2.0
const BITE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const BITE_DB := -2.0
const BITE_SKIP := 0.12                           # the file starts with 0.12 s of silence
const BURST_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const BURST_DB := -6.0
const BURST_SKIP := 0.02
const ARMOR_SOUND := preload("res://sounds/sword/sword_clash_06.wav")   # Q off its rind: the Pineapple's armour clang
const ARMOR_DB := -6.0
const ARMOR_SKIP := 0.012                         # the clang gets loud 13ms in

const SWIM_SPEED := 90.0                          # circling
const HUNT_SPEED := 300.0                         # closing in on you
const SINK := 11.0                                # its middle sits this far under the surface while it swims (its
												  # back just breaks the surface, its belly just clears the bed)
const KEEP_OFF := 110.0                           # it holds this far off you while it lines up
const STRIKE_REACH := 220.0                       # it strikes from this far (as far as the sand serpent's strike)
const TELL_TIME := 0.4                            # (the serpent's coil is 0.38)
const SNATCH_TELL := 0.1                          # you're in the air over its water: it hardly waits
const LEAP_GRAVITY := 1200.0
const LEAP_SPEED := 420.0                         # (how long it takes to reach you, by distance)
const LEAP_TIME := Vector2(0.32, 0.5)
const LEAP_MIN_RISE := 50.0                       # it always breaches at least this high over the surface
const HOMING := 900.0                             # on the way up it curves after you (px/s each second)
const COOLDOWN := 0.45                            # back in the water, before it can strike again
const IDLE_FROM_EDGE := 200.0                     # while you're out of its water, it circles this far into the basin
const FIRST_GRACE := 0.9                          # you've just got into its water: it waits this long before striking
const KNOCK_DIST := 150.0                         # hit as it leaps: knocked this far back (more for a W)
const KNOCK_TIME := 0.55
const FLING_SPIN := 14.0
const FLOP_EVERY := Vector2(0.35, 0.6)
const STRAND_GRACE := 0.3                         # just stranded: the wave that drained it doesn't count as a hit
const K := 1.5                                    # its size (Morgan wanted it bigger): the art is drawn this much up
const BODY := Rect2(-42, -15, 84, 30)             # its hurtbox, around its middle
const MOUTH := Rect2(21, -13, 30, 27)             # the bite (facing right)
const REST := 13.0                                # stranded: its middle this far over the bed
const PLAYER_GRAVITY := 980.0
const JUICE := Color("e8485a")

const IMG := Vector2i(100, 50)                    # the art, nose to the right
const MID := Vector2i(51, 30)                     # where its middle is in the art
const RIND_DARK := Color("2f6b2f")
const RIND := Color("4f8f3a")
const RIND_LIGHT := Color("8cc25a")
const RIND_PALE := Color("e8f2c4")                # the white rind between skin and flesh
const FLESH := Color("e8485a")
const FLESH_DARK := Color("b02a3e")
const SEED := Color("201a1a")
const BELLY := Color("cfe39a")                    # the pale patch a watermelon gets where it lay on the ground
const SHADOW := Color(0.05, 0.16, 0.28, 0.5)

enum S { SWIM, TELL, LEAP, FLUNG, STRANDED, DEAD }

var player: CharacterBody2D = null
var state := S.SWIM
var hp := 3
var facing := 1
var _names: Array = []
var _lb: Node = null                              # the living background (it owns the water)
var _w := {}                                      # our basin's water
var _time := 0.0                                  # in this state
var _t := 0.0
var _vel := Vector2.ZERO
var _cool := 0.0
var _tell := TELL_TIME
var _fin := 1.0                                   # how far its fin is up (0: sunk, striking)
var _mouth := 0.0                                 # 0 shut, 1 wide
var _rot := 0.0
var _bit := false                                 # this leap has bitten already
var _was_hunting := false
var _flop_in := 0.0
var _flash := 0.0                                 # white flash when hit
var _swing := Vector2(-1, -100)                   # the player's swing that last hit it: [state, start time]
var _bubbles: Array = []                          # [pos (local), age]
var _sparks: Array = []                           # off the rind when Q clangs on it: [pos (local), vel, life]
var _chunks: Array = []                           # rind, flesh and seeds flying when it bursts: [pos, vel, colour, size, life]
var _frames: Array = []                           # [mouth shut, half open, wide] (ImageTexture)
var _shadow: ImageTexture
var _splash_sound := AudioStreamPlayer.new()
var _bite_sound := AudioStreamPlayer.new()
var _burst_sound := AudioStreamPlayer.new()
var _armor_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	z_index = 3                                   # in front of the water (z 2), so its fin shows over it
	hp = max_hp
	for pair in [[_splash_sound, SPLASH_SOUND, SPLASH_DB], [_bite_sound, BITE_SOUND, BITE_DB], [_burst_sound, BURST_SOUND, BURST_DB],
			[_armor_sound, ARMOR_SOUND, ARMOR_DB]]:
		var s: AudioStreamPlayer = pair[0]
		s.stream = pair[1]
		s.volume_db = pair[2]
		add_child(s)
	var art := build_art()
	_frames = art.slice(0, 3)
	_shadow = art[3]


func _physics_process(delta: float):
	_t += delta
	_time += delta
	_cool = maxf(_cool - delta, 0.0)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_update_bubbles(delta)
	_update_chunks(delta)
	for sp: Array in _sparks:
		sp[1].y += 500.0 * delta
		sp[0] += sp[1] * delta
		sp[2] -= delta
	_sparks = _sparks.filter(func(sp): return sp[2] > 0.0)
	queue_redraw()
	if state == S.DEAD:
		return
	if _w.is_empty() and not _find_water():
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	_check_player_hits()
	match state:
		S.SWIM:
			_swim(delta)
		S.TELL:
			_tell_up(delta)
		S.LEAP:
			_leaping(delta)
		S.FLUNG:
			_flung(delta)
		S.STRANDED:
			_stranded(delta)


# the living background builds its water in its own _ready: look for it until it's there
func _find_water() -> bool:
	_lb = get_tree().get_first_node_in_group("living_background")
	if _lb == null or not _lb.has_method("water_region"):
		return false
	_w = _lb.water_region(global_position.x)
	if _w.is_empty():
		return false
	global_position.y = _level() + SINK
	return true


func _level() -> float:
	return _w["level"]


func _bed() -> float:
	return _w["bed"]


func _wet(x: float) -> bool:
	return _lb.wet_at(_w, x)


func _set_state(s: S):
	state = s
	_time = 0.0


# ---------- in the water ----------
# you're in its water: wading in it, or in the air over it
func _hunting() -> bool:
	var p := player.global_position
	if p.x < range_left - 16.0 or p.x > range_right + 16.0 or not _wet(p.x):
		return false
	return p.y >= _level() - 1.0 or not player.is_on_floor()


# how far it can swim each way from here before the water ends (it's drained there, or its range ends)
func _wet_span() -> Vector2:
	var lo := global_position.x
	while lo - 4.0 >= range_left and _wet(lo - 4.0):
		lo -= 4.0
	var hi := global_position.x
	while hi + 4.0 <= range_right and _wet(hi + 4.0):
		hi += 4.0
	return Vector2(lo, hi)


func _swim(delta: float):
	if not _wet(global_position.x):
		_strand()
		return
	var span := _wet_span()
	var hunting := _hunting()
	var px := player.global_position.x
	var target: float
	if hunting:                                   # close in, holding KEEP_OFF away on its side of you
		var side := signf(global_position.x - px)
		if side == 0.0:
			side = -float(facing)
		target = px + side * KEEP_OFF
	else:                                         # circle about where you'd come in
		var near_left := px < (range_left + range_right) / 2.0
		target = (range_left + IDLE_FROM_EDGE if near_left else range_right - IDLE_FROM_EDGE) + sin(_t * 1.1) * 48.0
	target = clampf(target, span.x, span.y)
	if hunting and not _was_hunting:              # you've just got in: a moment before it comes for you
		_cool = maxf(_cool, FIRST_GRACE)
	_was_hunting = hunting
	var speed := HUNT_SPEED if hunting else SWIM_SPEED
	var step := clampf(target - global_position.x, -speed * delta, speed * delta)
	global_position.x += step
	if absf(step) > 0.5:
		facing = int(signf(step))
	if hunting and absf(px - global_position.x) < KEEP_OFF * 1.3:
		facing = int(signf(px - global_position.x)) if px != global_position.x else facing
	_fin = move_toward(_fin, 1.0, delta * 4.0)
	_mouth = move_toward(_mouth, 0.0, delta * 4.0)
	global_position.y = _level() + SINK + (1.0 - _fin) * 18.0 + roundf(sin(_t * 3.0))
	if hunting and _cool <= 0.0 and absf(px - global_position.x) <= STRIKE_REACH:
		_tell = SNATCH_TELL if not player.is_on_floor() else TELL_TIME
		_set_state(S.TELL)


# the tell: its fin sinks, bubbles rise, a "!" pops up. It keeps lining up on you.
func _tell_up(delta: float):
	if not _wet(global_position.x):
		_strand()
		return
	if not _hunting():                            # you got out: back to circling
		_was_hunting = false
		_set_state(S.SWIM)
		return
	var px := player.global_position.x
	facing = int(signf(px - global_position.x)) if px != global_position.x else facing
	var span := _wet_span()
	var target := clampf(px - facing * KEEP_OFF, span.x, span.y)
	global_position.x += clampf(target - global_position.x, -HUNT_SPEED * 0.5 * delta, HUNT_SPEED * 0.5 * delta)
	_fin = move_toward(_fin, 0.0, delta / (_tell * 0.7))
	global_position.y = _level() + SINK + (1.0 - _fin) * 18.0
	if randf() < delta * 30.0:
		_bubbles.append([Vector2(randf_range(-30.0, 30.0), randf_range(0.0, 6.0)), 0.0])
	if _time >= _tell:
		_leap()


# out of the water at you: aimed where you'll be, always breaching high
func _leap():
	var from := global_position
	var target := player.global_position + Vector2(0, -20)
	var dist := from.distance_to(target)
	var t := clampf(dist / LEAP_SPEED, LEAP_TIME.x, LEAP_TIME.y)
	target.x += player.velocity.x * t
	if not player.is_on_floor():
		target.y += player.velocity.y * t + 0.5 * PLAYER_GRAVITY * t * t
	var vy := (target.y - from.y - 0.5 * LEAP_GRAVITY * t * t) / t
	var min_vy := -sqrt(2.0 * LEAP_GRAVITY * maxf(from.y - (_level() - LEAP_MIN_RISE), 0.0))
	if vy > min_vy:                               # too flat: go higher, and come down on you instead
		vy = min_vy
		var c := from.y - target.y
		var disc := vy * vy - 2.0 * LEAP_GRAVITY * c
		t = (-vy + sqrt(maxf(disc, 0.0))) / LEAP_GRAVITY
	_vel = Vector2((target.x - from.x) / maxf(t, 0.2), vy)
	facing = int(signf(_vel.x)) if _vel.x != 0.0 else facing
	_bit = false
	_set_state(S.LEAP)
	_fin = 1.0
	_splash(26, 280.0)


func _leaping(delta: float):
	_vel.y += LEAP_GRAVITY * delta
	global_position += _vel * delta
	_keep_in_basin()
	_mouth = move_toward(_mouth, 0.0 if _bit else 1.0, delta * (10.0 if _bit else 7.0))
	if not _bit and _vel.y < 0.0:                 # curving after you on the way up
		var dx := player.global_position.x - global_position.x
		var want := signf(dx) * minf(absf(dx) * 4.0, 560.0)
		_vel.x = move_toward(_vel.x, want, HOMING * delta)
		if absf(_vel.x) > 1.0:
			facing = int(signf(_vel.x))
	_rot = _tilt(_vel)
	if not _bit and _can_bite() and _mouth_box().intersects(_player_box()):
		_bite()
	_land(delta)


# coming down: back into the water, or onto the dry bed (stranded)
func _land(_delta: float):
	if _vel.y <= 0.0:
		return
	if _wet(global_position.x):
		if global_position.y >= _level() + SINK:
			global_position.y = _level() + SINK
			_vel = Vector2.ZERO
			_rot = 0.0
			_splash(20, 220.0)
			_cool = COOLDOWN
			_fin = 0.3
			_set_state(S.SWIM)
	elif global_position.y >= _bed() - REST:
		_strand()


func _keep_in_basin():
	var x0: float = _w["x0"] + 12.0
	var x1: float = _w["x0"] + _w["n"] - 12.0
	if global_position.x < x0 or global_position.x > x1:
		global_position.x = clampf(global_position.x, x0, x1)
		_vel.x = 0.0


func _can_bite() -> bool:
	return Time.get_ticks_msec() / 1000.0 >= FruitMinion._player_safe_until


# chomp: it throws you back out onto the bank you came in from
func _bite():
	_bit = true
	_bite_sound.pitch_scale = randf_range(1.2, 1.4)
	_bite_sound.play(BITE_SKIP)
	var p := player.global_position
	var g: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var t := 0.8
	var v := Vector2(clampf((throw_to.x - p.x) / t, -900.0, 900.0), (throw_to.y - p.y - 0.5 * g * t * t) / t)
	if player.has_method("launch"):
		player.launch(v, t * 0.8)
	else:
		player.velocity = v
	FruitMinion._player_safe_until = Time.get_ticks_msec() / 1000.0 + FruitMinion.PLAYER_SAFE_TIME
	player.modulate = Color(1, 0.35, 0.35)
	player.create_tween().tween_property(player, "modulate", Color.WHITE, FruitMinion.PLAYER_SAFE_TIME)
	FruitMinion.play_hurt_sound(player)
	player._shake(6.0, 0.25)
	_lb.splash(_w, p.x, 16, 240.0)


# immune to the counter (Morgan's call): Q as it leaps is just a Q, and clangs off it
func is_counterable() -> bool:
	return false


# hit as it leaps at you: knocked spinning back into the water, away from you (dir), further for a W (heavy).
# It comes straight back for you.
func _knock(dir: float, heavy: bool):
	_bit = true
	var to := clampf(global_position.x + dir * KNOCK_DIST * (1.5 if heavy else 1.0), range_left + 20.0, range_right - 20.0)
	var t := KNOCK_TIME
	var land := _level() + SINK
	_vel = Vector2((to - global_position.x) / t, (land - global_position.y - 0.5 * LEAP_GRAVITY * t * t) / t)
	_mouth = 0.3
	_flash = 1.0
	_set_state(S.FLUNG)


func _flung(delta: float):
	_vel.y += LEAP_GRAVITY * delta
	global_position += _vel * delta
	_keep_in_basin()
	_rot += FLING_SPIN * signf(_vel.x if _vel.x != 0.0 else 1.0) * delta
	_land(delta)


# ---------- stranded ----------
func _strand():
	_set_state(S.STRANDED)
	_rot = 0.0
	_flop_in = 0.2
	_vel = Vector2.ZERO


# flopping about on the dry bed, gasping. The water coming back sets it free.
func _stranded(delta: float):
	if _wet(global_position.x):
		global_position.y = _level() + SINK
		_rot = 0.0
		_vel = Vector2.ZERO
		_splash(18, 200.0)
		_cool = COOLDOWN
		_set_state(S.SWIM)
		return
	var floor_y := _bed() - REST
	_vel.y += LEAP_GRAVITY * delta
	global_position += _vel * delta
	_keep_in_basin()
	if global_position.y >= floor_y:
		global_position.y = floor_y
		if _vel.y > 120.0:                        # a wet slap on the bed
			_slap()
		_vel = Vector2(_vel.x * 0.5, 0.0) if absf(_vel.x) > 5.0 else Vector2.ZERO
		_flop_in -= delta
		if _flop_in <= 0.0:                       # flop!
			_flop_in = randf_range(FLOP_EVERY.x, FLOP_EVERY.y)
			_vel = Vector2(randf_range(-50.0, 50.0), -randf_range(140.0, 220.0))
			if randf() < 0.4:
				facing = -facing
	_rot = sin(_t * 14.0) * 0.35 if global_position.y < floor_y - 1.0 else sin(_t * 9.0) * 0.12
	_mouth = 0.5 + 0.5 * sin(_t * 9.0)            # gasping


func _slap():
	_splash_sound.pitch_scale = randf_range(0.6, 0.8)
	_splash_sound.volume_db = SPLASH_DB - 10.0
	_splash_sound.play()


# ---------- getting hit ----------
func _hurtbox() -> Rect2:
	return Rect2(global_position + BODY.position, BODY.size)


func _mouth_box() -> Rect2:
	var r := MOUTH
	if facing < 0:
		r.position.x = -r.position.x - r.size.x
	return Rect2(global_position + r.position, r.size)


func _player_box() -> Rect2:
	return Rect2(player.global_position + FruitMinion.PLAYER_BOX.position, FruitMinion.PLAYER_BOX.size)


# the player's attacks, read from their state like the minion does (each swing counts once)
func _check_player_hits():
	var st: String = _names[player.state]
	var damage := 0
	var push := Vector2.ZERO
	var hit := EnemyKit.player_attack_hitting(player, _names, _hurtbox())
	if not hit.is_empty():
		damage = hit["damage"]
		push = hit["push"]
	elif st == "CHARGED_SMASH":                   # the charged smash hits everything in its reach
		var d := player.global_position - global_position
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var height: float = player.get_script().CHARGE_HEIGHT
		if absf(d.x) <= lerpf(radius.x, radius.y, player.charge) + BODY.size.x / 2.0 and absf(d.y) <= height + 12.0:
			damage = 4
			push = Vector2(signf(-d.x) * 200.0, -260.0)
	if damage <= 0:
		return
	var swing := Vector2(player.state, _t - player.state_time)
	if swing.x == _swing.x and absf(swing.y - _swing.y) < 0.05:
		return
	_swing = swing
	var light := damage < 3                       # Q (and the light slam): it clangs off the rind
	if not light and state != S.STRANDED:         # a W does nothing either while it's in its water (no pop for
		_no_damage(global_position.y)             # take_hit: the drain's wall shouldn't say it)
	_hit(damage, push, light, light)


# something hit it (a wave, the flash, a spike): no clang, it's not a blade
func take_hit(damage: int, push: Vector2):
	_hit(damage, push, damage < 3, false)


func _hit(damage: int, push: Vector2, light: bool, clang: bool):
	var dir := signf(push.x)
	if dir == 0.0:
		dir = signf(global_position.x - player.global_position.x) if player else float(-facing)
	if dir == 0.0:
		dir = float(-facing)
	if clang:
		_clang(global_position + Vector2(-dir * BODY.size.x * 0.3, -6.0))
	match state:
		S.STRANDED:
			if _time < STRAND_GRACE:
				return
			if light:                             # only a W kills it: Q just makes it flop
				_vel = Vector2(dir * 40.0, -160.0)
				return
			hp -= damage
			_flash = 1.0
			_bite_sound.pitch_scale = 1.6
			_bite_sound.play(BITE_SKIP)
			if hp <= 0:
				_die(dir)
			else:                                 # a big flop
				_vel = Vector2(dir * 80.0, -260.0)
		S.LEAP:                                   # knocked back into the water, no bite
			_knock(dir, not light)
			if not light:
				_burst_sound.play(BURST_SKIP)
		S.SWIM, S.TELL:                           # it just dives
			_fin = 0.0
			_cool = maxf(_cool, 0.4)
			if state == S.TELL:
				_set_state(S.SWIM)
			if not clang:
				_splash(10, 160.0)


# Q off its rind: the Pineapple's armour clang, and sparks where the blade hit (world)
func _clang(at: Vector2):
	_armor_sound.pitch_scale = randf_range(0.95, 1.08)
	_armor_sound.play(ARMOR_SKIP)
	_no_damage(at.y)
	_flash = maxf(_flash, 0.5)
	for i in 10:
		_sparks.append([at - global_position, Vector2(randf_range(-160.0, 160.0), -randf_range(40.0, 200.0)), randf_range(0.15, 0.35)])


# the grey pop over it: IMMUNE IN WATER while it's in its water (so you know to drain it; Morgan's call), the usual
# NO DAMAGE once it's stranded (a Q)
func _no_damage(at_y: float):
	var text := NoDamagePop.TEXT if state == S.STRANDED else "IMMUNE IN WATER"
	NoDamagePop.show_on(self, Vector2(global_position.x, minf(at_y, global_position.y) - 30.0), text)


# the flash only goes for it once it's stranded
func is_alive() -> bool:
	return state == S.STRANDED


# it bursts: juice everywhere, chunks of rind and flesh, seeds
func _die(dir: float):
	hp = 0
	_set_state(S.DEAD)
	_bite_sound.pitch_scale = 0.8
	_bite_sound.volume_db = BITE_DB + 2.0
	_bite_sound.play(BITE_SKIP)
	_burst_sound.play(BURST_SKIP)
	for i in 4:
		var spray: Node2D = JuiceSpray.new()
		spray.color = JUICE
		spray.aim = Vector2.from_angle(-PI / 2.0 + (i - 1.5) * 0.6 + dir * 0.2)
		spray.power = 2.2
		spray.floor_y = _bed()
		spray.position = get_parent().to_local(global_position + Vector2(0, -4))
		get_parent().add_child(spray)
	for i in 44:
		var col: Color = [RIND_DARK, RIND, FLESH, FLESH, RIND_PALE, SEED][i % 6]
		var size := 2.0 if col == SEED else randf_range(3.0, 6.0)
		_chunks.append([Vector2(randf_range(-36.0, 36.0), randf_range(-12.0, 12.0)),
			Vector2(dir * randf_range(20.0, 200.0) + randf_range(-120.0, 120.0), -randf_range(120.0, 380.0)),
			col, roundf(size), randf_range(1.0, 1.6)])
	EnemyKit.hitstop(get_tree(), 0.08)
	player._shake(8.0, 0.35)
	get_tree().call_group("living_background", "burst", global_position, 4.0)


# ---------- effects ----------
func _splash(count: int, speed: float):
	if _lb and not _w.is_empty() and _wet(global_position.x):
		_lb.splash(_w, global_position.x, count, speed)
	_splash_sound.pitch_scale = randf_range(0.85, 1.1)
	_splash_sound.volume_db = SPLASH_DB
	_splash_sound.play()


func _update_bubbles(delta: float):
	for b: Array in _bubbles:
		b[1] += delta
		b[0].y -= 30.0 * delta
	_bubbles = _bubbles.filter(func(b): return b[1] < 0.4)


func _update_chunks(delta: float):
	if _chunks.is_empty():
		return
	var floor_y := (_bed() if not _w.is_empty() else global_position.y + 10.0) - global_position.y
	for c: Array in _chunks:
		c[1].y += 800.0 * delta
		c[0] += c[1] * delta
		c[4] -= delta
		if c[0].y > floor_y and c[1].y > 0.0:
			c[0].y = floor_y
			c[1] = Vector2(c[1].x * 0.4, -c[1].y * 0.25)
	_chunks = _chunks.filter(func(c): return c[4] > 0.0)


# the body's tilt to follow its flight (nose along its velocity), not past 60 degrees
func _tilt(v: Vector2) -> float:
	var a := atan2(v.y, absf(v.x))
	return clampf(a, -PI / 3.0, PI / 3.0)


# ---------- drawing ----------
func _draw():
	for c: Array in _chunks:
		var col: Color = c[2]
		draw_rect(Rect2((c[0] as Vector2).round(), Vector2(c[3], c[3])), Color(col, clampf(float(c[4]) * 3.0, 0.0, 1.0)))
	if state == S.DEAD or _frames.is_empty() or _w.is_empty():
		return
	var tex: ImageTexture = _frames[clampi(int(roundf(_mouth * 2.0)), 0, 2)]
	var flip := Vector2(facing, 1)
	if state == S.SWIM or state == S.TELL:
		# under the water: only its fin and back show above the surface, the rest is a dark shape under it
		# (down to the bed)
		var rows := clampi(int(_level() - (global_position.y - MID.y)), 0, IMG.y)
		var bed_rows := clampi(int(_bed() - (global_position.y - MID.y)), rows, IMG.y)
		draw_set_transform(Vector2.ZERO, 0.0, flip)
		if rows > 0:
			draw_texture_rect_region(tex, Rect2(-MID.x, -MID.y, IMG.x, rows), Rect2(0, 0, IMG.x, rows))
		if bed_rows > rows:
			draw_texture_rect_region(_shadow, Rect2(-MID.x, -MID.y + rows, IMG.x, bed_rows - rows), Rect2(0, rows, IMG.x, bed_rows - rows))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for b: Array in _bubbles:                 # the tell's bubbles, popping at the surface
			var p: Vector2 = b[0]
			var y := maxf(p.y, _level() - global_position.y)
			draw_rect(Rect2(Vector2(p.x, y).round(), Vector2(2, 2)), Pixel.OFF_WHITE)
		if state == S.TELL:                       # "!"
			var at := Vector2(-2, _level() - global_position.y - 34.0 - roundf(minf(_time * 60.0, 6.0)))
			Pixel.draw_cells(self, Pixel.cells("!", at.round(), 2), [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD])
		return
	draw_set_transform(Vector2.ZERO, _rot, flip)
	var tint := Color(1, 1, 1).lerp(Color(3, 3, 3), _flash)
	draw_texture(tex, Vector2(-MID.x, -MID.y), tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for sp: Array in _sparks:
		draw_rect(Rect2((sp[0] as Vector2).round(), Vector2(2, 2) if sp[2] > 0.2 else Vector2.ONE), Pixel.MUSTARD if int(sp[2] * 40.0) % 2 else Pixel.WHITE)


# the art, drawn once into textures (one per mouth opening): a striped rind torpedo with a dorsal fin, a
# forked tail and a pectoral fin, a pale belly patch, an angry eye, and a mouth that opens onto red flesh with
# black seeds for teeth. Outlined in BOOM's indigo.
# Returns [mouth shut, half open, wide, the dark shape under water]. Static: the surf wave (surf_wave.gd)
# borrows it for its sneak peek of the shark.
static func build_art() -> Array:
	var out: Array = []
	for k in 3:
		var img := Image.create(IMG.x, IMG.y, false, Image.FORMAT_RGBA8)
		_paint(img, k / 2.0)
		out.append(ImageTexture.create_from_image(img))
	var sil := Image.create(IMG.x, IMG.y, false, Image.FORMAT_RGBA8)
	var base: Image = out[0].get_image()
	for y in IMG.y:
		for x in IMG.x:
			if base.get_pixel(x, y).a > 0.0:
				sil.set_pixel(x, y, SHADOW)
	out.append(ImageTexture.create_from_image(sil))
	return out


static func _paint(img: Image, mouth: float):
	var cy := MID.y
	var x0 := roundi(6.0 * K)                     # tail end of the body
	var length := roundi(56.0 * K)
	var mouth_len := 14.0 * K
	var inside := func(x: int, y: int) -> int:    # 0 outside, 1 body, 2 fin, 3 mouth (flesh)
		var i := x - x0
		if i >= 0 and i <= length:
			var u := float(i) / length
			var hh := maxf(10.0 * K * sqrt(maxf(0.0, 1.0 - pow((u - 0.55) / 0.5, 2.0))), 2.5 * K)
			if i > length - 16.0 * K:
				hh += mouth * 4.0 * K * (float(i) - (length - 16.0 * K)) / (16.0 * K)   # the jaws spread as they open
			var top := cy - hh
			var bottom := cy + hh * 0.85
			if y >= roundi(top) and y <= roundi(bottom):
				var mi := float(i) - (length - mouth_len)
				if mouth > 0.0 and mi >= 0.0:                              # the open mouth: a wedge into the nose
					var gap := mouth * 6.5 * K * mi / mouth_len
					if absf(y - (cy + 2.0 * K)) < gap:
						return 3
				return 1
		var p := Vector2(x, y)
		var o := Vector2(x0, cy)
		# dorsal fin: a swept-back triangle on its back
		if Geometry2D.point_is_inside_triangle(p, o + Vector2(22, -9) * K, o + Vector2(36, -9) * K, o + Vector2(24, -19) * K):
			return 2
		# the forked tail
		if Geometry2D.point_is_inside_triangle(p, o + Vector2(2, 0) * K, o + Vector2(-6, -12) * K, o + Vector2(-1, -1) * K) \
				or Geometry2D.point_is_inside_triangle(p, o + Vector2(2, 0) * K, o + Vector2(-5, 9) * K, o + Vector2(-1, 1) * K) \
				or Rect2(o + Vector2(-1, -2) * K, Vector2(4, 4) * K).has_point(p):
			return 2
		# a pectoral fin under its front
		if Geometry2D.point_is_inside_triangle(p, o + Vector2(34, 6) * K, o + Vector2(40, 6) * K, o + Vector2(30, 12) * K):
			return 2
		return 0
	for y in IMG.y:
		for x in IMG.x:
			var k: int = inside.call(x, y)
			if k == 0:
				continue
			var edge := false
			for n: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var o: int = inside.call(x + n.x, y + n.y)
				if o == 0 or (k == 3) != (o == 3):
					edge = true
			var col: Color
			if k == 3:                            # the flesh inside the mouth, darker deep in
				col = FLESH_DARK if x < x0 + length - 9.0 * K else FLESH
				if edge:
					col = RIND_PALE               # the pale rind lines the cut
			elif edge:
				col = Pixel.INK
			elif k == 2:
				col = RIND_DARK if (x + y) % 5 else RIND
			else:
				var band := int(floorf((y - cy + 18.0 + 2.0 * sin(x * 0.3)) / 4.0)) % 2
				col = RIND_DARK if band == 0 else RIND
				if y > cy + 4.0 * K:
					col = BELLY if (y > cy + 6.0 * K or band == 1) else RIND_LIGHT
				elif y <= cy - 7.0 * K and band == 1:
					col = RIND_LIGHT              # lit along its back
			img.set_pixel(x, y, col)
	# teeth: black seeds along both jaws, 2px each
	if mouth > 0.0:
		var mi := 4.0
		while mi < mouth_len:
			var gap := mouth * 6.5 * K * mi / mouth_len
			var x := roundi(x0 + length - mouth_len + mi)
			var my := cy + 2.0 * K
			for yy in [roundi(my - gap + 1.0), roundi(my + gap - 2.0)]:
				for d in 2:
					if x + d < IMG.x and yy >= 0 and yy + 1 < IMG.y and img.get_pixel(x + d, yy).a > 0.0:
						img.set_pixel(x + d, yy, SEED)
			mi += 5.0
	# the eye, with an angry brow
	var ex := roundi(x0 + length - 13.0 * K)
	var ey := roundi(cy - 5.0 * K - mouth * 3.0)
	for e in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)]:
		img.set_pixelv(Vector2i(ex, ey) + e, Pixel.WHITE)
	img.set_pixelv(Vector2i(ex + 1, ey + 1), SEED)
	img.set_pixelv(Vector2i(ex + 2, ey + 1), SEED)
	img.set_pixelv(Vector2i(ex + 2, ey + 2), SEED)
	for b in 5:
		img.set_pixel(ex - 1 + b, ey - 2 + (1 if b < 3 else 0), Pixel.INK)
