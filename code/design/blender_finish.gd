extends Node2D
# THE BLENDER (level 1's ending, Morgan's idea, 2026-10-08): when the Pina Colada boss is beaten, a retro blender
# drops in where it fell. All the juice lying about the fight (every drop, chunk and puddle of the boss's
# juice_spray.gd effects) lifts off the floor one by one and arcs into the jar, which fills up as they land. The
# lid slams on, it whirs (the liquid spins into a whirlpool and bubbles, the jar shakes), then the jar tips and
# pours into a hurricane glass, the liquid staying level and running out of the spout. The glass gets a
# pineapple wedge and an umbrella with a sparkle. Then it emits `done` (bar_intro.gd carries on from there).
# The liquid is one colour (a pineapple cream) with a live surface: little springs across it ripple when drops
# land, slosh, and dip into a whirlpool while it blends. It's drawn as the jar's inside cut by that surface
# (Geometry2D), so it fills the tapered jar properly and stays level when the jar tips; its height is found from
# how much is in it.
# Place it on the floor where the boss fell (origin = the floor under it). `side`: which side the glass stands
# on (1 right, -1 left). PLACEHOLDER art drawn in code, in BOOM's flat-colour style.

signal done

@export var side := 1.0

const IMPACT_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const IMPACT_SKIP := 0.02
const MOTOR_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")   # pitched up: the motor
const PLIP_SOUND := preload("res://sounds/WATER_FOOTSTEP_freesound_community-splash-6213.mp3")
const DING_SOUND := preload("res://sounds/sword/sword_hit_metal_01.wav")   # pitched way up: a little "ting"
const Pixel := preload("res://code/design/pixel_font.gd")

const DROP_TIME := 0.35
const COLLECT_OVER := 1.3                         # the juice lifts off over this long (then flies 0.45-0.7s)
const COLLECT_RANGE := 600.0                      # juice this far away is collected
const MIN_DROPS := 30                             # (if there's less lying about, it makes up the rest)
const FILL_MAX := 3.2                             # the fill never waits longer than this
const LID_TIME := 0.2
const BLEND_TIME := 1.3
const TIP_TIME := 0.45
const POUR_TIME := 1.2
const GARNISH_TIME := 0.8
const HOLD_TIME := 0.6
const GRAVITY := 700.0
const COLUMNS := 16                               # the liquid's surface springs, across the jar
const WAVE := 900.0
const TENSION := 60.0
const DAMP := 5.0
const POUR_TILT := 112.0                          # degrees
const GLASS_AT := 40.0                            # the glass's middle, this far to the `side`

# the shapes (origin: the floor under the base; drawn for side = 1, mirrored for -1)
const BASE := [Vector2(-18, 0), Vector2(18, 0), Vector2(15, -17), Vector2(-15, -17)]
const JAR_IN := [Vector2(-9, -22), Vector2(9, -22), Vector2(13, -64), Vector2(-13, -64)]   # the inside
const JAR_OUT := [Vector2(-11, -20), Vector2(11, -20), Vector2(15, -65), Vector2(-15, -65)]
const PIVOT := Vector2(15, -63)                   # the spout corner it tips about
const GLASS_IN := [Vector2(-5, -27), Vector2(5, -27), Vector2(6, -21), Vector2(2, -15), Vector2(3, -11), Vector2(1, -8),
	Vector2(-1, -8), Vector2(-3, -11), Vector2(-2, -15), Vector2(-6, -21)]                  # a hurricane glass's bowl

const CREAM := Color("efe6d4")
const CREAM_SHADE := Color("c9bba2")
const CHROME := Color("b9c2c8")
const CHROME_DARK := Color("7d868c")
const DIAL := Color("c43a2a")
const LID := Color("3a3442")
const LID_LIGHT := Color("5a5266")
const GLASS_TINT := Color(0.78, 0.9, 0.96, 0.22)
const GLASS_EDGE := Color(0.88, 0.95, 0.98, 0.95)
const SHINE := Color(1, 1, 1, 0.45)
const JUICE := Color("f2d27a")                    # before it's blended: a touch more pineapple
const CREAMY := Color("f5e2a8")                   # blended: the pina colada
const JUICE_LIGHT := Color("fff3cf")
const JUICE_DARK := Color("d9b65e")
const UMBRELLA := Color("e86a9a")
const LEAF := Color("76964a")

