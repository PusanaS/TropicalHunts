extends CanvasLayer
# A level's on-screen text, in BOOM's pixel style like the tutorial and the combo counter: drawn with rects
# at the game's own resolution, in his palette, with the 5x7 pixel font (code/design/pixel_font.gd).
# code/design/level.gd drives it:
#   intro(number, name)        LEVEL 1 / JUNGLE RUN slams in, holds, then its letters drop away
#   timer_text                 the run's time, top left
#   checkpoint()               a little flag and CHECKPOINT! drop in from the top
#   toast(text)                a short tip near the bottom ({braces} highlight words)
#   oops()                     a white flash and OOPS! (fell in: back to the last checkpoint)
#   boss_intro(boss, name)     the boss's name slams in, then its health bar sits at the top
#   clear(time, rank, last)    LEVEL CLEAR!, the time, the rank letter, then PRESS ENTER (THE END on the last)
# Runs on real time. It's in the group "level_hud", so hazards can call_group("level_hud", "toast", text).

const Pixel := preload("res://code/design/pixel_font.gd")
# the clear screen's sounds (Morgan's picks): a jingle as LEVEL CLEAR! comes in, and "oh yeah" as the rank
# letter slams in
const SUCCESS_SOUND := preload("res://sounds/SUCCESS_meldix-success-340660.mp3")
const SUCCESS_DB := -3.0
const SUCCESS_SKIP := 0.08                # the file starts with 80ms of silence
const OH_YEAH_SOUND := preload("res://sounds/OH_YEAH_freesound_community-oh-yeah-106157.mp3")
const OH_YEAH_DB := 0.0
const OH_YEAH_SKIP := 2.78                # the voice only starts 2.8s into the file
const RANK_AT := 1.4                      # the rank letter slams in this long after LEVEL CLEAR! (and "oh yeah")

const TITLE := [Pixel.MUSTARD, Pixel.RUST, Pixel.OFF_WHITE]
const TEXT := [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE]
const WARN := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]
const BOSS := [Pixel.ORANGE, Pixel.RED, Pixel.MUSTARD]
const GOOD := [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE]
const RAINBOW := [[Pixel.MUSTARD, Pixel.RUST, Pixel.OFF_WHITE], [Pixel.ORANGE, Pixel.RED, Pixel.MUSTARD],
	[Pixel.TEAL, Pixel.TEAL_DARK, Pixel.WHITE], [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE]]
const RANK_COLORS := {"A": [Pixel.MUSTARD, Pixel.RUST, Pixel.OFF_WHITE], "B": [Pixel.TEAL, Pixel.TEAL_DARK, Pixel.WHITE],
	"C": [Pixel.PALE, Pixel.BROWN, Pixel.OFF_WHITE]}
const JUICE := [Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE, Pixel.RED]
const SLOT := Color(0.12, 0.09, 0.2)
const INTRO_HOLD := 1.8
const BOSS_HOLD := 1.3
const BAR_W := 220.0

var timer_text := ""
var final_title := "THE END!"    # the clear screen's title on the last level (level.gd sets it)
var boss: Node = null

var _canvas := Node2D.new()
var _now := 0.0
var _intro := {}                 # {"small", "big", "t"}
var _cp_t := -100.0
var _toast_text := ""
var _toast_t := -100.0
var _oops_t := -100.0
var _boss_t := -100.0
var _boss_name := ""
var _bar := 1.0                  # health shown (0..1)
var _bar_lag := 1.0              # the white chunk that drains after a hit
var _bar_hit_t := -100.0
var _clear := {}                 # {"t", "time", "rank", "last"}
var _drops := []                 # juice drops: [pos, vel, life, colour]
var _success_sound := AudioStreamPlayer.new()
var _oh_yeah_sound := AudioStreamPlayer.new()
var _oh_yeah_played := false


func _ready():
	layer = 11
	add_to_group("level_hud")
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	_success_sound.stream = SUCCESS_SOUND
	_success_sound.volume_db = SUCCESS_DB
	add_child(_success_sound)
	_oh_yeah_sound.stream = OH_YEAH_SOUND
	_oh_yeah_sound.volume_db = OH_YEAH_DB
	add_child(_oh_yeah_sound)
	_now = _real()


func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------- what level.gd calls ----------
func intro(number: int, name_text: String):
	_intro = {"small": "LEVEL %d" % number, "big": name_text, "t": _real()}


func checkpoint():
	_cp_t = _real()


func toast(text: String):
	_toast_text = text
	_toast_t = _real()


func oops():
	_oops_t = _real()


