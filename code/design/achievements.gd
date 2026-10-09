extends CanvasLayer
# ACHIEVEMENTS (Morgan's idea, 2026-10-09): unlock one with  Achievements.unlock(get_tree(), "id").
# It pops up in the top left corner, in the tropical look (Morgan's call): a wooden plank sign in a bamboo frame
# with rope-lashed corners, a hibiscus on its corner and a palm frond poking out behind. It shoots in from off
# screen (overshooting a little, then settling), a pixel pineapple pops in on a leaf with a bounce, a "ting" and
# a burst of juice, ACHIEVEMENT UNLOCKED! ripples in letter by letter with the name dropping in under it, a
# shine sweeps across, and sparkles twinkle round the pineapple. It slides back out after a few seconds; more
# than one at once queue up.
# Each pops up once ever: unlocked ones are saved (user://achievements.cfg). While TESTING is on they aren't
# saved and each pops up once a run instead, so they can be seen again and again (turn it off for the real game).
# It runs on real time (slow motion doesn't slow it), on its own layer over the HUDs, made on demand in the
# current scene (like cinema_bars.gd), so there's nothing to place. PLACEHOLDER art, drawn in code.

const Pixel := preload("res://code/design/pixel_font.gd")
const SAVE := "user://achievements.cfg"
const DING := preload("res://sounds/sword/sword_hit_metal_01.wav")   # the blender garnish's "ting"
const DING_DB := -8.0
const GIRL := preload("res://girl-Sheet.png")                   # Violeta's customer: her face for FIRST CUSTOMER
const FACE := Rect2(53, 38, 22, 22)                             # (in her first frame: hat brim, flower, eyes)
const TESTING := true            # every achievement pops up once a run, nothing saved

# id: name. Where each unlocks:
#   customer  level.gd: the level starts (you've met her at the tiki bar)
#   surf      surf_wave.gd: the wave throws you over its wall
#   dam       dam.gd: the dam bursts
#   counter   counter_chain.gd: one counter chains 10 or more
#   timber    palm_bridge.gd: the palm slams down across the sand
#   bomb      dynamite.gd: the dynamite blows
#   shark     melon_shark.gd: you get past it (up the far bank) without killing it
#   climb     level.gd: up the column climb to the plateau with no jumps or edge grabs: counters only
#   signs     barricade.gd: every warning sign barricade in front of the mine smashed
#   quicksand level.gd: the sand gets you (the quicksand swallows you, or a snake fruit pulls you under)
#   mine_back minecart.gd: back up the mine shaft after the crash, against the cave-in
#   shame     minecart.gd: after mine_back, all the way back down to the bottom of the shaft
#   hard_worker bar_intro.gd: out of juice, and you say YES to trying again
#   tutorial  level.gd: out of juice within your first 10 seconds of play
#   no_sweat  level.gd: you beat the boss without being dazed once (it pops as the boss goes down)
#   service   level.gd: an S rank
const LIST := {
	"customer": "MY FIRST CUSTOMER",
	"surf": "SURF'S UP",
	"dam": "FLOODGATES",
	"counter": "COUNTER CULTURE",
	"timber": "TIMBER!",
	"bomb": "DEMOLITION EXPERT",
	"shark": "NOT ON THE MENU",
	"climb": "CUTTING CORNERS",
	"signs": "YOU CAN'T TELL ME WHERE TO GO",
	"quicksand": "TAKING THE 'QUICK' OUT OF QUICKSAND",
	"mine_back": "WRONG WAY BRO",
	"shame": "THE WALK OF SHAME LOL",
	"hard_worker": "HARD WORKER",
	"tutorial": "PROBABLY NEED TO REDO THE TUTORIAL",
	"no_sweat": "NO SWEAT",
	"service": "GREAT CUSTOMER SERVICE",
}

const SLIDE_IN := 0.42
const HOLD := 2.8
const SLIDE_OUT := 0.3
const MARGIN := Vector2(8, 8)
const HEADER := "ACHIEVEMENT UNLOCKED!"
const JUICE := [Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE, Pixel.RED]
const WOOD := Color("6b4424")
const WOOD_DARK := Color("4a2e18")
const WOOD_LIGHT := Color("8e5c30")
const BAMBOO := Color("b8a356")
const BAMBOO_DARK := Color("7d6c32")
const BAMBOO_LIGHT := Color("d8c77a")
const ROPE := Color("c9a46a")
const HIBISCUS := Color("e8406a")
const HIBISCUS_LIGHT := Color("f6a0b8")
const LEAF := Color("76964a")
const LEAF_DARK := Color("4f6e2e")
const WATER := Color("2f63ad")
const WATER_DARK := Color("1f4482")
const FOAM := Color("eef3fa")
const RIND := Color("4e8a3a")
const RIND_DARK := Color("2f5a24")
const RIND_LIGHT := Color("9bc76a")
const TNT := Color("c43a2a")
const TNT_DARK := Color("8d1f16")
const CREAM := Color("f5e2a8")
# the pineapple, 11 x 14: g / G its crown, # gold, o the pattern, w the shine
const PINEAPPLE := [
	"..g..g..g..",
	"...g.g.g...",
	"....gGg....",
	"...gGgGg...",
	"....GgG....",
	"...#####...",
	"..##o#o##..",
	".##o#o#o##.",
	".wo#o#o#o#.",
	".w#o#o#o##.",
	".#o#o#o#o#.",
	".##o#o#o##.",
	"..##o#o##..",
	"...#####...",
]

static var _unlocked := {}       # saved ones (or, while TESTING, this run's)
static var _loaded := false
static var _carry: Array = []    # pop-ups a scene change cut short (saying YES to trying again reloads the level)

var _queue: Array = []           # ids still to show
var _cur := ""                   # the one showing
var _t0 := -100.0                # when it started (real time)
var _drops: Array = []           # juice from the pineapple: [pos, vel, life, colour]
var _canvas := Node2D.new()
var _ding := AudioStreamPlayer.new()
var _last := 0.0