enum Phase { DROP, FILL, LID, BLEND, TIP, POUR, GARNISH, HOLD, DONE }

var _phase := Phase.DROP
var _pt := 0.0
var _t := 0.0
var _y := -150.0                                  # the blender falling in
var _fill := 0.0                                  # 0..1 of the jar
var _mixed := 0.0
var _glass := 0.0                                 # 0..1 of the glass
var _tilt := 0.0
var _expected := 0                                # drops on their way
var _arrived := 0
var _own_drops: Array = []                        # the ones it makes up itself: [pos, vel, colour, life]
var _h := PackedFloat32Array()                    # the surface springs
var _v := PackedFloat32Array()
var _bubbles: Array = []                          # [x, y, age] (in the jar's frame)
var _bits: Array = []                             # splashes and sparkles: [pos, vel, colour, life]
var _plip_in := 0.0
var _motor := AudioStreamPlayer.new()
var _thud := AudioStreamPlayer.new()
var _plip := AudioStreamPlayer.new()
var _ding := AudioStreamPlayer.new()


func _ready():
	z_index = 5
	_h.resize(COLUMNS)
	_v.resize(COLUMNS)
	for s: Array in [[_motor, MOTOR_SOUND, -4.0], [_thud, IMPACT_SOUND, -6.0], [_plip, PLIP_SOUND, -14.0], [_ding, DING_SOUND, -8.0]]:
		var p: AudioStreamPlayer = s[0]
		p.stream = s[1]
		p.volume_db = s[2]
		add_child(p)
	_motor.pitch_scale = 2.4
	_ding.pitch_scale = 2.2
	_plip.max_polyphony = 3


func _phase_to(p: Phase):
	_phase = p
	_pt = 0.0


# the jar's mouth (global): where the juice is aimed
func _mouth() -> Vector2:
	return global_position + Vector2(0, -64)