func boss_intro(b: Node, title: String):
	boss = b
	_boss_name = title
	_boss_t = _real()
	_bar = 1.0
	_bar_lag = 1.0


func clear(time_text: String, rank: String, last: bool):
	_clear = {"t": _real(), "time": time_text, "rank": rank, "last": last}
	_success_sound.play(SUCCESS_SKIP)
	_oh_yeah_played = false
	var s := get_viewport().get_visible_rect().size
	_spray(Vector2(s.x / 2.0, s.y * 0.3), 40, 220.0)


func clear_ready() -> bool:
	return not _clear.is_empty() and _real() - float(_clear["t"]) > 2.2


# ---------- every frame ----------
func _process(_delta):
	var t := _real()
	var dt := minf(t - _now, 0.1)
	_now = t
	if boss and is_instance_valid(boss) and _boss_t > 0.0:
		var hp = boss.get("hp")
		var max_hp = boss.get("max_hp")
		if hp != null and max_hp != null and float(max_hp) > 0.0:
			var f := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			if f < _bar:
				_bar_hit_t = _now
			_bar = f
	if _now - _bar_hit_t > 0.45:          # the white chunk catches up a moment after each hit
		_bar_lag = move_toward(_bar_lag, _bar, dt * 0.8)
	_bar_lag = maxf(_bar_lag, _bar)
	if not _clear.is_empty() and not _oh_yeah_played and _now - float(_clear["t"]) >= RANK_AT:
		_oh_yeah_played = true
		_oh_yeah_sound.play(OH_YEAH_SKIP)
	if not _clear.is_empty() and _now - float(_clear["t"]) < 5.0:    # juice fountains while LEVEL CLEAR shows
		var screen := get_viewport().get_visible_rect().size
		for side in [0.0, 1.0]:
			if randf() < 0.6:
				var dir: float = 1.0 if side == 0.0 else -1.0
				_drops.append([Vector2(screen.x * side, screen.y), Vector2(dir * randf_range(40, 140), randf_range(-260, -180)),
					randf_range(1.0, 1.5), JUICE[randi() % JUICE.size()]])
	for d in _drops:
		d[0] += d[1] * dt
		d[1].y += 260.0 * dt
		d[2] -= dt
	_drops = _drops.filter(func(d): return d[2] > 0.0)
	_canvas.queue_redraw()


func _spray(at: Vector2, count: int, speed: float):
	for i in count:
		var dir := Vector2.from_angle(randf_range(-PI * 0.95, -PI * 0.05))
		_drops.append([at, dir * randf_range(speed * 0.4, speed), randf_range(0.4, 0.8), JUICE[i % JUICE.size()]])


# ---------- drawing ----------
func _draw_all():
	var screen := get_viewport().get_visible_rect().size
	_draw_timer()
	_draw_boss_bar(screen)
	_draw_checkpoint(screen)
	_draw_intro(screen)
	_draw_boss_intro(screen)
	_draw_toast(screen)
	_draw_oops(screen)
	_draw_clear(screen)
	for d in _drops:
		var pos: Vector2 = d[0]
		_canvas.draw_rect(Rect2(pos.round(), Vector2(2, 2)), Color(d[3], clampf(float(d[2]) * 4.0, 0.0, 1.0)))


func _draw_timer():
	if timer_text == "" or not _clear.is_empty():
		return
	Pixel.draw_cells(_canvas, Pixel.cells(timer_text, Vector2(8, 8), 1), TEXT)


# letters drop in one by one with a bounce (flashing white as they land), and after `out` seconds they
# fall away. t = seconds since it started.
func _letters(text: String, pos: Vector2, s: int, t: float, colors: Array, out := INF, step := 0.04,
		rainbow := false) -> void:
	var by_letter := {}
	for c in Pixel.cells(text, pos, s, true):
		var k := _k(t, 0.08 + c[2] * step, 0.22)
		if k <= 0.0:
			continue
		var r: Rect2 = c[0]
		r.position.y += roundf((1.0 - _ease_out_back(k)) * -4.0 * s)
		var fall: float = t - out - c[2] * 0.03
		if fall > 0.0:
			r.position.y += roundf(0.5 * 900.0 * fall * fall)
			c[3] = clampf(1.0 - fall / 0.35, 0.0, 1.0)
		else:
			c[3] = clampf(k * 3.0, 0.0, 1.0)
		if c[3] <= 0.0:
			continue
		c[0] = r
		c[4] = k < 0.4
		var list: Array = by_letter.get(c[2], [])
		list.append(c)
		by_letter[c[2]] = list
	for idx in by_letter:
		var cols: Array = colors
		if rainbow:
			cols = RAINBOW[int(_now * 8.0 - idx * 0.7 + 100.0) % RAINBOW.size()]
		Pixel.draw_cells(_canvas, by_letter[idx], cols)


