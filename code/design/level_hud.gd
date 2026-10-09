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
# the clear screen's sound (Morgan's pick): a jingle as LEVEL CLEAR! comes in. (The "oh yeah" was taken out,
# Morgan's call, 2026-10-08: it cheapened the game.)
const SUCCESS_SOUND := preload("res://sounds/SUCCESS_meldix-success-340660.mp3")
const SUCCESS_DB := -3.0
const SUCCESS_SKIP := 0.08                # the file starts with 80ms of silence
const RANK_AT := 1.4                      # (no count: the rank letter slams in this long after LEVEL CLEAR!)
# THE RANK REVEAL (Morgan's idea, 2026-10-09, the professor wanted the ranking to pop more): the time counts up to
# yours, a bar under it fills through the S / A / B / C zones, and the rank letter, in a slot machine window,
# starts on S. Each time the count passes a zone the letter spins like a reel and crashes onto the next rank
# (flash, shake, bits, an impact). When the count's done, the rank locks in with a big slam
const COUNT_AT := 0.8                      # the count starts this long after LEVEL CLEAR!...
const COUNT_MIN := 1.4                     # ...and takes this long, more for longer runs, up to COUNT_MAX
const COUNT_MAX := 3.0
const SPIN_TIME := 0.45                    # from one rank to the next: it shakes (SHAKE_TIME), drops out downward,
const SHAKE_TIME := 0.15                   # and the next one falls in from above and crashes into place
const DIRT := [Color("6b4424"), Color("8e5c30"), Color("4a2e18"), Color("b9a07a")]   # the crash's dirt
const RANK_BAR_W := 160.0
const RANKS := ["S", "A", "B", "C"]
const CRASH_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRASH_DB := -9.0

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
# the juice clock (level.gd's prototype switch): a countdown at the top instead of the timer
var juice_mode := false
var juice_left := 0.0
var _gain_t := -100.0
var _gain_text := ""
var _gain_sum := 0.0
var _loss_t := -100.0
var _loss_text := ""
var _fail_t := -100.0
var _card_t := -100.0            # the fail ending's THANKS FOR PLAYING card (bar_intro.gd, you said no)
# time on its way: each "+1s" pops up where you earned it, then swoops up into the countdown, and only counts
# when it lands there (juice_landed)
signal juice_landed(seconds: float)
var _flyers: Array = []          # [where it was earned (world), start (real time), flight time, seconds, text]
const FLY_HOVER := 0.25          # it pops up where you earned it for this long first
# A PENALTY ("-5s") CAN'T BE MISSED (Morgan's call, 2026-10-09): it's red, slams in at 4x the text size, settles at
# 3x shaking, hangs on for PENALTY_HOVER before it flies, the screen's edges flash red as you lose it and again as
# it lands, and the clock turns red and shakes
const PENALTY_HOVER := 0.75
const EDGE_FLASH := 0.35
var _pen_t := -100.0             # when a penalty last popped up (the red edges)
# the opening scene's line about the clock (bar_intro.gd, Morgan's call, 2026-10-08): level.gd hides the countdown
# while it plays, and juice_arrive() flies a red copy of the seconds she says up out of her bubble onto it. When
# it lands the countdown shows, punching in red
var juice_hidden := false
var _arrive := {}                # {"from" (screen), "t", "text"}
var _arrive_t := -100.0          # when it landed
const ARRIVE_POP := 0.35         # it floats up out of the bubble (popping to double size)...
const ARRIVE_FLY := 0.8          # ...then swoops up and over to the countdown
const RED := [Color("e8402e"), Color("a8201a"), Color("ff8a70")]
# the countdown shows whole seconds, and each new second pops in (the professor's idea, 2026-10-09): it comes in
# TICK_BIG times size and shrinks back over TICK_POP, then fades to TICK_FADE_TO by the next second (never out)
const TICK_POP := 0.2
const TICK_BIG := 1.6
const TICK_FADE_TO := 0.6
var _tick_t := -100.0            # when the number last changed
var _tick_sec := -1
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
var _clear := {}                 # {"t", "time", "rank", "last", "secs" (-1: no count), "ranks", "len"}
var _reel_at := 0                # the rank the reel shows (index in RANKS)
var _count_v := 0.0              # the time counted up so far: it stops at each zone's edge while the rank changes
var _spin_t := -1.0              # when the spin under way started (-1: not spinning)
var _crash_t := -100.0           # when it last crashed onto a rank
var _lock_t := -100.0            # when the final rank locked in
var _bits := []                  # the rank change's bits: [pos, vel, life, colour, size, gravity, starting life, dust?]
var _rings := []                 # its shockwaves along the ground: [centre, when]
var _crash_sound := AudioStreamPlayer.new()
var _drops := []                 # juice drops: [pos, vel, life, colour]
var _success_sound := AudioStreamPlayer.new()