func _process(delta: float):
	_t += delta
	_pt += delta
	_plip_in -= delta
	match _phase:
		Phase.DROP:
			var k := minf(_pt / DROP_TIME, 1.0)
			_y = -150.0 * (1.0 - k * k)
			if k >= 1.0:
				_y = 0.0
				_thud.play(IMPACT_SKIP)
				for i in 10:
					_bits.append([Vector2(randf_range(-18, 18), -2), Vector2(randf_range(-60, 60), -randf_range(20, 70)), Color("8a7a6a"), 0.5])
				_start_collecting()
				_phase_to(Phase.FILL)
		Phase.FILL:
			if (_arrived >= _expected and _own_drops.is_empty()) or _pt >= FILL_MAX:
				_phase_to(Phase.LID)
		Phase.LID:
			if _pt >= LID_TIME:
				_motor.play()
				_phase_to(Phase.BLEND)
		Phase.BLEND:
			_mixed = minf(_pt / BLEND_TIME, 1.0)
			if randf() < delta * 40.0:                        # bubbles churned up from the blades
				_bubbles.append([randf_range(-8.0, 8.0), -24.0, 0.0])
			if randf() < delta * 20.0:
				_v[randi() % COLUMNS] += randf_range(-80.0, 80.0)
			if _pt >= BLEND_TIME:
				_motor.stop()
				_phase_to(Phase.TIP)
		Phase.TIP:
			_tilt = side * deg_to_rad(POUR_TILT) * _ease(minf(_pt / TIP_TIME, 1.0))
			if _pt >= TIP_TIME:
				_phase_to(Phase.POUR)
		Phase.POUR:
			var k := minf(_pt / POUR_TIME, 1.0)
			_glass = k
			_fill = 1.0 - k * 0.85
			if randf() < delta * 30.0:
				_bits.append([Vector2(side * GLASS_AT + randf_range(-3, 3), -27), Vector2(randf_range(-30, 30), -randf_range(20, 50)), CREAMY, 0.3])
			if _plip_in <= 0.0:
				_plip_in = 0.12
				_plip.pitch_scale = randf_range(1.6, 2.0)
				_plip.play()
			if k >= 1.0:
				_phase_to(Phase.GARNISH)
		Phase.GARNISH:
			_tilt = side * deg_to_rad(POUR_TILT) * (1.0 - _ease(minf(_pt / 0.35, 1.0)))
			if _pt >= 0.35 and _pt - delta < 0.35:
				_ding.play()
				for i in 12:
					_bits.append([Vector2(side * GLASS_AT, -35), Vector2.from_angle(TAU * i / 12.0) * randf_range(40, 90), Pixel.MUSTARD if i % 2 else Pixel.WHITE, 0.45])
			if _pt >= GARNISH_TIME:
				_phase_to(Phase.HOLD)
		Phase.HOLD:
			if _pt >= HOLD_TIME:
				_phase_to(Phase.DONE)
				done.emit()
	_update_liquid(delta)
	_update_own_drops(delta)
	for b: Array in _bits:
		b[1].y += GRAVITY * 0.6 * delta
		b[0] += b[1] * delta
		b[3] -= delta
	_bits = _bits.filter(func(b): return b[3] > 0.0)
	queue_redraw()


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ---------- the juice coming in ----------
# all the juice lying about the fight is called in; if there's too little, it makes up the rest itself
func _start_collecting():
	for js in get_tree().get_nodes_in_group("juice_spray"):
		if js is Node2D and js.global_position.distance_to(global_position) < COLLECT_RANGE and js.has_method("collect"):
			_expected += js.collect(_mouth(), COLLECT_OVER, self)
	for i in maxi(MIN_DROPS - _expected, 0):
		var from := Vector2(-70.0 * side, -46.0) + Vector2(randf_range(-14, 14), randf_range(-12, 12))
		var to := Vector2(randf_range(-6, 6), -64.0)
		var t := randf_range(0.45, 0.7)
		var vel := Vector2((to.x - from.x) / t, (to.y - from.y - 0.5 * GRAVITY * t * t) / t)
		_own_drops.append([from, vel, [JUICE, CREAMY, Pixel.ORANGE][i % 3], t + randf_range(0.0, COLLECT_OVER)])


# a drop lands in the jar (juice_spray.gd calls this too): it fills a little and ripples the surface
func take_drop(col: Color):
	_arrived += 1
	var total := maxi(_expected + (MIN_DROPS - mini(_expected, MIN_DROPS)), 1)
	_fill = minf(float(_arrived) / float(total), 1.0)
	var c := randi() % COLUMNS
	_v[c] += 120.0
	if randi() % 3 == 0:
		_bits.append([Vector2(randf_range(-6, 6), _surface_y_local() - 1.0), Vector2(randf_range(-30, 30), -randf_range(30, 70)), col, 0.3])
	if _plip_in <= 0.0:
		_plip_in = 0.07
		_plip.pitch_scale = randf_range(1.4, 1.9)
		_plip.play()


func _update_own_drops(delta: float):
	for d: Array in _own_drops:
		d[3] -= delta
		if d[3] < 0.7:                                # (its turn: it flies)
			d[1].y += GRAVITY * delta
			d[0] += d[1] * delta
		if d[3] <= 0.0:
			_expected += 1
			take_drop(d[2])
	_own_drops = _own_drops.filter(func(d): return d[3] > 0.0)


# ---------- the liquid ----------
func _update_liquid(delta: float):
	for c in COLUMNS:
		var left: float = _h[c - 1] if c > 0 else _h[c]
		var right: float = _h[c + 1] if c < COLUMNS - 1 else _h[c]
		_v[c] += ((left + right - 2.0 * _h[c]) * WAVE - _h[c] * TENSION - _v[c] * DAMP) * delta
	for c in COLUMNS:
		_h[c] = clampf(_h[c] + _v[c] * delta, -5.0, 5.0)
	for b: Array in _bubbles:
		b[2] += delta
		b[1] -= 40.0 * delta
		b[0] += sin(b[2] * 12.0) * 0.4
	_bubbles = _bubbles.filter(func(b): return b[2] < 0.9)


