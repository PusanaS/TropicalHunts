extends Node2D
# STARFRUIT: Level 2's minion, and its way up. PLACEHOLDER look, drawn in code in BOOM's palette.
#
# Monster card
#   Moves:     "fall": drops slowly from where it appears, spinning, with a glittering trail like a
#              shooting star at sunset (star_shaft.gd and star_queen.gd drop them; it can hang still for
#              a moment first). "float": hangs in the air bobbing, a stepping stone over a gap.
#   Notices:   nothing. It isn't after you.
#   Attack:    none. Touching it is harmless.
#   Beaten by: any hit pops it. An AIR Q pops it AND throws you on to the next starfruit (or wherever
#              its shaft or the Star Queen says), with your double jump back: keep pressing Q to zigzag
#              up a shaft or hop across a gap.
#   After:     "fall" ones are gone; "float" ones grow back after respawn_time.
#   Drops:     one starfruit juice drop.
#   Animations BOOM / Violeta will need: SPIN (falling), FLOAT (bobbing), POP
#
# Whatever it belongs to can steer the throw: if its parent has next_target(fruit, player), that says
# where the player's feet should go (or null to let the starfruit pick the next one itself).

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const JuiceDrop := preload("res://code/design/juice_drop.gd")
# popping: the fruit minion's hit, played higher and quieter, so it's a light pop
const POP_SOUND := preload("res://sounds/sword/sword_hit_flesh_04.wav")
const POP_SOUND_DB := -8.0
const POP_PITCH := 1.35

const LIGHT := ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2"]
const R_OUT := 9.0               # the star's points reach this far from its middle (18 px across)...
const R_IN := 4.0                # ...and the dips between them this far
const HURT_R := 11.0             # the player hits it anywhere in this box around its middle
const STEPS := 48                # its spin is drawn in this many steps (each one cached)
# the throw: the next air Q connects when the feet land this far behind and below a starfruit
const AIM_OFFSET := Vector2(18, 26)
const GRAVITY := Vector2(0, 980)
const AIR_SPEED := 520.0         # a throw takes distance / this many seconds, between these two:
const AIR_TIME := Vector2(0.36, 0.7)   # (tuned so a throw crosses a 360-wide shaft without capping)
const MAX_THROW := Vector2(700, 760)   # caps on the throw's speed: sideways, up
const DEFAULT_HOP := Vector2(240, -460)   # an air Q with nothing to aim at: a hop forward
const SEARCH := Rect2(60, -260, 260, 320)  # where it looks for the next starfruit: x ahead, y from it
const MAX_FALL := 700.0          # a falling one this far below where it appeared is gone
const TRAIL_EVERY := 0.03
const TRAIL_LEN := 10

@export var mode := "fall"               # "fall" or "float"
@export var fall_speed := 70.0
@export var respawn_time := 2.5          # float mode: grows back after this long (0 = stays gone)
@export var juice_color := Color(0.96, 0.82, 0.3)

var hp := 1
var hang := 0.0                  # fall mode: hangs still this long before it falls (set by spawners)
var player: CharacterBody2D = null

static var _cache := {}          # spin step -> its pixels, shared by every starfruit

var _names: Array = []
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _home := Vector2.ZERO
var _start_y := 0.0
var _t := 0.0
var _spin := 0.0
var _pop_t := 0.0
var _gone := false               # fell to the floor and fizzled out (not a hit: hp stays)
var _trail := []                 # recent places it's been (global), newest last
var _trail_timer := 0.0
var _bits := []                  # sparkles: [pos (global), vel, life, colour]
var _sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	add_to_group("starfruit")
	_home = position
	_start_y = global_position.y
	_spin = randf() * TAU
	var r := AudioStreamRandomizer.new()
	r.add_stream(-1, POP_SOUND)
	r.random_pitch = 1.15
	_sound.stream = r
	_sound.volume_db = POP_SOUND_DB
	_sound.pitch_scale = POP_PITCH
	add_child(_sound)


func is_alive() -> bool:
	return hp > 0 and not _gone


# a little burst of sparkles, for a starfruit that just dropped in
func sparkle_in():
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0)
		_bits.append([global_position + d * 4.0, d * randf_range(40, 80), randf_range(0.25, 0.4), Pixel.OFF_WHITE])


# where the player's feet should go so their next air Q catches this starfruit, thrown from `from`
# (it allows for how far it will have fallen by then)
func aim_point(from: Vector2) -> Vector2:
	var t := throw_time(global_position - from)
	var at := global_position
	if mode == "fall":
		at.y += fall_speed * maxf(t - hang, 0.0)
	var side := signf(at.x - from.x)
	if side == 0.0:
		side = 1.0
	return at + Vector2(-side * AIM_OFFSET.x, AIM_OFFSET.y)