func _centered(text: String, y: float, s: int, screen: Vector2) -> Vector2:
	return Vector2(roundf(screen.x / 2.0 - (Pixel.width(text, s) + floorf(6.0 * s / 3.0)) / 2.0), roundf(y))


# two bars that sweep in from opposite sides, then pull into the middle
func _bars(screen: Vector2, top: float, bottom: float, width: float, t: float, out: float):
	var k_in := _ease_out(_k(t, 0.0, 0.15))
	var k_out := _k(t, out, 0.3)
	if k_out >= 1.0:
		return
	var w := width * (1.0 - k_out)
	var home := screen.x / 2.0 - w / 2.0
	for i in 2:
		var x := lerpf(-screen.x if i == 0 else screen.x, home, k_in)
		var y := top if i == 0 else bottom
		_canvas.draw_rect(Rect2(roundf(x), y, w, 3), Pixel.INK)
		_canvas.draw_rect(Rect2(roundf(x), y if i == 0 else y + 2.0, w, 1), Pixel.MUSTARD)


func _draw_intro(screen: Vector2):
	if _intro.is_empty():
		return
	var t := _now - float(_intro["t"])
	if t > INTRO_HOLD + 1.2:
		_intro = {}
		return
	var small: String = _intro["small"]
	var big: String = _intro["big"]
	var y := screen.y * 0.34
	_bars(screen, y - 10.0, y + 48.0, Pixel.width(big, 4) + 90.0, t, INTRO_HOLD)
	_letters(small, _centered(small, y, 2, screen), 2, t, TEXT, INTRO_HOLD)
	_letters(big, _centered(big, y + 18.0, 4, screen), 4, t - 0.2, TITLE, INTRO_HOLD - 0.2, 0.05)


func _draw_checkpoint(screen: Vector2):
	var t := _now - _cp_t
	if t > 1.8:
		return
	var drop := _ease_out_back(_k(t, 0.0, 0.25)) * (1.0 - _ease_in(_k(t, 1.5, 0.3)))
	var text := "CHECKPOINT!"
	var w := Pixel.width(text, 1) + 14.0
	var x := roundf(screen.x / 2.0 - w / 2.0)
	var y := roundf(lerpf(-16.0, 40.0, drop))
	_canvas.draw_rect(Rect2(x - 6, y - 4, w + 12, 15), Color(Pixel.INK, 0.8))
	_canvas.draw_rect(Rect2(x - 6, y - 5, w + 12, 1), Pixel.GREEN)
	_canvas.draw_rect(Rect2(x - 6, y + 11, w + 12, 1), Pixel.GREEN)
	# a little flag
	_canvas.draw_rect(Rect2(x, y - 2, 1, 10), Pixel.OFF_WHITE)
	for c in 6:
		var h := 5 - int(c * 0.7)
		var wave := roundf(sin(_now * 9.0 - c) * 0.8)
		_canvas.draw_rect(Rect2(x + 1 + c, y - 2 + wave + (5 - h) / 2, 1, h), Pixel.GREEN)
	Pixel.draw_cells(_canvas, Pixel.cells(text, Vector2(x + 12, y), 1), GOOD, 1.0, Pixel.HIGHLIGHT, false)


func _draw_toast(screen: Vector2):
	if _toast_text == "":
		return
	var tt := _now - _toast_t
	if tt > 2.8:
		_toast_text = ""
		return
	var a := 1.0 - _k(tt, 2.5, 0.3)
	var w := Pixel.width(_toast_text, 1)
	var y := roundf(screen.y - 30.0)
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


func _draw_oops(screen: Vector2):
	var t := _now - _oops_t
	if t > 1.0:
		return
	if t < 0.3:
		_canvas.draw_rect(Rect2(Vector2.ZERO, screen), Color(Pixel.WHITE, 0.6 * (1.0 - t / 0.3)))
	_letters("OOPS!", _centered("OOPS!", screen.y * 0.36, 3, screen), 3, t, WARN, 0.6, 0.03)


func _draw_boss_intro(screen: Vector2):
	var t := _now - _boss_t
	if t > BOSS_HOLD + 1.0 or _boss_name == "":
		return
	var y := screen.y * 0.36
	var s := 3 if Pixel.width(_boss_name, 4) > screen.x - 40.0 else 4
	_bars(screen, y - 12.0, y + 7.0 * s + 8.0, Pixel.width(_boss_name, s) + 90.0, t, BOSS_HOLD)
	_letters(_boss_name, _centered(_boss_name, y, s, screen), s, t, BOSS, BOSS_HOLD, 0.05)


