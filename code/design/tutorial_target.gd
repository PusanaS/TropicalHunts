extends Node2D
# Tutorial training dummy. PLACEHOLDER look, drawn in code in BOOM's palette: a stitched sack on a post,
# or hanging from a rope (hanging = true) for the air attacks. It never dies and isn't solid.
# It takes the player's attacks the same way the fruit minion does (EnemyKit's stand-in hitboxes), plus
# take_hit() for the flash, the charged smash and W waves. Each hit wobbles it, sprays straw and tells
# the tutorial (code/design/tutorial.gd, group "tutorial") which move hit it.
# It's in "enemies" with an hp that drops on every hit, so the combo counter and the grass react to it.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const HIT_SOUNDS := [
	preload("res://sounds/sword/sword_hit_flesh_02.wav"),
	preload("res://sounds/sword/sword_hit_flesh_03.wav"),
	preload("res://sounds/sword/sword_hit_flesh_04.wav"),
]
const HIT_SOUND_DB := -8.0

@export var hanging := false
@export var rope := 160.0        # hanging: how far up the rope goes
@export var flashable := false   # only the FLASH station's dummies: the others don't set the flash off

# 15 x 44, the bottom row sits on the ground. o outline, s sack, S sack shade, r rope, y straw,
# R the red target, w wood, W wood shade
const ART := [
	".....y.y.y.....",
	".....ooooo.....",
	"....ossssSo....",
	"....ososoSo....",
	"....ossssSo....",
	"....osoooSo....",
	".....ooooo.....",
	"......rrr......",
	"...ooooooooo...",
	"..osssssssSSo..",
	"wwosssssssSSoww",
	"WWosssssssSSoWW",
	"..osssssssSSo..",
	"..osssRRRsSSo..",
	"..ossRsssRSSo..",
	"..ossRsRsRSSo..",
	"..ossRsssRSSo..",
	"..osssRRRsSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"..osssssssSSo..",
	"...ooooooooo...",
	"....y.yyy.y....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	".....owwWo.....",
	"...owwwwwwWo...",
	"...ooooooooo...",
]
const HANGING_ROWS := 28         # hanging: just the head and the sack (rows 0-27), no post
const PALETTE := {
	"o": Pixel.INK, "s": Pixel.OFF_WHITE, "S": Pixel.PALE, "r": Pixel.RUST, "y": Pixel.MUSTARD,
	"R": Pixel.RED, "w": Color("624021"), "W": Color("4d321a"),
}
const STIFF := 160.0             # standing: the post wobbles like a stiff spring
const DAMP := 6.0
const MAX_LEAN := 12.0
# hanging: a pendulum on its rope. A hit swings it well out and back, tilting along the rope.
const SWING_W := 3.0             # how fast it swings (radians a second: about one swing every 2 s)
const SWING_DAMP := 0.35         # how slowly it settles
const SWING_KICK := 0.8          # a light hit gives it about this much swing speed (more for heavier hits)
const WOOD := Color("624021")
const DUST := [Color(0.38, 0.25, 0.13), Color(0.49, 0.43, 0.43)]   # same as the gates' dust

