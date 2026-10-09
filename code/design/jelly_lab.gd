extends Node2D
# THE JELLY JUICE FACTORY (Morgan's idea, 2026-10-09): Level 2, right after the rope bridge. Crossing the
# bridge you see it ahead: a sleek white building, its front all clean panels, a cyan light band, dark
# windows and JELLY JUICE CO. with its jelly-cube logo. Its glass door is shut, and as you come at it (even
# leaping off the breaking bridge) it slides open with a hiss and a puff of cold white air rolls out of the
# lab (Morgan's call, 2026-10-09). Walk in and the front fades away with a white flash, showing the inside: a bright, minimal,
# mostly white lab, like another world. The jungle's gone (the lab's back wall covers the sky, and the
# drifting leaves stop), and the door slides shut behind you. The far door opens as you come up to it, and
# walking out brings the front back.
# Room 1: the lab scientist's duel (lab_duel.gd, lab_scientist.gd), which can dim the lights to two spotlights
# (set_dim, set_spots). Beaten, he flees through the bunker door (bunker_door.gd) into the next part. (The
# jelly pool, jelly_bed.gd, and the gallop-only glass wall, lab_glass.gd, aren't in yet: Morgan's call.)
# Put it at the building's left edge, on the floor. Its walls, ceiling and floors are StaticBody2Ds in the
# scene (WallLab..., collision only): this draws them, and makes its two doors.
# PLACEHOLDER art, drawn in code.

const Pixel := preload("res://code/design/pixel_font.gd")
const TOP := -760.0                  # the building's top (well above anything you can see)
const BOTTOM := 128.0                # its foundations
const FADE := 0.35                   # the front fades out (in) over this long as you go in (out), real time
const FLASH := 0.3                   # the white flash as you go in
const DOOR_TIME := 0.25              # a door slides open or shut in this long
const SHUT_AFTER := 160.0            # the entrance shuts once you're this far in
const EXIT_OPENS := 220.0            # the far door opens once you're this close to it (inside)
# the entrance opens as you come at it, even mid-air (you jump at it from the breaking bridge: it used to wait
# for you to land and you crashed into it), but late enough that you see it open (Morgan's catches,
# 2026-10-09): once you're about DOOR_LEAD seconds from it at your speed, DOOR_NEAR..DOOR_FAR px away (the
# far end keeps it on screen)
const DOOR_LEAD := 0.4
const DOOR_NEAR := 110.0
const DOOR_FAR := 220.0
const PUFFS := 34                    # the puff of cold air out of the door
const PUFF := Color(0.96, 0.99, 1.0)
const HISS_SOUND := preload("res://sounds/sword/sword_swoosh_02.wav")   # (played low: air rushing out)
const HISS_DB := -4.0
const CLUNK_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")   # the lights going
const CLUNK_DB := -12.0
const DIM_TIME := 0.25               # the lights go down (or up) over this long
const SHADE := Color(0.05, 0.07, 0.13)
# the lab
const WALL := Color("e9eef2")
const PANEL_LIGHT := Color("f7fafc")
const PANEL_SHADE := Color("dde4ea")
const SEAM := Color("d1d9e0")
const DADO := Color("dfe6eb")
const FLOOR_TOP := Color("f8fafb")
const FLOOR := Color("d6dde3")
const FLOOR_DEEP := Color("c3ccd4")
const CEIL := Color("f3f6f8")
const CUT := Color("c9d2da")          # the walls and slabs where they're cut through
const CYAN := Color("7fe6ff")
const CYAN_GLOW := Color(0.5, 0.9, 1.0, 0.35)
const LIGHT := Color("ffffff")
const INK_SOFT := Color("9aa8b5")     # the lab's lettering
const METAL := Color("b8c3cc")
const METAL_DARK := Color("8d99a4")
const GLASS := Color(0.85, 0.95, 1.0, 0.35)
const JELLIES := [Color("f0962f"), Color("8fd14f"), Color("e8558f"), Color("9b6ad6")]   # mango, lime, berry, grape
# the outside
const FACADE := Color("f4f7f9")
const FACADE_SEAM := Color("d9e0e6")
const FACADE_EDGE := Color("b3bfc9")
const WINDOW := Color("2c3440")
const WINDOW_SHINE := Color("4a5868")
const FOUNDATION := Color("aab4bd")

