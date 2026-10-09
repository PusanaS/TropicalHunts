extends Node2D
# THE LAB BAY (Morgan's idea, 2026-10-09): past the bunker door, after a stretch of plain white corridor, the
# jelly factory opens up. The back wall of the corridor is a pair of huge shutters; as you come at them they
# slide apart (the top into the ceiling, the bottom into the floor) with a rumble, and behind your catwalk's
# railing there's a vast lab bay:
# a far wall with a neon JELLY JUICE CO. sign, giant glass vats of juice (mango, lime, berry, coconut,
# dragonfruit, grape) bubbling, with pipes, ladders and a catwalk between them; a conveyor of fruit with a
# robot arm dunking them; consoles with blinking screens; steam; and lots of little lab-coated scientists
# walking about, typing, carrying clipboards. You only see it for a moment as you gallop by.
# It's drawn in layers that move at different speeds (parallax) as you pass, behind you (z -49, over the lab's
# back wall), clipped to the opening. Put it at the opening's left end, on the floor; `width` along.
# PLACEHOLDER art, drawn in code.

const Pixel := preload("res://code/design/pixel_font.gd")
const SHUTTER_TIME := 1.2
const OPEN_LEAD := 0.5               # the shutters start opening about this long before you'd reach them...
const OPEN_NEAR := 140.0             # ...but no closer than this (walking: you see them go)...
const OPEN_FAR := 300.0              # ...or further than this (at a gallop)
const WALL := Color("dfe6eb")
const WALL_RIB := Color("c3ced8")
const WALL_DARK := Color("aab6c0")
const WINDOW := Color("3a4a5c")
const WINDOW_SHINE := Color("5a6e82")
const NEON := Color("7fe6ff")
const STEEL := Color("b8c3cc")
const STEEL_LIGHT := Color("dbe3e9")
const STEEL_DARK := Color("8d99a4")
const GLASS := Color(0.85, 0.95, 1.0, 0.45)
const PIPE := Color("9aa7b2")
const PIPE_DARK := Color("74828e")
const BELT := Color("4a5560")
const BELT_LIGHT := Color("6a7682")
const COAT := Color("f4f7f9")
const COAT_SHADE := Color("cdd6dd")
const SKIN := Color("ecded9")
const HAIR := Color("4a3a32")
const GOGGLE := Color("3a5a7a")
const LEGS := Color("3a3f4a")
const CLIP := Color("8e6a3c")
const RAIL := Color("c9d2da")
const RAIL_GLOW := Color("7fe6ff")
const STEAM := Color(1, 1, 1, 0.5)
const LAMP := Color("ffd84a")
const SHUTTER := Color("e9eef2")
const SHUTTER_SEAM := Color("c9d2da")
const HAZARD := Color("f2c22e")
const HAZARD_DARK := Color("2a2a30")
const JUICES := [["MANGO", Color("f0962f")], ["LIME", Color("8fd14f")], ["BERRY", Color("e8558f")],
	["COCONUT", Color("f2efe6")], ["DRAGON", Color("d23c8c")], ["GRAPE", Color("9b6ad6")]]
const FRUIT := [Color("f0962f"), Color("f2c22e"), Color("8fd14f"), Color("6a4a2a"), Color("d23c8c")]

@export var width := 990.0
@export var ceiling := -224.0

var _player: CharacterBody2D = null
var _open := 0.0                     # the shutters: 0 shut, 1 open
var _opening := false
var _t := 0.0
var _clip := Rect2()
var _vats: Array = []                # [x, w, h, juice index, level]
var _folk: Array = []                # scientists: [x, y, layer, kind, range, speed, phase]
var _rumble := AudioStreamPlayer.new()