# break_off(style): the last hit of a station can break the dummy. The pieces fly off spinning, bounce,
# lie there a moment, then blink out. Torn edges show fresh wood or straw, with an outline over them.
#   "cut"    one clean slanted cut under the sack, and the whole top flies off; the stump stays (SLASH)
#   "smash"  crushed flat for a moment, then it bursts: the post snaps low and jagged, and the head,
#            the sack and a chunk of post fly apart, with straw and a cloud of dust (SMASH)
#   "snap"   hanging only: the cord snaps just over its head, the dummy goes flying and the rest of the
#            cord springs back up, frayed (AIR SLASH)
const CUT_ROW := 31              # cut: the post is cut here, slanting with the slash
const SMASH_ROW := 37            # smash: the post snaps here...
const JAG := [0, 0, 0, 0, 0, -1, 1, -1, 1, 0, 0, 0, 0, 0, 0]   # ...this many rows lower, column by column
const CRUSH_TIME := 0.07         # smash: squashed flat this long before it bursts
const CRUSH_SCALE := Vector2(1.3, 0.55)
const SNAP_GAP := 10.0           # snap: the cord breaks this far above the head (that bit stays on it)
# the pieces of each style: [first row, last row + 1, launch (x away from the hit, up), spin]
const PIECES := {
	"cut": [[0, CUT_ROW + 2, Vector2(150, -300), 10.0]],
	"smash": [
		[0, 8, Vector2(90, -380), 16.0],                 # the head pops off, high
		[8, 28, Vector2(120, -170), 5.0],                # the sack: heavy, a low tumble
		[28, SMASH_ROW + 2, Vector2(210, -230), 22.0],   # a chunk of post, spinning fast
	],
	"snap": [[0, HANGING_ROWS, Vector2(170, -240), 9.0]],
}
const PIECE_GRAVITY := 900.0
const PIECE_BOUNCES := 2
const PIECE_REST := 0.8          # a piece lies on the ground this long, then blinks out
const BREAK_HITSTOP := {"cut": 0.12, "smash": 0.15, "snap": 0.12}
const BREAK_SHAKE := {"cut": Vector2(6, 0.25), "smash": Vector2(10, 0.3), "snap": Vector2(6, 0.25)}
const CUT_SOUND := preload("res://sounds/sword/sword_crash_01.wav")      # the boss finisher's final crash
const CUT_SOUND_DB := -8.0       # quieter than on the boss
const CUT_SOUND_SKIP := 0.03     # the crash swells in over 35ms; start partway in
const SMASH_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")   # the boss's impacts
const SMASH_SOUND_DB := -6.0
const SMASH_SOUND_SKIP := 0.02   # the file starts with 20ms of silence

var hp := 100000
var player: CharacterBody2D = null
var _names: Array = []
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _lean := 0.0                 # standing: how far the top leans (px)
var _lean_v := 0.0
var _swing := 0.0                # hanging: the rope's angle from straight down (radians, + = to the right)
var _swing_v := 0.0
var _flash := 0.0
var _spark := 1.0                # 0..1 through the hit spark
var _spark_dir := 1.0
var _straw := []                 # bits flying off: [pos (local), vel, life, colour]
var _sound := AudioStreamPlayer.new()
var _break_sound := AudioStreamPlayer.new()
var _style := ""                 # how it broke ("" = still whole)
var _dir := 1.0                  # the way the breaking hit went
var _crush := 0.0                # smash: time left squashed flat
var _slash := 1.0                # cut: 0..1 through the slash streak along the cut
var _cord := 1.0                 # snap: how far the snapped cord reaches (1 = its full length); it recoils
var _cord_v := 0.0
var _floor_y := 0.0              # where the pieces land (local); hanging dummies look for the floor below
var _pieces := []                # each: {pivot (in the art), half, pos (local), vel, rot, spin, t, bounces, rest, rest_rot}


func _ready():
	add_to_group("enemies")
	var r := AudioStreamRandomizer.new()
	for s in HIT_SOUNDS:
		r.add_stream(-1, s)
	r.random_pitch = 1.15
	_sound.stream = r
	_sound.volume_db = HIT_SOUND_DB
	_sound.max_polyphony = 3
	add_child(_sound)
	add_child(_break_sound)


# player.gd's flash only goes for enemies that are alive. So a dummy that isn't flashable plays dead
# while the player gallops, and galloping at it before the FLASH station doesn't flash it. (The only
# other thing that asks is the charged smash, which never happens mid-gallop.) A broken one is just dead.
func is_alive() -> bool:
	if _style != "":
		return false
	return flashable or player == null or _names[player.state] != "GALLOP"


func _rows() -> int:
	return HANGING_ROWS if hanging else ART.size()


# ---------- where things are ----------
# hanging: where the rope is tied, high up (it stays put)
func _anchor() -> Vector2:
	return Vector2(0.0, -HANGING_ROWS - rope)


# hanging: "down" along the rope
func _down() -> Vector2:
	return Vector2(sin(_swing), cos(_swing))


# a point down the middle of the dummy, `row` rows from the top of its art, in local space
func _body_point(row: float) -> Vector2:
	if hanging:
		return _anchor() + _down() * (rope + row)
	var rows := float(ART.size())
	return Vector2(roundf(_lean * (rows - row) / rows), row - rows)


