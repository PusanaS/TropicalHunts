extends CanvasLayer
# The tutorial's on-screen explanations, in BOOM's pixel style like the combo counter: drawn at the game's
# own resolution with rects only, in his palette, with the 5x7 pixel font (code/design/pixel_font.gd).
# code/design/tutorial.gd drives it:
#   show_card(step, number, total)  a station's card. Its title slams in big in the middle of the screen,
#                                   then flies up to the top; the keys rise into a dark band at the bottom
#                                   and act out how to press them. They light up when you press the real key.
#   add_progress(world_pos)         a juice drop flies from that spot in the world into the next progress pip
#   clear(word) / finale()          once the drops have landed: the CLEAR stamp / the ending
#   fail(text)                      once the drops have landed: the pips shake, drain, and a tip shows
#   toast(text)                     a short tip above the keys
#   banner(lines, sub, hold)        big text in the middle (the intro)
# Runs on real time, so hit-freezes and the counter's time stop don't slow it down.

const Pixel := preload("res://code/design/pixel_font.gd")

# the keys a card can show: [label, width, the input it mirrors]
const KEYS := {
	"LEFT": ["←", 15, "ui_left"],
	"RIGHT": ["→", 15, "ui_right"],
	"SPACE": ["SPACE", 41, "ui_accept"],
	"Q": ["Q", 15, "attack_light"],
	"W": ["W", 15, "attack_heavy"],
}

# a card's entrance, in seconds after it appears
const T_BADGE := 0.05
const T_LETTERS := 0.12          # the first title letter starts dropping in...
const T_LETTER_STEP := 0.035     # ...and each next one this much later
const T_SHINE := 0.55            # a light sweeps across the title
const T_FLY := 1.05              # the title flies up to the top...
const FLY_TIME := 0.35
const T_BAND := 1.15             # ...the dark band opens at the bottom...
const T_KEYS := 1.25             # ...the keys rise into it...
const T_HINT := 1.35             # ...the hint ripples in under them...
const T_PIPS := 1.4              # ...and the progress pips pop in under the title
# the hint lines under the keys (each step's "hint" in tutorial.gd) are hidden (Morgan's call, 2026-10-08: the
# playtesters never read them): the band shows just the keys. true brings them back.
const SHOW_HINTS := false

const TITLE_TOP := 8.0           # the title's top edge once it's up
const INTRO_Y := 0.36            # where it first slams in (share of the screen height)
const PIP_GAP := 11.0
const FLIGHT_TIME := 0.45        # a juice drop flying from the world to its pip
const STAMP_HOLD := 1.0          # the CLEAR stamp holds this long, then its letters drop away
const GO_DELAY := 1.3            # after the stamp: GO arrows until the next card
const KEY_GAP := 5.0
const METER_W := 48.0            # the bar beside a key you hold down
const SHINE_EVERY := 5.0         # the title catches the light again this often

# a progress pip is a juice drop
const DROP := ["...#...", "..###..", ".#####.", ".#####.", "#######", "#######", ".#####.", "..###.."]
const SLOT := Color(0.12, 0.09, 0.2)       # an empty pip or meter (the gallop meter's empty colour)
const TITLE := [Pixel.MUSTARD, Pixel.RUST, Pixel.OFF_WHITE]
const DONE := [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE]
const TEXT := [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE]
const WARN := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]
const RAINBOW := [[Pixel.MUSTARD, Pixel.RUST, Pixel.OFF_WHITE], [Pixel.ORANGE, Pixel.RED, Pixel.MUSTARD],
	[Pixel.TEAL, Pixel.TEAL_DARK, Pixel.WHITE], [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE]]
const JUICE := [Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE, Pixel.RED]

var meter_source: Callable       # (kind) -> 0..1 while the player is really holding that key, else -1
var station_total := 0
var station_index := 0           # stations before this one are done

var _canvas := Node2D.new()
var _now := 0.0

var _card := {}
var _num := 0
var _card_t := -100.0
var _keys_w := 0.0
var _band_w := 0.0
var _band_h := 0.0
var _filled := 0                 # pips drawn full
var _pip_t := []                 # when each pip filled
var _flights := []               # [from (screen), start time, pip index]
var _pending_clear := ""         # the stamp waits for the flying drops to land ("*" = the ending)
var _pending_fail := ""
var _cleared_t := -100.0
var _stamp_word := ""
var _stamp_t := -100.0           # the stamp outlives its card: the next card waits for it
var _fail_t := -100.0
var _old := {}                   # the last card's title, sliding away
var _toast_text := ""
var _toast_t := -100.0
var _banner := {}
var _finale := false
var prompt := ""                 # blinks near the bottom when set (PRESS ENTER FOR LEVEL 1)
var _drops := []                 # juice drops: [pos, vel, life, color]
var _bursts := []                # pixel rings: [center, start time, color]
var _key_centers := {}           # action -> centres of its key caps on screen (for the press rings)
var _down := {}                  # action -> held last frame
var _pressed_t := {}             # action -> last real press (the demo pauses for a moment after one)


