extends RefCounted
# A 5x7 pixel font and keyboard key caps in BOOM's style, drawn with plain rects at the game's own
# resolution. Used by the tutorial (tutorial_hud.gd and tutorial.gd). The combo HUD has its own copy of
# the few letters it needs; these match them, plus the rest of the alphabet and some punctuation.
# "#" = a lit pixel. Every glyph is 7 rows tall; widths vary.
# Text inside {braces} is highlighted (drawn in the highlight colours; the braces aren't drawn).

# BOOM's palette, taken from Sprite/PsV3.png (same as code/combo_hud.gd)
const WHITE := Color(1, 1, 1)
const OFF_WHITE := Color(0.925, 0.875, 0.859)
const PALE := Color(0.737, 0.659, 0.635)
const MUSTARD := Color(0.8, 0.678, 0.294)
const ORANGE := Color(0.827, 0.4, 0.094)
const RUST := Color(0.765, 0.322, 0.086)
const RED := Color(0.553, 0.055, 0.055)
const BROWN := Color(0.384, 0.251, 0.129)
const TEAL := Color(0.447, 0.722, 0.808)
const TEAL_DARK := Color(0.22, 0.58, 0.694)
const INK := Color(0.208, 0.153, 0.357)      # the hat's indigo, used for outlines
# the living background's leaf greens, for "done"
const GREEN := Color("a4bf68")
const GREEN_DARK := Color("76964a")

const HIGHLIGHT := [MUSTARD, RUST, OFF_WHITE]   # fill, shade, light

const KEY_H := 15            # a key cap: 12 tall face + 3 tall edge under it

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"s": ["....", "....", ".###", "#...", ".##.", "...#", "###."],    # lower case, for "+1s" (a capital S read as a 5)
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	",": ["..", "..", "..", "..", "..", ".#", "#."],
	":": [".", ".", "#", ".", ".", "#", "."],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	"-": ["...", "...", "...", "###", "...", "...", "..."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"/": ["...#", "...#", "..#.", "..#.", ".#..", ".#..", "#..."],
	"(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
	"→": [".....", "..#..", "...#.", "#####", "...#.", "..#..", "....."],
	"←": [".....", "..#..", ".#...", "#####", ".#...", "..#..", "....."],
	"✓": [".....", "....#", "...#.", "#..#.", "#.#..", ".#...", "....."],
	"♥": [".#.#.", "#####", "#####", "#####", ".###.", "..#..", "....."],
	"*": ["..#..", "#.#.#", ".###.", "#.#.#", "..#..", ".....", "....."],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}


# the lit pixels of `text` at `pos` (top left), each font pixel s game pixels big, as cells:
# [Rect2, row, char index, alpha, white, highlighted]. Change a cell's rect, alpha (1 = as drawn) or
# white (true = drawn white) to animate single letters. italic: rows lean right towards the top.
static func cells(text: String, pos: Vector2, s: int, italic := false) -> Array:
	var out := []
	var x := pos.x
	var idx := 0
	var hi := false
	for ch in text:
		if ch == "{":
			hi = true
			continue
		if ch == "}":
			hi = false
			continue
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		for row in 7:
			var line: String = g[row]
			var lean := floorf((6 - row) * s / 3.0) if italic else 0.0
			for col in line.length():
				if line[col] == "#":
					out.append([Rect2(x + col * s + lean, pos.y + row * s, s, s), row, idx, 1.0, false, hi])
		var first: String = g[0]
		x += (first.length() + 1) * s
		idx += 1
	return out


static func width(text: String, s: int) -> float:
	var w := 0
	for ch in text:
		if ch == "{" or ch == "}":
			continue
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		var first: String = g[0]
		w += (first.length() + 1) * s
	return maxf(w - s, 0.0)


# number of drawn characters (braces don't count)
static func char_count(text: String) -> int:
	return text.replace("{", "").replace("}", "").length()


# drop shadow, 1px indigo outline, then the fill: light top row, shaded bottom rows.
# colors = [fill, shade, light]; highlighted cells use hi instead.
static func draw_cells(canvas: CanvasItem, list: Array, colors: Array, a := 1.0, hi: Array = HIGHLIGHT, shadow := true):
	if shadow:
		for c in list:
			var r: Rect2 = c[0].grow(1.0)
			canvas.draw_rect(Rect2(r.position + Vector2(1, 1), r.size), Color(BROWN, 0.5 * a * c[3]))
	for c in list:
		canvas.draw_rect(c[0].grow(1.0), Color(INK, a * c[3]))
	for c in list:
		var cols: Array = hi if c[5] else colors
		var row: int = c[1]
		var col: Color = cols[2] if row == 0 else (cols[1] if row >= 5 else cols[0])
		if c[4]:
			col = WHITE
		canvas.draw_rect(c[0], Color(col, a * c[3]))


# a keyboard key cap, top left at pos, w wide. pressed: the face sinks into its edge.
# lit: a real key press (mustard face).
static func draw_key(canvas: CanvasItem, pos: Vector2, w: int, label: String, pressed: bool, lit: bool, a := 1.0):
	var face_h := KEY_H - 3
	var depth := 1 if pressed else 3
	var top := pos.y + (2.0 if pressed else 0.0)
	var h := face_h + depth
	# outline with the corners left out, so it reads rounded
	canvas.draw_rect(Rect2(pos.x, top - 1, w, h + 2), Color(INK, a))
	canvas.draw_rect(Rect2(pos.x - 1, top, w + 2, h), Color(INK, a))
	canvas.draw_rect(Rect2(pos.x, top + face_h, w, depth), Color(RUST if lit else PALE, a))
	canvas.draw_rect(Rect2(pos.x, top, w, face_h), Color(MUSTARD if lit else OFF_WHITE, a))
	canvas.draw_rect(Rect2(pos.x + 1, top, w - 2, 1), Color(OFF_WHITE if lit else WHITE, a))
	canvas.draw_rect(Rect2(pos.x, top + face_h - 1, w, 1), Color(RUST if lit else PALE, a))
	var lp := Vector2(pos.x + floorf((w - width(label, 1)) / 2.0), top + 2)
	for c in cells(label, lp, 1):
		canvas.draw_rect(c[0], Color(INK, a))
