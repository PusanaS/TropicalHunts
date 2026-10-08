extends Node2D
# A PLACARD (Morgan's idea, 2026-10-08): a sign on a wooden post that teaches with pictograms, no words, like a
# bathroom or hazard sign: white figures on blue. `picture` picks what it shows:
#   "surf"        like a tsunami warning sign: a big curling wave behind a stick figure sprinting away from it
#                 (speed lines), and on a little plaque under it, two → key caps pressing in turn: double-tap
#                 to gallop, and a wave builds behind you. (Kept in our back pocket, Morgan's call.)
#   "quicksand"   a yellow warning triangle (Morgan's call, 2026-10-08): a stick figure sunk to the waist in wavy
#                 sand, arms up, slowly sinking and bobbing back. On one post, no plaque. In level 1 it stands on
#                 the mine's rock floor just before the snakes' quicksand, by a lantern.
#   "surf_ride"   level 1's surf run (Morgan's call, 2026-10-08): a wider board, two panels read left to right
#                 with a white arrow between them: the "surf" picture, then the figure riding on top of the wave on
#                 a surfboard, arms out. Two posts; the → → plaque under the first panel.
#   "drain"       level 1's watermelon shark (Morgan's call, 2026-10-08), on the near bank before its river: drain
#                 the water to beat it. Two panels like "surf_ride": the figure standing in the water on the left,
#                 charging its blade overhead (sparks gathering, a ring at full charge), facing a shark fin circling
#                 on the right, then
#                 the water rolling away both ways and the shark stranded on the dry bed, flopping. The plaque
#                 holds a W key down while a charge bar fills. (The shark itself says IMMUNE IN WATER when hit.)
# Place it with its posts' feet on the floor. It stands behind you (z -1). PLACEHOLDER art drawn in code.

@export var picture := "surf"

const Pixel := preload("res://code/design/pixel_font.gd")
const SIGN := Rect2(-38, -98, 76, 42)             # the board
const SIGN_WIDE := Rect2(-80, -98, 160, 42)       # two panels
const PLAQUE := Rect2(-24, -52, 48, 21)           # the little plaque under it (centred on its post)
const BLUE := Color("1f5fa8")                     # a hazard-sign blue
const BLUE_DARK := Color("164682")
const WHITE := Color("f4f1ea")
const WOOD := Color("6b4424")
const WOOD_LIGHT := Color("8e5c30")
const WOOD_DARK := Color("4a2e18")
const BOLT := Color("9c9ba4")
const WARN_YELLOW := Color("f2c22e")
const WARN_INK := Color("1d1820")

var _t := 0.0


func _ready():
	z_index = -1


func _process(delta: float):
	_t += delta
	queue_redraw()


func _draw():
	if picture == "quicksand":
		_draw_quicksand()
		return
	var wide := picture == "surf_ride" or picture == "drain"
	var board := SIGN_WIDE if wide else SIGN
	var posts: Array = [board.position.x + 26.0, board.end.x - 26.0] if wide else [0.0]
	var plaque := Rect2(PLAQUE.position + Vector2(posts[0], 0), PLAQUE.size)
	# the posts
	for px: float in posts:
		var top := plaque.end.y if px == posts[0] else board.end.y
		draw_rect(Rect2(px - 3.0, top, 6, -top), WOOD)
		draw_rect(Rect2(px - 3.0, top, 2, -top), WOOD_LIGHT)
		draw_rect(Rect2(px + 2.0, top, 1, -top), WOOD_DARK)
	draw_rect(Rect2(float(posts[0]) - 3.0, board.end.y, 6, plaque.position.y - board.end.y), WOOD)
	# the board: blue, bolts in the corners, a white border round each panel
	draw_rect(board.grow(1.0), Pixel.INK)
	draw_rect(board, BLUE)
	draw_rect(Rect2(board.position + Vector2(0, board.size.y - 3.0), Vector2(board.size.x, 3)), BLUE_DARK)
	for c in [board.position + Vector2(1, 1), Vector2(board.end.x - 2.0, board.position.y + 1.0)]:
		draw_rect(Rect2(c, Vector2(1, 1)), BOLT)
	var inner := board.grow(-3.0)
	if wide:
		var half := inner.size.x / 2.0 - 8.0
		var left := Rect2(inner.position, Vector2(half, inner.size.y))
		var right := Rect2(inner.end.x - half, inner.position.y, half, inner.size.y)
		_frame(left)
		_frame(right)
		if picture == "drain":
			_draw_charge(left)
			_draw_stranded(right)
		else:
			_draw_surf(left)
			_draw_ride(right)
		_arrow(Vector2(inner.get_center().x, inner.get_center().y))
	else:
		_frame(inner)
		match picture:
			"surf":
				_draw_surf(inner)
	# the plaque under the first panel, with what to press: two → keys, pressed one after the other (or W held)
	draw_rect(plaque.grow(1.0), Pixel.INK)
	draw_rect(plaque, WOOD)
	draw_rect(Rect2(plaque.position, Vector2(plaque.size.x, 1)), WOOD_LIGHT)
	if picture == "drain":
		_draw_hold_w(plaque)
		return
	var beat := fmod(_t, 1.4)
	var first := beat < 0.12
	var second := beat >= 0.24 and beat < 0.36
	Pixel.draw_key(self, plaque.position + Vector2(6, 3), 15, "→", first, first)
	Pixel.draw_key(self, plaque.position + Vector2(27, 3), 15, "→", second, second)