# unlock an achievement: it pops up (once ever; once a run while TESTING)
static func unlock(tree: SceneTree, id: String):
	if not LIST.has(id) or tree == null or tree.current_scene == null:
		return
	_load()
	if _unlocked.has(id):
		return
	_unlocked[id] = true
	if not TESTING:
		var cfg := ConfigFile.new()
		for k in _unlocked:
			cfg.set_value("unlocked", k, true)
		cfg.save(SAVE)
	var node: Node = tree.current_scene.get_node_or_null("Achievements")
	if node == null:
		node = load("res://code/design/achievements.gd").new()
		node.name = "Achievements"
		tree.current_scene.add_child(node)
	node.show_one(id)


static func is_unlocked(id: String) -> bool:
	_load()
	return _unlocked.has(id)


static func _load():
	if _loaded:
		return
	_loaded = true
	if TESTING:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK and cfg.has_section("unlocked"):
		for k in cfg.get_section_keys("unlocked"):
			_unlocked[k] = true


# the scene's changing (the level reloading): any pop-up that hasn't had its turn yet shows in the next one. One
# already showing doesn't (Morgan's call: HARD WORKER came up twice, once as you said YES and again after)
func _exit_tree():
	_carry.append_array(_queue)


# the new scene's up (level.gd calls this): the carried pop-ups show
static func resume(tree: SceneTree):
	if _carry.is_empty() or tree == null or tree.current_scene == null:
		return
	var node: Node = tree.current_scene.get_node_or_null("Achievements")
	if node == null:
		node = load("res://code/design/achievements.gd").new()
		node.name = "Achievements"
		tree.current_scene.add_child(node)
	for id in _carry:
		node.show_one(id)
	_carry.clear()


# (while TESTING, a fresh run of the scene starts the run over: they can all pop up again)
static func new_run():
	if TESTING:
		_unlocked.clear()


func _ready():
	layer = 12                                   # over the level HUD (11) and the cinema bars (9)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.draw.connect(_draw_toast)
	add_child(_canvas)
	_ding.stream = DING
	_ding.volume_db = DING_DB
	_ding.pitch_scale = 2.2
	add_child(_ding)
	_last = _real()


func show_one(id: String):
	_queue.append(id)


func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta):
	var now := _real()
	var dt := minf(now - _last, 0.1)
	_last = now
	if _cur != "" and now - _t0 > SLIDE_IN + HOLD + SLIDE_OUT:
		_cur = ""
	if _cur == "" and not _queue.is_empty():
		_cur = _queue.pop_front()
		_t0 = now
	if _cur != "" and now - _t0 >= 0.2 and now - _t0 - dt < 0.2:   # the pineapple lands: a ting and a splash
		_ding.play()
		var c := _icon_center()
		for i in 18:
			var dir := Vector2.from_angle(randf_range(-PI * 0.95, PI * 0.15))
			_drops.append([c, dir * randf_range(50.0, 150.0), randf_range(0.35, 0.7), JUICE[i % JUICE.size()]])
	for d in _drops:
		d[1].y += 300.0 * dt
		d[0] += d[1] * dt
		d[2] -= dt
	_drops = _drops.filter(func(d): return d[2] > 0.0)
	_canvas.queue_redraw()


func _size() -> Vector2:
	var name_text: String = LIST[_cur]
	return Vector2(maxf(Pixel.width(HEADER, 1), Pixel.width(name_text, 1)) + 46.0, 30)


# where the sign's top left is: shooting in with an overshoot, holding, then sliding back off
func _panel_pos() -> Vector2:
	var t := _real() - _t0
	var off := -_size().x - 16.0
	var x := MARGIN.x
	if t < SLIDE_IN:
		var k := t / SLIDE_IN
		var c1 := 1.9
		x = lerpf(off, MARGIN.x, 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0))   # ease out back
	elif t > SLIDE_IN + HOLD:
		var k := clampf((t - SLIDE_IN - HOLD) / SLIDE_OUT, 0.0, 1.0)
		x = lerpf(MARGIN.x, off, k * k)
	return Vector2(roundf(x), MARGIN.y)


func _icon_center() -> Vector2:
	return _panel_pos() + Vector2(18, 15)


func _draw_toast():
	if _cur != "":
		var t := _real() - _t0
		var p := _panel_pos()
		var size := _size()
		_draw_frond(p, size)                                                        # behind the sign
		_canvas.draw_rect(Rect2(p + Vector2(3, 3), size), Color(Pixel.INK, 0.5))    # its shadow
		_draw_sign(p, size)
		_draw_icon(t)
		var tx := p.x + 38.0
		var shown := int((t - 0.15) / 0.022)                                         # the header ripples in
		var keep := []
		for c in Pixel.cells(HEADER, Vector2(tx, p.y + 6.0), 1):
			if c[2] < shown:
				var cr: Rect2 = c[0]
				cr.position.y += roundf(sin(t * 10.0 - c[2] * 0.6) * 0.8) if t < 1.2 else 0.0
				c[0] = cr
				keep.append(c)
		Pixel.draw_cells(_canvas, keep, Pixel.HIGHLIGHT)
		var name_text: String = LIST[_cur]
		var nk := clampf((t - 0.45) / 0.18, 0.0, 1.0)                               # the name drops in
		if nk > 0.0:
			var ncells := Pixel.cells(name_text, Vector2(tx, p.y + 17.0 + roundf((1.0 - nk) * -6.0)), 1)
			if t < 0.7:
				for c in ncells:
					c[4] = true                                                     # (white as it lands)
			Pixel.draw_cells(_canvas, ncells, [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE], nk)
		var sweep := (t - 0.75) / 0.4                                               # a shine across it, once
		if sweep > 0.0 and sweep < 1.0:
			var sx := p.x + sweep * (size.x + 20.0) - 10.0
			for i in 6:                                                             # (slanted: lower is further left)
				_canvas.draw_rect(Rect2(sx - i * 2.0, p.y + 1.0 + i * 5.0, 3, 5), Color(1, 1, 1, 0.2))
		_draw_hibiscus(p + Vector2(size.x - 1.0, 0))
	for d in _drops:
		_canvas.draw_rect(Rect2((d[0] as Vector2).round(), Vector2(2, 2)), Color(d[3], clampf(float(d[2]) * 3.0, 0.0, 1.0)))