func _ready():
	z_as_relative = false
	z_index = -49
	_clip = Rect2(0, ceiling + 6.0, width, -ceiling - 6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var x := -60.0
	var i := 0
	while x < width + 200.0:                         # the vats
		var w := rng.randf_range(64.0, 90.0)
		_vats.append([x, w, rng.randf_range(118.0, 160.0), i % JUICES.size(), rng.randf_range(0.45, 0.85)])
		x += w + rng.randf_range(70.0, 120.0)
		i += 1
	for k in 26:                                      # the scientists: on the floor, and up on the catwalk
		var up := k % 4 == 0
		_folk.append([rng.randf_range(-40.0, width + 120.0), -100.0 if up else -8.0, 1 if up else 2,
			rng.randi() % 4, rng.randf_range(10.0, 60.0), rng.randf_range(12.0, 26.0), rng.randf() * TAU])
	_rumble.stream = preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")
	_rumble.volume_db = -10.0
	_rumble.pitch_scale = 1.2
	add_child(_rumble)


func _process(delta: float):
	_t += delta
	if not _opening:
		_watch_player()
	if _opening:
		_open = minf(_open + delta / SHUTTER_TIME, 1.0)
	var cam := get_viewport().get_camera_2d()
	if cam and absf(cam.get_screen_center_position().x - (global_position.x + width / 2.0)) < width / 2.0 + 300.0:
		queue_redraw()


# the shutters open as you come at them (a stretch past the bunker door, so the door and the bay don't go
# at once: Morgan's call, 2026-10-09)
func _watch_player():
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if _player == null:
			return
	var ahead := global_position.x - _player.global_position.x
	var lead := clampf(absf(_player.velocity.x) * OPEN_LEAD, OPEN_NEAR, OPEN_FAR)
	if ahead <= lead:
		_opening = true
		_rumble.play()


# a layer's sideways shift: far ones (small f) hardly move as you pass
func _off(f: float) -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.0
	return (cam.get_screen_center_position().x - (global_position.x + width / 2.0)) * (1.0 - f)


# a rect, clipped to the opening
func _r(x: float, y: float, w: float, h: float, col: Color):
	var r := Rect2(x, y, w, h).intersection(_clip)
	if r.size.x > 0.0 and r.size.y > 0.0:
		draw_rect(r, col)


func _draw():
	if _open <= 0.0:
		_draw_shutters()
		return
	_draw_far()
	_draw_vats()
	_draw_floor_bits()
	_draw_rail()
	_draw_shutters()
	_draw_frame()


# the far wall: ribs, a band of windows, hanging lamps, and the neon sign
func _draw_far():
	var o := _off(0.15)
	_r(0, ceiling, width, -ceiling, WALL)
	var x := fposmod(o, 90.0) - 90.0
	while x < width + 90.0:
		_r(x, ceiling, 6, -ceiling, WALL_RIB)
		_r(x + 6.0, ceiling, 1, -ceiling, WALL_DARK)
		x += 90.0
	x = fposmod(o, 46.0) - 46.0
	while x < width + 46.0:
		_r(x, ceiling + 30.0, 38, 22, WINDOW)
		_r(x + 4.0, ceiling + 33.0, 3, 16, WINDOW_SHINE)
		x += 46.0
	_r(0, ceiling + 56.0, width, 2, WALL_DARK)
	var sign_x := width / 2.0 - 90.0 + o
	for c: Array in Pixel.cells("JELLY JUICE CO.", Vector2(sign_x, ceiling + 66.0), 2):
		var r: Rect2 = c[0]
		_r(r.position.x - 1.0, r.position.y - 1.0, r.size.x + 2.0, r.size.y + 2.0, Color(NEON, 0.25))
	for c: Array in Pixel.cells("JELLY JUICE CO.", Vector2(sign_x, ceiling + 66.0), 2):
		var r: Rect2 = c[0]
		var flick := 0.85 + 0.15 * sin(_t * 9.0 + r.position.x)
		_r(r.position.x, r.position.y, r.size.x, r.size.y, Color(NEON, flick))
	x = fposmod(o * 1.2, 140.0) - 140.0
	while x < width + 140.0:                          # hanging lamps
		_r(x + 10.0, ceiling + 6.0, 1, 18, STEEL_DARK)
		_r(x + 4.0, ceiling + 24.0, 13, 4, STEEL)
		_r(x + 5.0, ceiling + 28.0, 11, 2, Color(1, 1, 0.9))
		x += 140.0


# the vats (with their juice sloshing behind the glass, bubbles, a lamp blinking, steam), pipes, ladders, a
# catwalk between them, and the scientists up on it
func _draw_vats():
	var o := _off(0.35)
	for v: Array in _vats:
		var x: float = v[0] + o
		var w: float = v[1]
		var h: float = v[2]
		var col: Color = JUICES[v[3]][1]
		var top := -6.0 - h
		_r(x, top + 10.0, w, h - 10.0, STEEL)                          # the shell
		_r(x, top + 10.0, 3, h - 10.0, STEEL_LIGHT)
		_r(x + w - 3.0, top + 10.0, 3, h - 10.0, STEEL_DARK)
		for k in 4:                                                     # its domed top
			_r(x + 6.0 + k * 4.0, top + 6.0 - k * 2.0, w - 12.0 - k * 8.0, 4, STEEL if k % 2 == 0 else STEEL_LIGHT)
		var gx := x + 10.0                                              # the window, and the juice in it
		var gw := w - 20.0
		var gtop := top + 26.0
		var gh := h - 52.0
		_r(gx, gtop, gw, gh, Color(0.2, 0.25, 0.3))
		var level: float = v[4] + sin(_t * 1.1 + x * 0.01) * 0.02
		var surf := gtop + gh * (1.0 - level)
		var xx := 0.0
		while xx < gw:
			var wave := roundf(sin(_t * 3.0 + (gx + xx) * 0.15) * 1.5)
			_r(gx + xx, surf + wave, 2, gtop + gh - surf - wave, col)
			_r(gx + xx, surf + wave, 2, 1, col.lightened(0.35))
			xx += 2.0
		for b in 5:                                                    # bubbles
			var by := gtop + gh - fposmod(_t * (18.0 + b * 7.0) + b * 31.0, gh * level)
			_r(gx + 4.0 + fposmod(b * 17.0, gw - 8.0), by, 2, 2, Color(1, 1, 1, 0.6))
		_r(gx, gtop, gw, gh, GLASS)
		_r(gx + 3.0, gtop + 2.0, 2, gh - 4.0, Color(1, 1, 1, 0.4))
		_r(gx - 2.0, gtop - 2.0, gw + 4.0, 2, STEEL_DARK)
		_r(gx - 2.0, gtop + gh, gw + 4.0, 2, STEEL_DARK)
		var label: String = JUICES[v[3]][0]                              # its label
		var lw := Pixel.width(label, 1)
		_r(x + w / 2.0 - lw / 2.0 - 2.0, top + 14.0, lw + 4.0, 9, Color("2a3340"))
		for c: Array in Pixel.cells(label, Vector2(roundf(x + w / 2.0 - lw / 2.0), top + 15.0), 1):
			var r: Rect2 = c[0]
			_r(r.position.x, r.position.y, r.size.x, r.size.y, col)
		if int(_t * 2.0 + x) % 2 == 0:                                  # a lamp blinking on it
			_r(x + w - 9.0, top + 12.0, 3, 3, LAMP)
		_r(x + w / 2.0 - 3.0, ceiling, 6, top + 6.0 - ceiling, PIPE)    # a pipe up into the ceiling
		_r(x + w / 2.0 - 3.0, ceiling, 2, top + 6.0 - ceiling, PIPE_DARK)
		for k in 6:                                                     # a ladder up its side
			_r(x - 6.0, top + 20.0 + k * 14.0, 6, 1, STEEL_DARK)
		_r(x - 6.0, top + 18.0, 1, 86, STEEL_DARK)
		_r(x - 1.0, top + 18.0, 1, 86, STEEL_DARK)
		var steam_y := top + 4.0 - fposmod(_t * 14.0 + x, 30.0)        # steam off its vent
		_r(x + w * 0.7, steam_y, 6, 4, Color(STEAM, 0.5 * (1.0 - (top + 4.0 - steam_y) / 30.0)))
	_r(-50 + o, -100, width + 300, 3, STEEL_DARK)                       # the catwalk, and its railing
	_r(-50 + o, -97, width + 300, 2, STEEL)
	_r(-50 + o, -116, width + 300, 1, STEEL_DARK)
	var px := fposmod(o, 30.0) - 30.0
	while px < width + 30.0:
		_r(px, -116, 1, 16, STEEL_DARK)
		px += 30.0
	_r(-50 + o, -150, width + 300, 6, PIPE)                             # a big pipe along the top
	_r(-50 + o, -150, width + 300, 2, Color("b8c4ce"))
	for f: Array in _folk:
		if int(f[2]) == 1:
			_person(f, o)


# the bay's floor: a conveyor of fruit with a robot arm dunking them, consoles with blinking screens, and
# scientists at work
func _draw_floor_bits():
	var o := _off(0.6)
	_r(0, -8, width, 8, WALL_DARK)
	_r(-40 + o, -18, width + 300, 8, BELT)                               # the conveyor
	var rx := fposmod(o - _t * 30.0, 12.0) - 12.0
	while rx < width + 12.0:
		_r(rx, -18, 2, 8, BELT_LIGHT)
		rx += 12.0
	for k in 40:                                                         # fruit riding it
		var fx := fposmod(k * 53.0 + _t * 30.0, width + 400.0) - 200.0 + o
		var c: Color = FRUIT[k % FRUIT.size()]
		_r(fx, -24, 6, 6, c)
		_r(fx + 1.0, -24, 2, 2, c.lightened(0.3))
	var ax := fposmod(o, 420.0) + 120.0                                  # a robot arm, dunking
	while ax < width + 420.0:
		var dip := roundf(absf(sin(_t * 2.2)) * 18.0)
		_r(ax, ceiling + 10.0, 6, -ceiling - 70.0 + dip, STEEL_DARK)
		_r(ax - 8.0, -60.0 + dip, 22, 6, STEEL)
		_r(ax - 8.0, -54.0 + dip, 3, 8, STEEL_DARK)
		_r(ax + 11.0, -54.0 + dip, 3, 8, STEEL_DARK)
		ax += 420.0
	var cx := fposmod(o, 260.0) + 40.0                                   # consoles
	while cx < width + 260.0:
		_r(cx, -30, 28, 22, STEEL)
		_r(cx + 3.0, -27, 22, 10, Color("16222e"))
		for g in 5:
			var gh := 2.0 + roundf(absf(sin(_t * 3.0 + g + cx)) * 6.0)
			_r(cx + 5.0 + g * 4.0, -18.0 - gh, 2, gh, NEON if g % 2 else Color("5fe36a"))
		cx += 260.0
	for f: Array in _folk:
		if int(f[2]) == 2:
			_person(f, o)


# one little scientist: lab coat, goggles, hair; walking back and forth (legs going), or typing, or with a
# clipboard, or peering at something
func _person(f: Array, o: float):
	var kind: int = f[3]
	var walk := kind == 0 or kind == 2
	var x: float = f[0] + o
	var face := 1.0
	if walk:
		var s := sin(_t * float(f[5]) / float(f[4]) + float(f[6]))
		x += s * float(f[4])
		face = 1.0 if cos(_t * float(f[5]) / float(f[4]) + float(f[6])) > 0.0 else -1.0
	var y: float = f[1]
	var step := int(_t * 8.0 + f[6]) % 2 if walk else 0
	_r(x - 2.0, y - 4.0, 2, 4 - step, LEGS)                         # legs
	_r(x + 1.0, y - 4.0, 2, 4 - (1 - step if walk else 0), LEGS)
	_r(x - 3.0, y - 13.0, 7, 9, COAT)                               # the coat
	_r(x + (1.0 if face > 0.0 else -3.0), y - 13.0, 2, 9, COAT_SHADE)
	_r(x - 2.0, y - 18.0, 5, 5, SKIN)                               # head, hair, goggles
	_r(x - 2.0, y - 19.0, 5, 2, HAIR)
	_r(x - 2.0 + (1.0 if face > 0.0 else 0.0), y - 16.0, 4, 1, GOGGLE)
	match kind:
		2:                                                        # a clipboard
			_r(x + face * 4.0 - 1.0, y - 11.0, 3, 4, CLIP)
			_r(x + face * 4.0, y - 10.0, 1, 2, COAT)
		1:                                                        # typing (an arm going)
			var arm := roundf(absf(sin(_t * 12.0 + f[6])) * 2.0)
			_r(x + 3.0, y - 9.0 - arm, 3, 2, COAT)
		3:                                                        # peering, a hand to the goggles
			_r(x + face * 3.0, y - 16.0, 2, 3, SKIN)


# the railing along your catwalk, in front of the bay (lit along its top)
func _draw_rail():
	_r(0, -30, width, 2, RAIL)
	_r(0, -31, width, 1, Color(RAIL_GLOW, 0.8))
	_r(0, -16, width, 1, RAIL)
	var x := 0.0
	while x <= width:
		_r(x, -30, 2, 30, RAIL)
		x += 48.0


# the shutters over the opening: the top one slides up into the ceiling and the bottom one down into the
# floor as they open, hazard stripes where they meet
func _draw_shutters():
	if _open >= 1.0:
		return
	var mid := (ceiling + 6.0) / 2.0
	var k := _open * _open * (3.0 - 2.0 * _open)
	var top_edge := mid - k * (mid - ceiling)
	var bottom_edge := mid + k * (-mid)
	_r(0, ceiling, width, top_edge - ceiling, SHUTTER)
	_r(0, bottom_edge, width, -bottom_edge, SHUTTER)
	var x := 0.0
	while x < width:
		_r(x, ceiling, 1, top_edge - ceiling, SHUTTER_SEAM)
		_r(x, bottom_edge, 1, -bottom_edge, SHUTTER_SEAM)
		x += 96.0
	for e in [top_edge - 6.0, bottom_edge]:                         # the hazard stripes on their edges
		_r(0, e, width, 6, HAZARD_DARK)
		x = 0.0
		while x < width:
			_r(x, e, 6, 6, HAZARD)
			x += 12.0


# the opening's frame: steel posts at its ends and a beam along its top
func _draw_frame():
	draw_rect(Rect2(-4, ceiling, 8, -ceiling), STEEL_DARK)
	draw_rect(Rect2(width - 4.0, ceiling, 8, -ceiling), STEEL_DARK)
	draw_rect(Rect2(0, ceiling, width, 8), STEEL)
	draw_rect(Rect2(0, ceiling + 7.0, width, 1), STEEL_DARK)