@export var width := 2212.0          # the building, outside wall to outside wall
@export var ceiling := -224.0        # the inside's ceiling (its floor is at 0)
@export var wall := 32.0             # the outside walls' thickness
@export var door_h := 112.0
@export var tubes: Array[float] = [420.0, 452.0, 1700.0, 1732.0]   # glass tubes of jelly on the back wall (x)

var _player: Node2D = null
var _inside := false
var _front_a := 1.0
var _flash_a := 0.0
var _t := 0.0
var _in_open := 0.0                  # the doors: 1 open, 0 shut
var _in_opening := false             # the entrance has opened for you
var _out_open := 0.0
var _in_shut := false                # the entrance has shut for good
var _out_opening := false            # the far door is opening (it stays open)
var _back := Node2D.new()            # the lab, drawn once (behind everything that moves)
var _live := Node2D.new()            # the bits that move: bubbles in the tubes, the doors
var _front := Node2D.new()           # the building's front, in front of the player while you're outside
var _flash_layer := CanvasLayer.new()
var _flash := ColorRect.new()
var _door_in := StaticBody2D.new()
var _door_out := StaticBody2D.new()
var _bubbles: Array = []             # [tube index, y, speed, x jitter]
var _puffs: Array = []               # [position, velocity, radius, age, life] the cold air rolling out
var _air := Node2D.new()             # ...drawn in front of everything
var _shade := Node2D.new()           # the lights down: a dark wash over the lab with spotlights
var _dim := 0.0
var _dim_to := 0.0
var _spots: Array = []               # world x of each spotlight
var _hiss := AudioStreamPlayer.new()
var _clunk := AudioStreamPlayer.new()


func _ready():
	for n: Array in [[_back, -50], [_live, -49], [_shade, -48], [_front, 6], [_air, 7]]:
		var node: Node2D = n[0]
		node.z_as_relative = false
		node.z_index = n[1]
		add_child(node)
	_back.draw.connect(_draw_back)
	_live.draw.connect(_draw_live)
	_front.draw.connect(_draw_front)
	_air.draw.connect(_draw_air)
	_shade.draw.connect(_draw_shade)
	for p in [[_hiss, HISS_SOUND, HISS_DB], [_clunk, CLUNK_SOUND, CLUNK_DB]]:
		var snd: AudioStreamPlayer = p[0]
		snd.stream = p[1]
		snd.volume_db = p[2]
		add_child(snd)
	_flash_layer.layer = 8
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_layer.add_child(_flash)
	add_child(_flash_layer)
	_make_door(_door_in, Vector2(wall / 2.0, -door_h / 2.0), "WallLabDoorIn")
	_make_door(_door_out, Vector2(width - wall / 2.0, -door_h / 2.0), "WallLabDoorOut")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in tubes.size():
		for k in 5:
			_bubbles.append([i, rng.randf_range(ceiling + 40.0, -60.0), rng.randf_range(10.0, 22.0), rng.randi_range(-4, 4)])


func _make_door(body: StaticBody2D, at: Vector2, door_name: String):
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(wall, door_h)
	shape.shape = rect
	body.add_child(shape)
	body.position = at
	body.name = door_name
	add_child(body)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


var _last := -1.0