func _ready():
	layer = 11                   # over the combo counter
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	_now = _real()


# ---------- what tutorial.gd calls ----------
func show_card(step: Dictionary, number: int, total: int):
	# the last station was cleared but its stamp hadn't shown yet (you went straight on): show it now
	if _pending_clear != "" and _pending_clear != "*":
		_flights.clear()
		_start_stamp(_pending_clear)
	if not _card.is_empty():
		_old = {"title": _card["title"], "num": _num, "t": _real(), "done": _cleared_t >= _card_t}
	_card = step
	_num = number
	station_total = total
	if _stamp_end() > _real():
		# a stamp is still playing in the middle (you went straight on): skip the big entrance and put
		# the card straight up top, so its pips are there for whatever you hit next
		_card_t = _real() - (T_FLY + FLY_TIME)
	else:
		_card_t = maxf(_real(), _banner_end())     # waits for the intro to clear the middle of the screen
	var goal: int = step["goal"]
	_filled = 0
	_pip_t.resize(goal)
	_pip_t.fill(-100.0)
	_flights.clear()
	_pending_clear = ""
	_pending_fail = ""
	_cleared_t = -100.0
	_fail_t = -100.0
	_toast_text = ""
	var keys: Array = step["keys"]
	_keys_w = 0.0
	for i in keys.size():
		_keys_w += _item_width(keys[i]) + (KEY_GAP if i > 0 else 0.0)
	if SHOW_HINTS:
		var hint: String = step["hint"]
		var lines := hint.split("\n")
		var hint_w := 0.0
		for line in lines:
			hint_w = maxf(hint_w, Pixel.width(line, 1))
		_band_w = maxf(maxf(_keys_w, hint_w) + 32.0, 160.0)
		_band_h = 5.0 + Pixel.KEY_H + 7.0 + lines.size() * 10.0 - 3.0 + 6.0
	else:                                         # just the keys
		_band_w = maxf(_keys_w + 32.0, 96.0)
		_band_h = 5.0 + Pixel.KEY_H + 5.0


func add_progress(world_pos: Vector2):
	if _pip_t.is_empty():
		return
	var from := get_viewport().get_canvas_transform() * world_pos
	var idx := mini(_filled + _flights.size(), _pip_t.size() - 1)
	_flights.append([from, maxf(_real(), _card_t + T_PIPS), idx])   # once the pips are there to fly to


func clear(word: String):
	_pending_clear = word
	_resolve()


func finale():
	_pending_clear = "*"
	_resolve()


func fail(text: String):
	_pending_fail = text
	_resolve()


func toast(text: String):
	_toast_text = text
	_toast_t = _real()


func banner(lines: Array, sub: String, hold: float, rainbow := false):
	_banner = {"lines": lines, "sub": sub, "t": _real(), "hold": hold, "rainbow": rainbow}


# ---------- time ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


# when the stamp will have cleared off (0 if there isn't one)
func _stamp_end() -> float:
	if _stamp_word == "":
		return 0.0
	return _stamp_t + STAMP_HOLD + 0.6


# when the intro banner will have cleared off (0 if there isn't one)
func _banner_end() -> float:
	if _banner.is_empty() or _finale:
		return 0.0
	return float(_banner["t"]) + float(_banner["hold"]) + 0.6


func _process(_delta):
	var t := _real()
	var dt := minf(t - _now, 0.1)
	_now = t

	var landed := _flights.filter(func(f): return _now - f[1] >= FLIGHT_TIME)
	_flights = _flights.filter(func(f): return _now - f[1] < FLIGHT_TIME)
	for f in landed:
		var idx: int = f[2]
		_pip_t[idx] = _now
		_filled = maxi(_filled, idx + 1)
		var p := _pip_pos(idx)
		_bursts.append([p, _now, Pixel.ORANGE])
		_spray(p, 6, 70.0)
	if not landed.is_empty() or _pending_clear != "" or _pending_fail != "":
		_resolve()
	if _fail_t > 0.0 and _now - _fail_t >= 0.45:       # the shake is over: drain the pips
		_fail_t = -100.0
		_filled = 0
		_pip_t.fill(-100.0)

	_watch_keys()

	if _finale and not _banner.is_empty():              # the ending: juice fountains from both corners
		var screen := get_viewport().get_visible_rect().size
		for side in [0.0, 1.0]:
			if randf() < 0.7:
				var dir: float = 1.0 if side == 0.0 else -1.0
				_drops.append([Vector2(screen.x * side, screen.y), Vector2(dir * randf_range(40, 140), randf_range(-260, -180)),
					randf_range(1.0, 1.5), JUICE[randi() % JUICE.size()]])
	for d in _drops:
		d[0] += d[1] * dt
		d[1].y += 260.0 * dt
		d[2] -= dt
	_drops = _drops.filter(func(d): return d[2] > 0.0)
	_bursts = _bursts.filter(func(b): return _now - b[1] < 0.3)
	_canvas.queue_redraw()