# a panel's white border
func _frame(r: Rect2):
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), WHITE)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1.0), Vector2(r.size.x, 1)), WHITE)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), WHITE)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1.0, 0), Vector2(1, r.size.y)), WHITE)


# the white arrow between two panels: then this
func _arrow(at: Vector2):
	var nudge := roundf(absf(sin(_t * 3.0)) * 1.5)
	draw_rect(Rect2(at.x - 6.0 + nudge, at.y - 1.0, 7, 3), WHITE)
	for i in 4:
		draw_rect(Rect2(at.x + 1.0 + nudge + i, at.y - 4.0 + i, 1, 9.0 - i * 2.0), WHITE)


# the wave pictogram: a big white wave curling over on the left, a stick figure sprinting away to the right with
# speed lines behind it (a tsunami sign, but here it means: run and a wave builds behind you)
func _draw_surf(inner: Rect2):
	var base := inner.end.y - 3.0                     # the ground line
	draw_rect(Rect2(inner.position.x + 3.0, base, inner.size.x - 6.0, 1), WHITE)
	# the wave: a swell rising to a crest, its lip curling over toward the runner, hollow under the curl
	var x0 := inner.position.x + 3.0
	var wave := PackedVector2Array([Vector2(x0, base), Vector2(x0, base - 8.0), Vector2(x0 + 6.0, base - 18.0),
		Vector2(x0 + 14.0, base - 26.0), Vector2(x0 + 22.0, base - 29.0), Vector2(x0 + 29.0, base - 26.0),
		Vector2(x0 + 32.0, base - 20.0), Vector2(x0 + 28.0, base - 15.0), Vector2(x0 + 25.0, base - 19.0),
		Vector2(x0 + 21.0, base - 18.0), Vector2(x0 + 19.0, base - 10.0), Vector2(x0 + 25.0, base)])
	draw_colored_polygon(wave, WHITE)
	draw_circle(Vector2(x0 + 24.0, base - 12.0), 3.5, BLUE)                 # the hollow under the lip
	for i in 3:                                                           # spray off the lip
		draw_rect(Rect2(x0 + 33.0 + i * 2.0, base - 24.0 + i * 3.0 + roundf(sin(_t * 4.0 + i)), 1, 1), WHITE)
	# the runner, mid-stride, leaning into it (a little bob)
	var bob := roundf(absf(sin(_t * 8.0)))
	var hip := Vector2(inner.end.x - 16.0, base - 9.0 - bob)
	var neck := hip + Vector2(4, -9)
	draw_line(hip, neck, WHITE, 3.0)                                      # body
	draw_circle(neck + Vector2(2, -4), 2.5, WHITE)                        # head
	draw_line(neck + Vector2(-1, 1), neck + Vector2(-6, 4), WHITE, 2.0)   # back arm
	draw_line(neck + Vector2(0, 1), neck + Vector2(5, 5), WHITE, 2.0)     # front arm
	draw_line(hip, hip + Vector2(6, 4), WHITE, 2.0)                       # front leg...
	draw_line(hip + Vector2(6, 4), hip + Vector2(4, 9), WHITE, 2.0)
	draw_line(hip, hip + Vector2(-5, 5), WHITE, 2.0)                      # ...back leg kicked up
	draw_line(hip + Vector2(-5, 5), hip + Vector2(-9, 3), WHITE, 2.0)
	for i in 3:                                                           # speed lines behind it
		var y := hip.y - 6.0 + i * 4.0
		var dash := 5.0 - i
		draw_rect(Rect2(hip.x - 12.0 - dash, y, dash, 1), WHITE)