func _process(_delta: float):
	var now := _now()
	var dt := 0.0 if _last < 0.0 else minf(now - _last, 0.1)      # real time: the fade isn't slowed
	_last = now
	_t += dt
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	var px := _player.global_position.x - global_position.x
	var inside := px > wall * 0.5 and px < width - wall * 0.5 and _player.global_position.y > global_position.y + ceiling - 40.0
	if inside != _inside:
		_inside = inside
		get_tree().call_group("living_background", "set_indoors", inside)    # (the leaves stop)
		if inside:
			_flash_a = 0.55
	_front_a = move_toward(_front_a, 0.0 if _inside else 1.0, dt / FADE)
	_front.modulate.a = _front_a
	_front.visible = _front_a > 0.0
	_flash_a = move_toward(_flash_a, 0.0, dt / FLASH)
	_flash.color.a = _flash_a
	# the doors: the entrance opens as you land by it (a puff of cold air), shuts behind you for good, and the
	# far one opens as you come up to it
	var door_at := clampf(absf(_player.velocity.x) * DOOR_LEAD + 40.0, DOOR_NEAR, DOOR_FAR) if _player is CharacterBody2D else DOOR_NEAR
	if not _in_opening and px > -door_at and px < wall:
		_open_entrance()
	if not _in_shut and _inside and px > wall + SHUT_AFTER:
		shut_entrance()
	if not _out_opening and _inside and px > width - wall - EXIT_OPENS:
		_out_opening = true
		_door_out.get_child(0).set_deferred("disabled", true)
	var doors_were := Vector2(_in_open, _out_open)
	_in_open = move_toward(_in_open, 1.0 if _in_opening and not _in_shut else 0.0, dt / DOOR_TIME)
	_out_open = move_toward(_out_open, 1.0 if _out_opening else 0.0, dt / DOOR_TIME)
	for f: Array in _puffs:                          # the cold air: rolling out, slowing, spreading, fading
		f[3] += dt
		f[0] += f[1] * dt
		f[1] *= exp(-1.6 * dt)
		f[1].y += 6.0 * dt                           # (cold air sinks a little)
		f[2] += 9.0 * dt
	var puffing := not _puffs.is_empty()
	_puffs = _puffs.filter(func(f): return f[3] < f[4])
	if puffing:
		_air.queue_redraw()
	var dim_was := _dim
	_dim = move_toward(_dim, _dim_to, dt / DIM_TIME)
	if _dim > 0.0 or dim_was > 0.0:
		_shade.queue_redraw()
	var near := absf(px - width / 2.0) < width / 2.0 + 300.0
	if near:
		for b: Array in _bubbles:                    # bubbles rising up the tubes
			b[1] -= b[2] * dt
			if b[1] < ceiling + 34.0:
				b[1] = -60.0
		_live.queue_redraw()
		if doors_were != Vector2(_in_open, _out_open) and _front_a > 0.0:
			_front.queue_redraw()                    # (the front shows the doors too)


# the entrance slides open with a hiss, and cold air puffs out of the lab and rolls along the ground
func _open_entrance():
	_in_opening = true
	_door_in.get_child(0).set_deferred("disabled", true)
	_hiss.pitch_scale = 0.55
	_hiss.play()
	for i in PUFFS:
		var low := i % 3 == 0                         # a third hug the floor
		var y := -randf_range(2.0, 10.0) if low else -randf_range(8.0, door_h - 10.0)
		_puffs.append([Vector2(wall * 0.5 + randf_range(-4.0, 6.0), y),
			Vector2(-randf_range(90.0, 300.0), randf_range(-10.0, 4.0) if low else randf_range(-50.0, 10.0)),
			randf_range(4.0, 9.0), randf_range(-0.15, 0.0), randf_range(1.0, 1.9)])


# the entrance shuts for good (behind you once you're in, or straight away: the duel shuts it)
func shut_entrance():
	if _in_shut:
		return
	_in_shut = true
	_door_in.get_child(0).set_deferred("disabled", false)
	_hiss.pitch_scale = 0.8
	_hiss.play()


# the lights go down to two spotlights (lab_duel.gd), or come back up
func set_dim(on: bool):
	if on != (_dim_to > 0.0):
		_clunk.pitch_scale = 0.55 if on else 0.75
		_clunk.play(0.02)
	_dim_to = 1.0 if on else 0.0


# a white flash over the screen (the duel's last clash)
func flash(a: float):
	_flash_a = maxf(_flash_a, a)


