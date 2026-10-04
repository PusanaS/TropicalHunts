extends StaticBody2D
# THE MOUNTAIN over the mine (level 1, Morgan's idea): a big mountain sits on top of the tunnel, with
# steep cliffs on both sides and jungle along its ridge, so there's no way over it. The rails run into a
# tunnel mouth cut into the foot of its left cliff: the mine cart is the only way on. The dynamite's
# crater is at the foot of its right cliff, so you're blasted out of the mountain's base.
# Its collision is this body's own Shape (a tall block as wide as the mountain); its plain Look polygon
# (what the editor shows) is hidden while the game runs. The tunnel's inside is drawn over it by
# mine_cave.gd (z -60), so the mountain sits behind that (z -70), in front of the jungle's parallax.
# PLACEHOLDER art drawn in code, in earthy browns close to the mine's earth (so the shaft through it
# reads as one rock) and the living background's greens. BOOM's style: flat colours, one shade each.

const OUTLINE := [   # global, clockwise from the foot of the left cliff
	Vector2(5040, 64), Vector2(5040, -20), Vector2(5034, -70), Vector2(5044, -120), Vector2(5030, -175),
	Vector2(5040, -230), Vector2(5028, -290), Vector2(5046, -350), Vector2(5070, -420), Vector2(5120, -470),
	Vector2(5210, -520), Vector2(5330, -600), Vector2(5440, -640), Vector2(5530, -720), Vector2(5620, -690),
	Vector2(5730, -760), Vector2(5850, -700), Vector2(5990, -730), Vector2(6120, -660), Vector2(6280, -700),
	Vector2(6430, -630), Vector2(6580, -660), Vector2(6720, -590), Vector2(6840, -520), Vector2(6930, -440),
	Vector2(6970, -360), Vector2(6996, -280), Vector2(6990, -200), Vector2(7004, -130), Vector2(6996, -60),
	Vector2(7002, 64)]
const LEFT_FACE := 8                 # OUTLINE[1..LEFT_FACE] is the left cliff
const RIDGE := Vector2i(8, 24)       # OUTLINE[8..24] is the ridge along the top
const RIGHT_FACE := 24               # OUTLINE[24..] is the right cliff
const PORTAL := Rect2(5040, -72, 100, 72)   # the tunnel mouth (mine_cave.gd draws its inside)
const LEDGES := [Vector2(5044, -120), Vector2(5040, -230), Vector2(5046, -350), Vector2(6996, -280), Vector2(6990, -200)]
const VINES := [[Vector2(5032, -118), 44.0], [Vector2(5029, -172), 64.0], [Vector2(5027, -288), 86.0],
	[Vector2(5044, -348), 70.0], [Vector2(5036, -228), 52.0]]   # [from, length] down the left cliff

const ROCK := Color("4e3a28")
const ROCK_LIGHT := Color("6e553b")      # the sunlit left cliff and the ridge
const ROCK_SHADE := Color("33251a")      # the right cliff, in shade
const STRATA := Color("443222")
const CRACK := Color("2a1e14")
const STONE := Color("6e6250")
const STONE_SHADE := Color("564c40")
const LEAF_DARK := Color("3c522a")
const LEAF := Color("526e36")
const LEAF_MID := Color("76964a")
const LEAF_LIGHT := Color("a4bf68")
const TRUNK := Color("4d321a")
const FLOWERS := [Color("d36618"), Color("ccad4b"), Color("8d0e0e")]

var _poly := PackedVector2Array()        # the outline, local
var _trees: Array = []                   # [foot (local), radius, colour shift]
var _cracks: Array = []                  # [PackedVector2Array]


func _ready():
	z_index = -70
	var look := get_node_or_null("Look") as CanvasItem
	if look:
		look.visible = false
	for p: Vector2 in OUTLINE:
		_poly.append(p - global_position)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5040
	for i in range(RIDGE.x, RIDGE.y):                                   # trees all along the ridge
		var a: Vector2 = OUTLINE[i]
		var b: Vector2 = OUTLINE[i + 1]
		var d := a.distance_to(b)
		var t := rng.randf_range(0.0, 30.0)
		while t < d:
			_trees.append([a.lerp(b, t / d) - global_position + Vector2(0, 4), rng.randf_range(14.0, 28.0), rng.randi() % 3])
			t += rng.randf_range(30.0, 58.0)
	for i in 14:                                                        # cracks down the cliff faces
		var left := i < 9
		var x := rng.randf_range(5040.0, 5110.0) if left else rng.randf_range(6930.0, 6995.0)
		var y := rng.randf_range(-420.0, -110.0)
		var line := PackedVector2Array([Vector2(x, y) - global_position])
		for k in rng.randi_range(3, 5):
			y += rng.randf_range(8.0, 18.0)
			x += rng.randf_range(-5.0, 5.0)
			line.append(Vector2(x, y) - global_position)
		_cracks.append(line)