# the stamp and the fail tip wait until every flying drop has landed, and the card has finished coming in
func _resolve():
	if not _flights.is_empty() or _real() - _card_t < T_PIPS + 0.1:
		return
	if _pending_fail != "":
		_fail_t = _now
		toast(_pending_fail)
		_pending_fail = ""
	if _pending_clear == "*":
		_pending_clear = ""
		_cleared_t = _real()
		_stamp_word = ""
		_finale = true
		banner(["TUTORIAL", "COMPLETE!"], "NOW GO HUNT SOME FRUIT!", 6.0, true)
		_spray(_screen_mid(), 40, 200.0)
	elif _pending_clear != "":
		_start_stamp(_pending_clear)


func _start_stamp(word: String):
	_stamp_word = word
	_pending_clear = ""
	_cleared_t = _real()
	_stamp_t = _cleared_t
	_spray(_screen_mid(), 28, 180.0)


# a real key press: a ring pops around every key cap showing that key
func _watch_keys():
	for key in KEYS:
		var action: String = KEYS[key][2]
		if not InputMap.has_action(action):
			continue
		var down := Input.is_action_pressed(action)
		if down and not _down.get(action, false):
			_pressed_t[action] = _now
			for c in _key_centers.get(action, []):
				_bursts.append([c, _now, Pixel.MUSTARD])
		_down[action] = down


func _spray(at: Vector2, count: int, speed: float):
	for i in count:
		var dir := Vector2.from_angle(randf_range(-PI * 0.95, -PI * 0.05))
		_drops.append([at, dir * randf_range(speed * 0.4, speed), randf_range(0.4, 0.8), JUICE[i % JUICE.size()]])


func _screen_mid() -> Vector2:
	var s := get_viewport().get_visible_rect().size
	return Vector2(roundf(s.x / 2.0), roundf(s.y * 0.42))


# ---------- drawing ----------
func _draw_all():
	var screen := get_viewport().get_visible_rect().size
	_key_centers.clear()
	_draw_dots()
	_draw_old_title(screen)
	if not _card.is_empty():
		_draw_title(screen)
		_draw_pips()
		_draw_band(screen)
	_draw_flights()
	_draw_stamp(screen)
	_draw_banner(screen)
	_draw_go(screen)
	_draw_toast(screen)
	if prompt != "" and int(_now * 2.0) % 2 == 0:
		var w := Pixel.width(prompt, 1)
		Pixel.draw_cells(_canvas, Pixel.cells(prompt, Vector2(roundf(screen.x / 2.0 - w / 2.0), screen.y - 24.0), 1), TEXT)
	for b in _bursts:
		var k := (_now - float(b[1])) / 0.3
		var r := lerpf(3.0, 13.0, _ease_out(k))
		var center: Vector2 = b[0]
		for i in 10:
			var p := (center + Vector2.from_angle(i * TAU / 10.0) * r).round()
			_canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color(b[2], 1.0 - k))
	for d in _drops:
		var pos: Vector2 = d[0]
		_canvas.draw_rect(Rect2(pos.round(), Vector2(2, 2)), Color(d[3], clampf(float(d[2]) * 4.0, 0.0, 1.0)))


# one segment per station along the top left: done, this one (pulsing), still to come
func _draw_dots():
	if station_total <= 0 or _card.is_empty() or _now < _card_t:
		return
	for i in station_total:
		var p := Vector2(8 + i * 6, 8)
		_canvas.draw_rect(Rect2(p - Vector2(1, 1), Vector2(6, 6)), Pixel.INK)
		var col := SLOT
		if i < station_index:
			col = Pixel.MUSTARD
		elif i == station_index:
			col = Pixel.OFF_WHITE.lerp(Pixel.PALE, 0.5 + 0.5 * sin(_now * 6.0))
		_canvas.draw_rect(Rect2(p, Vector2(4, 4)), col)