func _ready():
	layer = 11
	add_to_group("level_hud")
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	_success_sound.stream = SUCCESS_SOUND
	_success_sound.volume_db = SUCCESS_DB
	_crash_sound.stream = CRASH_SOUND
	_crash_sound.volume_db = CRASH_DB
	_crash_sound.max_polyphony = 2
	add_child(_crash_sound)
	add_child(_success_sound)
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


# the juice clock: time added (a kill, a checkpoint) flashes by the countdown, adding up while it keeps coming
func juice_gain(seconds: float):
	if seconds < 0.0:                                # time lost: a red "-5s" by the countdown instead
		_loss_t = _real()
		_loss_text = "-%ds" % int(roundf(-seconds))
		return
	if _real() - _gain_t > 0.7:
		_gain_sum = 0.0
	_gain_sum += seconds
	_gain_t = _real()
	_gain_text = "+%ds" % int(roundf(_gain_sum))


# the seconds in her line (bar_intro.gd), at `from` (screen): a copy flies up onto the countdown, which then shows
func juice_arrive(from: Vector2, text: String):
	_arrive = {"from": from, "t": _real(), "text": text}


# time earned at `world` (a kill's spot): a "+1s" pops up there, then flies up into the countdown
func fly_gain(seconds: float, world: Vector2, delay := 0.0):
	var label := ("+%ds" % int(roundf(seconds))) if seconds >= 0.0 else ("-%ds" % int(roundf(-seconds)))
	_flyers.append([world, _real() + delay, randf_range(0.5, 0.7), seconds, label,
		PENALTY_HOVER if seconds < 0.0 else FLY_HOVER])
	if seconds < 0.0:
		_pen_t = _real() + delay


# time still on its way to the countdown
func pending_gain() -> float:
	var total := 0.0
	for f: Array in _flyers:
		total += maxf(float(f[3]), 0.0)          # (only time coming in: a penalty on its way doesn't count)
	return total


# where a flying "+1s" is: hovering where it was earned, then swooping (a curve up and over) into the clock
# (it keeps to its spot in the world, worked out on screen every frame: right after a respawn the camera's still
# catching up, and a "-5s" over the player came out off at the screen's edge)
func _flyer_pos(f: Array, screen: Vector2) -> Vector2:
	var from: Vector2 = get_viewport().get_canvas_transform() * (f[0] as Vector2)
	var t := _now - float(f[1])
	var hover: float = f[5]
	if t < hover:
		return from + Vector2(0, -roundf(10.0 * minf(t / 0.25, 1.0)))
	var k := clampf((t - hover) / float(f[2]), 0.0, 1.0)
	k = k * k
	var a := from + Vector2(0, -10)
	var to := Vector2(screen.x / 2.0, 14.0)
	var c := Vector2(lerpf(a.x, to.x, 0.3), minf(a.y, to.y) - 30.0)
	return a.lerp(c, k).lerp(c.lerp(to, k), k)


# the juice clock ran out
func out_of_juice():
	_fail_t = _real()


# you said no to trying again: THANKS FOR PLAYING!, and ENTER to try again (bar_intro.gd reloads)
func fail_card():
	_card_t = _real()


func boss_intro(b: Node, title: String):
	boss = b
	_boss_name = title
	_boss_t = _real()
	_bar = 1.0
	_bar_lag = 1.0


# the boss is beaten and an ending scene plays: its name and health bar go
func hide_boss():
	_boss_name = ""