# the sign: two wooden planks with their grain, in a frame of bamboo poles (nodes along them), rope at the corners
func _draw_sign(p: Vector2, size: Vector2):
	var r := Rect2(p, size)
	_canvas.draw_rect(r.grow(3.0), Pixel.INK)
	_canvas.draw_rect(r, WOOD)
	_canvas.draw_rect(Rect2(p.x, p.y + 15.0, size.x, 1), WOOD_DARK)                  # the seam between planks
	var gx := 4.0
	while gx < size.x - 4.0:                                                         # grain
		var row := 4.0 + float(posmod(int(gx) * 7, 9))
		_canvas.draw_rect(Rect2(p.x + gx, p.y + row + (15.0 if int(gx) % 2 else 0.0), 6, 1), WOOD_LIGHT)
		gx += 11.0
	for edge: float in [-2.0, size.y - 1.0]:                                         # bamboo along the top and bottom
		_canvas.draw_rect(Rect2(p.x - 2.0, p.y + edge, size.x + 4.0, 3), BAMBOO)
		_canvas.draw_rect(Rect2(p.x - 2.0, p.y + edge, size.x + 4.0, 1), BAMBOO_LIGHT)
		var nx := 9.0
		while nx < size.x:
			_canvas.draw_rect(Rect2(p.x + nx, p.y + edge, 1, 3), BAMBOO_DARK)
			nx += 14.0
	for side: float in [-2.0, size.x - 1.0]:                                         # and up the sides
		_canvas.draw_rect(Rect2(p.x + side, p.y - 2.0, 3, size.y + 4.0), BAMBOO)
		_canvas.draw_rect(Rect2(p.x + side, p.y - 2.0, 1, size.y + 4.0), BAMBOO_LIGHT)
		_canvas.draw_rect(Rect2(p.x + side, p.y + 13.0, 3, 1), BAMBOO_DARK)
	for corner: Vector2 in [p + Vector2(-2, -2), p + Vector2(size.x - 1.0, -2), p + Vector2(-2, size.y - 1.0),
			p + Vector2(size.x - 1.0, size.y - 1.0)]:                                # rope lashed round the corners
		_canvas.draw_rect(Rect2(corner + Vector2(-1, 1), Vector2(5, 1)), ROPE)
		_canvas.draw_rect(Rect2(corner + Vector2(1, -1), Vector2(1, 5)), ROPE)
	var nook := p + Vector2(18, 15)                                                  # a hole carved in the wood for the icon
	_disc(nook, 12.0, Pixel.INK)
	_disc(nook, 11.0, WOOD_DARK)
	_disc(nook + Vector2(0, 1), 10.0, Color("3a2414"))


# a palm frond poking out from behind the sign's bottom left corner, swaying a little
func _draw_frond(p: Vector2, size: Vector2):
	var root := p + Vector2(10, size.y + 1.0)
	var sway := sin(_real() * 2.0) * 1.5
	for i in 6:
		var a := deg_to_rad(150.0 + i * 12.0)
		var tip := root + Vector2.from_angle(a) * (16.0 - i) + Vector2(sway, 0)
		_canvas.draw_line(root, tip, Pixel.INK, 3.0)
		_canvas.draw_line(root, tip, LEAF if i % 2 == 0 else LEAF_DARK, 1.0)


# a hibiscus pinned on the sign's top right corner
func _draw_hibiscus(at: Vector2):
	for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-2, -2), Vector2(2, 2), Vector2(2, -2), Vector2(-2, 2)]:
		_canvas.draw_rect(Rect2(at + off - Vector2(2, 2), Vector2(4, 4)), Pixel.INK)
	for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-2, -2), Vector2(2, 2), Vector2(2, -2), Vector2(-2, 2)]:
		_canvas.draw_rect(Rect2(at + off - Vector2(1, 1), Vector2(2, 2)), HIBISCUS)
	_canvas.draw_rect(Rect2(at + Vector2(-3, -1), Vector2(1, 1)), HIBISCUS_LIGHT)
	_canvas.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(2, 2)), Pixel.MUSTARD)


# the achievement's own icon (Morgan's call, 2026-10-09): pops in (tiny, past full size, settling) as the sign
# lands, sways a little, and sparkles twinkle round it. Each is drawn about its middle, within 9px or so
func _draw_icon(t: float):
	if t <= 0.18:
		return
	var c := _icon_center()
	var u := clampf((t - 0.18) / 0.25, 0.0, 1.0)
	var c1 := 2.4
	var k := lerpf(0.2, 1.0, 1.0 + (c1 + 1.0) * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0))
	_canvas.draw_set_transform(c, sin(t * 3.0) * 0.06, Vector2(k, k))
	match _cur:
		"customer": _icon_customer()
		"surf": _icon_surf(t)
		"dam": _icon_dam(t)
		"counter": _icon_counter(t)
		"timber": _icon_timber(t)
		"bomb": _icon_bomb(t)
		"shark": _icon_shark(t)
		"climb": _icon_climb(t)
		"signs": _icon_signs(t)
		"quicksand": _icon_quicksand(t)
		"mine_back": _icon_mine_back(t)
		"shame": _icon_shame(t)
		"hard_worker": _icon_hard_worker(t)
		"tutorial": _icon_tutorial(t)
		"no_sweat": _icon_no_sweat(t)
		"service": _icon_service(t)
		_: _icon_pineapple()
	_canvas.draw_set_transform(Vector2.ZERO)
	if t > 0.4:                                                                    # sparkles
		for i in 3:
			var ph := fmod(t * 1.6 + i * 0.37, 1.0)
			if ph < 0.5:
				var at := c + Vector2([-11.0, 10.0, 7.0][i], [-8.0, -6.0, 9.0][i])
				var a := sin(ph / 0.5 * PI)
				_canvas.draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(1, 1, 1, a))
				for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					_canvas.draw_rect(Rect2((at + off).round(), Vector2(1, 1)), Color(Pixel.MUSTARD, a * 0.8))