# the jar's frame: points of the upright jar to where they are now (it tips about the spout corner)
func _jar_xf(p: Vector2, at: Vector2) -> Vector2:
	var q := Vector2(p.x * side, p.y)
	var pivot := Vector2(PIVOT.x * side, PIVOT.y)
	return at + pivot + (q - pivot).rotated(_tilt)


# the surface's height at x (local to `at`): a level, the springs' ripples, and the whirlpool while it blends
func _surface(x: float, level: float, jar_x: float, whirl: float) -> float:
	var col := clampi(int((x - jar_x + 13.0) / 26.0 * COLUMNS), 0, COLUMNS - 1)
	var u := clampf((x - jar_x) / 13.0, -1.0, 1.0)
	return level + _h[col] * (1.0 - absf(_tilt) / PI) + whirl * (1.0 - u * u) - whirl * 0.4


# the liquid: the inside of a shape, below a surface at `level` (which is found so that `amount` of its area is
# filled). Returns the polygons to draw and the level found.
func _liquid(inside: PackedVector2Array, amount: float, jar_x: float, whirl: float) -> Array:
	if amount <= 0.001:
		return [[], 0.0]
	var full := _area([inside])
	var lo := INF
	var hi := -INF
	for p in inside:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var a := lo - 8.0
	var b := hi
	var polys: Array = []
	for i in 14:                                       # find the level that holds this much
		var mid := (a + b) / 2.0
		polys = Geometry2D.intersect_polygons(inside, _below(mid, jar_x, whirl, inside))
		if _area(polys) > amount * full:
			a = mid
		else:
			b = mid
	return [Geometry2D.intersect_polygons(inside, _below((a + b) / 2.0, jar_x, whirl, inside)), (a + b) / 2.0]


func _below(level: float, jar_x: float, whirl: float, inside: PackedVector2Array) -> PackedVector2Array:
	var x0 := INF
	var x1 := -INF
	for p in inside:
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
	var out := PackedVector2Array()
	var x := x0 - 4.0
	while x <= x1 + 4.0:
		out.append(Vector2(x, _surface(x, level, jar_x, whirl)))
		x += 2.0
	out.append(Vector2(x1 + 4.0, 200))
	out.append(Vector2(x0 - 4.0, 200))
	return out


func _area(polys: Array) -> float:
	var total := 0.0
	for poly: PackedVector2Array in polys:
		var s := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			s += p.x * q.y - q.x * p.y
		total += absf(s) / 2.0
	return total


func _surface_y_local() -> float:
	return -22.0 - 42.0 * _fill


# ---------- drawing ----------
func _draw():
	var shake := Vector2(roundf(sin(_t * 70.0)), roundf(cos(_t * 55.0))) * minf(_mixed * 3.0, 1.0) if _phase == Phase.BLEND else Vector2.ZERO
	var at := Vector2(0, _y) + shake
	_draw_glass()
	_draw_base(at)
	_draw_jar(at)
	for d: Array in _own_drops:
		if d[3] < 0.7:
			draw_rect(Rect2((d[0] as Vector2).round(), Vector2(2, 2)), d[2])
	for b: Array in _bits:
		var c: Color = b[2]
		draw_rect(Rect2((b[0] as Vector2).round(), Vector2(2, 2)), Color(c, clampf(float(b[3]) * 4.0, 0.0, 1.0)))


# a retro cream blender base: chrome trim, a red dial (it spins while it runs), two buttons, little feet
func _draw_base(at: Vector2):
	var base := PackedVector2Array()
	for p: Vector2 in BASE:
		base.append(at + p)
	draw_colored_polygon(base, CREAM)
	draw_polyline(base + PackedVector2Array([base[0]]), Pixel.INK, 1.0)
	draw_rect(Rect2(at + Vector2(-15, -17), Vector2(30, 3)), CHROME)
	draw_rect(Rect2(at + Vector2(-15, -14), Vector2(30, 1)), CHROME_DARK)
	draw_rect(Rect2(at + Vector2(13, -13), Vector2(4, 12)), CREAM_SHADE)
	draw_rect(Rect2(at + Vector2(-17, -2), Vector2(6, 2)), Pixel.INK)
	draw_rect(Rect2(at + Vector2(11, -2), Vector2(6, 2)), Pixel.INK)
	var dial := at + Vector2(0, -8)
	draw_circle(dial, 4.0, Pixel.INK)
	draw_circle(dial, 3.0, DIAL)
	var a := _t * 20.0 if _phase == Phase.BLEND else -0.8
	draw_line(dial, dial + Vector2.from_angle(a) * 2.5, Pixel.WHITE, 1.0)
	for bx: float in [-10.0, 8.0]:
		var lit: bool = _phase == Phase.BLEND and bx > 0.0
		draw_rect(Rect2(at + Vector2(bx, -10), Vector2(3, 3)), Pixel.INK)
		draw_rect(Rect2(at + Vector2(bx + 0.5, -9.5), Vector2(2, 2)), Pixel.ORANGE if lit else CHROME)