func clear(time_text: String, rank: String, last: bool, seconds := -1.0, ranks := Vector3.ZERO):
	var count := clampf(COUNT_MIN + seconds * 0.01, COUNT_MIN, COUNT_MAX) if seconds >= 0.0 else 0.0
	_clear = {"t": _real(), "time": time_text, "rank": rank, "last": last, "secs": seconds, "ranks": ranks,
		"len": count}
	_reel_at = 0 if seconds >= 0.0 else maxi(RANKS.find(rank), 0)
	_count_v = 0.0
	_spin_t = -1.0
	_lock_t = -100.0 if seconds >= 0.0 else _real() + RANK_AT
	_success_sound.play(SUCCESS_SKIP)
	var s := get_viewport().get_visible_rect().size
	_spray(Vector2(s.x / 2.0, s.y * 0.3), 40, 220.0)


func clear_ready() -> bool:
	return not _clear.is_empty() and _lock_t > 0.0 and _real() - _lock_t > 0.6


# the time counted up so far (-1: no count)
func _counted(_at: float) -> float:
	var secs: float = _clear.get("secs", -1.0)
	return -1.0 if secs < 0.0 else _count_v


func _fmt(sec: float) -> String:
	var m := int(sec / 60.0)
	return "%d:%05.2f" % [m, sec - m * 60.0]


# the reveal, every frame: the count runs up (the time and the bar with it) until it reaches the edge of the next
# zone; there it stops while the rank changes (the shake, the drop, the crash), then carries on (Morgan's call,
# 2026-10-09). When it's all counted, the rank locks in
func _update_reveal(dt: float):
	if not _clear.is_empty() and float(_clear["secs"]) >= 0.0:
		var secs: float = _clear["secs"]
		var t := _now - float(_clear["t"])
		if _spin_t >= 0.0 and _now - _spin_t >= SPIN_TIME:   # landed on the next one: the count goes on
			_spin_t = -1.0
			_reel_at += 1
			_crash()
		if t >= COUNT_AT and _spin_t < 0.0 and _count_v < secs:
			var next := minf(_count_v + secs / maxf(float(_clear["len"]), 0.01) * dt, secs)
			if _reel_at < 3:
				var r: Vector3 = _clear["ranks"]
				var edge: float = [r.x, r.y, r.z][_reel_at]
				if next >= edge:                          # into the next zone: stop right there and change
					next = edge
					_spin_t = _now
			_count_v = next
		if _count_v >= secs and _spin_t < 0.0 and _lock_t < 0.0 and t >= COUNT_AT:
			_lock()
	if _spin_t >= 0.0 and not _clear.is_empty():          # crumbs off the letter as it shakes, then trailing its drop
		var st := _now - _spin_t
		var pos := _reel_pos(get_viewport().get_visible_rect().size)
		if st < SHAKE_TIME and randf() < dt * 40.0:
			_bit(pos + Vector2(randf_range(2.0, 34.0), randf_range(4.0, 40.0)), Vector2(randf_range(-20, 20), -randf_range(0, 30)),
				0.5, DIRT[randi() % DIRT.size()], 1.0, 300.0)
		elif st >= SHAKE_TIME:
			var out := clampf((st - SHAKE_TIME) / (SPIN_TIME - SHAKE_TIME) / 0.6, 0.0, 1.0)
			if out < 1.0 and randf() < dt * 60.0:
				_bit(pos + Vector2(randf_range(0.0, 32.0), 42.0 + out * out * 30.0), Vector2(randf_range(-15, 15), randf_range(0, 40)),
					0.4, DIRT[randi() % DIRT.size()], randf_range(1.0, 2.0), 300.0)
	for b in _bits:
		b[1].y += float(b[5]) * dt
		if b[7]:
			b[1] *= maxf(1.0 - 2.5 * dt, 0.0)                 # dust slows and hangs
		b[0] += b[1] * dt
		b[2] -= dt
	_bits = _bits.filter(func(b): return b[2] > 0.0)
	_rings = _rings.filter(func(r): return _now - float(r[1]) < 0.4)


func _rank_colors(i: int) -> Array:
	return RAINBOW[int(_now * 8.0) % RAINBOW.size()] if i == 0 else RANK_COLORS.get(RANKS[i], TEXT)


# where the reel's window is (its letter's top left)
func _reel_pos(screen: Vector2) -> Vector2:
	var lw := Pixel.width("RANK", 2) + 10.0 + 5.0 * 6.0
	return Vector2(roundf(screen.x / 2.0 - lw / 2.0) + Pixel.width("RANK", 2) + 10.0, roundf(screen.y * 0.6))


