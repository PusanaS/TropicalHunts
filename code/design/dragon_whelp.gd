extends Node2D
# DRAGONFRUIT WHELP: Level 3's flying fruit (Volcano Heart). A little dragon made of a dragonfruit.
# It flies, so it has no collision body: place it in the air where it should hover (its origin is the
# middle of its body). Joins "enemies"; take_hit(damage, push) like the other fruit.
# PLACEHOLDER look, drawn in code in BOOM's palette plus the dragonfruit's magenta and green. Violeta
# designs the real one, BOOM animates it.
#
# Monster card
#   Moves:     hovers where it's placed, bobbing, drifting back and forth (patrol_range).
#   Notices:   the player within sight_range, any direction -> rises a little, its eyes flash.
#   Attack:    pulls back, wings flared, glowing red and shaking (the warning, windup_time), then swoops
#              down along a curve at where the player's chest was, skims past and pulls back up.
#   After:     climbs slowly back home = the punish window (air Q it).
#   Beaten by: any one hit. Air Q reaches it while it hovers; ground hits reach it low in the swoop.
#              Q during the swoop COUNTERS it (until the swoop has hit you), and the counter's chain
#              teleports you beside every other whelp on screen (Level 3 uses that to cross a chasm).
#   Touch:     hurts only during the swoop.
#   Drops:     one Dragonfruit juice.
#   Animations BOOM will need: HOVER (wing flap), NOTICE, WINDUP, SWOOP (wings tucked), CLIMB, DIE

enum State { HOVER, NOTICE, WINDUP, SWOOP, CLIMB, DEAD }

@export_group("Fruit look")
@export var fruit_name := "Dragonfruit"
@export var juice_color := Color(0.86, 0.2, 0.52)

@export_group("Stats")
@export var patrol_range := 70.0       # how far it drifts either side of where it's placed (0 = hovers on the spot)
@export var sight_range := 230.0       # notices the player this close, any direction
@export var windup_time := 0.5         # the warning before the swoop
@export var swoop_speed := 320.0
@export var respawn_time := 0.0        # comes back after this long, 0 = stays dead

const Pixel := preload("res://code/design/pixel_font.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const JuiceDrop := preload("res://code/design/juice_drop.gd")

# the dragonfruit: magenta skin, green-tipped scale flaps, white flesh with black seeds
const MAGENTA := Color(0.86, 0.2, 0.52)
const MAGENTA_DARK := Color(0.6, 0.1, 0.36)
const PINK := Color(0.97, 0.56, 0.74)
const WING := Color(0.42, 0.08, 0.28)
const SCALE_GREEN := Color("76964a")
const SCALE_TIP := Color("a4bf68")
const EYE := Pixel.MUSTARD
const HORN := Pixel.PALE

const NOTICE_TIME := 0.35
const NOTICE_RISE := 12.0              # it lifts up a little when it spots you
const PULL_BACK := Vector2(14, -6)     # the windup: drawn back (away from the player) and up
const CLIMB_TIME := 0.9
const RENOTICE := 0.6                  # after climbing home it waits this long before it can spot you again
const MAX_HEIGHT_GAP := 260.0          # ignores a player this far above or below
const HOVER_SPEED := 90.0
const FLAP_RATE := [6.0, 16.0]         # wing frames a second: hovering, winding up
const HURTBOX := Rect2(-10, -8, 20, 16)
const TOUCH_BOX := Rect2(-8, -6, 16, 12)
const CHEST := Vector2(0, -20)         # it swoops at the player's chest, not their feet
const HITSTOP_LIGHT := 0.05
const HITSTOP_HEAVY := 0.08
const SWOOP_SOUND := preload("res://sounds/sword/sword_swoosh_02.wav")   # the dive
const SWOOP_SOUND_DB := -10.0
const KILL_SOUND := preload("res://sounds/sword/sword_hit_flesh_01.wav") # the fruit minion's kill sound
const KILL_SOUND_DB := -3.0
const KILL_SOUND_SKIP := 0.025
const DAMAGE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const DAMAGE_SOUND_DB := 0.0
const DAMAGE_SOUND_SKIP := 0.12

# the drawn frames, built once and shared: name -> {"map": {Vector2i: Color}, "runs": [[y, x, length, colour]]}
static var _frames := {}

var state: State = State.HOVER
var state_time := 0.0
var facing := 1
var hp := 1
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _names: Array = []
var _last_player_state := -1
var _last_player_time := 0.0
var _hit_this_swing := false
var _t := 0.0
var _renotice := 0.0
var _landed := false                   # this swoop already hit the player: too late to counter it
var _from := Vector2.ZERO              # notice / windup / climb: where the move started
var _sw := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]   # the swoop's curve: start, bend, end
var _swoop_time := 0.8
var _flash := 0.0
var _fade := 1.0                       # fades in after a respawn
var _kill_sound := AudioStreamPlayer.new()
var _damage_sound := AudioStreamPlayer.new()
var _swoop_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	home = global_position
	_build_frames()
	_kill_sound.stream = KILL_SOUND
	_kill_sound.volume_db = KILL_SOUND_DB
	add_child(_kill_sound)
	var squelch := AudioStreamRandomizer.new()
	squelch.add_stream(-1, DAMAGE_SOUND)
	squelch.random_pitch = 1.3
	_damage_sound.stream = squelch
	_damage_sound.volume_db = DAMAGE_SOUND_DB
	add_child(_damage_sound)
	_swoop_sound.stream = SWOOP_SOUND
	_swoop_sound.volume_db = SWOOP_SOUND_DB
	add_child(_swoop_sound)
	_t = randf() * 10.0                # whelps placed together don't bob in step


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
		State.SWOOP:
			_start_swoop()


