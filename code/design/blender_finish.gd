extends Node2D
# THE BLENDER (level 1's ending, Morgan's idea, 2026-10-08): when the Pina Colada boss is beaten, a tiki blender
# (Morgan's call, 2026-10-09: in the tropical theme; it was a retro cream one) drops in where it fell. All the juice lying about the fight (every drop, chunk and puddle of the boss's
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

const CHROME_DARK := Color("7d868c")
const GLASS_TINT := Color(0.78, 0.9, 0.96, 0.22)
const GLASS_EDGE := Color(0.88, 0.95, 0.98, 0.95)
const SHINE := Color(1, 1, 1, 0.45)
const JUICE := Color("f2d27a")                    # before it's blended: a touch more pineapple
const CREAMY := Color("f5e2a8")                   # blended: the pina colada
const JUICE_LIGHT := Color("fff3cf")
const JUICE_DARK := Color("d9b65e")
const UMBRELLA := Color("e86a9a")
const LEAF := Color("76964a")
const LEAF_DARK := Color("4f6e2e")
# the tiki blender
const WOOD := Color("6b4424")
const WOOD_DARK := Color("4a2e18")
const WOOD_LIGHT := Color("8e5c30")
const BAMBOO := Color("b8a356")
const BAMBOO_DARK := Color("7d6c32")
const BAMBOO_LIGHT := Color("d8c77a")
const HIBISCUS := Color("e8406a")
const HIBISCUS_LIGHT := Color("f6a0b8")
const COCONUT := Color("5a3a22")
const LID_GOLD := Color("d8a23a")
const LID_GOLD_DARK := Color("a8741e")

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
	add_to_group("foreground_clear")              # the foreground's plants clear out of the way (foreground.gd)
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
	# (never above the brim: a completely full glass found its level 8px over it, and the light line along the
	# drink's surface floated in the air above the glass)
	var level := maxf((a + b) / 2.0, lo)
	return [Geometry2D.intersect_polygons(inside, _below(level, jar_x, whirl, inside)), level]


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
# where it is, for foreground.gd: plants over it fade right out (it was hidden behind them sometimes). Big
# enough for the jar tipped over and the glass on either side
func foreground_rect() -> Rect2:
	return Rect2(global_position + Vector2(-64, -112), Vector2(128, 118))


func _draw():
	var shake := Vector2(roundf(sin(_t * 70.0)), roundf(cos(_t * 55.0))) * minf(_mixed * 3.0, 1.0) if _phase == Phase.BLEND else Vector2.ZERO
	var at := Vector2(0, _y) + shake
	_draw_shadows(at)
	_draw_glass()
	_draw_base(at)
	_draw_jar(at)
	for d: Array in _own_drops:
		if d[3] < 0.7:
			draw_rect(Rect2((d[0] as Vector2).round(), Vector2(2, 2)), d[2])
	for b: Array in _bits:
		var c: Color = b[2]
		draw_rect(Rect2((b[0] as Vector2).round(), Vector2(2, 2)), Color(c, clampf(float(b[3]) * 4.0, 0.0, 1.0)))


# so it pops out (the professor's note, 2026-10-09): a shadow on the ground under it (small and faint while it
# drops in, spreading and darkening as it lands) and under the glass, and a drop shadow behind the blender itself
func _draw_shadows(at: Vector2):
	var land := 1.0 - clampf(-_y / 150.0, 0.0, 1.0)            # 0 high up .. 1 landed
	var a := lerpf(0.15, 0.55, land)                          # (stronger, Morgan's call: it didn't show)
	for row in 4:                                            # a stepped ellipse on the floor, widest at its line
		var half := roundf(lerpf(12.0, 32.0, land) * [0.75, 1.0, 0.85, 0.5][row])
		draw_rect(Rect2(-half, -2.0 + row, half * 2.0, 1), Color(Pixel.INK, a))
	var g := Vector2(side * GLASS_AT, 0)
	draw_rect(Rect2(g.x - 9.0, -1, 18, 1), Color(Pixel.INK, 0.4))   # and under the glass
	draw_rect(Rect2(g.x - 6.0, 0, 12, 1), Color(Pixel.INK, 0.3))
	var drop := Vector2(4, 3)                                # behind it: its shape, down and to the right
	var base := PackedVector2Array()
	for p: Vector2 in BASE:
		base.append(at + p + drop)
	draw_colored_polygon(base, Color(Pixel.INK, 0.55))
	var jar := PackedVector2Array()
	for p: Vector2 in JAR_OUT:
		jar.append(_jar_xf(p, at) + drop)
	draw_colored_polygon(jar, Color(Pixel.INK, 0.45))
	var bowl := PackedVector2Array()
	for p: Vector2 in GLASS_IN:
		bowl.append(g + p + Vector2(3, 2))
	draw_colored_polygon(bowl, Color(Pixel.INK, 0.35))