# where the spotlights are (world x)
func set_spots(xs: Array):
	_spots = xs


# ---------- the inside (drawn once) ----------
func _draw_back():
	var ci := _back
	var inner := Rect2(wall, ceiling, width - 2.0 * wall, -ceiling)
	ci.draw_rect(Rect2(0, TOP, width, BOTTOM - TOP), CUT)                     # the building, cut through
	ci.draw_rect(inner, WALL)                                                # the back wall
	var x := inner.position.x                                                # its panels
	while x < inner.end.x:
		var w := minf(96.0, inner.end.x - x)
		for row in 2:
			var y0 := ceiling + 8.0 + row * ((-56.0 - ceiling - 8.0) / 2.0)
			var h := (-56.0 - ceiling - 8.0) / 2.0 - 2.0
			ci.draw_rect(Rect2(x + 1, y0, w - 2, h), WALL)
			ci.draw_rect(Rect2(x + 1, y0, w - 2, 1), PANEL_LIGHT)
			ci.draw_rect(Rect2(x + 1, y0 + h - 1, w - 2, 1), PANEL_SHADE)
			ci.draw_rect(Rect2(x, y0, 1, h), SEAM)
		x += 96.0
	ci.draw_rect(Rect2(inner.position.x, -48, inner.size.x, 48), DADO)        # the lower band
	ci.draw_rect(Rect2(inner.position.x, -48, inner.size.x, 1), SEAM)
	ci.draw_rect(Rect2(inner.position.x, -53, inner.size.x, 1), CYAN_GLOW)    # its glowing strip
	ci.draw_rect(Rect2(inner.position.x, -52, inner.size.x, 2), CYAN)
	ci.draw_rect(Rect2(inner.position.x, -50, inner.size.x, 1), CYAN_GLOW)
	ci.draw_rect(Rect2(0, ceiling - 40.0, width, 40), CEIL)                   # the ceiling
	ci.draw_rect(Rect2(inner.position.x, ceiling - 1.0, inner.size.x, 1), SEAM)
	x = inner.position.x + 64.0
	while x + 64.0 < inner.end.x:                                            # its lights, glowing down
		ci.draw_rect(Rect2(x, ceiling - 3.0, 64, 3), LIGHT)
		for k in 4:
			ci.draw_rect(Rect2(x - k * 4.0, ceiling + k * 3.0, 64 + k * 8.0, 3), Color(1, 1, 1, 0.18 - k * 0.04))
		x += 192.0
	ci.draw_rect(Rect2(0, 0, width, 3), FLOOR_TOP)                            # the floor: a bright edge,
	ci.draw_rect(Rect2(0, 3, width, 40), FLOOR)                               # then the slab, getting deeper
	ci.draw_rect(Rect2(0, 43, width, BOTTOM - 43.0), FLOOR_DEEP)
	x = 0.0
	while x < width:
		ci.draw_rect(Rect2(x, 3, 1, 10), SEAM)
		x += 64.0
	for side in [0.0, width - wall]:                                          # the outside walls, cut through
		ci.draw_rect(Rect2(side, TOP, wall, -door_h - TOP), CUT)
		ci.draw_rect(Rect2(side + (wall - 1.0 if side == 0.0 else 0.0), ceiling, 1, -door_h - ceiling), SEAM)
	_draw_text(ci, "JELLY JUICE CO.", Vector2(wall + 120.0, ceiling + 40.0), 2, INK_SOFT)
	_draw_logo(ci, Vector2(wall + 96.0, ceiling + 47.0))
	_draw_text(ci, "LAB 01", Vector2(wall + 120.0, ceiling + 64.0), 1, METAL)
	for i in tubes.size():                                                    # the tubes' glass and caps
		var tx: float = tubes[i]
		ci.draw_rect(Rect2(tx - 1.0, ceiling + 14.0, 20, 6), METAL)
		ci.draw_rect(Rect2(tx - 1.0, -62.0, 20, 6), METAL)
		ci.draw_rect(Rect2(tx - 1.0, -57.0, 20, 1), METAL_DARK)


