extends CanvasLayer
# Combo counter in BOOM's pixel-art style: drawn at the game's own resolution in his palette,
# with a hand-made 5x7 pixel font.
# The player adds it in _ready.
# A hit = any enemy in the "enemies" group losing hp. Scripted moves (like the boss finisher's
# flurry) add hits directly with: get_tree().call_group("combo_hud", "add_hits", n)
# and can end the combo on the spot with: get_tree().call_group("combo_hud", "finish")
# Runs on real time, so hitstop freezes don't slow it down.

const WINDOW := 2.0          # seconds after the last hit before the combo ends
const SHOW_FROM := 2         # slides in on the second hit
const TICK := 0.045          # waiting hits count up at this pace...
const CATCH_UP := 6          # ...several per tick when more than this many are waiting

# BOOM's palette, taken from Sprite/PsV3.png
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

# [hits, word, fill, shade, light]. The last tier cycles through the others' colors.
const BASE := [0, "", OFF_WHITE, PALE, WHITE]
const TIERS := [
	[5, "NICE", MUSTARD, RUST, OFF_WHITE],
	[10, "GREAT", ORANGE, RED, MUSTARD],
	[20, "JUICY!", RED, BROWN, ORANGE],
	[35, "TROPICAL!!", TEAL, TEAL_DARK, WHITE],
	[50, "FRESH SQUEEZED", OFF_WHITE, PALE, WHITE],
]

# layout, in game pixels from the anchor (top right)
const NUM_S := 4                 # one font pixel of the number = 4 game pixels (5 when it punches)
const NUM_RIGHT := -34
const NUM_TOP := 8
const BAR := Rect2(-104, 46, 100, 3)

const GLYPHS := {
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
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}

var _art := Node2D.new()
var _hp := {}                # enemy instance id -> hp last frame

var _now := 0.0
var _count := 0              # hits counted
var _shown := 0              # hits on screen, counts up to _count
var _last_hit := -100.0
var _tick_left := 0.0
var _ending := false
var _locked := false         # after finish(): the count is final until this combo has left the screen
var _slide := 0.0            # 0 = off screen to the right, 1 = in place
var _punch := 0.0            # 1 on each hit, fades to 0
var _ring := 1.0             # progress 0..1 of each animation, 1 = finished
var _rank_pop := 1.0
var _drops := []             # juice drops: [pos, vel, life, color]

# the COUNTER banner (code/counter_chain.gd drives it through counter_start/counter_cut/counter_end)
var _ctr := Node2D.new()
var _ctr_start := -1.0       # real time it appeared, -1 = not showing
var _ctr_end := -1.0         # real time the counter finished: it holds a moment, then fades
var _ctr_cuts := 0
var _ctr_pop := 0.0


func _ready():
	layer = 10
	add_to_group("combo_hud")
	_art.visible = false
	_art.draw.connect(_draw_art)
	add_child(_art)
	_ctr.draw.connect(_draw_counter)
	add_child(_ctr)
	_now = Time.get_ticks_msec() / 1000.0


# scripted moves call this through the "combo_hud" group
func add_hits(n: int):
	if _locked:
		return
	if _ending:              # hit again while it was leaving: start a fresh combo
		_ending = false
		_count = 0
		_shown = 0
	_count += n
	_last_hit = Time.get_ticks_msec() / 1000.0


# a combo ender (the boss finisher's final cut): jump to the full total right away, one last pop,
# then ignore every hit until this combo has left the screen
func finish():
	if _count == 0 or _locked:
		return
	_shown = _count
	_locked = true
	_last_hit = Time.get_ticks_msec() / 1000.0
	_punch = 1.0
	_ring = 0.0
	_rank_pop = 0.0