# where the player can hit it, in the world
func _hurtbox() -> Rect2:
	var h := float(_rows())
	var center := global_position + _body_point(h / 2.0)
	return Rect2(center - Vector2(7.0, h / 2.0), Vector2(14.0, h))


# ---------- every frame ----------
func _physics_process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	if _style == "":
		_check_player_attack()
	if hanging:          # (the snapped cord keeps swinging too)
		_swing_v += (-SWING_W * SWING_W * sin(_swing) - SWING_DAMP * _swing_v) * delta
		_swing = clampf(_swing + _swing_v * delta, -1.2, 1.2)
	else:
		_lean_v += (-STIFF * _lean - DAMP * _lean_v) * delta
		_lean = clampf(_lean + _lean_v * delta, -MAX_LEAN, MAX_LEAN)
	if _style == "snap":  # the cord recoils up, then bounces back down to hang
		_cord_v += (-200.0 * (_cord - 1.0) - 9.0 * _cord_v) * delta
		_cord += _cord_v * delta
	_flash -= delta
	_spark = minf(_spark + delta / 0.14, 1.0)
	_slash = minf(_slash + delta / 0.18, 1.0)
	if _crush > 0.0:
		_crush -= delta
		if _crush <= 0.0:
			_burst()
	elif _style != "":
		for piece in _pieces:
			_update_piece(piece, delta)
	for s in _straw:
		s[0] += s[1] * delta
		s[1].y += 420.0 * delta
		s[2] -= delta
	_straw = _straw.filter(func(s): return s[2] > 0.0)
	queue_redraw()


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
	take_hit(hit["damage"], hit["push"])


func take_hit(damage: int, push: Vector2):
	if _style != "":
		return
	hp -= maxi(damage, 1)
	var dir := signf(push.x)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	if hanging:
		_swing_v += dir * SWING_KICK * (1.0 + 0.3 * damage)
	else:
		_lean_v += dir * (90.0 + 40.0 * damage)
	_flash = 0.07
	_spark = 0.0
	_spark_dir = dir
	var mid := _body_point(15.0)         # the red target
	for k in 6 + 2 * damage:
		var v := Vector2(dir * randf_range(30, 140), randf_range(-170, -40))
		_straw.append([mid + Vector2(randf_range(-4, 4), randf_range(-6, 6)), v, randf_range(0.35, 0.6), Pixel.MUSTARD])
	_sound.play()
	var move := ""
	if player:
		move = "FLASH" if player.flashing else _names[player.state]
	get_tree().call_group("tutorial", "target_hit", self, move)    # the station's last hit may break it (break_off)
	EnemyKit.hitstop(get_tree(), BREAK_HITSTOP[_style] if _style != "" else (0.06 if damage >= 3 else 0.03))


# ---------- breaking ----------
# the station's last hit: style "cut", "smash" or "snap" (see the top). The pieces go the way it was hit.
func break_off(style: String):
	if _style != "" or not PIECES.has(style) or hanging != (style == "snap"):
		return
	_style = style
	_dir = _spark_dir
	_lean = 0.0
	_lean_v = 0.0
	_flash = 0.07
	_pieces.clear()
	for spec in PIECES[style]:
		_pieces.append(_make_piece(spec, _pieces.size()))
	var shake: Vector2 = BREAK_SHAKE[style]
	if player:
		player._shake(shake.x, shake.y)
	match style:
		"cut":
			_slash = 0.0
			_play(CUT_SOUND, CUT_SOUND_DB, CUT_SOUND_SKIP)
			_spray(22, _pieces[0]["pos"], Vector2(-40, 220), Vector2(-260, -40), Pixel.MUSTARD)    # straw out of the sack
			_spray(8, Vector2(0.0, CUT_ROW - ART.size()), Vector2(20, 160), Vector2(-200, -60), WOOD)    # splinters
			_launch()
		"smash":
			_crush = CRUSH_TIME   # squashed flat first; _burst() sends the pieces off
			_play(SMASH_SOUND, SMASH_SOUND_DB, SMASH_SOUND_SKIP)
		"snap":
			_floor_y = _find_floor()
			# the dummy starts from exactly where it hangs, tilted along the rope
			var piece: Dictionary = _pieces[0]
			var pivot: Vector2 = piece["pivot"]
			piece["pos"] = _body_point(0.0) + (pivot - Vector2(7.0, 0.0)).rotated(-_swing)
			piece["rot"] = -_swing
			_cord = 1.0
			_cord_v = -9.0        # the cut cord whips back up
			_play(CUT_SOUND, CUT_SOUND_DB, CUT_SOUND_SKIP)
			_spray(18, _body_point(14.0), Vector2(-40, 200), Vector2(-240, -40), Pixel.MUSTARD)    # straw
			_spray(6, _body_point(-SNAP_GAP), Vector2(-60, 60), Vector2(-120, 20), Pixel.RUST)     # cord fibres
			_launch()
			# the swing it had carries into the throw
			piece["vel"] += Vector2(cos(_swing), -sin(_swing)) * _swing_v * rope * 0.5