# the glass jar: a chrome collar, the blades, the liquid, the glass with its shine, measuring marks and a
# handle, and the lid while it blends. It all tips together about the spout corner to pour.
func _draw_jar(at: Vector2):
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for p: Vector2 in JAR_OUT:
		outer.append(_jar_xf(p, at))
	for p: Vector2 in JAR_IN:
		inner.append(_jar_xf(p, at))
	# collar
	var collar := PackedVector2Array([_jar_xf(Vector2(-12, -17), at), _jar_xf(Vector2(12, -17), at), _jar_xf(Vector2(11, -21), at), _jar_xf(Vector2(-11, -21), at)])
	draw_colored_polygon(collar, CHROME)
	draw_polyline(collar + PackedVector2Array([collar[0]]), Pixel.INK, 1.0)
	# the glass, behind the liquid
	draw_colored_polygon(outer, GLASS_TINT)
	# blades (under the liquid when it's full)
	var hub := _jar_xf(Vector2(0, -24), at)
	var spin := _t * 40.0 if _phase == Phase.BLEND else 0.4
	for k in 2:
		var d := Vector2.from_angle(spin + k * PI / 2.0) * Vector2(6, 1.5)
		draw_line(hub - d, hub + d, CHROME_DARK, 2.0)
	# the liquid
	var whirl := 7.0 * _ease(minf(_pt / 0.4, 1.0)) * (1.0 - _ease(maxf((_pt - BLEND_TIME + 0.3) / 0.3, 0.0))) if _phase == Phase.BLEND else 0.0
	var res := _liquid(inner, _fill, at.x, whirl)
	var polys: Array = res[0]
	var col := JUICE.lerp(CREAMY, _mixed)
	for poly: PackedVector2Array in polys:
		draw_colored_polygon(poly, col)
	if not polys.is_empty():
		var level: float = res[1]
		var x := at.x - 20.0
		while x <= at.x + 20.0:                       # a lighter line along the surface
			var sy := _surface(x, level, at.x, whirl)
			if Geometry2D.is_point_in_polygon(Vector2(x, sy + 1.0), inner):
				draw_rect(Rect2(roundf(x), roundf(sy), 2, 1), JUICE_LIGHT)
				if whirl > 1.0 and posmod(int(x + _t * 50.0), 6) < 2:
					draw_rect(Rect2(roundf(x), roundf(sy) + 2.0, 2, 1), JUICE_DARK)   # the spin
			x += 2.0
		for b: Array in _bubbles:                     # bubbles churned up while it blends
			var bp := _jar_xf(Vector2(b[0], b[1]), at)
			if bp.y > level + 1.0 and Geometry2D.is_point_in_polygon(bp, inner):
				draw_rect(Rect2(bp.round(), Vector2(1, 1)), JUICE_LIGHT)
	# the glass over it: edges, shine, measuring marks, handle
	draw_polyline(outer + PackedVector2Array([outer[0]]), Pixel.INK, 1.0)
	draw_line(_jar_xf(Vector2(-12, -22), at), _jar_xf(Vector2(-14, -62), at), GLASS_EDGE, 1.0)
	draw_line(_jar_xf(Vector2(12, -22), at), _jar_xf(Vector2(14, -62), at), GLASS_EDGE, 1.0)
	draw_line(_jar_xf(Vector2(-8, -27), at), _jar_xf(Vector2(-10, -58), at), SHINE, 2.0)
	for my: float in [-30.0, -38.0, -46.0, -54.0]:
		var half := 2.0 if int(my) % 16 == 2 else 1.0
		draw_line(_jar_xf(Vector2(8.0 + (my + 22.0) * -0.1 - half, my), at), _jar_xf(Vector2(10.0 + (my + 22.0) * -0.1, my), at), SHINE, 1.0)
	var handle := PackedVector2Array([_jar_xf(Vector2(-14, -56), at), _jar_xf(Vector2(-21, -54), at),
		_jar_xf(Vector2(-21, -32), at), _jar_xf(Vector2(-12, -29), at)])
	draw_polyline(handle, Pixel.INK, 3.0)
	draw_polyline(handle, GLASS_EDGE, 1.0)
	# the spout lip
	draw_line(_jar_xf(Vector2(13, -65), at), _jar_xf(Vector2(17, -67), at), Pixel.INK, 2.0)
	# the lid (on while it blends)
	if _phase == Phase.LID or _phase == Phase.BLEND:
		var drop := (1.0 - minf(_pt / LID_TIME, 1.0)) * 20.0 if _phase == Phase.LID else 0.0
		var lid := Rect2(at + Vector2(-16, -69 - drop), Vector2(32, 5))
		draw_rect(lid.grow(1.0), Pixel.INK)
		draw_rect(lid, LID)
		draw_rect(Rect2(lid.position, Vector2(lid.size.x, 1)), LID_LIGHT)
		draw_rect(Rect2(at + Vector2(-4, -72 - drop), Vector2(8, 3)), LID)
	# the pour: a stream from the spout curving down into the glass
	if _phase == Phase.POUR:
		var spout := _jar_xf(Vector2(16, -66), at)
		var mouth := Vector2(side * GLASS_AT, -26.0)
		var y := spout.y
		var n := 0
		while y < mouth.y:
			var k := (y - spout.y) / maxf(mouth.y - spout.y, 1.0)
			var sx := lerpf(spout.x, mouth.x, 1.0 - (1.0 - k) * (1.0 - k))
			draw_rect(Rect2(roundf(sx) - 1.0, y, 3, 2), CREAMY if (n + int(_t * 30.0)) % 4 else JUICE_LIGHT)
			y += 2.0
			n += 1