func _draw_text(ci: CanvasItem, text: String, at: Vector2, s: int, col: Color):
	for c: Array in Pixel.cells(text, at, s):
		ci.draw_rect(c[0], col)


# the jelly-cube logo: a wobbly orange cube with a shine
func _draw_logo(ci: CanvasItem, at: Vector2, k := 1.0):
	ci.draw_rect(Rect2(at, Vector2(14, 12) * k), JELLIES[0])
	ci.draw_rect(Rect2(at + Vector2(0, 9) * k, Vector2(14, 3) * k), JELLIES[0].darkened(0.2))
	ci.draw_rect(Rect2(at + Vector2(2, 2) * k, Vector2(3, 2) * k), Color(1, 1, 1, 0.8))
	ci.draw_rect(Rect2(at + Vector2(-1, -2) * k, Vector2(16, 2) * k), JELLIES[0].lightened(0.25))


# ---------- the bits that move ----------
func _draw_live():
	var ci := _live
	for i in tubes.size():                                                    # the tubes of jelly
		var tx: float = tubes[i]
		var col: Color = JELLIES[i % JELLIES.size()]
		var top := ceiling + 20.0
		var fill := top + 28.0 + sin(_t * 1.3 + i) * 2.0
		ci.draw_rect(Rect2(tx, top, 18, -62.0 - top), GLASS)
		ci.draw_rect(Rect2(tx, fill, 18, -62.0 - fill), Color(col, 0.85))
		ci.draw_rect(Rect2(tx, fill, 18, 1), col.lightened(0.35))
		ci.draw_rect(Rect2(tx + 3.0, top, 1, -62.0 - top), Color(1, 1, 1, 0.55))   # the glass's shine
	for b: Array in _bubbles:
		var tx: float = tubes[b[0]]
		var fill := ceiling + 48.0 + sin(_t * 1.3 + b[0]) * 2.0
		if b[1] > fill + 2.0:
			ci.draw_rect(Rect2(tx + 8.0 + b[3], roundf(b[1]), 2, 2), Color(1, 1, 1, 0.6))
	_draw_door(ci, 0.0, _in_open)
	_draw_door(ci, width - wall, _out_open)


# a glass sliding door in a wall's doorway: it slides up into the wall as it opens
func _draw_door(ci: CanvasItem, x: float, open: float):
	ci.draw_rect(Rect2(x, -door_h - 2.0, wall, 2), METAL)                    # the frame over the doorway
	var h := door_h * (1.0 - open)
	if h <= 0.5:
		return
	ci.draw_rect(Rect2(x + wall / 2.0 - 3.0, -door_h, 6, h), Color(0.9, 0.97, 1.0, 0.7))
	ci.draw_rect(Rect2(x + wall / 2.0 - 3.0, -door_h, 1, h), Color(1, 1, 1, 0.9))
	ci.draw_rect(Rect2(x + wall / 2.0 - 3.0, -door_h + h - 2.0, 6, 2), CYAN)


# the puff of cold air: soft round clouds (a few rings fading out), on top of everything
func _draw_air():
	for f: Array in _puffs:
		var age: float = f[3]
		if age < 0.0:
			continue
		var k: float = age / f[4]
		var a := (1.0 - k) * minf(age / 0.12, 1.0) * 0.55
		var r: float = f[2]
		_air.draw_circle(f[0], r, Color(PUFF, a * 0.45))
		_air.draw_circle(f[0], r * 0.7, Color(PUFF, a * 0.6))
		_air.draw_circle(f[0] + Vector2(-r * 0.2, -r * 0.25), r * 0.35, Color(1, 1, 1, a * 0.7))