# ---------- drawing helpers (in the icon's own space) ----------
# a filled pixel circle, row by row
func _disc(c: Vector2, r: float, col: Color):
	for dy in range(-int(r), int(r) + 1):
		var half := floorf(sqrt(maxf(r * r - dy * dy, 0.0)) + 0.3)
		_canvas.draw_rect(Rect2(c.x - half, c.y + dy, half * 2.0 + 1.0, 1), col)


# a line with an ink outline round it
func _stroke(a: Vector2, b: Vector2, w: float, col: Color):
	_canvas.draw_line(a, b, Pixel.INK, w + 2.0)
	_canvas.draw_line(a, b, col, w)


# a filled shape with an ink outline round it
func _poly(pts: PackedVector2Array, col: Color):
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var o := PackedVector2Array()
		for q in pts:
			o.append(q + off)
		_canvas.draw_colored_polygon(o, Pixel.INK)
	_canvas.draw_colored_polygon(pts, col)


# water along the bottom: a dark body, a wavy lighter top and foam on the crests
func _water(top: float, t: float):
	for y in range(int(top), 10):                                                      # (rounded to the hole it sits in)
		var half := floorf(sqrt(maxf(100.0 - y * y, 0.0)))
		_canvas.draw_rect(Rect2(-half, y, half * 2.0, 1), WATER_DARK)
	for x in range(-9, 9):
		var y := top + roundf(sin(x * 0.9 + t * 4.0))
		_canvas.draw_rect(Rect2(x, y, 1, 2), WATER)
		if posmod(x, 4) == 0:
			_canvas.draw_rect(Rect2(x, y - 1.0, 1, 1), FOAM)


# ---------- the icons ----------
# FIRST CUSTOMER: her face, from Violeta's sprite (hat brim, the flower, her eyes), cut round to the hole
func _icon_customer():
	var r := FACE.size.x / 2.0
	for y in int(FACE.size.y):
		var dy := y - r + 0.5
		var half := floorf(sqrt(maxf(r * r - dy * dy, 0.0)))
		if half <= 0.0:
			continue
		_canvas.draw_texture_rect_region(GIRL, Rect2(-half, y - r, half * 2.0, 1),
			Rect2(FACE.position.x + r - half, FACE.position.y + y, half * 2.0, 1))


# SURF'S UP: like the surf placard's ride panel: a curling wave with a foamy lip, and the figure standing on a
# surfboard on top of it, arms out for balance (bobbing), spray off the board's tail
func _icon_surf(t: float):
	_water(6.0, t)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(-9, 9), Vector2(-9, 4), Vector2(-6, 2), Vector2(-2, 0),
		Vector2(2, 0), Vector2(5, 2), Vector2(6, 4), Vector2(4, 5), Vector2(3, 3), Vector2(1, 4), Vector2(0, 9)]), WATER)
	_canvas.draw_line(Vector2(-9, 4), Vector2(-6, 2), FOAM, 1.0)
	for q: Vector2 in [Vector2(5, 2), Vector2(6, 3), Vector2(4, 4), Vector2(3, 1)]:   # the foam on its lip
		_canvas.draw_rect(Rect2(q, Vector2(1, 1)), FOAM)
	var bob := roundf(sin(t * 5.0) * 0.6)
	var o := Vector2(0, bob)
	_stroke(Vector2(-6, 1) + o, Vector2(2, -1) + o, 1.0, Pixel.OFF_WHITE)              # the board
	_canvas.draw_rect(Rect2(Vector2(-2, 0) + o, Vector2(1, 1)), Pixel.ORANGE)
	var hip := Vector2(-2, -4) + o
	_stroke(Vector2(-4, 0) + o, hip, 1.0, Pixel.WHITE)                                # legs
	_stroke(Vector2(0, -1) + o, hip, 1.0, Pixel.WHITE)
	_stroke(hip, hip + Vector2(0, -3), 1.0, Pixel.WHITE)                               # body
	var arm := roundf(sin(t * 5.0))
	_stroke(hip + Vector2(0, -2), hip + Vector2(-4, -2 + arm), 1.0, Pixel.WHITE)       # arms out
	_stroke(hip + Vector2(0, -2), hip + Vector2(4, -3 - arm), 1.0, Pixel.WHITE)
	_disc(hip + Vector2(0, -5), 1.5, Pixel.INK)                                        # head
	_canvas.draw_rect(Rect2(hip + Vector2(0, -5), Vector2(1, 1)), Pixel.WHITE)
	for i in 3:                                                                        # spray off the tail
		_canvas.draw_rect(Rect2(Vector2(-8.0 - i, 0.0 - i) + o, Vector2(1, 1)), FOAM)


# FLOODGATES (Morgan's call, 2026-10-09): just the dam's diagonal brace being chopped in two: the beam split in the
# middle, its halves drifting apart, the sword across the cut with a white slash, and wood chips flying off it
func _icon_dam(t: float):
	var apart := 0.5 + absf(sin(t * 3.0)) * 0.8                                       # the beam, cut in two
	_stroke(Vector2(-8, 8) + Vector2(-apart, apart), Vector2(-2, 2) + Vector2(-apart, apart), 3.0, WOOD)
	_stroke(Vector2(2, -2) + Vector2(apart, -apart), Vector2(8, -8) + Vector2(apart, -apart), 3.0, WOOD)
	_canvas.draw_line(Vector2(-8, 7) + Vector2(-apart, apart), Vector2(-3, 2) + Vector2(-apart, apart), WOOD_LIGHT, 1.0)
	_canvas.draw_line(Vector2(2, -3) + Vector2(apart, -apart), Vector2(7, -8) + Vector2(apart, -apart), WOOD_LIGHT, 1.0)
	_stroke(Vector2(-5, -5), Vector2(6, 6), 1.0, Pixel.OFF_WHITE)                      # the sword's blade...
	_canvas.draw_line(Vector2(-4, -5), Vector2(6, 5), Pixel.WHITE, 1.0)
	_stroke(Vector2(-7, -3), Vector2(-3, -7), 1.0, Pixel.MUSTARD)                      # ...its crossguard...
	_stroke(Vector2(-5, -5), Vector2(-8, -8), 1.0, WOOD_DARK)                          # ...and handle
	_canvas.draw_rect(Rect2(-9, -9, 1, 1), Pixel.MUSTARD)
	for i in 3:                                                                        # the slash
		_canvas.draw_rect(Rect2(-1.0 + i * 2.0, 2.0 + i * 2.0, 1, 1), Color(1, 1, 1, 0.7))
	for i in 4:                                                                        # chips flying off the cut
		var ph := fmod(t * 1.5 + i * 0.25, 1.0)
		var dir := Vector2.from_angle(-PI * 0.5 + (i - 1.5) * 0.8)
		var at := dir * (2.0 + ph * 7.0) + Vector2(0, ph * ph * 4.0)
		_canvas.draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(WOOD_LIGHT, 1.0 - ph))