# the hurricane glass beside it: a curvy bowl on a stem, filling level with the same liquid, then a pineapple
# wedge and a little umbrella
func _draw_glass():
	var g := Vector2(side * GLASS_AT, 0)
	draw_rect(Rect2(g.x - 6.0, -2, 12, 2), GLASS_EDGE)                # foot
	draw_rect(Rect2(g.x - 1.0, -8, 2, 6), GLASS_EDGE)                 # stem
	var bowl := PackedVector2Array()
	for p: Vector2 in GLASS_IN:
		bowl.append(g + p)
	draw_colored_polygon(bowl, GLASS_TINT)
	var res := _liquid(bowl, _glass, g.x, 0.0)
	for poly: PackedVector2Array in res[0]:
		draw_colored_polygon(poly, CREAMY)
	if not (res[0] as Array).is_empty():
		draw_rect(Rect2(g.x - 4.0, roundf(res[1]), 8, 1), JUICE_LIGHT)
	draw_polyline(bowl + PackedVector2Array([bowl[0]]), Pixel.INK, 1.0)
	draw_line(g + Vector2(-4, -24), g + Vector2(-5, -19), SHINE, 1.0)
	if (_phase == Phase.GARNISH and _pt >= 0.35) or _phase > Phase.GARNISH:
		draw_rect(Rect2(g.x + 3.0, -31, 6, 5), Color("f2c22e"))         # the pineapple wedge
		draw_rect(Rect2(g.x + 5.0, -34, 2, 3), LEAF)
		draw_line(g + Vector2(-2, -27), g + Vector2(-7, -38), Pixel.PALE, 1.0)
		draw_rect(Rect2(g.x - 12.0, -40, 10, 2), UMBRELLA)                # the umbrella
		draw_rect(Rect2(g.x - 10.0, -41, 6, 1), UMBRELLA.lightened(0.3))