# a carved tiki base: dark wood with its grain, a bamboo band round the top, a tiki face (its eyes glow and its
# mouth chatters while it blends), coconut-half feet and a hibiscus flower tucked in the band
func _draw_base(at: Vector2):
	var base := PackedVector2Array()
	for p: Vector2 in BASE:
		base.append(at + p)
	draw_colored_polygon(base, WOOD)
	draw_rect(Rect2(at + Vector2(10, -14), Vector2(5, 13)), WOOD_DARK)          # the shaded side
	for gx: float in [-12.0, -7.0, 8.0]:                                         # grain
		draw_line(at + Vector2(gx, -13), at + Vector2(gx + 1.0, -3), WOOD_LIGHT, 1.0)
	draw_polyline(base + PackedVector2Array([base[0]]), Pixel.INK, 1.0)
	var band := Rect2(at + Vector2(-16, -18), Vector2(32, 4))                    # the bamboo band
	draw_rect(band.grow(1.0), Pixel.INK)
	draw_rect(band, BAMBOO)
	draw_rect(Rect2(band.position, Vector2(band.size.x, 1)), BAMBOO_LIGHT)
	for nx: float in [-9.0, 0.0, 9.0]:
		draw_rect(Rect2(at + Vector2(nx, -18), Vector2(1, 4)), BAMBOO_DARK)
	var blending := _phase == Phase.BLEND
	var glow := Pixel.ORANGE if blending and int(_t * 12.0) % 2 == 0 else (Pixel.MUSTARD if blending else WOOD_LIGHT)
	draw_rect(Rect2(at + Vector2(-10, -13), Vector2(20, 1)), WOOD_DARK)        # the brow
	for ex: float in [-9.0, 3.0]:                                                # the eyes
		draw_rect(Rect2(at + Vector2(ex, -12), Vector2(6, 4)), Pixel.INK)
		draw_rect(Rect2(at + Vector2(ex + 1.0, -11), Vector2(4, 2)), glow)
		draw_rect(Rect2(at + Vector2(ex + 2.0, -11), Vector2(2, 2)), Pixel.INK)
	draw_rect(Rect2(at + Vector2(-1, -8), Vector2(2, 2)), WOOD_DARK)            # the nose
	var open := 4.0 if blending and int(_t * 16.0) % 2 == 0 else 3.0           # the grin (chattering)
	draw_rect(Rect2(at + Vector2(-7, -6), Vector2(14, open + 1.0)), Pixel.INK)
	for tx in 4:
		draw_rect(Rect2(at + Vector2(-6.0 + tx * 3.0, -5), Vector2(2, 1)), Pixel.WHITE)
	draw_rect(Rect2(at + Vector2(-1, -6.0 + open), Vector2(2, 1)), HIBISCUS)    # the tongue
	for fx: float in [-16.0, 11.0]:                                              # coconut feet
		draw_rect(Rect2(at + Vector2(fx, -2), Vector2(6, 2)), COCONUT)
		draw_rect(Rect2(at + Vector2(fx + 1.0, -2), Vector2(4, 1)), WOOD_LIGHT)
	var f := at + Vector2(-14, -19)                                             # the hibiscus
	for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-1, -1), Vector2(1, 1)]:
		draw_rect(Rect2(f + off - Vector2(1, 1), Vector2(2, 2)), HIBISCUS)
	draw_rect(Rect2(f + Vector2(-2, -2), Vector2(1, 1)), HIBISCUS_LIGHT)
	draw_rect(Rect2(f, Vector2(1, 1)), Pixel.MUSTARD)


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
	draw_colored_polygon(collar, BAMBOO)                       # a bamboo collar
	draw_polyline(collar + PackedVector2Array([collar[0]]), Pixel.INK, 1.0)
	for nx: float in [-6.0, 6.0]:
		draw_line(_jar_xf(Vector2(nx, -17), at), _jar_xf(Vector2(nx, -21), at), BAMBOO_DARK, 1.0)
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
	draw_polyline(handle, Pixel.INK, 4.0)                      # a bamboo handle
	draw_polyline(handle, BAMBOO, 2.0)
	for hy: float in [-48.0, -40.0]:
		draw_line(_jar_xf(Vector2(-22, hy), at), _jar_xf(Vector2(-19, hy), at), BAMBOO_DARK, 1.0)
	# the spout lip
	draw_line(_jar_xf(Vector2(13, -65), at), _jar_xf(Vector2(17, -67), at), Pixel.INK, 2.0)
	# the lid (on while it blends)
	if _phase == Phase.LID or _phase == Phase.BLEND:
		var drop := (1.0 - minf(_pt / LID_TIME, 1.0)) * 20.0 if _phase == Phase.LID else 0.0
		var lid := Rect2(at + Vector2(-16, -69 - drop), Vector2(32, 5))        # a pineapple lid with its crown
		draw_rect(lid.grow(1.0), Pixel.INK)
		draw_rect(lid, LID_GOLD)
		for dx in range(0, 32, 4):
			draw_rect(Rect2(lid.position + Vector2(dx + (2 if dx % 8 else 0), 2), Vector2(1, 1)), LID_GOLD_DARK)
		draw_rect(Rect2(lid.position, Vector2(lid.size.x, 1)), Pixel.MUSTARD)
		var crown := at + Vector2(0, -70 - drop)
		var sway := sin(_t * 30.0) * 1.0 if _phase == Phase.BLEND else 0.0
		for k in 5:
			var lean := (k - 2) * 2.2
			var tip := crown + Vector2(lean * 1.6 + sway, -6.0 - (2 - absi(k - 2)) * 2.5)
			draw_line(crown + Vector2(lean * 0.4, 0), tip, Pixel.INK, 3.0)
			draw_line(crown + Vector2(lean * 0.4, 0), tip, LEAF if k % 2 == 0 else LEAF_DARK, 1.0)
	if _phase == Phase.POUR:
		_draw_pour(at)