func _process(_delta):
	var t := Time.get_ticks_msec() / 1000.0
	var dt := minf(t - _now, 0.1)
	_now = t

	var hits := _scan_hits()
	if hits > 0:
		add_hits(hits)

	if _shown < _count:
		_tick_left -= dt
		if _tick_left <= 0.0:
			var before := _shown
			_shown = mini(_shown + maxi(1, ceili(float(_count - _shown) / CATCH_UP)), _count)
			_tick_left = TICK
			_on_tick(before)

	if _count > 0 and not _ending and _shown == _count and t - _last_hit > WINDOW:
		if _slide > 0.0:
			_ending = true
			_punch = 1.0     # one last pop before it leaves
		else:
			_count = 0       # a single hit that never showed
			_shown = 0
			_locked = false

	if _ending:
		_slide = move_toward(_slide, 0.0, dt * 2.2)
		if _slide == 0.0:
			_ending = false
			_locked = false
			_count = 0
			_shown = 0
	elif _shown >= SHOW_FROM:
		_slide = move_toward(_slide, 1.0, dt * 4.0)

	_punch *= exp(-dt * 9.0)
	_ring = minf(_ring + dt / 0.3, 1.0)
	_rank_pop = minf(_rank_pop + dt / 0.3, 1.0)
	for d in _drops:
		d[0] += d[1] * dt
		d[1].y += 260.0 * dt
		d[2] -= dt
	_drops = _drops.filter(func(d): return d[2] > 0.0)

	var screen := get_viewport().get_visible_rect().size
	var slide := (1.0 - _ease_out_back(_slide)) * 180.0
	var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 3.0 * _punch
	_art.position = (Vector2(screen.x - 10.0 + slide, 40.0) + shake).round()
	_art.visible = _slide > 0.0
	_art.queue_redraw()

	_ctr_pop *= exp(-dt * 10.0)
	if _ctr_end >= 0.0 and t - _ctr_end > 0.9:
		_ctr_start = -1.0
		_ctr_end = -1.0
	_ctr.position = Vector2(roundf(screen.x / 2.0), 58.0)
	_ctr.visible = _ctr_start >= 0.0
	_ctr.queue_redraw()


# ---------- the COUNTER banner ----------
func counter_start():
	_ctr_start = Time.get_ticks_msec() / 1000.0
	_ctr_end = -1.0
	_ctr_cuts = 0


func counter_cut(cuts: int):
	_ctr_cuts = cuts
	_ctr_pop = 1.0


func counter_end():
	_ctr_end = Time.get_ticks_msec() / 1000.0


# "COUNTER!" slams in and steps down to size, two bars sweep in from opposite sides,
# and from the second cut a chain count punches up underneath
func _draw_counter():
	if _ctr_start < 0.0:
		return
	var age := _now - _ctr_start
	var a := 1.0
	if _ctr_end >= 0.0:
		a = 1.0 - clampf((_now - _ctr_end - 0.5) / 0.4, 0.0, 1.0)
	var word := "COUNTER!"
	var screen_w := get_viewport().get_visible_rect().size.x
	var bar_w := _width(word, 4) + 80.0
	var p := _ease_out(clampf(age / 0.15, 0.0, 1.0))
	var x_top := roundf(lerpf(-screen_w, -bar_w / 2.0, p))     # from the left
	var x_bottom := roundf(lerpf(screen_w, -bar_w / 2.0, p))   # from the right
	_ctr.draw_rect(Rect2(x_top, -20, bar_w, 3), Color(INK, a))
	_ctr.draw_rect(Rect2(x_top, -20, bar_w, 1), Color(MUSTARD, a))
	_ctr.draw_rect(Rect2(x_bottom, 17, bar_w, 3), Color(INK, a))
	_ctr.draw_rect(Rect2(x_bottom, 19, bar_w, 1), Color(MUSTARD, a))
	var s := 6 if age < 0.05 else (5 if age < 0.1 else 4)
	var w := _width(word, s)
	_text(_ctr, word, Vector2(roundf(-w / 2.0), -roundf(3.5 * s)), s, ORANGE, RED, MUSTARD, a)
	if _ctr_cuts >= 2:
		var cs := 3 if _ctr_pop > 0.5 else 2
		var chain := "X" + str(_ctr_cuts)
		_text(_ctr, chain, Vector2(roundf(-_width(chain, cs) / 2.0), 24.0), cs, OFF_WHITE, PALE, WHITE, a)


func _scan_hits() -> int:
	var hits := 0
	var seen := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		var hp = e.get("hp")
		if hp == null:
			continue
		var id: int = e.get_instance_id()
		seen[id] = true
		if _hp.has(id) and hp < _hp[id]:
			hits += 1
		_hp[id] = hp
	for id in _hp.keys():
		if not seen.has(id):
			_hp.erase(id)
	return hits


func _on_tick(before: int):
	_punch = 1.0
	_ring = 0.0
	var drops := 5
	if _tier_index(_shown) > _tier_index(before):
		_rank_pop = 0.0
		drops = 16
	if _shown >= SHOW_FROM:
		var tier := _tier(_shown)
		var center := _num_center(NUM_S)
		for i in drops:
			var dir := Vector2.from_angle(randf_range(-PI * 0.95, -PI * 0.05))
			var col: Color = tier[2] if i % 3 != 0 else tier[4]
			_drops.append([center, dir * randf_range(40.0, 110.0), randf_range(0.4, 0.7), col])


func _tier_index(hits: int) -> int:
	var found := -1
	for i in TIERS.size():
		if hits >= TIERS[i][0]:
			found = i
	return found