# COUNTER CULTURE: a mango sliced through, a white slash across it with sparks at its ends
func _icon_counter(_t: float):
	_disc(Vector2(-1, 1), 7.0, Pixel.INK)
	_disc(Vector2(-1, 1), 6.0, Pixel.ORANGE)
	_disc(Vector2(-3, -1), 2.0, Pixel.MUSTARD)
	_canvas.draw_rect(Rect2(0, -7, 3, 2), LEAF)
	_canvas.draw_rect(Rect2(1, -8, 2, 1), LEAF_DARK)
	_stroke(Vector2(-9, 8), Vector2(9, -7), 1.0, Pixel.WHITE)
	for end: Vector2 in [Vector2(-9, 8), Vector2(9, -7)]:
		for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_canvas.draw_rect(Rect2(end + off, Vector2(1, 1)), Pixel.MUSTARD)


# TIMBER!: a palm tree toppling over, its crown swishing, from a stump on the sand
func _icon_timber(t: float):
	_canvas.draw_rect(Rect2(-9, 7, 18, 2), Pixel.MUSTARD)
	_canvas.draw_rect(Rect2(-9, 7, 18, 1), Pixel.OFF_WHITE)
	var lean := 0.12 * sin(t * 4.0)
	var top := Vector2(6, -5).rotated(lean)
	_stroke(Vector2(-6, 7), top, 2.0, WOOD)
	for k in 3:
		var q := Vector2(-6, 7).lerp(top, 0.25 + k * 0.25)
		_canvas.draw_rect(Rect2(q.round(), Vector2(1, 1)), WOOD_DARK)
	for a: float in [-2.6, -1.8, -1.0, -0.2, 0.6]:
		_stroke(top, top + Vector2.from_angle(a + lean) * 6.0, 1.0, LEAF if int(a * 10.0) % 2 == 0 else LEAF_DARK)
	for i in 3:                                                                        # it's falling: motion dashes
		_canvas.draw_rect(Rect2(-1.0 + i * 3.0, -8.0 + i, 2, 1), Pixel.PALE)


# DEMOLITION EXPERT: a bundle of red dynamite, a band round it, and a fuse fizzing with sparks
func _icon_bomb(t: float):
	for i in 3:
		var x := -7.0 + i * 4.5
		_canvas.draw_rect(Rect2(x - 1.0, -4, 6, 14), Pixel.INK)
		_canvas.draw_rect(Rect2(x, -3, 4, 12), TNT)
		_canvas.draw_rect(Rect2(x + 3.0, -3, 1, 12), TNT_DARK)
		_canvas.draw_rect(Rect2(x, -3, 1, 12), Color(1, 1, 1, 0.3))
	_canvas.draw_rect(Rect2(-8, 3, 16, 2), Pixel.INK)                                 # the band
	_canvas.draw_line(Vector2(0, -4), Vector2(2, -7), WOOD_LIGHT, 1.0)                # the fuse
	_canvas.draw_line(Vector2(2, -7), Vector2(5, -8), WOOD_LIGHT, 1.0)
	var spark := Vector2(6, -9)
	var f := absf(sin(t * 20.0))
	_canvas.draw_rect(Rect2(spark, Vector2(1, 1)), Pixel.WHITE)
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1)]:
		_canvas.draw_rect(Rect2(spark + off * (1.0 + f), Vector2(1, 1)), Pixel.MUSTARD if f > 0.5 else Pixel.ORANGE)


# NOT ON THE MENU: the watermelon shark's striped fin cutting through the water
func _icon_shark(t: float):
	var x := roundf(sin(t * 3.0) * 1.5)
	_poly(PackedVector2Array([Vector2(-5 + x, 4), Vector2(2 + x, -8), Vector2(5 + x, 4)]), RIND)
	for k in 3:                                                                        # its stripes
		var sx := -2.0 + x + k * 2.5
		_canvas.draw_line(Vector2(sx, 3), Vector2(sx + 1.5 - k * 0.5, -4.0 + k * 2.0), RIND_DARK, 1.0)
	_canvas.draw_line(Vector2(2 + x, -7), Vector2(4 + x, 3), RIND_LIGHT, 1.0)        # its lit edge
	_water(3.0, t)
	_canvas.draw_rect(Rect2(-6 + x, 3, 3, 1), FOAM)                                   # foam where it cuts the water
	_canvas.draw_rect(Rect2(5 + x, 3, 3, 1), FOAM)