func _play(stream: AudioStream, db: float, skip: float):
	_break_sound.stream = stream
	_break_sound.volume_db = db
	_break_sound.play(skip)


# the floor under a hanging dummy (local y), so its pieces land on it
func _find_floor() -> float:
	var from := global_position
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 1000))
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 1000.0
	var at: Vector2 = hit["position"]
	return to_local(at).y


# smash: after the crush, everything bursts out at once
func _burst():
	var snap := Vector2(0.0, SMASH_ROW - ART.size())
	_spray(32, Vector2(0.0, -24.0), Vector2(-160, 200), Vector2(-280, -40), Pixel.MUSTARD)   # straw everywhere
	_spray(10, snap, Vector2(20, 200), Vector2(-220, -50), WOOD)                            # splinters
	for k in 14:          # a dust cloud rolling out along the ground, both ways
		var side := 1.0 if k % 2 == 0 else -1.0
		_straw.append([Vector2(side * randf_range(2, 8), -1), Vector2(side * randf_range(50, 170), randf_range(-50, -10)),
			randf_range(0.3, 0.55), DUST[k % 2]])
	_launch()


func _launch():
	for i in _pieces.size():
		var spec: Array = PIECES[_style][i]
		var launch: Vector2 = spec[2]
		var piece: Dictionary = _pieces[i]
		piece["vel"] = Vector2(_dir * launch.x * randf_range(0.9, 1.1), launch.y * randf_range(0.9, 1.1))
		piece["spin"] = _dir * float(spec[3])


func _spray(count: int, at: Vector2, vx: Vector2, vy: Vector2, color: Color):
	for k in count:
		var v := Vector2(_dir * randf_range(vx.x, vx.y), randf_range(vy.x, vy.y))
		var c := color if color != WOOD or k % 2 == 0 else Pixel.MUSTARD
		_straw.append([at + Vector2(randf_range(-5, 5), randf_range(-8, 8)), v, randf_range(0.4, 0.85), c])


# a piece's pivot and size come from the pixels it's made of
func _make_piece(spec: Array, index: int) -> Dictionary:
	var lo := Vector2(99, 99)
	var hi := Vector2(-1, -1)
	for row in range(spec[0], spec[1]):
		var line: String = ART[row]
		for col in line.length():
			if line[col] != "." and _piece_of(col, row) == index:
				lo = lo.min(Vector2(col, row))
				hi = hi.max(Vector2(col + 1, row + 1))
	var pivot := (lo + hi) / 2.0
	return {"index": index, "r0": spec[0], "r1": spec[1], "pivot": pivot, "half": (hi - lo) / 2.0,
		"pos": Vector2(pivot.x - 7.0, pivot.y - ART.size()), "vel": Vector2.ZERO, "rot": 0.0, "spin": 0.0,
		"t": 0.0, "bounces": 0, "rest": -1.0, "rest_rot": 0.0}


# which piece a pixel of the art ends up on: an index into _pieces, -1 for the stump, or -2 if the
# pixel isn't part of this dummy at all (a hanging one has no post)
func _piece_of(col: int, row: int) -> int:
	if hanging:
		return 0 if row < HANGING_ROWS else -2
	if _style == "cut":
		return 0 if row < CUT_ROW + roundi((col - 7) * 0.5 * _dir) else -1
	if row >= SMASH_ROW + JAG[col]:
		return -1
	return 0 if row < 8 else (1 if row < 28 else 2)