# the pour (the professor's note, 2026-10-09: fluid, not a column of little squares): one smooth stream from the
# spout curving down into the glass, thicker at the spout and thinning as it falls, with a darker edge, a
# highlight flowing down it and a slight wobble. It runs down from the spout at the start, and at the end its
# tail leaves the spout and falls in
func _draw_pour(at: Vector2):
	var spout := _jar_xf(Vector2(16, -66), at)
	var mouth := Vector2(side * GLASS_AT, -26.0)
	var head := clampf(_pt / 0.15, 0.0, 1.0)                 # how far down it's reached
	var tail := clampf((_pt - (POUR_TIME - 0.2)) / 0.2, 0.0, 1.0)   # how far its end has fallen
	if head <= tail:
		return
	var n := 18
	var pts := PackedVector2Array()
	var widths := PackedFloat32Array()
	for i in n + 1:
		var k := lerpf(tail, head, float(i) / n)
		var p := Vector2(lerpf(spout.x, mouth.x, 1.0 - (1.0 - k) * (1.0 - k)), lerpf(spout.y, mouth.y, k))
		p.x += sin(k * 9.0 - _t * 14.0) * 0.6 * k            # a little wobble, more as it falls
		pts.append(p)
		widths.append(lerpf(0.8, 3.8, k))                     # a thin trickle at the spout, wider into the glass
	for pass_i in 2:                                         # the darker edge, then the stream over it
		var col := JUICE_DARK if pass_i == 0 else CREAMY
		for i in n:
			var d := (pts[i + 1] - pts[i]).normalized().orthogonal()
			var e0 := (0.35 + 0.65 * widths[i] / 3.8) if pass_i == 0 else 0.0     # (the edge thins with it)
			var e1 := (0.35 + 0.65 * widths[i + 1] / 3.8) if pass_i == 0 else 0.0
			var w0 := widths[i] / 2.0 + e0
			var w1 := widths[i + 1] / 2.0 + e1
			var d1 := d if i + 1 >= n else (pts[i + 2] - pts[i + 1]).normalized().orthogonal()
			draw_primitive(PackedVector2Array([pts[i] + d * w0, pts[i + 1] + d1 * w1,    # (a plain quad: as a
				pts[i + 1] - d1 * w1, pts[i] - d * w0]), PackedColorArray([col, col, col, col]),   # polygon, a squashed
				PackedVector2Array())                     # one, as the stream starts and ends, failed to triangulate)
	for i in n:                                              # the highlight, in dashes flowing down it
		var k := float(i) / n
		if fposmod(k * 40.0 - _t * 24.0, 4.0) < 2.0:
			var d := (pts[i + 1] - pts[i]).normalized().orthogonal()
			draw_line(pts[i] + d * widths[i] * 0.2, pts[i + 1] + d * widths[i + 1] * 0.2, JUICE_LIGHT, 1.0)


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