func _draw():
	draw_colored_polygon(_poly, ROCK)
	# strata: bands of darker rock across the whole mountain, clipped to its outline
	var y := -742.0
	while y < 60.0:
		for band in Geometry2D.intersect_polygons(_band(y, 6.0), _poly):
			draw_colored_polygon(band, STRATA)
		y += 36.0
	# light on the left cliff and the ridge, shade on the right cliff
	for i in range(1, LEFT_FACE):
		draw_line(_poly[i] + Vector2(2, 0), _poly[i + 1] + Vector2(2, 0), ROCK_LIGHT, 3.0)
	for i in range(RIDGE.x, RIDGE.y):
		draw_line(_poly[i] + Vector2(0, 2), _poly[i + 1] + Vector2(0, 2), ROCK_LIGHT, 3.0)
	for i in range(RIGHT_FACE, _poly.size() - 1):
		draw_line(_poly[i] + Vector2(-4, 0), _poly[i + 1] + Vector2(-4, 0), ROCK_SHADE, 7.0)
	for c: PackedVector2Array in _cracks:
		draw_polyline(c, CRACK, 1.0)
	_draw_portal_stones()
	for v: Array in VINES:                                              # vines hanging down the left cliff
		_draw_vine(v[0] - global_position, v[1])
	for l: Vector2 in LEDGES:                                           # bushes on the ledges
		_draw_bush(l - global_position)
	for t: Array in _trees:
		_draw_tree(t[0], t[1], t[2])


# a horizontal band, wide enough to cross the whole mountain
func _band(y: float, h: float) -> PackedVector2Array:
	var x0 := 4980.0 - global_position.x
	var x1 := 7060.0 - global_position.x
	var yy := y - global_position.y
	return PackedVector2Array([Vector2(x0, yy), Vector2(x1, yy), Vector2(x1, yy + h), Vector2(x0, yy + h)])


# a row of cut stones over the tunnel mouth, a keystone in the middle (the cart's timber frame stands in front)
func _draw_portal_stones():
	var top := PORTAL.position - global_position + Vector2(-8, -26)
	var x := 0.0
	var i := 0
	while x < PORTAL.size.x + 16.0:
		var w := 14.0 if i % 2 == 0 else 12.0
		var r := Rect2(top + Vector2(x, 0), Vector2(w - 1.0, 10))
		draw_rect(r, STONE)
		draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2), STONE_SHADE)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), ROCK_LIGHT)
		x += w
		i += 1
	var key := Rect2(top + Vector2((PORTAL.size.x + 16.0) / 2.0 - 8.0, -4), Vector2(16, 15))
	draw_rect(key, STONE)
	draw_rect(Rect2(key.position.x, key.end.y - 2.0, key.size.x, 2), STONE_SHADE)
	draw_rect(Rect2(key.position, Vector2(key.size.x, 1)), ROCK_LIGHT)


func _draw_vine(from: Vector2, length: float):
	for s in int(length):
		var p := from + Vector2(roundf(sin(s * 0.18) * 1.0), s)
		draw_rect(Rect2(p, Vector2(1, 1)), LEAF_DARK)
		if s % 6 == 3:
			var side := -2.0 if int(s / 6.0) % 2 == 0 else 1.0
			draw_rect(Rect2(p + Vector2(side, 0), Vector2(2, 2)), LEAF)
			draw_rect(Rect2(p + Vector2(side, 0), Vector2(1, 1)), LEAF_MID)
	draw_rect(Rect2(from + Vector2(-1, length), Vector2(3, 3)), LEAF)


func _draw_bush(at: Vector2):
	draw_circle(at + Vector2(-4, -3), 6.0, LEAF_DARK)
	draw_circle(at + Vector2(4, -4), 7.0, LEAF)
	draw_circle(at + Vector2(1, -7), 5.0, LEAF_MID)
	draw_rect(Rect2(at + Vector2(-1, -10), Vector2(2, 2)), FLOWERS[int(at.y) % FLOWERS.size()])


# a jungle tree on the ridge: a short trunk, a round canopy in three greens with a lit top-left
func _draw_tree(foot: Vector2, r: float, shift: int):
	draw_line(foot, foot + Vector2(0, -r * 0.9), TRUNK, 3.0)
	var c := foot + Vector2(0, -r * 1.2)
	var dark: Color = [LEAF_DARK, LEAF, LEAF_DARK][shift]
	var mid: Color = [LEAF, LEAF_MID, LEAF][shift]
	draw_circle(c + Vector2(r * 0.25, r * 0.15), r, dark)
	draw_circle(c, r * 0.85, mid)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, LEAF_MID if shift != 1 else LEAF_LIGHT)
	draw_circle(c + Vector2(-r * 0.4, -r * 0.45), r * 0.18, LEAF_LIGHT)