# the second panel: the same wave, and the figure riding on top of it, standing on a surfboard with its arms out
# for balance (a little bob), spray kicking up behind the board
func _draw_ride(panel: Rect2):
	var base := panel.end.y - 3.0
	draw_rect(Rect2(panel.position.x + 3.0, base, panel.size.x - 6.0, 1), WHITE)
	var x0 := panel.position.x + 6.0
	var wave := PackedVector2Array([Vector2(x0, base), Vector2(x0, base - 4.0), Vector2(x0 + 10.0, base - 11.0),
		Vector2(x0 + 20.0, base - 15.0), Vector2(x0 + 28.0, base - 16.0), Vector2(x0 + 35.0, base - 13.0),
		Vector2(x0 + 38.0, base - 8.0), Vector2(x0 + 35.0, base - 4.0), Vector2(x0 + 32.0, base - 8.0),
		Vector2(x0 + 29.0, base - 6.0), Vector2(x0 + 29.0, base)])
	draw_colored_polygon(wave, WHITE)
	draw_circle(Vector2(x0 + 33.0, base - 6.0), 2.5, BLUE)                  # the hollow under the lip
	var bob := roundf(sin(_t * 5.0))
	# the board, along the top of the wave, its nose kicked up
	var tail := Vector2(x0 + 11.0, base - 13.0 + bob)
	var nose := Vector2(x0 + 26.0, base - 18.0 + bob)
	draw_line(tail, nose, WHITE, 2.0)
	draw_rect(Rect2(nose + Vector2(0, -2), Vector2(2, 1)), WHITE)
	# the rider: feet apart on the board, a little crouch, arms out
	var hip := Vector2(x0 + 18.0, base - 21.0 + bob)
	var neck := hip + Vector2(1, -6)
	draw_line(hip, tail.lerp(nose, 0.25) + Vector2(0, -1), WHITE, 2.0)        # back leg
	draw_line(hip, tail.lerp(nose, 0.75) + Vector2(0, -1), WHITE, 2.0)        # front leg
	draw_line(hip, neck, WHITE, 3.0)                                          # body
	draw_circle(neck + Vector2(1, -3), 2.5, WHITE)                            # head
	draw_line(neck, neck + Vector2(-7, 1 - bob), WHITE, 2.0)                  # arms out
	draw_line(neck, neck + Vector2(7, -1 + bob), WHITE, 2.0)
	for i in 3:                                                               # spray off the tail
		draw_rect(Rect2(tail.x - 3.0 - i * 2.0, tail.y - 2.0 - i + roundf(sin(_t * 6.0 + i)), 1, 1), WHITE)


# the quicksand warning: a yellow triangle with a black border on a post, a figure sunk to its waist in wavy sand,
# arms up, slowly going under and bobbing back
func _draw_quicksand():
	draw_rect(Rect2(-3, -52, 6, 52), WOOD)
	draw_rect(Rect2(-3, -52, 2, 52), WOOD_LIGHT)
	draw_rect(Rect2(2, -52, 1, 52), WOOD_DARK)
	var top := Vector2(0, -104)
	var left := Vector2(-32, -48)
	var right := Vector2(32, -48)
	draw_colored_polygon(PackedVector2Array([top + Vector2(0, -2), left + Vector2(-2, 1), right + Vector2(2, 1)]), Pixel.INK)
	draw_colored_polygon(PackedVector2Array([top, left, right]), WARN_INK)
	var inset := 4.0
	var it := top + Vector2(0, inset * 2.0)
	var il := left + Vector2(inset * 1.7, -inset)
	var ir := right + Vector2(-inset * 1.7, -inset)
	draw_colored_polygon(PackedVector2Array([it, il, ir]), WARN_YELLOW)
	# the figure, sinking and bobbing back up
	var sink := roundf((sin(_t * 1.6) * 0.5 + 0.5) * 3.0)
	var sand_y := -62.0
	var hip := Vector2(0, sand_y + 2.0 + sink)
	var neck := hip + Vector2(0, -9)
	var head := neck + Vector2(0, -4)
	if head.y + 3.0 < sand_y:
		draw_circle(head, 3.0, WARN_INK)
	if neck.y < sand_y:
		draw_line(neck, Vector2(0, minf(hip.y, sand_y)), WARN_INK, 3.0)            # body, down into the sand
	var wave := sin(_t * 6.0) * 1.5
	draw_line(neck + Vector2(0, 1), neck + Vector2(-6, -7 + wave), WARN_INK, 2.0)   # arms up, waving
	draw_line(neck + Vector2(0, 1), neck + Vector2(6, -7 - wave), WARN_INK, 2.0)
	# the sand: two wavy rows, the top one over the figure's waist
	for row in 2:
		var y := sand_y + row * 4.0
		var x := -18.0 + row * 3.0
		while x < 18.0 - row * 3.0:
			var dy := roundf(sin(x * 0.6 + _t * 2.0 + row) * 1.0)
			draw_rect(Rect2(x, y + dy, 3, 2), WARN_INK)
			x += 4.0
	for i in 3:                                                                  # grains flicking up
		var gx := -8.0 + i * 8.0
		var gy := sand_y - 3.0 - roundf(absf(sin(_t * 3.0 + i * 2.0)) * 3.0)
		draw_rect(Rect2(gx, gy, 1, 1), WARN_INK)