func _crash():
	_crash_t = _now
	_crash_sound.pitch_scale = [1.3, 1.1, 0.9, 0.75][_reel_at]
	_crash_sound.play(0.02)
	var screen := get_viewport().get_visible_rect().size
	var foot := _reel_pos(screen) + Vector2(0, 42)  # the letter's bottom: dirt kicked out to the left and right
	for i in 70:                                    # dirt (lots, Morgan's call), all sizes
		var dir := -1.0 if i % 2 == 0 else 1.0
		var from := foot + Vector2(randf_range(-2.0, 4.0) if dir < 0.0 else randf_range(26.0, 32.0), -randf_range(0.0, 4.0))
		_bit(from, Vector2(dir * randf_range(50.0, 240.0), -randf_range(20.0, 140.0)), randf_range(0.35, 0.85),
			DIRT[i % DIRT.size()], float(1 + i % 3), randf_range(280.0, 420.0))
	for i in 14:                                    # pebbles thrown up high
		var dir := -1.0 if i % 2 == 0 else 1.0
		_bit(foot + Vector2(15.0 + dir * 12.0, -2), Vector2(dir * randf_range(30.0, 110.0), -randf_range(150.0, 240.0)),
			randf_range(0.6, 0.9), DIRT[2], randf_range(2.0, 3.0), 520.0)
	var cols := _rank_colors(_reel_at)              # chips in the new rank's colours, bursting off the letter
	for i in 18:
		var d := Vector2.from_angle(randf() * TAU)
		_bit(foot + Vector2(16, -21) + d * 14.0, d * randf_range(70.0, 170.0), randf_range(0.3, 0.6), cols[i % 3],
			float(1 + i % 2), 200.0)
	for i in 10:                                    # dust puffs that swell and drift up
		var dir := -1.0 if i % 2 == 0 else 1.0
		_bit(foot + Vector2(15.0 + dir * randf_range(6.0, 20.0), -2), Vector2(dir * randf_range(20.0, 70.0), -randf_range(5.0, 25.0)),
			randf_range(0.5, 0.9), Pixel.PALE if i % 3 else DIRT[3], randf_range(4.0, 7.0), -15.0, true)
	_rings.append([foot + Vector2(16, 0), _now])    # and a shockwave along the ground


func _bit(at: Vector2, vel: Vector2, life: float, col: Color, size := 2.0, gravity := 300.0, dust := false):
	_bits.append([at, vel, life, col, size, gravity, life, dust])


func _lock():
	_lock_t = _now
	_crash_sound.pitch_scale = 0.65 if _reel_at > 0 else 1.5
	_crash_sound.play(0.02)
	var screen := get_viewport().get_visible_rect().size
	if _reel_at == 0:                              # an S: juice everywhere
		_spray(_reel_pos(screen) + Vector2(18, 21), 50, 260.0)


# ---------- every frame ----------
func _process(_delta):
	var t := _real()
	var dt := minf(t - _now, 0.1)
	_now = t
	_update_reveal(dt)
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
	if juice_mode and not juice_hidden and int(_clock_text()) != _tick_sec:     # a new second: it pops
		_tick_sec = int(_clock_text())
		_tick_t = _now
	if not _arrive.is_empty() and _now - float(_arrive["t"]) >= ARRIVE_POP + ARRIVE_FLY:
		_arrive = {}
		juice_hidden = false
		_arrive_t = _now
	var landed: Array = []
	for f: Array in _flyers:                     # the "+1s"s reaching the countdown
		if t >= float(f[1]) + float(f[5]) + float(f[2]):
			landed.append(f)
	for f: Array in landed:
		_flyers.erase(f)
		juice_gain(f[3])
		juice_landed.emit(f[3])
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
	_draw_edge_flash(screen)
	_draw_timer()
	_draw_boss_bar(screen)
	_draw_checkpoint(screen)
	_draw_intro(screen)
	_draw_boss_intro(screen)
	_draw_toast(screen)
	_draw_oops(screen)
	_draw_fail(screen)
	_draw_card(screen)
	_draw_clear(screen)
	for d in _drops:
		var pos: Vector2 = d[0]
		_canvas.draw_rect(Rect2(pos.round(), Vector2(2, 2)), Color(d[3], clampf(float(d[2]) * 4.0, 0.0, 1.0)))


func _draw_timer():
	if not _clear.is_empty():
		return
	if juice_mode:
		_draw_juice_clock()
		return
	if timer_text == "":
		return
	Pixel.draw_cells(_canvas, Pixel.cells(timer_text, Vector2(8, 8), 1), TEXT)