static func throw_time(d: Vector2) -> float:
	return clampf(d.length() / AIR_SPEED, AIR_TIME.x, AIR_TIME.y)


# the throw that carries the player's feet from `from` to `to`: [velocity, seconds]
static func throw_arc(from: Vector2, to: Vector2) -> Array:
	var d := to - from
	var t := throw_time(d)
	var v := d / t - GRAVITY * 0.5 * t
	v.x = clampf(v.x, -MAX_THROW.x, MAX_THROW.x)
	v.y = maxf(v.y, -MAX_THROW.y)
	return [v, t]


# ---------- every frame ----------
func _physics_process(delta: float):
	_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player:
			_names = player.get_script().State.keys()
	_update_bits(delta)
	queue_redraw()
	if hp <= 0 or _gone:
		_pop_t += delta
		if hp <= 0 and mode == "float" and respawn_time > 0.0:
			if _pop_t >= respawn_time:
				_grow_back()
		elif _pop_t >= 0.7:            # (long enough for the burst and the pop sound)
			queue_free()
		return

	if mode == "float":
		position = _home + Vector2(0, roundf(sin(_t * 2.4) * 3.0))
		_spin += delta * 0.8
	elif hang > 0.0:
		hang -= delta
		_spin += delta * 1.2
	else:
		position.y += fall_speed * delta
		_spin += delta * 2.6
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = TRAIL_EVERY
			_trail.append(global_position)
			if _trail.size() > TRAIL_LEN:
				_trail.pop_front()
			if randf() < 0.35:             # a twinkle left behind now and then
				_bits.append([global_position + Vector2(randf_range(-4, 4), -6), Vector2(randf_range(-8, 8), -10), 0.35, Pixel.WHITE])
		if _on_floor() or global_position.y > _start_y + MAX_FALL:
			_fizzle()
			return
	if player:
		_check_player_attack()


func _hurtbox() -> Rect2:
	return Rect2(global_position - Vector2(HURT_R, HURT_R), Vector2(HURT_R, HURT_R) * 2.0)


func _on_floor() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, R_OUT + 2.0), 1)
	if player:
		q.exclude = [player.get_rid()]
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


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
	var move: String = _names[ps]
	var throw: bool = move in LIGHT and player.light_in_air and not player.is_on_floor()
	_pop()
	if throw:
		_throw_player()


# ---------- getting hit ----------
func take_hit(_damage: int, _push: Vector2):
	_pop()


# the counter's chain cuts it like any other enemy: it just pops
func cut_in_half(_dir: int, _a := Vector2.INF, _b := Vector2.INF):
	_pop()


func _pop():
	if hp <= 0 or _gone:
		return
	hp = 0
	_pop_t = 0.0
	_trail.clear()
	_sound.play()
	EnemyKit.hitstop(get_tree(), 0.035)
	# a star-shaped burst: five long rays out of its points, and a scatter between them
	var turn := _spin_step() * TAU / STEPS - PI / 2.0
	for i in 5:
		var d := Vector2.from_angle(turn + i * TAU / 5.0)
		for k in 3:
			_bits.append([global_position + d * 4.0, d * (90.0 + k * 45.0), 0.35 + k * 0.05, Pixel.WHITE if k == 0 else Pixel.MUSTARD])
	for i in 10:
		var d := Vector2.from_angle(randf() * TAU)
		_bits.append([global_position, d * randf_range(30, 90), randf_range(0.25, 0.45), Pixel.GREEN if i % 3 == 0 else Pixel.MUSTARD])
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = "Starfruit"
	drop.color = juice_color
	drop.top_level = true            # its parent may be moving (the Star Queen holds her starfruits)
	drop.position = global_position
	get_parent().add_child.call_deferred(drop)


# an air Q popped it: throw the player on to the next one
func _throw_player():
	var aim = null
	var parent := get_parent()
	if parent and parent.has_method("next_target"):
		aim = parent.next_target(self, player)
	if not (aim is Vector2):
		aim = _next_fruit_aim()
	if aim is Vector2:
		var arc := throw_arc(player.global_position, aim)
		player.launch(arc[0], float(arc[1]) * 0.9)
	else:
		player.launch(Vector2(player.facing * DEFAULT_HOP.x, DEFAULT_HOP.y), 0.3)