# CUTTING CORNERS: three stone columns stepping up, the counter's teal teleport streak zigzagging up them (a
# bright dash running along it) and a slash mark on each column
func _icon_climb(t: float):
	var tops := [3.0, -2.0, -7.0]
	for k in 3:
		var x := -8.0 + k * 6.0
		var top: float = tops[k]
		_canvas.draw_rect(Rect2(x - 1.0, top - 1.0, 7, 9.0 - top), Pixel.INK)
		_canvas.draw_rect(Rect2(x, top, 5, 7.0 - top), Color("54607a"))
		_canvas.draw_rect(Rect2(x, top, 5, 1), Color("8a96b0"))
		_canvas.draw_rect(Rect2(x + 4.0, top + 1.0, 1, 6.0 - top), Color("3c4458"))
		_canvas.draw_line(Vector2(x + 1.0, top - 3.0), Vector2(x + 4.0, top - 1.0), Pixel.WHITE, 1.0)   # slash
	var path := [Vector2(-6, 1), Vector2(0, -4), Vector2(6, -9)]
	for i in 2:
		_canvas.draw_line(path[i], path[i + 1], Color(Pixel.TEAL, 0.8), 1.0)
	var ph := fmod(t * 1.2, 1.0) * 2.0                                                 # the dash running up it
	var seg := mini(int(ph), 1)
	var at: Vector2 = (path[seg] as Vector2).lerp(path[seg + 1], ph - seg)
	_canvas.draw_rect(Rect2(at.round() - Vector2(1, 1), Vector2(3, 3)), Pixel.WHITE)
	_canvas.draw_rect(Rect2(at.round(), Vector2(1, 1)), Pixel.TEAL)


# YOU CAN'T TELL ME WHERE TO GO (Morgan's call, 2026-10-09): just the KEEP OUT sign, as on the barricade: a yellow
# board with a dark border and black letters (a tiny 3 x 5 font, the only way they fit) on a little wooden post
const MINI := {
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"E": ["###", "#..", "##.", "#..", "###"],
	"P": ["##.", "#.#", "##.", "#..", "#.."],
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
}


func _icon_signs(_t: float):
	_canvas.draw_rect(Rect2(-2, 5, 4, 5), Pixel.INK)                                  # the post
	_canvas.draw_rect(Rect2(-1, 6, 2, 3), WOOD)
	_canvas.draw_rect(Rect2(-9, -7, 18, 13), Pixel.INK)                               # the board (corners cut, so it
	_canvas.draw_rect(Rect2(-8, -8, 16, 15), Pixel.INK)                               # sits inside the round hole)
	_canvas.draw_rect(Rect2(-8, -7, 16, 13), Color("f2c22e"))
	_canvas.draw_rect(Rect2(-8, -7, 16, 1), Color("f8dc6a"))
	_mini_text("KEEP", Vector2(-7, -6))
	_mini_text("OUT", Vector2(-5, 0))


func _mini_text(text: String, at: Vector2):
	var x := at.x
	for ch in text:
		var g: Array = MINI[ch]
		for row in 5:
			var line: String = g[row]
			for col in 3:
				if line[col] == "#":
					_canvas.draw_rect(Rect2(x + col, at.y + row, 1, 1), Color("1d1820"))
		x += 4.0


# TAKING THE 'QUICK' OUT OF QUICKSAND: a hand reaching up out of a mound of golden sand (more lifelike, Morgan's
# call: four fingers of different lengths with gaps between, a thumb out to the side, the palm and the wrist, a
# shaded side, knuckle creases and paler fingertips), sinking and bobbing back, grains flicking up round it
func _icon_quicksand(t: float):
	var o := Vector2(0, roundf(sin(t * 1.5)))
	var skin := Color("e8b890")
	var shade := Color("c48c64")
	var tip := Color("f6d8c0")
	var fingers := [[-5.0, -5.0], [-2.0, -7.0], [1.0, -8.0], [4.0, -7.0]]           # [left x, top y]: pinky .. index
	var palm := Rect2(Vector2(-5, -2) + o, Vector2(11, 5))
	var wrist := Rect2(Vector2(-3, 3) + o, Vector2(7, 4))                            # (ends well inside the sand)
	_canvas.draw_rect(palm.grow(1.0), Pixel.INK)                                      # ink round it all first
	_canvas.draw_rect(wrist.grow(1.0), Pixel.INK)
	for f: Array in fingers:
		_canvas.draw_rect(Rect2(Vector2(f[0] - 1.0, f[1] - 1.0) + o, Vector2(4, -float(f[1]) + 1.0)), Pixel.INK)
	_canvas.draw_line(Vector2(5, 1) + o, Vector2(8, -3) + o, Pixel.INK, 4.0)
	_canvas.draw_rect(wrist, skin)                                                     # the wrist
	_canvas.draw_rect(Rect2(wrist.end.x - 2.0, wrist.position.y, 2, wrist.size.y), shade)
	_canvas.draw_rect(palm, skin)                                                      # the palm
	_canvas.draw_rect(Rect2(palm.end.x - 2.0, palm.position.y, 2, palm.size.y), shade)
	_canvas.draw_rect(Rect2(palm.position.x + 1.0, palm.position.y + 2.0, 6, 1), shade)   # its crease
	for f: Array in fingers:                                                          # the fingers
		var r := Rect2(Vector2(f[0], f[1]) + o, Vector2(2, -float(f[1]) - 1.0))
		_canvas.draw_rect(r, skin)
		_canvas.draw_rect(Rect2(r.position + Vector2(1, 0), Vector2(1, r.size.y)), shade)
		_canvas.draw_rect(Rect2(r.position, Vector2(1, 1)), tip)
		_canvas.draw_rect(Rect2(r.position + Vector2(0, floorf(r.size.y / 2.0)), Vector2(2, 1)), shade)   # knuckle
	_canvas.draw_line(Vector2(5, 1) + o, Vector2(8, -3) + o, skin, 2.0)              # the thumb
	_canvas.draw_rect(Rect2(Vector2(8, -4) + o, Vector2(1, 1)), tip)
	for x in range(-10, 11):                                                           # the sand, over its wrist and
		var top := 4.0 + roundf(sin(x * 0.7 + t * 2.0) * 0.8)                         # filling the hole's whole bottom
		var bottom := 1.0 + floorf(sqrt(maxf(100.0 - x * x, 0.0)) + 0.3) + 1.0      # (to the hole's edge: its disc is
		if bottom <= top:                                                             # centred 1px down, radius 10)
			continue
		_canvas.draw_rect(Rect2(x, top, 1, bottom - top), Pixel.MUSTARD)
		_canvas.draw_rect(Rect2(x, top, 1, 1), Color("f8dc6a"))
		if posmod(x * 7, 5) == 0:
			_canvas.draw_rect(Rect2(x, top + 2.0, 1, 1), Pixel.RUST)
	for i in 3:                                                                        # grains flicking up
		var ph := fmod(t * 1.3 + i * 0.33, 1.0)
		_canvas.draw_rect(Rect2(-7.0 + i * 7.0, roundf(3.0 - ph * 5.0), 1, 1), Color(Pixel.MUSTARD, 1.0 - ph))