# the countdown, big at the top: whole seconds, each popping in then fading a little; green as time's added, red under
# 10 seconds, and the "+1s" beside it
func _draw_juice_clock():
	var screen := get_viewport().get_visible_rect().size
	_draw_arrive(screen)
	if juice_hidden:
		return
	var text := _clock_text()
	var gained := _now - _gain_t < 0.3
	var lost := _now - _loss_t < 0.6
	var low := juice_left < 10.0                   # red from here on
	var arrived := _now - _arrive_t < 0.5          # her seconds just landed on it: red a moment
	var colors: Array = RED if arrived or lost else (GOOD if gained else (WARN if low else TEXT))
	var s := 2
	var w := Pixel.width(text, s)
	var since := _now - _tick_t                    # pop: big, back to size; then fade till the next second
	var pop_k := 1.0
	var fade_a := 1.0
	if since < TICK_POP:
		var e := since / TICK_POP
		pop_k = lerpf(TICK_BIG, 1.0, 1.0 - (1.0 - e) * (1.0 - e))
	else:
		fade_a = lerpf(1.0, TICK_FADE_TO, clampf((since - TICK_POP) / (1.0 - TICK_POP), 0.0, 1.0))
	if gained or lost or arrived:
		fade_a = 1.0
	var center := Vector2(roundf(screen.x / 2.0 - w / 2.0) + w / 2.0, 6.0 + 3.5 * s)
	if _now - _loss_t < 0.35:                      # time taken off: it shakes as it lands
		center.x += roundf(sin(_now * 90.0) * 3.0 * (1.0 - (_now - _loss_t) / 0.35))
	_canvas.draw_set_transform(center, 0.0, Vector2(pop_k, pop_k))
	Pixel.draw_cells(_canvas, Pixel.cells(text, Vector2(-w / 2.0, -3.5 * s), s), colors, fade_a)
	_canvas.draw_set_transform(Vector2.ZERO)
	if _now - _gain_t < 0.7:
		var k := (_now - _gain_t) / 0.7
		Pixel.draw_cells(_canvas, Pixel.cells(_gain_text, Vector2(roundf(screen.x / 2.0 + w / 2.0 + 6.0), 10.0 - roundf(k * 6.0)), 1),
			GOOD, 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0))
	if _now - _loss_t < 1.4:
		var k := (_now - _loss_t) / 1.4
		Pixel.draw_cells(_canvas, Pixel.cells(_loss_text, Vector2(roundf(screen.x / 2.0 - w / 2.0 - Pixel.width(_loss_text, 2) - 6.0), 7.0 + roundf(k * 6.0)), 2),
			RED, 1.0 - clampf((k - 0.7) / 0.3, 0.0, 1.0))
	for f: Array in _flyers:                     # the "+1s"s on their way, with a little trail
		if _now < float(f[1]):
			continue
		var p := _flyer_pos(f, screen)
		var label: String = f[4]
		var tw := Pixel.width(label, 1)
		var age := _now - float(f[1])
		var penalty := float(f[3]) < 0.0
		if age > float(f[5]):
			var back := f.duplicate()
			back[1] = float(f[1]) + 0.05
			var q := _flyer_pos(back, screen)
			_canvas.draw_rect(Rect2((q + Vector2(-1, 2)).round(), Vector2(3, 3)), Color(RED[0] if penalty else Pixel.GREEN, 0.5))
		var fs := 1
		var jig := Vector2.ZERO
		if penalty:                                  # slams in big, shakes, then flies in at 2x
			fs = (4 if age < 0.08 else 3) if age < float(f[5]) else 2
			if age < float(f[5]):
				jig = Vector2(roundf(sin(_now * 70.0) * 1.5), 0)
		tw = Pixel.width(label, fs)
		Pixel.draw_cells(_canvas, Pixel.cells(label, (p + jig - Vector2(tw / 2.0, 3.5 * fs)).round(), fs), RED if penalty else GOOD)