# the lights down: the lab washed dark, the cyan strip still glowing, and a cone of light down onto each
# spotlit spot with a pool of light on the floor
func _draw_shade():
	if _dim <= 0.0:
		return
	var inner := Rect2(wall, ceiling, width - 2.0 * wall, -ceiling + 4.0)
	_shade.draw_rect(inner, Color(SHADE, 0.62 * _dim))
	_shade.draw_rect(Rect2(inner.position.x, -52, inner.size.x, 2), Color(CYAN, 0.9 * _dim))
	for sx: float in _spots:
		var x: float = sx - global_position.x
		for k in 3:
			var top_w := 8.0 + k * 4.0
			var bottom_w := 34.0 + k * 10.0
			_shade.draw_colored_polygon(PackedVector2Array([Vector2(x - top_w, ceiling), Vector2(x + top_w, ceiling),
				Vector2(x + bottom_w, 0), Vector2(x - bottom_w, 0)]), Color(1, 1, 1, (0.07 - k * 0.018) * _dim))
		for k in 3:
			_shade.draw_rect(Rect2(x - 30.0 - k * 8.0, -2.0 + k, 60.0 + k * 16.0, 3.0), Color(1, 1, 1, (0.2 - k * 0.05) * _dim))
		_shade.draw_rect(Rect2(x - 7.0, ceiling, 14, 2), Color(1, 1, 1, 0.9 * _dim))     # the lamp


# ---------- the outside: the building's front ----------
func _draw_front():
	var ci := _front
	var door_l := Rect2(0, -door_h, wall + 16.0, door_h)                      # (left clear: you see in)
	var door_r := Rect2(width - wall - 16.0, -door_h, wall + 16.0, door_h)
	ci.draw_rect(Rect2(0, TOP, width, -door_h - TOP), FACADE)                 # above the doors
	ci.draw_rect(Rect2(door_l.end.x, -door_h, door_r.position.x - door_l.end.x, door_h), FACADE)
	ci.draw_rect(Rect2(0, 0, width, BOTTOM), FOUNDATION)                      # the foundations
	ci.draw_rect(Rect2(0, 0, width, 2), FACADE_EDGE)
	var x := 128.0                                                            # its panels
	while x < width - 64.0:
		ci.draw_rect(Rect2(x, TOP, 1, -door_h - TOP if x < door_l.end.x or x > door_r.position.x else -TOP), FACADE_SEAM)
		x += 128.0
	var y := -96.0 * 3.0
	while y > TOP:
		ci.draw_rect(Rect2(0, y, width, 1), FACADE_SEAM)
		y -= 96.0
	ci.draw_rect(Rect2(0, -205, width, 34), WINDOW)                           # the dark window band
	x = 40.0
	while x < width:
		for k in 6:
			ci.draw_rect(Rect2(x + k, -204 + k * 5, 2, 5), WINDOW_SHINE)      # reflections
		x += 150.0
	ci.draw_rect(Rect2(0, -168, width, 1), FACADE_SEAM)
	ci.draw_rect(Rect2(0, -127, width, 1), CYAN_GLOW)                         # the cyan light band
	ci.draw_rect(Rect2(0, -126, width, 3), CYAN)
	ci.draw_rect(Rect2(0, -123, width, 1), CYAN_GLOW)
	_draw_logo(ci, Vector2(wall + 40.0, -160.0), 2.0)                         # JELLY JUICE CO.
	_draw_text(ci, "JELLY JUICE CO.", Vector2(wall + 80.0, -158.0), 3, INK_SOFT)
	for r: Rect2 in [door_l, door_r]:                                         # the doorways' frames
		ci.draw_rect(Rect2(r.position.x, -door_h - 4.0, r.size.x, 4), METAL)
	if _in_open < 1.0:                                                        # a shut door: glass
		ci.draw_rect(Rect2(0, -door_h, wall, door_h * (1.0 - _in_open)), Color(0.85, 0.95, 1.0, 0.85))
	ci.draw_rect(Rect2(width - wall, -door_h, wall, door_h * (1.0 - _out_open)), Color(0.85, 0.95, 1.0, 0.85))
	ci.draw_rect(Rect2(0, TOP, 2, -TOP), FACADE_EDGE)                         # its edges
	ci.draw_rect(Rect2(width - 2.0, TOP, 2, -TOP), FACADE_EDGE)