func _physics_process(delta: float):
	_t += delta
	state_time += delta
	_flash -= delta
	if state == State.DEAD:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		return
	_fade = minf(_fade + delta * 3.0, 1.0)
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	if player:
		_check_player_attack()
	if state == State.DEAD:
		return
	match state:
		State.HOVER:
			_state_hover(delta)
		State.NOTICE:
			_state_notice()
		State.WINDUP:
			_state_windup()
		State.SWOOP:
			_state_swoop()
		State.CLIMB:
			_state_climb()
	queue_redraw()


# ---------- senses ----------
func _sees_player() -> bool:
	if player == null:
		return false
	var d := player.global_position + CHEST - global_position
	return d.length() <= sight_range and absf(d.y) <= MAX_HEIGHT_GAP


func _face_player():
	if player and absf(player.global_position.x - global_position.x) > 2.0:
		facing = int(signf(player.global_position.x - global_position.x))


# ---------- states ----------
func _state_hover(delta: float):
	var target := home + Vector2(sin(_t * 0.8) * patrol_range, sin(_t * 3.0) * 3.0)
	var before := global_position.x
	global_position = global_position.move_toward(target, HOVER_SPEED * delta)
	if absf(global_position.x - before) > 0.05:
		facing = int(signf(global_position.x - before))
	if state_time >= _renotice and _sees_player():
		_set_state(State.NOTICE)


func _state_notice():
	_face_player()
	var k := clampf(state_time / NOTICE_TIME, 0.0, 1.0)
	global_position = _from + Vector2(0, -NOTICE_RISE * _ease_out(k))
	if state_time >= NOTICE_TIME:
		_set_state(State.WINDUP)


func _state_windup():
	_face_player()
	var k := clampf(state_time / (windup_time * 0.6), 0.0, 1.0)
	global_position = _from + Vector2(-facing * PULL_BACK.x, PULL_BACK.y) * _ease_out(k)
	if state_time >= windup_time:
		_set_state(State.SWOOP)


# the swoop is a curve that goes down through where the player's chest was and back up the far side
func _start_swoop():
	_landed = false
	var s := global_position
	var target := (player.global_position + CHEST) if player else s + Vector2(facing * 120.0, 80.0)
	var dir := signf(target.x - s.x)
	if dir == 0.0:
		dir = float(facing)
	facing = int(dir)
	var e := Vector2(target.x + dir * maxf(absf(target.x - s.x), 90.0), s.y)
	var bend := 2.0 * target - (s + e) / 2.0          # makes the curve pass right through the target halfway
	_sw = [s, bend, e]
	_swoop_time = clampf((s.distance_to(target) + target.distance_to(e)) / swoop_speed, 0.55, 1.2)
	_swoop_sound.play()


func _state_swoop():
	var u := clampf(state_time / _swoop_time, 0.0, 1.0)
	global_position = _bezier(_sw[0], _sw[1], _sw[2], u)
	if player and EnemyKit.hurt_player(player, Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size), global_position.x):
		_landed = true
	if u >= 1.0:
		_set_state(State.CLIMB)