func _update_piece(piece: Dictionary, delta: float):
	piece["t"] += delta
	var pos: Vector2 = piece["pos"]
	var rest: float = piece["rest"]
	if rest >= 0.0:       # lying on the ground: roll onto a flat side, then wait to blink out
		piece["rest"] = rest + delta
		piece["rot"] = move_toward(piece["rot"], piece["rest_rot"], 12.0 * delta)
		piece["pos"] = Vector2(pos.x, _floor_y - _half_height(piece))
		return
	var vel: Vector2 = piece["vel"]
	vel.y += PIECE_GRAVITY * delta
	pos += vel * delta
	piece["rot"] += piece["spin"] * delta
	var half_size: Vector2 = piece["half"]
	if piece["t"] < 0.5 and piece["index"] == (1 if _style == "smash" else 0) and randf() < 0.6:
		# straw trailing out of the sack as it flies
		var tail := pos + Vector2(0, half_size.y).rotated(piece["rot"])
		_straw.append([tail, Vector2(randf_range(-30, 30), randf_range(-40, 10)), randf_range(0.3, 0.5), Pixel.MUSTARD])
	var half := _half_height(piece)
	if pos.y + half >= _floor_y and vel.y > 0.0:      # hits the floor
		pos.y = _floor_y - half
		for k in 4:
			_straw.append([pos + Vector2(randf_range(-6, 6), half), Vector2(randf_range(-60, 60), randf_range(-90, -30)),
				randf_range(0.25, 0.4), Pixel.MUSTARD if k % 2 == 0 else DUST[1]])
		if piece["bounces"] < PIECE_BOUNCES:
			piece["bounces"] += 1
			vel = Vector2(vel.x * 0.55, -vel.y * 0.35)
			piece["spin"] *= 0.5
		else:
			piece["rest"] = 0.0
			piece["rest_rot"] = snappedf(piece["rot"], PI / 2.0)
	piece["pos"] = pos
	piece["vel"] = vel


# how far a spinning piece reaches below its pivot
func _half_height(piece: Dictionary) -> float:
	var half: Vector2 = piece["half"]
	var rot: float = piece["rot"]
	return absf(cos(rot)) * half.y + absf(sin(rot)) * half.x


# a torn edge: the pixel next to this one (dr = -1 above, 1 below) is there but on another piece
func _torn(col: int, row: int, dr: int) -> bool:
	var r := row + dr
	if r < 0 or r >= ART.size():
		return false
	var line: String = ART[r]
	var other := _piece_of(col, r)
	return line[col] != "." and other != -2 and other != _piece_of(col, row)


# ---------- drawing ----------
func _draw():
	if _style == "":
		_draw_whole()
	else:
		_draw_broken()
	# hit spark: a quick star of rays
	if _spark < 1.0 and _style == "":
		var center := _body_point(15.0) - Vector2(_spark_dir * 6.0, 0.0)
		var e := 1.0 - pow(1.0 - _spark, 3.0)
		for i in 8:
			var d := Vector2.from_angle(i * TAU / 8.0)
			for k in 3:
				var p := (center + d * (3.0 + e * 9.0 + k * 2.0)).round()
				draw_rect(Rect2(p, Vector2(1, 1)), Color(Pixel.WHITE if i % 2 == 0 else Pixel.MUSTARD, 1.0 - _spark))
	for s in _straw:
		var p: Vector2 = s[0]
		var horizontal := absf(s[1].x) > absf(s[1].y)
		draw_rect(Rect2(p.round(), Vector2(2, 1) if horizontal else Vector2(1, 2)), Color(s[3], clampf(float(s[2]) * 5.0, 0.0, 1.0)))


# a rope: one pixel at a time from a to b
func _draw_rope(a: Vector2, b: Vector2):
	var steps := maxi(int(a.distance_to(b)), 1)
	for k in steps + 1:
		draw_rect(Rect2(a.lerp(b, float(k) / steps).round(), Vector2(1, 1)), Pixel.RUST)


# one row of the art, as runs of the same colour, with its left edge at x and its top at y
func _draw_row(row: int, x: float, y: float, white: bool):
	var line: String = ART[row]
	var col := 0
	while col < line.length():
		var ch := line[col]
		var run := 1
		while col + run < line.length() and line[col + run] == ch:
			run += 1
		if ch != ".":
			var c: Color = PALETTE[ch]
			if white and ch != "o":
				c = Pixel.WHITE
			draw_rect(Rect2(x + col, y, run, 1), c)
		col += run