# THE WALK OF SHAME: a hunched little figure trudging down a slope, a grey rain cloud dripping on its head
func _icon_shame(t: float):
	_canvas.draw_line(Vector2(-10, 0), Vector2(10, 9), Pixel.INK, 3.0)                # the slope
	_canvas.draw_line(Vector2(-10, -1), Vector2(10, 8), Color("8a96b0"), 1.0)
	var k := fmod(t * 0.25, 1.0)                                                       # it trudges down it
	var feet := Vector2(lerpf(-6.0, 4.0, k), 0.0)
	feet.y = -1.0 + (feet.x + 10.0) * 0.45 - 1.0
	feet = feet.round()
	var step := roundf(sin(t * 6.0))
	var hip := feet + Vector2(0, -4)
	_stroke(hip, feet + Vector2(-1.0 - step, 0), 1.0, Pixel.WHITE)                    # legs
	_stroke(hip, feet + Vector2(1.0 + step, 0), 1.0, Pixel.WHITE)
	_stroke(hip, hip + Vector2(1, -3), 1.0, Pixel.WHITE)                               # hunched body
	_stroke(hip + Vector2(1, -2), hip + Vector2(0, 1), 1.0, Pixel.WHITE)              # arms hanging
	_disc(hip + Vector2(2, -4), 1.5, Pixel.INK)                                        # head hung low
	_canvas.draw_rect(Rect2(hip + Vector2(2, -4), Vector2(1, 1)), Pixel.WHITE)
	var cloud := hip + Vector2(1, -9)                                                  # its own rain cloud
	_disc(cloud, 2.5, Pixel.INK)
	_disc(cloud + Vector2(3, 0), 2.0, Pixel.INK)
	_disc(cloud + Vector2(-3, 1), 1.5, Pixel.INK)
	_disc(cloud, 1.5, Color("8a8a96"))
	_disc(cloud + Vector2(3, 0), 1.0, Color("8a8a96"))
	_disc(cloud + Vector2(-3, 1), 1.0, Color("6e6e7a"))
	for i in 3:
		var ph := fmod(t * 2.0 + i * 0.33, 1.0)
		_canvas.draw_rect(Rect2(cloud + Vector2(-2.0 + i * 2.0, 3.0 + ph * 4.0), Vector2(1, 1)), Color(Pixel.TEAL, 1.0 - ph))


# WRONG WAY BRO: the mine's timber doorway, filled with rubble from the cave-in, dust
# drifting off it
func _icon_mine_back(t: float):
	for px: float in [-8.0, 5.0]:                                                      # the posts
		_canvas.draw_rect(Rect2(px - 1.0, -7, 5, 17), Pixel.INK)
		_canvas.draw_rect(Rect2(px, -6, 3, 15), WOOD)
		_canvas.draw_rect(Rect2(px, -6, 1, 15), WOOD_LIGHT)
	_canvas.draw_rect(Rect2(-10, -10, 20, 5), Pixel.INK)                              # the beam over them
	_canvas.draw_rect(Rect2(-9, -9, 18, 3), WOOD)
	_canvas.draw_rect(Rect2(-9, -9, 18, 1), WOOD_LIGHT)
	var stone := Color("8a8a96")
	var stone_dark := Color("5e5e6a")
	for r: Array in [[Vector2(-3, 6), 3.0], [Vector2(2, 6), 3.0], [Vector2(0, 2), 2.5], [Vector2(-3, 0), 2.0],
			[Vector2(3, 1), 2.0], [Vector2(-1, -3), 2.0], [Vector2(2, -4), 1.5]]:        # the rubble filling the way
		_disc(r[0], float(r[1]) + 1.0, Pixel.INK)
	for r: Array in [[Vector2(-3, 6), 3.0], [Vector2(2, 6), 3.0], [Vector2(0, 2), 2.5], [Vector2(-3, 0), 2.0],
			[Vector2(3, 1), 2.0], [Vector2(-1, -3), 2.0], [Vector2(2, -4), 1.5]]:
		_disc(r[0], r[1], stone if int((r[0] as Vector2).x) % 2 == 0 else stone_dark)
		_canvas.draw_rect(Rect2((r[0] as Vector2) - Vector2(1, 1), Vector2(1, 1)), Color("b4b4c0"))
	for i in 3:                                                                        # dust drifting off it
		var ph := fmod(t * 0.8 + i * 0.33, 1.0)
		_canvas.draw_rect(Rect2(-4.0 + i * 4.0, roundf(-5.0 - ph * 4.0), 2, 2), Color(Pixel.PALE, 0.6 * (1.0 - ph)))