func _state_climb():
	var k := clampf(state_time / CLIMB_TIME, 0.0, 1.0)
	global_position = _from.lerp(home, _ease_in_out(k))
	if absf(home.x - _from.x) > 2.0:
		facing = int(signf(home.x - _from.x))
	if k >= 1.0:
		_renotice = RENOTICE
		_set_state(State.HOVER)


func _bezier(a: Vector2, b: Vector2, c: Vector2, u: float) -> Vector2:
	return a.lerp(b, u).lerp(b.lerp(c, u), u)


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


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
	var hit := EnemyKit.player_attack_hitting(player, _names, Rect2(global_position + HURTBOX.position, HURTBOX.size))
	if hit.is_empty():
		return
	_hit_this_swing = true
	take_hit(hit["damage"], hit["push"])


func take_hit(damage: int, _push: Vector2):
	if state == State.DEAD:
		return
	hp -= damage
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	EnemyKit.hitstop(get_tree(), HITSTOP_HEAVY if damage >= 3 else HITSTOP_LIGHT)
	_flash = 0.08
	if hp <= 0:
		if player and _names[player.state] in FruitMinion.KILLING_SWINGS:
			_kill_sound.play(KILL_SOUND_SKIP)
		_die(true)


func is_alive() -> bool:
	return state != State.DEAD and hp > 0


# the player's counter (Q) catches it any time in the swoop, until the swoop has hit them
func is_counterable() -> bool:
	return state == State.SWOOP and not _landed


# killed by the counter: it splits in two along the counter's slash (a to b, in the world), the halves
# slide apart and drop. Without a line it splits straight across.
func cut_in_half(dir: int, a := Vector2.INF, b := Vector2.INF):
	if state == State.DEAD:
		return
	hp = 0
	EnemyKit.hitstop(get_tree(), HITSTOP_HEAVY)
	_spawn_halves(dir, a, b)
	_die(false)


func _die(burst: bool):
	_set_state(State.DEAD)
	hp = 0
	if burst:
		_splash()
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = fruit_name
	drop.color = juice_color
	drop.position = get_parent().to_local(global_position)
	get_parent().add_child.call_deferred(drop)
	queue_redraw()
	if respawn_time <= 0.0:              # stays dead: go once the sounds are done
		get_tree().create_timer(1.5).timeout.connect(queue_free)


func _respawn():
	global_position = home
	hp = 1
	_landed = false
	_fade = 0.0
	_renotice = RENOTICE
	_set_state(State.HOVER)


# a pop of magenta skin and white seeds
func _splash():
	for i in 2:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = 14 if i == 0 else 8
		p.lifetime = 0.6
		p.explosiveness = 1.0
		p.direction = Vector2.UP
		p.spread = 180.0
		p.initial_velocity_min = 60.0
		p.initial_velocity_max = 160.0
		p.gravity = Vector2(0, 500)
		p.scale_amount_min = 2.0
		p.scale_amount_max = 2.0
		p.color = juice_color if i == 0 else Pixel.OFF_WHITE
		p.position = get_parent().to_local(global_position)
		p.finished.connect(p.queue_free)
		get_parent().add_child.call_deferred(p)
		p.set_deferred("emitting", true)