# where the title, its number badge and the bars go. fly: 0 = big in the middle, 1 = up top.
func _title_layout(screen: Vector2, title: String, num: int, fly: float) -> Dictionary:
	var big := fly < 0.5
	var ts := 3 if big else 2
	var ns := 2 if big else 1
	var num_text := "%02d" % num
	var tw := Pixel.width(title, ts) + floorf(6.0 * ts / 3.0)
	var badge := Vector2(Pixel.width(num_text, ns) + 6.0, 7.0 * ns + 6.0)
	var w := badge.x + 3.0 * ts + tw
	var cy := lerpf(screen.y * INTRO_Y, TITLE_TOP + 7.0, fly)
	var x0 := roundf(screen.x / 2.0 - w / 2.0)
	return {
		"ts": ts, "ns": ns, "num": num_text, "w": w, "x0": x0,
		"badge": Rect2(x0, roundf(cy - badge.y / 2.0), badge.x, badge.y),
		"pos": Vector2(x0 + badge.x + 3.0 * ts, roundf(cy - 3.5 * ts)),
	}


func _draw_title(screen: Vector2):
	var age := _now - _card_t
	var fly := _ease_in_out(_k(age, T_FLY, FLY_TIME))
	var title: String = _card["title"]
	var lay := _title_layout(screen, title, _num, fly)
	var ts: int = lay["ts"]
	var pos: Vector2 = lay["pos"]
	var w: float = lay["w"]
	var done := _cleared_t >= _card_t and _now - _cleared_t > 0.1

	# two bars sweep in from opposite sides, then pull into the middle as the title flies up
	var bars_out := _k(age, T_FLY, FLY_TIME * 0.6)
	if bars_out < 1.0:
		var bars_in := _ease_out(_k(age, 0.0, 0.15))
		var bw := (w + 80.0) * (1.0 - bars_out)
		var home := screen.x / 2.0 - bw / 2.0
		_bar(roundf(lerpf(-screen.x, home, bars_in)), pos.y - 9.0, bw, true)
		_bar(roundf(lerpf(screen.x, home, bars_in)), pos.y + 7.0 * ts + 6.0, bw, false)

	if age >= T_BADGE:
		_draw_badge(lay["badge"], lay["num"], lay["ns"], age < T_BADGE + 0.06, done)

	# letters drop in one by one with a bounce, flashing white as they land
	var shine := _shine_x(age, pos.x, w)
	var keep := []
	for c in Pixel.cells(title, pos, ts, true):
		var li := _k(age, T_LETTERS + c[2] * T_LETTER_STEP, 0.2)
		if li <= 0.0:
			continue
		var r: Rect2 = c[0]
		r.position.y += roundf((1.0 - _ease_out_back(li)) * -14.0)
		c[0] = r
		c[3] = clampf(li * 3.0, 0.0, 1.0)
		c[4] = li < 0.4 or _in_shine(r, pos.y, shine, ts)
		keep.append(c)
	Pixel.draw_cells(_canvas, keep, DONE if done else TITLE)

	if done:      # a tick pops in after the title
		var tk := _now - _cleared_t - 0.1
		var s := ts + 1 if tk < 0.1 else ts
		var tick := Pixel.cells("✓", Vector2(pos.x + Pixel.width(title, ts) + 3.0 * ts, pos.y + 7.0 * ts - 7.0 * s), s)
		for c in tick:
			c[4] = tk < 0.06
		Pixel.draw_cells(_canvas, tick, DONE)


# the previous station's title slides up and out when a new card comes in
func _draw_old_title(screen: Vector2):
	if _old.is_empty():
		return
	var k := (_now - float(_old["t"])) / 0.25
	if k >= 1.0:
		_old = {}
		return
	var title: String = _old["title"]
	var lay := _title_layout(screen, title, _old["num"], 1.0)
	var pos: Vector2 = lay["pos"]
	var dy := roundf(-24.0 * _ease_in(k))
	var cs := Pixel.cells(title, pos + Vector2(0, dy), lay["ts"], true)
	Pixel.draw_cells(_canvas, cs, DONE if _old["done"] else TITLE, 1.0 - k)


func _bar(x: float, y: float, w: float, light_on_top: bool):
	_canvas.draw_rect(Rect2(x, y, w, 3), Pixel.INK)
	_canvas.draw_rect(Rect2(x, y if light_on_top else y + 2.0, w, 1), Pixel.MUSTARD)


func _draw_badge(r: Rect2, num: String, s: int, flash: bool, done: bool):
	_canvas.draw_rect(Rect2(r.position.x, r.position.y - 1, r.size.x, r.size.y + 2), Pixel.INK)
	_canvas.draw_rect(Rect2(r.position.x - 1, r.position.y, r.size.x + 2, r.size.y), Pixel.INK)
	var fill := Pixel.WHITE if flash else (Pixel.GREEN if done else Pixel.MUSTARD)
	var shade := Pixel.GREEN_DARK if done else Pixel.RUST
	_canvas.draw_rect(r, fill)
	_canvas.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), shade)
	_canvas.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, 1), Pixel.OFF_WHITE)
	for c in Pixel.cells(num, r.position + Vector2(3, 3), s):
		_canvas.draw_rect(c[0], Pixel.INK)