# the drain sign's beat (1.8s, shared by the plaque and the first panel): how full the charge is (0-1), -1 = let go
func _charge() -> float:
	var beat := fmod(_t, 1.8)
	if beat < 0.2 or beat >= 1.5:
		return -1.0
	return clampf((beat - 0.2) / 0.9, 0.0, 1.0)


# the drain plaque: the W key held down while a little charge bar fills, flashing white when it's full
func _draw_hold_w(plaque: Rect2):
	var k := _charge()
	var held := k >= 0.0
	Pixel.draw_key(self, plaque.position + Vector2(4, 3), 15, "W", held, held)
	var bar := Rect2(plaque.position + Vector2(24, 8), Vector2(19, 5))
	draw_rect(bar.grow(1.0), Pixel.INK)
	draw_rect(bar, Pixel.PALE)
	if held:
		var full := k >= 1.0
		draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * k), bar.size.y)),
			WHITE if full and fmod(_t, 0.16) < 0.08 else Pixel.MUSTARD)


# two wavy rows of water across a panel at y
func _water_rows(panel: Rect2, y: float, from := 0.0, to := 1.0):
	for row in 2:
		var x := panel.position.x + 3.0 + panel.size.x * from + row * 2.0
		while x < panel.position.x + panel.size.x * to - 5.0:
			var dy := roundf(sin(x * 0.5 + _t * 3.0 + row * 2.0))
			draw_rect(Rect2(x, y + row * 3.0 + dy, 3, 1), WHITE)
			x += 4.0


# the drain sign's first panel: the figure standing in the water up to its shins on the left, facing right, blade
# raised overhead and charging (sparks pull in to its tip, and a ring at full charge), and the shark's fin circling
# in the water on the right (Morgan's call: figure left, shark right)
func _draw_charge(panel: Rect2):
	var base := panel.end.y - 3.0
	draw_rect(Rect2(panel.position.x + 3.0, base, panel.size.x - 6.0, 1), WHITE)       # the bed
	var surf := base - 6.0
	_water_rows(panel, surf)
	# the fin, gliding back and forth, with a wake
	var swim := sin(_t * 1.5)
	var fx := roundf(panel.end.x - 18.0 + swim * 5.0)
	var lean := 1.0 if cos(_t * 1.5) >= 0.0 else -1.0                            # swept back the way it goes
	draw_colored_polygon(PackedVector2Array([Vector2(fx - 4.0, surf), Vector2(fx - lean * 2.0, surf - 9.0),
		Vector2(fx + 4.0, surf)]), WHITE)
	for i in 2:
		draw_rect(Rect2(fx - lean * (7.0 + i * 3.0) - 1.0, surf - 1.0 - i, 2, 1), WHITE)
	# the figure, facing the fin, a little crouch as it charges
	var k := _charge()
	var dip := 1.0 if k >= 0.0 else 0.0
	var feet := Vector2(panel.position.x + 18.0, base)
	var hip := feet + Vector2(0, -8.0 + dip)
	var neck := hip + Vector2(-1, -8)
	draw_line(hip, feet + Vector2(-3, 0), WHITE, 2.0)                            # legs, in the water
	draw_line(hip, feet + Vector2(3, 0), WHITE, 2.0)
	draw_line(hip, neck, WHITE, 3.0)                                             # body
	draw_circle(neck + Vector2(1, -3), 2.5, WHITE)                              # head
	var hands := neck + Vector2(-2, -6)
	draw_line(neck, hands, WHITE, 2.0)                                           # arms up
	var tip := hands + Vector2(-7, -3)
	draw_line(hands, tip, WHITE, 2.0)                                            # the blade, held back overhead
	if k >= 1.0:                                                                 # full: a ring flashes round the tip
		draw_arc(tip, 3.0 + fmod(_t * 20.0, 3.0), 0.0, TAU, 12, WHITE, 1.0)
	elif k >= 0.0:                                                               # charging: sparks pulling in
		for i in 4:
			var a := i * TAU / 4.0 + _t * 4.0
			var r := 6.0 * (1.0 - k) + 2.0
			draw_rect(Rect2((tip + Vector2(cos(a), sin(a)) * r).round(), Vector2(1, 1)), WHITE)