# the frame it's showing right now, split by the line a-b into two pieces that slide apart and fall
func _spawn_halves(dir: int, a: Vector2, b: Vector2):
	var map: Dictionary = _frames[_frame_name()]["map"]
	var la := Vector2(-20, 0)
	var lb := Vector2(20, 0)
	if a != Vector2.INF and b != Vector2.INF and a != b:
		la = to_local(a)
		lb = to_local(b)
	var sides := [[], []]
	for key in map:
		var p: Vector2i = key
		var center := Vector2(facing * (p.x + 0.5), p.y + 0.5)    # where that pixel is, facing either way
		var side := 0 if (lb - la).cross(center - la) >= 0.0 else 1
		sides[side].append([center, map[key]])
	var along := (lb - la).normalized()
	if along.y < 0.0 or (along.y == 0.0 and along.x * dir < 0.0):
		along = -along                        # the top half slides off down the slope of the cut
	var top := 0 if _mean_y(sides[0]) < _mean_y(sides[1]) else 1
	for i in 2:
		if sides[i].is_empty():
			continue
		var c := Vector2.ZERO
		for px in sides[i]:
			c += px[0]
		c /= sides[i].size()
		var half := Half.new()
		for px in sides[i]:
			half.pixels.append([px[0] - c - Vector2(0.5, 0.5), px[1]])
		get_parent().add_child(half)
		half.global_position = to_global(c)
		var is_top: bool = i == top
		var slide := along * (16.0 if is_top else -3.0)
		var t := half.create_tween()
		t.tween_property(half, "position", half.position + slide, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(half, "rotation", signf(along.x) * (0.6 if is_top else -0.2), 0.3)
		t.tween_property(half, "position:y", half.position.y + slide.y + 70.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(half, "modulate:a", 0.0, 0.4)
		t.tween_callback(half.queue_free)


func _mean_y(list: Array) -> float:
	var y := 0.0
	for px in list:
		y += px[0].y
	return y / maxf(list.size(), 1.0)


# a piece of a cut whelp: just its pixels
class Half extends Node2D:
	var pixels := []                     # [offset, colour]

	func _draw():
		for px in pixels:
			draw_rect(Rect2(px[0], Vector2(1, 1)), px[1])


# ---------- drawing ----------
func _frame_name() -> String:
	if state == State.SWOOP:
		return "tuck"
	var rate: float = FLAP_RATE[1] if state == State.WINDUP else FLAP_RATE[0]
	return ["up", "mid", "down", "mid"][int(_t * rate) % 4]


func _draw():
	if state == State.DEAD:
		return
	var runs: Array = _frames[_frame_name()]["runs"]
	var offset := Vector2.ZERO
	var winding := state == State.WINDUP
	if winding:                          # the warning shake
		offset = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)).round()
	var tilt := 0.0
	if state == State.SWOOP:             # leans into the dive
		var u := clampf(state_time / _swoop_time, 0.0, 1.0)
		var v: Vector2 = (_sw[1] - _sw[0]).lerp(_sw[2] - _sw[1], u)
		tilt = atan2(v.y * facing, absf(v.x)) * 0.6
	var pulse := 0.5 + 0.5 * sin(_t * 30.0)
	if winding:                          # a red glow around it
		for i in 16:
			var p := (offset + Vector2.from_angle(i * TAU / 16.0) * (13.0 + pulse * 2.0)).round()
			draw_rect(Rect2(p, Vector2(2, 2)), Color(Pixel.RED if i % 2 == 0 else Pixel.ORANGE, 0.6 * _fade))
	var eyes_lit := state == State.NOTICE or winding
	draw_set_transform(offset, tilt, Vector2(facing, 1))
	for r in runs:
		var c: Color = r[3]
		if _flash > 0.0 and c != Pixel.INK:
			c = Pixel.WHITE
		elif c == EYE and eyes_lit:
			c = Pixel.WHITE
		elif winding and c != Pixel.INK:
			c = c.lerp(Pixel.ORANGE, 0.35 * pulse)
		draw_rect(Rect2(r[1], r[0], r[2], 1), Color(c, _fade))
	draw_set_transform(Vector2.ZERO)