# x of the light sweeping across the title (it leans like the letters), or far away when there's none
func _shine_x(age: float, x0: float, w: float) -> float:
	var k := _k(age, T_SHINE, 0.3)
	if k <= 0.0 or k >= 1.0:
		var since := age - (T_FLY + FLY_TIME + 1.0)
		if since < 0.0:
			return -1000.0
		k = fmod(since, SHINE_EVERY) / 0.4
		if k >= 1.0:
			return -1000.0
	return lerpf(x0 - 30.0, x0 + w + 30.0, k)


func _in_shine(r: Rect2, top: float, shine: float, s: int) -> bool:
	return absf(r.position.x + (r.position.y - top) * 0.6 - shine) < 2.0 * s


# ---------- progress pips ----------
func _pip_gap() -> float:
	var g := PIP_GAP
	for label in _card.get("labels", []):
		g = maxf(g, Pixel.width(label, 1) + 8.0)
	return g


func _pip_pos(i: int) -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	var n := _pip_t.size()
	var gap := _pip_gap()
	return Vector2(roundf(screen.x / 2.0 - (n - 1) * gap / 2.0 + i * gap), TITLE_TOP + 24.0)


func _draw_pips():
	var age := _now - _card_t
	var labels: Array = _card.get("labels", [])
	var failing := _fail_t > 0.0
	for i in _pip_t.size():
		var pa := _k(age, T_PIPS + i * 0.05, 0.15)
		if pa <= 0.0:
			continue
		var p := _pip_pos(i)
		if failing:
			p.x += 1.0 if int(_now * 40.0) % 2 == 0 else -1.0
		var full := i < _filled
		var since: float = _now - float(_pip_t[i])
		var s := 2 if pa < 0.6 or since < 0.12 else 1
		_draw_drop(p, s, full, since < 0.06, failing and full)
		if i < labels.size():
			var label: String = labels[i]
			var cs := Pixel.cells(label, Vector2(roundf(p.x - Pixel.width(label, 1) / 2.0), p.y + 7.0), 1)
			Pixel.draw_cells(_canvas, cs, TEXT if full else [Pixel.PALE, Pixel.PALE, Pixel.PALE], 1.0 if full else 0.6, Pixel.HIGHLIGHT, false)


func _draw_drop(center: Vector2, s: int, full: bool, white: bool, red: bool):
	var tl := (center - Vector2(3.5 * s, 4.0 * s)).round()
	for outline in [true, false]:
		for row in DROP.size():
			var line: String = DROP[row]
			for col in line.length():
				if line[col] != "#":
					continue
				var r := Rect2(tl + Vector2(col * s, row * s), Vector2(s, s))
				if outline:
					_canvas.draw_rect(r.grow(1.0), Pixel.INK)
					continue
				var c := SLOT
				if white:
					c = Pixel.WHITE
				elif red:
					c = Pixel.RED
				elif full:
					c = Pixel.OFF_WHITE if col == 2 and (row == 3 or row == 4) else (Pixel.RUST if row >= 6 else Pixel.ORANGE)
				_canvas.draw_rect(r, c)


# juice drops arcing from where it happened up into their pips, with a little trail
func _draw_flights():
	for f in _flights:
		if _now < float(f[1]):
			continue                  # waiting for its pip to appear
		var k := clampf((_now - float(f[1])) / FLIGHT_TIME, 0.0, 1.0)
		var from: Vector2 = f[0]
		var to := _pip_pos(f[2])
		var ctrl := Vector2(from.x, to.y + 10.0)
		for j in range(3, -1, -1):
			var e := _ease_in_out(clampf(k - j * 0.05, 0.0, 1.0))
			var p := from.lerp(ctrl, e).lerp(ctrl.lerp(to, e), e).round()
			if j == 0:
				_draw_drop(p, 1, true, k < 0.15, false)
			else:
				_canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color(Pixel.MUSTARD, 1.0 - j * 0.25))


# ---------- the band at the bottom: keys and hint ----------
func _item_width(it: Dictionary) -> float:
	if it.has("sep"):
		return Pixel.width(it["sep"], 1) + 2.0
	var info: Array = KEYS[it["key"]]
	return float(info[1]) + (METER_W + 5.0 if it.has("meter") else 0.0)