# the screen's edges flash red when time's taken: as the "-5s" pops up, and again as it lands on the clock
func _draw_edge_flash(screen: Vector2):
	var since := INF
	for t0: float in [_pen_t, _loss_t]:
		if _now >= t0:
			since = minf(since, _now - t0)
	if since >= EDGE_FLASH:
		return
	var a := 0.55 * (1.0 - since / EDGE_FLASH)
	for i in 3:                                      # (a few bands, fainter inwards)
		var t := 4.0 * (i + 1)
		var c := Color(RED[0], a * (0.5 - i * 0.15))
		_canvas.draw_rect(Rect2(0, 0, screen.x, t), c)
		_canvas.draw_rect(Rect2(0, screen.y - t, screen.x, t), c)
		_canvas.draw_rect(Rect2(0, t, t, screen.y - t * 2.0), c)
		_canvas.draw_rect(Rect2(screen.x - t, t, t, screen.y - t * 2.0), c)


# the countdown's text: whole seconds, rounded up (it reads 1 till it really hits 0)
func _clock_text() -> String:
	return str(int(ceilf(maxf(juice_left, 0.0))))


# her seconds on their way: they float up out of the bubble shaking, pop to double size, then swoop up and over
# onto the countdown's first digits (it's hidden till they land), with a little red trail
func _draw_arrive(screen: Vector2):
	if _arrive.is_empty():
		return
	var age := _now - float(_arrive["t"])
	var text: String = _arrive["text"]
	var clock := _clock_text()
	var start: Vector2 = _arrive["from"] + Vector2(Pixel.width(text, 1) / 2.0, 3.5)       # (centres)
	var up := start + Vector2(0, -14)
	var end := Vector2(roundf(screen.x / 2.0 - Pixel.width(clock, 2) / 2.0) + Pixel.width(text, 2) / 2.0, 6.0 + 7.0)
	var at := _arrive_pos(age, start, up, end)
	var s := 1 if age < 0.1 else 2
	var shake := Vector2(roundf(sin(_now * 41.0)), roundf(cos(_now * 37.0))) if age < ARRIVE_POP else Vector2.ZERO
	if age > ARRIVE_POP:
		for i in 3:
			var back := _arrive_pos(age - 0.03 * (i + 1), start, up, end)
			_canvas.draw_rect(Rect2((back + Vector2(-1, -1)).round(), Vector2(3, 3)), Color(RED[0], 0.45 - i * 0.12))
	var top_left := (at + shake - Vector2(Pixel.width(text, s) / 2.0, 3.5 * s)).round()
	Pixel.draw_cells(_canvas, Pixel.cells(text, top_left, s), RED)