# ---------- the placeholder art, built from shapes into pixels ----------
func _build_frames():
	if not _frames.is_empty():
		return
	# wings, behind the body: [polygon, bone tip] for each frame
	var wings := {
		"up": [[Vector2(-3, -3), Vector2(2, -3), Vector2(4, -12), Vector2(0, -9), Vector2(-4, -13), Vector2(-8, -8)], Vector2(-4, -12)],
		"mid": [[Vector2(-3, -3), Vector2(2, -3), Vector2(1, -8), Vector2(-4, -9), Vector2(-10, -7), Vector2(-7, -3)], Vector2(-9, -7)],
		"down": [[Vector2(-3, -2), Vector2(2, -2), Vector2(0, 4), Vector2(-4, 6), Vector2(-10, 4), Vector2(-7, 0)], Vector2(-9, 4)],
		"tuck": [[Vector2(-3, -3), Vector2(2, -3), Vector2(-3, -6), Vector2(-11, -5), Vector2(-7, -2)], Vector2(-10, -5)],
	}
	for frame_name in wings:
		var map := {}
		var wing: Array = wings[frame_name]
		fill_poly(map, PackedVector2Array(wing[0]), WING)
		draw_line_px(map, Vector2(0, -3), wing[1], MAGENTA_DARK)
		# the tail, ending in a green spade
		draw_line_px(map, Vector2(-6, 1), Vector2(-10, 3), MAGENTA)
		draw_line_px(map, Vector2(-6, 2), Vector2(-9, 3), MAGENTA_DARK)
		fill_poly(map, PackedVector2Array([Vector2(-10, 1), Vector2(-14, 3), Vector2(-10, 5)]), SCALE_GREEN)
		# the body: magenta, darker underneath, a highlight on top, white flesh and seeds on the belly
		var body := {}
		fill_ellipse(body, Vector2(0, 0), Vector2(6.5, 4.5), MAGENTA)
		for key in body:
			var p: Vector2i = key
			var c := MAGENTA
			if p.y >= 2:
				c = MAGENTA_DARK
			if p.y <= -3 and p.x <= 0:
				c = PINK
			if p.y >= 1 and p.x >= 0 and p.x <= 5:
				c = Pixel.OFF_WHITE
			map[p] = c
		for seed_px in [Vector2i(1, 2), Vector2i(3, 1), Vector2i(4, 3), Vector2i(2, 4)]:
			if map.get(seed_px, Color()) == Pixel.OFF_WHITE:
				map[seed_px] = Pixel.INK
		# scale flaps along the back, green-tipped
		for flap in [Vector2i(-4, -4), Vector2i(-1, -5), Vector2i(2, -5), Vector2i(-6, -1)]:
			map[flap] = SCALE_GREEN
			map[flap + Vector2i(-1, -1)] = SCALE_TIP
		# the head: snout, a horn, a glowing eye
		fill_ellipse(map, Vector2(7, -3), Vector2(3.2, 2.8), MAGENTA)
		for p in [Vector2i(10, -3), Vector2i(10, -2), Vector2i(11, -2)]:
			map[p] = MAGENTA
		map[Vector2i(11, -3)] = MAGENTA_DARK
		map[Vector2i(9, -1)] = MAGENTA_DARK
		for p in [Vector2i(6, -6), Vector2i(5, -7), Vector2i(4, -8)]:
			map[p] = HORN
		map[Vector2i(8, -4)] = EYE
		# little claws tucked under the belly
		map[Vector2i(-2, 5)] = MAGENTA_DARK
		map[Vector2i(3, 5)] = MAGENTA_DARK
		outline(map, Pixel.INK)
		_frames[frame_name] = {"map": map, "runs": runs(map)}


# ---------- pixel helpers (the Dragonfruit Drake uses them too) ----------
static func fill_ellipse(map: Dictionary, c: Vector2, r: Vector2, color: Color):
	for y in range(floori(c.y - r.y), ceili(c.y + r.y) + 1):
		for x in range(floori(c.x - r.x), ceili(c.x + r.x) + 1):
			var d := Vector2((x + 0.5 - c.x) / r.x, (y + 0.5 - c.y) / r.y)
			if d.length_squared() <= 1.0:
				map[Vector2i(x, y)] = color


static func fill_poly(map: Dictionary, poly: PackedVector2Array, color: Color):
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	for y in range(floori(box.position.y), ceili(box.end.y) + 1):
		for x in range(floori(box.position.x), ceili(box.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				map[Vector2i(x, y)] = color


static func draw_line_px(map: Dictionary, a: Vector2, b: Vector2, color: Color):
	var steps := maxi(int(ceilf(a.distance_to(b))), 1)
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps).floor()
		map[Vector2i(int(p.x), int(p.y))] = color


# a one-pixel outline around everything in the map
static func outline(map: Dictionary, color: Color):
	var edge := {}
	for key in map:
		var p: Vector2i = key
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not map.has(p + d):
				edge[p + d] = true
	for p in edge:
		map[p] = color


# the map as horizontal runs of one colour, cheap to draw: [y, x, length, colour]
static func runs(map: Dictionary) -> Array:
	var keys := map.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := []
	for key in keys:
		var p: Vector2i = key
		var c: Color = map[p]
		if not out.is_empty():
			var last: Array = out[-1]
			if last[0] == p.y and last[1] + last[2] == p.x and last[3] == c:
				last[2] += 1
				continue
		out.append([p.y, p.x, 1, c])
	return out