func _draw_band(screen: Vector2):
	var age := _now - _card_t
	var fold := 0.0
	if _cleared_t >= _card_t:
		fold = _k(_now - _cleared_t, STAMP_HOLD, 0.25)
	var open := _ease_out(_k(age, T_BAND, 0.25)) * (1.0 - _ease_in(fold))
	if open <= 0.0:
		return
	var bw := roundf(_band_w * open)
	var by := roundf(screen.y - 6.0 - _band_h)
	var bx := roundf(screen.x / 2.0 - bw / 2.0)
	_canvas.draw_rect(Rect2(bx, by, bw, _band_h), Color(Pixel.INK, 0.8))
	_canvas.draw_rect(Rect2(bx, by - 1, bw, 1), Pixel.MUSTARD)
	_canvas.draw_rect(Rect2(bx, by + _band_h, bw, 1), Pixel.MUSTARD)
	for x in [bx - 2.0, bx + bw]:
		_canvas.draw_rect(Rect2(x, by - 1, 2, 3), Pixel.MUSTARD)
		_canvas.draw_rect(Rect2(x, by + _band_h - 2, 2, 3), Pixel.MUSTARD)
	if fold == 0.0 and open < 0.98:
		return
	var a := clampf(1.0 - fold * 4.0, 0.0, 1.0)
	if a > 0.0:
		_draw_keys(screen, by, age, a)
		if SHOW_HINTS:
			_draw_hint(screen, by, age, a)


# the keys act out their presses on a loop; a real press shows instead (lit) and pauses the act a moment
func _draw_keys(screen: Vector2, by: float, age: float, a: float):
	var items: Array = _card["keys"]
	var period: float = _card.get("period", 1.2)
	var cyc := fmod(maxf(age - T_KEYS, 0.0), period)
	var x := roundf(screen.x / 2.0 - _keys_w / 2.0)
	var y := by + 5.0
	for i in items.size():
		var it: Dictionary = items[i]
		var w := _item_width(it)
		var ka := _k(age, T_KEYS + i * 0.06, 0.3)
		if ka > 0.0:
			var rise := roundf((1.0 - _ease_out_back(ka)) * 18.0)
			var alpha := clampf(ka * 3.0, 0.0, 1.0) * a
			if it.has("sep"):
				var cs := Pixel.cells(it["sep"], Vector2(x + 1.0, y + 4.0 + rise), 1)
				Pixel.draw_cells(_canvas, cs, [Pixel.PALE, Pixel.PALE, Pixel.OFF_WHITE], alpha, Pixel.HIGHLIGHT, false)
			else:
				var info: Array = KEYS[it["key"]]
				var kw: int = info[1]
				var action: String = info[2]
				var live := InputMap.has_action(action) and Input.is_action_pressed(action)
				var demo := -1.0             # how far through an acted press, -1 = not pressed
				if _now - float(_pressed_t.get(action, -100.0)) > 1.5:
					for win in it["press"]:
						if cyc >= win[0] and cyc < win[1]:
							demo = (cyc - win[0]) / (win[1] - win[0])
				Pixel.draw_key(_canvas, Vector2(x, y + rise), kw, info[0], live or demo >= 0.0, live, alpha)
				var centers: Array = _key_centers.get(action, [])
				centers.append(Vector2(x + kw / 2.0, y + 6.0))
				_key_centers[action] = centers
				if it.has("meter"):
					_draw_meter(Vector2(x + kw + 5.0, y + 5.0 + rise), it, demo, alpha)
		x += w + KEY_GAP


# the bar beside a held key: shows the real hold (speed build-up, W charge) while you do it
func _draw_meter(p: Vector2, it: Dictionary, demo: float, a: float):
	var v := -1.0
	if meter_source.is_valid():
		v = meter_source.call(it["meter"])
	if v < 0.0:
		v = maxf(demo, 0.0)
	_canvas.draw_rect(Rect2(p.x - 1, p.y - 1, METER_W + 2, 5), Color(Pixel.INK, a))
	_canvas.draw_rect(Rect2(p.x, p.y, METER_W, 3), Color(SLOT, a))
	var fw := roundf(METER_W * clampf(v, 0.0, 1.0))
	if fw > 0.0:
		var full := v >= 1.0
		var col := Pixel.WHITE if full and int(_now * 12.0) % 2 == 0 else Pixel.MUSTARD
		_canvas.draw_rect(Rect2(p.x, p.y, fw, 3), Color(col, a))
		_canvas.draw_rect(Rect2(p.x, p.y, fw, 1), Color(Pixel.OFF_WHITE, a))
	for tick in it.get("ticks", []):
		_canvas.draw_rect(Rect2(p.x + roundf(METER_W * tick), p.y, 1, 3), Color(Pixel.INK, a))