func _draw_whole():
	var white := _flash > 0.0
	if hanging:        # on its rope, tilted along it
		var top := _body_point(0.0)
		_draw_rope(_anchor(), top)
		draw_set_transform(top.round(), -_swing)
		for row in HANGING_ROWS:
			_draw_row(row, -7.0, row, white)
		draw_set_transform(Vector2.ZERO)
		return
	var rows := ART.size()
	for row in rows:                      # standing: each row leans a bit more the higher it is
		var height := float(rows - row)
		_draw_row(row, -7.0 + roundf(_lean * height / rows), -height, white)


# one pixel of the broken dummy, at `at` in whatever transform is set. Torn edges show fresh wood or
# straw, with an outline just past them.
func _draw_bit(col: int, row: int, at: Vector2, white: bool):
	var line: String = ART[row]
	var ch := line[col]
	var c: Color = PALETTE[ch]
	if ch != "o":
		for dr in [-1, 1]:
			if _torn(col, row, dr):
				c = Pixel.MUSTARD
				draw_rect(Rect2(at + Vector2(0, dr), Vector2(1, 1)), Pixel.INK)
	draw_rect(Rect2(at, Vector2(1, 1)), Pixel.WHITE if white and ch != "o" else c)


func _draw_broken():
	var n := ART.size()
	var white := _flash > 0.0
	if _style == "snap":                  # what's left of the cord: recoiling, then hanging frayed
		var end := _anchor() + _down() * maxf(rope - SNAP_GAP, 0.0) * clampf(_cord, 0.2, 1.3)
		_draw_rope(_anchor(), end)
		draw_rect(Rect2(end.round() + Vector2(-1, 1), Vector2(1, 1)), Pixel.RUST)
		draw_rect(Rect2(end.round() + Vector2(1, 1), Vector2(1, 1)), Pixel.MUSTARD)
	else:
		for row in n:                     # the stump, where it stands
			var line: String = ART[row]
			for col in line.length():
				if line[col] != "." and _piece_of(col, row) == -1:
					_draw_bit(col, row, Vector2(col - 7, row - n), white)

	if _crush > 0.0:                      # smash: everything above the snap, squashed flat onto the stump
		var base := Vector2(0.0, SMASH_ROW - n)
		draw_set_transform(base, 0.0, CRUSH_SCALE)
		for row in n:
			var line: String = ART[row]
			for col in line.length():
				if line[col] != "." and _piece_of(col, row) >= 0:
					_draw_bit(col, row, Vector2(col - 7, row - SMASH_ROW), white)
		draw_set_transform(Vector2.ZERO)
		return

	for piece in _pieces:
		var rest: float = piece["rest"]
		if rest > PIECE_REST + 0.5 or (rest > PIECE_REST and int(rest / 0.06) % 2 == 1):
			continue                      # blinking out
		var pivot: Vector2 = piece["pivot"]
		var pos: Vector2 = piece["pos"]
		draw_set_transform(pos.round(), piece["rot"])
		if _style == "snap":              # the bit of cord still tied to its head
			_draw_rope(Vector2(7.0, 0.0) - pivot, Vector2(7.0, -SNAP_GAP) - pivot)
		for row in range(piece["r0"], piece["r1"]):
			var line: String = ART[row]
			for col in line.length():
				if line[col] != "." and _piece_of(col, row) == piece["index"]:
					_draw_bit(col, row, Vector2(col, row) - pivot, white)
		draw_set_transform(Vector2.ZERO)

	if _slash < 1.0:      # cut: the slash itself, a streak along the cut that stretches out and fades
		var e := 1.0 - pow(1.0 - _slash, 3.0)
		var half := 6.0 + e * 20.0
		var center := Vector2(0.0, CUT_ROW - n)
		var x := -half
		while x <= half:
			var p := (center + Vector2(x, x * 0.5 * _dir)).round()
			var core := absf(x) < half * 0.6
			draw_rect(Rect2(p, Vector2(1, 2 if core else 1)), Color(Pixel.WHITE if core else Pixel.MUSTARD, 1.0 - _slash))
			x += 1.0