# HARD WORKER: a flexed arm, a fist up and the bicep bulging, a drop of sweat flying off it
func _icon_hard_worker(t: float):
	var skin := Color("e8b890")
	var shade := Color("c48c64")
	var flex := roundf(absf(sin(t * 4.0)))                                           # it pumps
	var bicep := Vector2(-4, 1 - flex)
	_canvas.draw_rect(Rect2(-10, 2, 11, 6), Pixel.INK)                                # ink round it all first
	_disc(bicep, 4.5, Pixel.INK)
	_canvas.draw_rect(Rect2(-1, -6, 7, 14), Pixel.INK)
	_canvas.draw_rect(Rect2(-2, -10, 9, 6), Pixel.INK)
	_canvas.draw_rect(Rect2(-9, 3, 9, 4), skin)                                       # the upper arm
	_disc(bicep, 3.5, skin)                                                           # the bicep
	_canvas.draw_rect(Rect2(bicep + Vector2(-1, -2), Vector2(2, 1)), Color("f6d8c0"))
	_canvas.draw_rect(Rect2(0, -5, 5, 12), skin)                                      # the forearm, up
	_canvas.draw_rect(Rect2(4, -5, 1, 12), shade)
	_canvas.draw_rect(Rect2(-1, -9, 7, 4), skin)                                      # the fist
	_canvas.draw_rect(Rect2(-1, -6, 7, 1), shade)
	for kx in 3:
		_canvas.draw_rect(Rect2(0.0 + kx * 2.0, -9, 1, 1), shade)                      # knuckles
	var ph := fmod(t * 1.2, 1.0)                                                       # a drop of sweat flying off
	var drop := Vector2(-6, -4) + Vector2(-ph * 4.0, ph * ph * 6.0 - ph * 3.0)
	_canvas.draw_rect(Rect2(drop.round(), Vector2(1, 1)), Color(Pixel.TEAL, 1.0 - ph))
	_canvas.draw_rect(Rect2(drop.round() + Vector2(-1, 1), Vector2(3, 2)), Color(Pixel.TEAL, 1.0 - ph))
	_canvas.draw_rect(Rect2(drop.round() + Vector2(-1, 1), Vector2(1, 1)), Color(Pixel.WHITE, 0.8 * (1.0 - ph)))


# PROBABLY NEED TO REDO THE TUTORIAL: an open book (the tutorial), lines of text on its pages, a red "?" bobbing
# over it
func _icon_tutorial(t: float):
	var paper := Color("f3ead0")
	var paper_shade := Color("d8cba6")
	_poly(PackedVector2Array([Vector2(-9, -1), Vector2(0, 1), Vector2(0, 9), Vector2(-9, 7)]), paper)       # left page
	_poly(PackedVector2Array([Vector2(0, 1), Vector2(9, -1), Vector2(9, 7), Vector2(0, 9)]), paper_shade)   # right page
	_canvas.draw_line(Vector2(0, 1), Vector2(0, 9), Pixel.INK, 1.0)                    # the spine
	for k in 3:                                                                        # lines of text
		_canvas.draw_line(Vector2(-7, 1.5 + k * 2.0), Vector2(-2, 2.5 + k * 2.0), Color("8a7a6a"), 1.0)
		_canvas.draw_line(Vector2(2, 2.5 + k * 2.0), Vector2(7, 1.5 + k * 2.0), Color("8a7a6a"), 1.0)
	var y := -8.0 + roundf(sin(t * 4.0))                                                # the "?"
	var q := Color("e8402e")
	for p: Vector2 in [Vector2(-1, 0), Vector2(0, -1), Vector2(1, -1), Vector2(2, 0), Vector2(2, 1), Vector2(1, 2),
			Vector2(0, 3), Vector2(0, 5)]:
		_canvas.draw_rect(Rect2(Vector2(-1, y) + p - Vector2(1, 1), Vector2(3, 3)), Pixel.INK)
	for p: Vector2 in [Vector2(-1, 0), Vector2(0, -1), Vector2(1, -1), Vector2(2, 0), Vector2(2, 1), Vector2(1, 2),
			Vector2(0, 3), Vector2(0, 5)]:
		_canvas.draw_rect(Rect2(Vector2(-1, y) + p, Vector2(1, 1)), q)


# NO SWEAT: a cool customer: a sunny face in sunglasses, grinning
func _icon_no_sweat(_t: float):
	_disc(Vector2.ZERO, 8.0, Pixel.INK)
	_disc(Vector2.ZERO, 7.0, Pixel.MUSTARD)
	_disc(Vector2(-2, -2), 3.0, Color(1, 1, 1, 0.25))
	_canvas.draw_rect(Rect2(-6, -2, 5, 3), Pixel.INK)                                # the shades
	_canvas.draw_rect(Rect2(1, -2, 5, 3), Pixel.INK)
	_canvas.draw_rect(Rect2(-1, -2, 2, 1), Pixel.INK)
	_canvas.draw_rect(Rect2(-5, -2, 1, 1), Pixel.WHITE)
	_canvas.draw_rect(Rect2(2, -2, 1, 1), Pixel.WHITE)
	for q: Vector2 in [Vector2(-3, 3), Vector2(-2, 4), Vector2(-1, 4), Vector2(0, 4), Vector2(1, 4), Vector2(2, 3)]:
		_canvas.draw_rect(Rect2(q, Vector2(1, 1)), Pixel.INK)                        # the grin


# GREAT CUSTOMER SERVICE: the pina colada: a hurricane glass of cream, an umbrella and a pineapple wedge
func _icon_service(_t: float):
	_poly(PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(4, 0), Vector2(1, 3), Vector2(-1, 3),
		Vector2(-4, 0)]), CREAM)
	_canvas.draw_rect(Rect2(-4, -5, 8, 1), Pixel.WHITE)
	_canvas.draw_rect(Rect2(-1, 3, 2, 4), Pixel.PALE)                                 # the stem and foot
	_canvas.draw_rect(Rect2(-4, 7, 8, 1), Pixel.PALE)
	_canvas.draw_line(Vector2(-5, -9), Vector2(-1, -4), Pixel.PALE, 1.0)             # the umbrella
	_canvas.draw_rect(Rect2(-9, -10, 7, 2), HIBISCUS)
	_canvas.draw_rect(Rect2(-8, -11, 5, 1), HIBISCUS_LIGHT)
	_canvas.draw_rect(Rect2(3, -8, 3, 3), Pixel.MUSTARD)                              # the wedge
	_canvas.draw_rect(Rect2(4, -10, 1, 2), LEAF)


# (any without an icon of its own) the pineapple
func _icon_pineapple():
	var cols := {"g": LEAF, "G": LEAF_DARK, "#": Pixel.MUSTARD, "o": Pixel.RUST, "w": Pixel.WHITE}
	for row in PINEAPPLE.size():
		var line: String = PINEAPPLE[row]
		for col in line.length():
			if cols.has(line[col]):
				_canvas.draw_rect(Rect2(col - 5.5, row - 7.0, 1, 1), cols[line[col]])