func _arrive_pos(age: float, start: Vector2, up: Vector2, end: Vector2) -> Vector2:
	if age < ARRIVE_POP:
		return start.lerp(up, _ease_out(clampf(age / ARRIVE_POP, 0.0, 1.0)))
	var k := clampf((age - ARRIVE_POP) / ARRIVE_FLY, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var ctrl := Vector2(up.x, end.y)                       # up first, then across
	return up.lerp(ctrl, k).lerp(ctrl.lerp(end, k), k)


func _draw_card(screen: Vector2):
	if _card_t < 0.0:
		return
	var t := _now - _card_t
	_canvas.draw_rect(Rect2(Vector2.ZERO, screen), Color(Pixel.INK, 0.6 * _k(t, 0.0, 0.5)))
	var title := "THANKS FOR PLAYING!"
	_letters(title, _centered(title, screen.y * 0.36, 3, screen), 3, t, GOOD, INF, 0.04, true)
	if t > 1.2 and int(_now * 2.0) % 2 == 0:
		var press := "PRESS {ENTER} TO TRY AGAIN"
		Pixel.draw_cells(_canvas, Pixel.cells(press, _centered(press, screen.y * 0.6, 1, screen), 1), TEXT)


func _draw_fail(screen: Vector2):
	var t := _now - _fail_t
	if t > 1.6:
		return
	if t < 0.3:
		_canvas.draw_rect(Rect2(Vector2.ZERO, screen), Color(Pixel.RED, 0.45 * (1.0 - t / 0.3)))
	_letters("OUT OF JUICE!", _centered("OUT OF JUICE!", screen.y * 0.36, 3, screen), 3, t, WARN, 1.2, 0.03)


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
		_canvas.draw_rect(Rect2(x + 1 + c, y - 2 + wave + floorf((5 - h) / 2.0), 1, h), Pixel.GREEN)
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
	var top := 32.0 if juice_mode else 8.0          # under the juice countdown (it pulses up to y 27), not over it
	var x := roundf(screen.x / 2.0 - BAR_W / 2.0)
	var y := top + 12.0
	var name_pos := Vector2(roundf(screen.x / 2.0 - Pixel.width(_boss_name, 1) / 2.0), top)
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
	var secs: float = _clear["secs"]
	var v := _counted(t)
	var counting := secs >= 0.0
	var time_text: String = "TIME " + (_fmt(v) if counting and v < secs else String(_clear["time"]))
	if t > 0.8:
		var tc: Array = GOOD if counting and _lock_t > 0.0 and _now - _lock_t < 0.3 else TEXT
		_letters(time_text, _centered(time_text, screen.y * 0.4, 2, screen), 2, t - 0.8, tc, INF, 0.02)
	if counting and t > COUNT_AT - 0.2:
		_draw_rank_bar(screen, roundf(screen.y * 0.5), maxf(v, 0.0), _k(t, COUNT_AT - 0.2, 0.2))
	if (counting and t > COUNT_AT - 0.2) or (not counting and t > RANK_AT):
		_draw_rank(screen, _k(t, COUNT_AT - 0.2, 0.2) if counting else 1.0)
	for r in _rings:                                 # the shockwave: a flat ring of pixels spreading along the ground
		var age := _now - float(r[1])
		var rad := 6.0 + age * 110.0
		for i in 20:
			var a := TAU * i / 20.0
			var q := (r[0] as Vector2) + Vector2(cos(a) * rad, sin(a) * rad * 0.25)
			_canvas.draw_rect(Rect2(q.round(), Vector2(2, 1)), Color(Pixel.OFF_WHITE, 0.8 * (1.0 - age / 0.4)))
	for b in _bits:
		var k: float = float(b[2]) / float(b[6])      # 1 new .. 0 gone
		if b[7]:                                     # dust: swells and fades
			var sz := roundf(lerpf(2.0, float(b[4]), 1.0 - k))
			_canvas.draw_rect(Rect2(((b[0] as Vector2) - Vector2(sz, sz) / 2.0).round(), Vector2(sz, sz)), Color(b[3], 0.55 * k))
		else:
			var sz: float = b[4]
			_canvas.draw_rect(Rect2((b[0] as Vector2).round(), Vector2(sz, sz)), Color(b[3], clampf(float(b[2]) * 3.0, 0.0, 1.0)))
	var after := (_now - _lock_t) if _lock_t > 0.0 else -1.0     # (the thanks wait for the rank to lock in)
	if last and after > 0.4:
		var thanks := "THANKS FOR PLAYING!"
		_letters(thanks, _centered(thanks, screen.y * 0.85, 2, screen), 2, after - 0.4, GOOD, INF, 0.02, true)
	elif not last and after > 0.6 and int(_now * 2.0) % 2 == 0:
		var press := "PRESS {ENTER} TO CONTINUE"
		Pixel.draw_cells(_canvas, Pixel.cells(press, _centered(press, screen.y * 0.88, 1, screen), 1), TEXT)


# the bar under the time: the S / A / B / C zones, all in colour at the start; as the time counts up, the part it's
# passed fades out, left to right (Morgan's call, 2026-10-09: what's left in colour is the ranks you can still
# get). A letter over each zone (dimmed once the count's past it) and a little white marker at the fade's edge
func _draw_rank_bar(screen: Vector2, y: float, v: float, a: float):
	var r: Vector3 = _clear["ranks"]
	var top_t := maxf(r.z * 1.3, float(_clear["secs"]) * 1.08)
	var x0 := roundf(screen.x / 2.0 - RANK_BAR_W / 2.0)
	var edges := [0.0, r.x, r.y, r.z, top_t]
	_canvas.draw_rect(Rect2(x0 - 1.0, y - 1.0, RANK_BAR_W + 2.0, 8), Color(Pixel.INK, a))
	var fill := x0 + roundf(RANK_BAR_W * clampf(v / top_t, 0.0, 1.0))
	for i in 4:
		var x1 := x0 + roundf(RANK_BAR_W * clampf(float(edges[i]) / top_t, 0.0, 1.0))
		var x2 := x0 + roundf(RANK_BAR_W * clampf(float(edges[i + 1]) / top_t, 0.0, 1.0))
		var cols := _rank_colors(i)
		var fx := clampf(fill, x1, x2)
		if fx > x1:                                # passed: faded out
			_canvas.draw_rect(Rect2(x1, y, fx - x1, 6), Color(cols[1], 0.35 * a))
		if fx < x2:                                # still to come: in colour
			_canvas.draw_rect(Rect2(fx, y, x2 - fx, 6), Color(cols[0], a))
			_canvas.draw_rect(Rect2(fx, y, x2 - fx, 1), Color(cols[2], a))
		if i > 0:                                  # the line between zones
			_canvas.draw_rect(Rect2(x1, y - 1.0, 1, 8), Color(Pixel.INK, a))
		var lit := v < float(edges[i + 1])
		var lc: Array = cols if lit else [Pixel.PALE, Pixel.BROWN, Pixel.PALE]
		var lx := roundf((x1 + x2) / 2.0 - 2.0)
		Pixel.draw_cells(_canvas, Pixel.cells(RANKS[i], Vector2(lx, y - 10.0), 1), lc, a * (1.0 if lit else 0.6))
	for row in 3:                                   # the marker
		_canvas.draw_rect(Rect2(fill - 2.0 + row, y - 3.0 + row, 5.0 - row * 2.0, 1), Color(Pixel.WHITE, a))


# RANK and the reel: a slot machine window with the letter in it. While it spins, letters scroll up through
# the window (blurred ones, then the next rank), clipped to it; landing (and locking in) it slams and flashes
func _draw_rank(screen: Vector2, a: float):
	var pos := _reel_pos(screen)
	var s := 6
	var lh := 7.0 * s
	if _now - _crash_t < 0.25:                      # the crash shakes it
		var k := 1.0 - (_now - _crash_t) / 0.25
		pos += Vector2(roundf(sin(_now * 90.0) * 3.0 * k), roundf(cos(_now * 70.0) * 2.0 * k))
	Pixel.draw_cells(_canvas, Pixel.cells("RANK", Vector2(pos.x - Pixel.width("RANK", 2) - 10.0, pos.y + lh - 14.0), 2, true), TEXT, a)
	var flash := _now - _crash_t < 0.06 or (_lock_t > 0.0 and _now - _lock_t < 0.08)
	if _spin_t >= 0.0:                              # to the next rank (no box round it, Morgan's call)
		var st := _now - _spin_t
		if st < SHAKE_TIME:                         # it shakes side to side, harder and harder...
			var jx := roundf(sin(st * 90.0) * (1.0 + 2.0 * st / SHAKE_TIME))
			Pixel.draw_cells(_canvas, Pixel.cells(RANKS[_reel_at], pos + Vector2(jx, 0), s, true), _rank_colors(_reel_at), a)
			return
		var u := clampf((st - SHAKE_TIME) / (SPIN_TIME - SHAKE_TIME), 0.0, 1.0)
		var out := clampf(u / 0.6, 0.0, 1.0)        # ...drops out downward, fading...
		if out < 1.0:
			Pixel.draw_cells(_canvas, Pixel.cells(RANKS[_reel_at], (pos + Vector2(0, out * out * 30.0)).round(), s, true),
				_rank_colors(_reel_at), a * (1.0 - out))
		var fall := u * u                           # ...and the next falls in from above, faster and faster
		Pixel.draw_cells(_canvas, Pixel.cells(RANKS[_reel_at + 1], (pos - Vector2(0, 46.0 * (1.0 - fall))).round(), s, true),
			_rank_colors(_reel_at + 1), a * clampf(u * 3.0, 0.0, 1.0))
		return
	var big := 0                                    # landing and locking in: a slam, a size up
	if _lock_t > 0.0 and _now - _lock_t < 0.1:
		big = 2 if _now - _lock_t < 0.05 else 1
	elif _now - _crash_t < 0.08:
		big = 1
	var ls := s + big
	var at := pos - Vector2(big * 2.5, big * 3.5)
	var cells := Pixel.cells(RANKS[_reel_at], at.round(), ls, true)
	if flash:
		for c in cells:
			c[4] = true
	Pixel.draw_cells(_canvas, cells, _rank_colors(_reel_at), a)


# ---------- easing ----------
func _k(t: float, start: float, length: float) -> float:
	return clampf((t - start) / length, 0.0, 1.0)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _ease_in(x: float) -> float:
	return x * x * x


func _ease_out_back(x: float) -> float:
	return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