func _draw_hint(screen: Vector2, by: float, age: float, a: float):
	var hint: String = _card["hint"]
	var y := by + 5.0 + Pixel.KEY_H + 7.0
	var j := 0                    # letters so far, for the ripple
	for line in hint.split("\n"):
		var x := roundf(screen.x / 2.0 - Pixel.width(line, 1) / 2.0)
		var keep := []
		for c in Pixel.cells(line, Vector2(x, y), 1):
			var k := _k(age, T_HINT + (j + c[2]) * 0.012, 0.15)
			if k <= 0.0:
				continue
			var r: Rect2 = c[0]
			r.position.y += roundf((1.0 - _ease_out(k)) * 4.0)
			c[0] = r
			c[3] = k
			keep.append(c)
		Pixel.draw_cells(_canvas, keep, TEXT, a, Pixel.HIGHLIGHT, false)
		j += Pixel.char_count(line)
		y += 10.0


# ---------- big moments ----------
# CLEAR!: slams in big and steps down to size with a flash and a burst of rays, holds, then its
# letters drop away one by one
func _draw_stamp(screen: Vector2):
	if _stamp_word == "" or _stamp_t < 0.0:
		return
	var ct := _now - _stamp_t
	if ct > STAMP_HOLD + 0.8:
		return
	var center := _screen_mid()
	if ct < 0.08:
		_canvas.draw_rect(Rect2(Vector2.ZERO, screen), Color(Pixel.WHITE, 0.2 * (1.0 - ct / 0.08)))
	if ct < 0.45:
		var e := _ease_out(ct / 0.45)
		for i in 16:
			var dir := Vector2.from_angle(i * TAU / 16.0 + 0.1) * Vector2(1.6, 1.0)
			var r0 := 26.0 + 80.0 * e
			var d := 0.0
			while d < 24.0 * (1.0 - e):
				var p := (center + dir * (r0 + d)).round()
				_canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color(Pixel.MUSTARD if i % 2 == 0 else Pixel.OFF_WHITE, 1.0 - e))
				d += 3.0
	var s := 7 if ct < 0.04 else (6 if ct < 0.08 else 5)
	var w := Pixel.width(_stamp_word, s) + floorf(6.0 * s / 3.0)
	var pos := Vector2(roundf(center.x - w / 2.0), roundf(center.y - 3.5 * s))
	var keep := []
	for c in Pixel.cells(_stamp_word, pos, s, true):
		var fall: float = ct - STAMP_HOLD - c[2] * 0.04
		if fall > 0.0:
			var r: Rect2 = c[0]
			r.position.y += roundf(0.5 * 900.0 * fall * fall)
			c[0] = r
			c[3] = clampf(1.0 - fall / 0.35, 0.0, 1.0)
			if c[3] <= 0.0:
				continue
		c[4] = ct < 0.08
		keep.append(c)
	Pixel.draw_cells(_canvas, keep, TITLE)