# the nearest other starfruit ahead of the player and not too far up or down; where to aim for it
func _next_fruit_aim():
	var dir := float(player.facing)
	var best: Node2D = null
	var best_d := INF
	for f in get_tree().get_nodes_in_group("starfruit"):
		if f == self or not is_instance_valid(f) or not f.is_alive():
			continue
		var d: Vector2 = f.global_position - global_position
		var ahead := d.x * dir
		if ahead < SEARCH.position.x or ahead > SEARCH.end.x or d.y < SEARCH.position.y or d.y > SEARCH.end.y:
			continue
		if d.length() < best_d:
			best_d = d.length()
			best = f
	if best == null:
		return null
	return best.aim_point(player.global_position)


# fell all the way to the floor: it fizzles out (no juice, and it doesn't count as a hit)
func _fizzle():
	_gone = true
	_pop_t = 0.0
	_trail.clear()
	remove_from_group("starfruit")
	remove_from_group("enemies")     # (it keeps its hp, so the counter chain would still teleport to it)
	for i in 6:
		var d := Vector2.from_angle(PI + i * PI / 5.0)
		_bits.append([global_position, d * randf_range(20, 50), randf_range(0.2, 0.35), Pixel.MUSTARD])


func _grow_back():
	hp = 1
	_pop_t = 0.0
	position = _home
	sparkle_in()


func _update_bits(delta: float):
	for b in _bits:
		b[0] += b[1] * delta
		b[1] *= 0.92
		b[2] -= delta
	_bits = _bits.filter(func(b): return b[2] > 0.0)


# ---------- drawing ----------
func _spin_step() -> int:
	return posmod(int(roundf(_spin / TAU * STEPS)), STEPS)


# the pixels of a five-point starfruit slice, its points r_out from the middle and the dips r_in,
# turned by `angle`: each [offset from the middle, kind] (0 outline, 1 green rim, 2 flesh, 3 light
# flesh, 4 the pale seed star in the middle). Shared with the Star Queen (bigger).
static func star_pixels(r_out: float, r_in: float, angle: float) -> Array:
	var outer := PackedVector2Array()
	var core := PackedVector2Array()
	for i in 10:
		var a := angle - PI / 2.0 + i * PI / 5.0
		var r := r_out if i % 2 == 0 else r_in
		outer.append(Vector2(cos(a), sin(a)) * r)
		core.append(Vector2(cos(a), sin(a)) * r * 0.32)
	var inside := {}
	var n := int(ceilf(r_out)) + 1
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), outer):
				inside[Vector2i(x, y)] = true
	var out := []
	var sides := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for p in inside:
		var kind := 3 if p.x + p.y < 0 else 2        # lit from the top left
		var edge := false
		var rim := false
		for d in sides:
			if not inside.has(p + d):
				edge = true
			elif not inside.has(p + d * 2):
				rim = true
		if edge:
			kind = 0
		elif rim:
			kind = 1
		elif Geometry2D.is_point_in_polygon(Vector2(p.x + 0.5, p.y + 0.5), core):
			kind = 4
		out.append([Vector2(p.x, p.y), kind])
	return out


static func star_colour(kind: int) -> Color:
	match kind:
		0: return Pixel.INK
		1: return Pixel.GREEN
		3: return Pixel.MUSTARD.lightened(0.3)
		4: return Pixel.OFF_WHITE
	return Pixel.MUSTARD


func _star(step: int) -> Array:
	if not _cache.has(step):
		_cache[step] = star_pixels(R_OUT, R_IN, step * TAU / STEPS)
	return _cache[step]


func _draw():
	# the shooting-star trail: fading dots back along its path
	for i in _trail.size():
		var k := float(i + 1) / float(_trail.size() + 1)
		var p: Vector2 = to_local(_trail[i]).round()
		draw_rect(Rect2(p + Vector2(-1, -1), Vector2(2, 2)), Color(Pixel.MUSTARD, 0.5 * k))
		if i % 3 == 0:
			draw_rect(Rect2(p, Vector2(1, 1)), Color(Pixel.WHITE, 0.7 * k))
	if hp > 0 and not _gone:
		if mode == "float":            # a soft pulse around a stepping stone
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			var r := 12.0 + pulse
			for i in 20:
				var p := (Vector2.from_angle(i * TAU / 20.0) * r).round()
				draw_rect(Rect2(p, Vector2(1, 1)), Color(Pixel.MUSTARD, 0.2 + 0.25 * pulse))
		for px in _star(_spin_step()):
			draw_rect(Rect2(px[0], Vector2(1, 1)), star_colour(px[1]))
		draw_rect(Rect2(-3, -4, 1, 1), Pixel.WHITE)          # a glint, top left
		draw_rect(Rect2(-4, -3, 1, 1), Pixel.WHITE)
	for b in _bits:
		var p: Vector2 = to_local(b[0]).round()
		draw_rect(Rect2(p, Vector2(1, 1)), Color(b[3], clampf(float(b[2]) * 4.0, 0.0, 1.0)))