# [hits, word, fill, shade, light] for this many hits
func _tier(hits: int) -> Array:
	var i := _tier_index(hits)
	if i < 0:
		return BASE
	if i == TIERS.size() - 1:
		var src: Array = TIERS[int(_now / 0.1) % (TIERS.size() - 1)]
		return [TIERS[i][0], TIERS[i][1], src[2], src[3], src[4]]
	return TIERS[i]


func _num_center(s: int) -> Vector2:
	return Vector2(NUM_RIGHT - _width(str(_shown), s) / 2.0, NUM_TOP + 3.5 * NUM_S)


func _draw_art():
	var a := clampf(_slide * 2.0, 0.0, 1.0)
	var tier := _tier(_shown)
	var fill: Color = tier[2]
	var shade: Color = tier[3]
	var light: Color = tier[4]

	# pixel ring burst
	if _ring < 1.0:
		var rr := lerpf(10.0, 44.0, _ease_out(_ring))
		var center := _num_center(NUM_S)
		for k in 28:
			var p := (center + Vector2.from_angle(k * TAU / 28.0) * rr).round()
			_art.draw_rect(Rect2(p, Vector2(2, 2)), Color(light, (1.0 - _ring) * a))

	# the number: one font-pixel bigger and white for a moment on each hit, growing up and left
	var s := NUM_S + (1 if _punch > 0.6 else 0)
	var num := str(_shown)
	var flash := _punch > 0.75
	var top := NUM_TOP + 7 * NUM_S - 7 * s
	_text(_art, num, Vector2(NUM_RIGHT - _width(num, s), top), s,
		WHITE if flash else fill, WHITE if flash else shade, WHITE if flash else light, a)
	_text(_art, "HITS", Vector2(NUM_RIGHT + 4, NUM_TOP + 7 * NUM_S - 7), 1, fill, shade, light, a)

	# rank word: slams in big and steps down to size
	var word: String = tier[1]
	if word != "":
		var rs := 4 if _rank_pop < 0.2 else (3 if _rank_pop < 0.45 else 2)
		_text(_art, word, Vector2(-2 - _width(word, rs), 4 - 7 * rs), rs, fill, shade, light, a)

	# time left in the combo: drains toward the number
	var left := 0.0 if _ending else 1.0 - clampf((_now - _last_hit) / WINDOW, 0.0, 1.0)
	_art.draw_rect(BAR.grow(1.0), Color(INK, a))
	var fw := roundf(BAR.size.x * left)
	if fw > 0.0:
		_art.draw_rect(Rect2(BAR.end.x - fw, BAR.position.y, fw, BAR.size.y), Color(fill, a))
		_art.draw_rect(Rect2(BAR.end.x - fw, BAR.position.y - 1, 1, BAR.size.y + 2), Color(WHITE, a))

	# juice drops
	for d in _drops:
		var pos: Vector2 = d[0]
		var life: float = d[2]
		var col: Color = d[3]
		_art.draw_rect(Rect2(pos.round(), Vector2(2, 2)), Color(col, clampf(life * 4.0, 0.0, 1.0) * a))


# pixel text: drop shadow, 1px indigo outline, then the fill (light top row, shaded bottom rows)
func _text(canvas: CanvasItem, text: String, pos: Vector2, s: int, fill: Color, shade: Color, light: Color, a: float):
	var cells := _cells(text, pos, s)
	for c in cells:
		var r: Rect2 = c[0]
		canvas.draw_rect(Rect2(r.grow(1.0).position + Vector2(1, 1), r.grow(1.0).size), Color(BROWN, 0.5 * a))
	for c in cells:
		var r: Rect2 = c[0]
		canvas.draw_rect(r.grow(1.0), Color(INK, a))
	for c in cells:
		var r: Rect2 = c[0]
		var row: int = c[1]
		var col := light if row == 0 else (shade if row >= 5 else fill)
		canvas.draw_rect(r, Color(col, a))


# the lit font pixels of `text` as [Rect2, row]. Rows lean right towards the top (pixel italics).
func _cells(text: String, pos: Vector2, s: int) -> Array:
	var out := []
	var x := pos.x
	for ch in text:
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		for row in 7:
			var line: String = g[row]
			var lean := floorf((6 - row) * s / 3.0)
			for col in line.length():
				if line[col] == "#":
					out.append([Rect2(x + col * s + lean, pos.y + row * s, s, s), row])
		var gw: String = g[0]
		x += (gw.length() + 1) * s
	return out


func _width(text: String, s: int) -> float:
	var w := 0
	for ch in text:
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		var gw: String = g[0]
		w += (gw.length() + 1) * s
	return maxf(w - s, 0.0)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_out_back(x: float) -> float:
	return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