func _draw_boss_bar(screen: Vector2):
	if _boss_t < 0.0 or _boss_name == "":
		return
	var t := _now - _boss_t
	var a := _k(t, BOSS_HOLD, 0.3)
	if not _clear.is_empty():
		a *= 1.0 - _k(_now - float(_clear["t"]), 0.0, 0.4)
	if a <= 0.0:
		return
	var x := roundf(screen.x / 2.0 - BAR_W / 2.0)
	var y := 20.0
	var name_pos := Vector2(roundf(screen.x / 2.0 - Pixel.width(_boss_name, 1) / 2.0), 8.0)
	Pixel.draw_cells(_canvas, Pixel.cells(_boss_name, name_pos, 1), BOSS, a, Pixel.HIGHLIGHT, false)
	_canvas.draw_rect(Rect2(x - 1, y - 1, BAR_W + 2, 7), Color(Pixel.INK, a))
	_canvas.draw_rect(Rect2(x, y, BAR_W, 5), Color(SLOT, a))
	var lag := roundf(BAR_W * _bar_lag)
	var fill := roundf(BAR_W * _bar)
	if lag > fill:
		_canvas.draw_rect(Rect2(x + fill, y, lag - fill, 5), Color(Pixel.WHITE, a))
	if fill > 0.0:
		var hit := _now - _bar_hit_t < 0.08
		_canvas.draw_rect(Rect2(x, y, fill, 5), Color(Pixel.WHITE if hit else Pixel.ORANGE, a))
		_canvas.draw_rect(Rect2(x, y, fill, 1), Color(Pixel.MUSTARD, a))
		_canvas.draw_rect(Rect2(x, y + 4, fill, 1), Color(Pixel.RUST, a))
	for i in range(1, 4):                 # quarter marks
		_canvas.draw_rect(Rect2(x + roundf(BAR_W * i / 4.0), y, 1, 5), Color(Pixel.INK, a))


func _draw_clear(screen: Vector2):
	if _clear.is_empty():
		return
	var t := _now - float(_clear["t"])
	_canvas.draw_rect(Rect2(Vector2.ZERO, screen), Color(Pixel.INK, 0.45 * _k(t, 0.0, 0.4)))
	var last: bool = _clear["last"]
	var title := final_title if last else "LEVEL CLEAR!"
	_letters(title, _centered(title, screen.y * 0.18, 4, screen), 4, t, TITLE, INF, 0.05, last)
	var time_text: String = "TIME " + String(_clear["time"])
	if t > 0.8:
		_letters(time_text, _centered(time_text, screen.y * 0.42, 2, screen), 2, t - 0.8, TEXT, INF, 0.02)
	var rank: String = _clear["rank"]
	if t > RANK_AT:
		var rt := t - RANK_AT
		var s := 8 if rt < 0.05 else (7 if rt < 0.1 else 6)
		var label := "RANK"
		var lw := Pixel.width(label, 2) + 8.0 + Pixel.width(rank, 6)
		var x := roundf(screen.x / 2.0 - lw / 2.0)
		var y := roundf(screen.y * 0.56)
		Pixel.draw_cells(_canvas, Pixel.cells(label, Vector2(x, y + 28.0), 2, true), TEXT)
		var colors: Array = RAINBOW[int(_now * 8.0) % RAINBOW.size()] if rank == "S" else RANK_COLORS.get(rank, TEXT)
		var cells := Pixel.cells(rank, Vector2(x + Pixel.width(label, 2) + 8.0, y + 42.0 - 7.0 * s), s, true)
		for c in cells:
			c[4] = rt < 0.08
		Pixel.draw_cells(_canvas, cells, colors)
	if last and t > 2.0:
		var thanks := "THANKS FOR PLAYING!"
		_letters(thanks, _centered(thanks, screen.y * 0.82, 2, screen), 2, t - 2.0, GOOD, INF, 0.02, true)
	elif not last and t > 2.2 and int(_now * 2.0) % 2 == 0:
		var press := "PRESS {ENTER} TO CONTINUE"
		Pixel.draw_cells(_canvas, Pixel.cells(press, _centered(press, screen.y * 0.85, 1, screen), 1), TEXT)


# ---------- easing ----------
func _k(t: float, start: float, length: float) -> float:
	return clampf((t - start) / length, 0.0, 1.0)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in(x: float) -> float:
	return x * x * x


func _ease_out_back(x: float) -> float:
	return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