# big centred text (the intro, the ending): bars sweep in, letters drop in, a light passes over them;
# after `hold` the letters drop away. Rainbow: every letter cycles through the colours, in a wave.
func _draw_banner(screen: Vector2):
	if _banner.is_empty():
		return
	var bt := _now - float(_banner["t"])
	var out := bt - float(_banner["hold"])
	if out > 1.0:
		_banner = {}
		return
	var lines: Array = _banner["lines"]
	var sub: String = _banner["sub"]
	var rainbow: bool = _banner["rainbow"]
	var s := 4
	var line_h := 7.0 * s + 8.0
	var top := roundf(screen.y * 0.4 - (lines.size() * line_h + 10.0) / 2.0)
	var widest := 0.0
	for text in lines:
		widest = maxf(widest, Pixel.width(text, s))

	var bars_in := _ease_out(_k(bt, 0.0, 0.15))
	var bars_out := _k(out, 0.0, 0.3)
	if bars_out < 1.0:
		var bw := (widest + 90.0) * (1.0 - bars_out)
		var home := screen.x / 2.0 - bw / 2.0
		_bar(roundf(lerpf(-screen.x, home, bars_in)), top - 10.0, bw, true)
		_bar(roundf(lerpf(screen.x, home, bars_in)), top + lines.size() * line_h + 14.0, bw, false)

	var n := 0                    # letters so far
	for li in lines.size():
		var text: String = lines[li]
		var w := Pixel.width(text, s) + floorf(6.0 * s / 3.0)
		var pos := Vector2(roundf(screen.x / 2.0 - w / 2.0), top + li * line_h)
		var shine := _shine_x(bt - 0.2, pos.x, w)
		var by_letter := {}
		for c in Pixel.cells(text, pos, s, true):
			var k := _k(bt, 0.1 + (n + c[2]) * 0.05, 0.22)
			if k <= 0.0:
				continue
			var r: Rect2 = c[0]
			r.position.y += roundf((1.0 - _ease_out_back(k)) * -18.0)
			var fall: float = out - (n + c[2]) * 0.03
			if fall > 0.0:
				r.position.y += roundf(0.5 * 900.0 * fall * fall)
				c[3] = clampf(1.0 - fall / 0.35, 0.0, 1.0)
			else:
				c[3] = clampf(k * 3.0, 0.0, 1.0)
			c[0] = r
			c[4] = k < 0.4 or _in_shine(r, pos.y, shine, s)
			if c[3] > 0.0:
				var list: Array = by_letter.get(c[2], [])
				list.append(c)
				by_letter[c[2]] = list
		for idx in by_letter:
			var colors: Array = TITLE
			if rainbow:
				colors = RAINBOW[int(_now * 8.0 - idx * 0.7 + 100.0) % RAINBOW.size()]
			Pixel.draw_cells(_canvas, by_letter[idx], colors)
		n += Pixel.char_count(text)

	if sub != "":
		var w := Pixel.width(sub, 1)
		var pos := Vector2(roundf(screen.x / 2.0 - w / 2.0), top + lines.size() * line_h + 2.0)
		var keep := []
		for c in Pixel.cells(sub, pos, 1):
			var k := _k(bt, 0.1 + n * 0.05 + c[2] * 0.015, 0.15)
			if k <= 0.0:
				continue
			var r: Rect2 = c[0]
			r.position.y += roundf((1.0 - _ease_out(k)) * 4.0)
			c[0] = r
			c[3] = k * (1.0 - clampf(out / 0.3, 0.0, 1.0))
			keep.append(c)
		Pixel.draw_cells(_canvas, keep, TEXT)


# after a clear: GO and three arrows chasing to the right, until the next station's card comes in
func _draw_go(screen: Vector2):
	if _finale or _card.is_empty() or _cleared_t < _card_t:
		return
	var gt := _now - _cleared_t - GO_DELAY
	if gt < 0.0:
		return
	var slide := (1.0 - _ease_out_back(clampf(gt / 0.3, 0.0, 1.0))) * 60.0
	var x := roundf(screen.x - 14.0 + slide + sin(_now * 6.0) * 2.0)
	var y := roundf(screen.y * 0.42)
	for i in 3:
		var k := fmod(_now * 2.5 - i * 0.3 + 10.0, 1.0)
		var cs := Pixel.cells("→", Vector2(x - (3 - i) * 12.0, y - 7.0), 2)
		Pixel.draw_cells(_canvas, cs, TITLE, 0.35 + 0.65 * (1.0 - k))
	Pixel.draw_cells(_canvas, Pixel.cells("GO", Vector2(x - 34.0, y - 26.0), 2, true), TITLE)


# a short tip just above the band: pops in with a shake, then fades
func _draw_toast(screen: Vector2):
	if _toast_text == "":
		return
	var tt := _now - _toast_t
	if tt > 2.4:
		_toast_text = ""
		return
	var a := 1.0 - _k(tt, 2.1, 0.3)
	var w := Pixel.width(_toast_text, 1)
	var y := roundf(screen.y - 6.0 - _band_h - 18.0) if not _card.is_empty() else roundf(screen.y - 24.0)
	var x := roundf(screen.x / 2.0 - w / 2.0) + roundf(sin(tt * 60.0) * 2.0 * (1.0 - _k(tt, 0.0, 0.3)))
	var back := Rect2(x - 6.0, y - 3.0, w + 12.0, 13.0)
	_canvas.draw_rect(back, Color(Pixel.INK, 0.8 * a))
	_canvas.draw_rect(Rect2(back.position.x, back.position.y - 1, back.size.x, 1), Color(Pixel.ORANGE, a))
	_canvas.draw_rect(Rect2(back.position.x, back.end.y, back.size.x, 1), Color(Pixel.ORANGE, a))
	var keep := []
	for c in Pixel.cells(_toast_text, Vector2(x, y), 1):
		var k := _k(tt, c[2] * 0.006, 0.08)
		if k <= 0.0:
			continue
		c[3] = k
		keep.append(c)
	Pixel.draw_cells(_canvas, keep, WARN, a, TEXT, false)


# ---------- easing ----------
func _k(t: float, start: float, length: float) -> float:
	return clampf((t - start) / length, 0.0, 1.0)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in(x: float) -> float:
	return x * x * x


func _ease_in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


func _ease_out_back(x: float) -> float:
	return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