# the drain sign's second panel: the water rolling away to both ends as two curling walls, the bed dry between
# them, and the shark stranded on it in the middle, on its belly, flopping
func _draw_stranded(panel: Rect2):
	var base := panel.end.y - 3.0
	draw_rect(Rect2(panel.position.x + 3.0, base, panel.size.x - 6.0, 1), WHITE)
	var roll := roundf(absf(sin(_t * 3.0)) * 2.0)
	_curl(Vector2(panel.position.x + 13.0 - roll, base), -1.0)
	_curl(Vector2(panel.end.x - 13.0 + roll, base), 1.0)
	# the shark, nose left: a fat body, a forked tail, the dorsal fin, a blue eye and mouth; hops now and then
	var flop := fmod(_t, 0.9)
	var hop := roundf(sin(flop / 0.3 * PI) * 3.0) if flop < 0.3 else 0.0
	var tilt := 0.25 * sin(flop / 0.3 * PI) if flop < 0.3 else 0.0
	var c := Vector2(panel.get_center().x - 1.0, base - 4.0 - hop)
	draw_set_transform(c, tilt, Vector2(0.85, 0.85))      # a bit smaller, to fit between the walls
	var body := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		body.append(Vector2(cos(a) * 11.0, sin(a) * 4.5))
	draw_colored_polygon(body, WHITE)
	draw_colored_polygon(PackedVector2Array([Vector2(9, 0), Vector2(16, -6), Vector2(14, 0), Vector2(16, 5)]), WHITE)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -4), Vector2(2, -9), Vector2(4, -4)]), WHITE)
	draw_rect(Rect2(-7, -2, 1, 1), BLUE)                                         # eye
	draw_line(Vector2(-11, 1), Vector2(-5, 2), BLUE, 1.0)                        # mouth, gasping
	draw_set_transform(Vector2.ZERO)
	if flop < 0.3:                                                               # two "!" over it as it flops
		for i in 2:                                                              # (bigger, Morgan's call)
			var top := Vector2(c.x - 7.0 + i * 11.0, c.y - 19.0 - i)
			draw_rect(Rect2(top, Vector2(2, 5)), WHITE)
			draw_rect(Rect2(top + Vector2(0, 6), Vector2(2, 2)), WHITE)


# a small wall of water rolling away along the bed, its lip curling over the way it goes (dir), spray ahead of it
func _curl(foot: Vector2, dir: float):
	var pts := PackedVector2Array()
	for p: Vector2 in [Vector2(-10, 0), Vector2(-7, -5), Vector2(-2, -10), Vector2(2, -12), Vector2(6, -10),
			Vector2(7, -6), Vector2(5, -4), Vector2(3, -7), Vector2(1, -6), Vector2(2, 0)]:
		pts.append(foot + Vector2(p.x * dir, p.y))
	if dir < 0.0:
		pts.reverse()
	draw_colored_polygon(pts, WHITE)
	for i in 3:
		draw_rect(Rect2(foot.x + dir * (8.0 + i * 2.0), foot.y - 10.0 + i * 3.0 + roundf(sin(_t * 5.0 + i)), 1, 1), WHITE)
