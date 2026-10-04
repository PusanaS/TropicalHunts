extends Node2D
# THE MINE (level 1, Morgan's idea): everything you see underground between the tunnel mouth (in the
# mountain's foot, mountain.gd) and the dynamite. The mine cart (minecart.gd) races you down the rails through a slanted shaft into a long
# tunnel with snake fruit in its quicksand (sand_serpent.gd), and the dynamite at its end (dynamite.gd)
# blows you back out to the surface.
#  - the earth around it all: strata, stones and roots, so the jungle behind never shows underground
#  - the shaft and the tunnel: a stone back wall with a rocky rim, timber supports, hanging lanterns,
#    crates, dust drifting in the lantern light, glints in the rock and water dripping from the roof
#  - the light: the world darkens as you go down (a CanvasModulate), the lanterns light it warm, and a
#    soft light follows you so you never lose yourself in the dark. The jungle's leaves and the
#    foreground plants are told you're indoors (set_indoors) and hide.
#  - dynamite.gd calls open_crater() when it blows (the earth over the tunnel's end is gone: sky shows
#    through) and fill_crater() once you're out (rubble fills it back up to the ground).
# The collision is the level's own bodies (WallMine*, CeilingMine, SandBedMine): their plain Look
# polygons are for the editor and are hidden here. Put this node at the origin.
# PLACEHOLDER art drawn in code, in BOOM's style (flat colours, one shade each).

const RAIL := [Vector2(4970, 0), Vector2(5040, 0), Vector2(5085, 6), Vector2(5130, 22), Vector2(5440, 286),
	Vector2(5480, 312), Vector2(5520, 320), Vector2(6168, 320)]   # the same rails as minecart.gd
const MOUTH := Vector2(5040, 5260)       # where the rails leave the surface and head down (x from, to)
const PORTAL_TOP := -72.0               # the tunnel mouth in the mountain's foot (mountain.gd): its top
const EARTH_X := Vector2(4700, 7900)     # earth drawn this wide, past the mine, so its edges stay off-screen
const EARTH_TOP := 64.0                  # under the surface floors
const EARTH_BOTTOM := 720.0
const DETAIL_BOTTOM := 470.0             # stones and strata only this deep (below is never on screen)
const TUNNEL := Rect2(5440, 180, 1860, 140)   # the tunnel's inside, to the dead end at x 7300
const HEADROOM := 100.0                  # the shaft's inside reaches this far above the rails
const FLOOR_Y := 320.0
const ROCK_FLOORS := [Vector2(5440, 6260), Vector2(7100, 7560)]   # bare rock floor (the sand covers the rest)
const PLUG := Rect2(7000, 0, 560, 320)   # what the dynamite blows open
const UNDER := Vector2(5040, 7560)       # you're underground inside these x...
const DEPTH_FROM := 20.0                 # ...from this deep, fading in over DEPTH_FADE
const DEPTH_FADE := 140.0
const DARK := Color(0.3, 0.27, 0.4)      # the world's tint deep underground (the lanterns light it back up)
const SUPPORTS := [5300.0, 5390.0, 5560.0, 5710.0, 5860.0, 6010.0, 6160.0, 6310.0, 6460.0, 6610.0, 6760.0,
	6910.0, 7060.0]   # none over the TNT
const LANTERNS := [5390.0, 5560.0, 5860.0, 6160.0, 6460.0, 6760.0, 7060.0]
const DRIPS := [Vector2(5612, 186), Vector2(7283, 186)]

const EARTH := Color("3a2614")
const EARTH_BAND := Color("432d18")
const EARTH_DARK := Color("2a1b0e")
const RIM := Color("5a4128")
const RIM_DARK := Color("1d130a")
const STONE := Color("5e5244")
const STONE_SHADE := Color("463c32")
const ROOT := Color("5c3a1c")
const WALL := Color("2b2233")            # the tunnel's back wall
const WALL_BLOCK := Color("352b3d")
const WALL_CRACK := Color("1e1826")
const ROCK_TOP := Color("6a5642")
const TIMBER := Color("7a4a22")
const TIMBER_SHADE := Color("5a3518")
const TIMBER_LIGHT := Color("9a6532")
const IRON := Color("2e2a26")
const GLASS := Color("ffcf6a")
const FLAME := [Color("fff2b0"), Color("ffcf6a"), Color("f2a23c")]
const CRATE := Color("8a5a2c")
const CRATE_SHADE := Color("664020")
const SURFACE_LOOK := Color(0.22, 0.25, 0.32)   # the level's plain floor blocks (the plug's top, before the blast)
const GLINT := [Color("f6e2ad"), Color("9fe0e8")]
const WATER := Color("72b8ce")
const MOTE := Color("ffe0a0")
const EMBER := [Color("ffcf6a"), Color("f2a23c"), Color("e8761e")]
const LIGHT_COLOR := Color(1.0, 0.74, 0.45)
const PLAYER_LIGHT_COLOR := Color(1.0, 0.93, 0.82)

var player: Node2D = null
var _crater := false                     # the dynamite has blown the end open
var _filled := false                     # ...and rubble has filled it back in
var _crater_t := 0.0
var _depth := 0.0
var _indoors := false
var _t := 0.0
var _modulate := CanvasModulate.new()
var _lights: Array = []                  # [PointLight2D, base energy, phase]
var _player_light := PointLight2D.new()
var _live := Node2D.new()                # what moves: flames, dust, glints, drips, embers
var _stones: Array = []                  # [Rect2, shade?]
var _roots: Array = []                   # [from, to]
var _blocks: Array = []                  # [Rect2] stone blocks in the back wall
var _cracks: Array = []                  # [from, to]
var _glints: Array = []                  # [pos, phase, colour]
var _motes: Array = []                   # [lantern x, offset, phase]
var _rubble: Array = []                  # [Rect2, colour]


func _ready():
	add_to_group("mine_cave")
	global_position = Vector2.ZERO
	z_index = -60                        # over the jungle's parallax layers, behind everything you play in
	add_child(_modulate)
	_modulate.color = Color.WHITE
	_live.z_index = 5                    # -55: over the back wall and supports, still behind you
	_live.draw.connect(_draw_live)
	add_child(_live)
	var tex := _light_texture()
	for x: float in LANTERNS:
		var l := PointLight2D.new()
		l.texture = tex
		l.texture_scale = 2.6
		l.color = LIGHT_COLOR
		l.energy = 1.1
		l.position = Vector2(x, _lantern_y(x) + 4.0)
		l.enabled = false
		add_child(l)
		_lights.append([l, 1.1, randf() * TAU])
	_player_light.texture = tex
	_player_light.texture_scale = 1.8
	_player_light.color = PLAYER_LIGHT_COLOR
	_player_light.energy = 0.6
	_player_light.enabled = false
	add_child(_player_light)
	_hide_looks(get_tree().current_scene if get_tree().current_scene else get_parent())
	_build_details()


# a soft round light: white in the middle fading to nothing at the edge
func _light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


# the underground bodies' plain editor looks: the cave draws them instead
func _hide_looks(root: Node):
	if root == null:
		return
	for n in root.find_children("*", "StaticBody2D", true, false):
		var body_name := String(n.name)
		if body_name.begins_with("WallMine") or body_name.begins_with("CeilingMine") or body_name.begins_with("SandBedMine"):
			var look := n.get_node_or_null("Look") as CanvasItem
			if look:
				look.visible = false


func _build_details():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5040
	var area := (EARTH_X.y - EARTH_X.x) * (DETAIL_BOTTOM - EARTH_TOP)
	for i in int(area / 900.0):
		var w := float(rng.randi_range(2, 6))
		var p := Vector2(rng.randf_range(EARTH_X.x, EARTH_X.y), rng.randf_range(EARTH_TOP + 4.0, DETAIL_BOTTOM))
		_stones.append([Rect2(p.round(), Vector2(w, float(rng.randi_range(2, 4)))), rng.randf() < 0.4])
	var x := EARTH_X.x
	while x < EARTH_X.y:                                           # roots reaching down from the surface
		if x < MOUTH.x or x > MOUTH.y:
			var length := rng.randf_range(10.0, 46.0)
			_roots.append([Vector2(x, EARTH_TOP), Vector2(x + rng.randf_range(-8.0, 8.0), EARTH_TOP + length)])
			if rng.randf() < 0.5:
				var mid := Vector2(x, EARTH_TOP).lerp(_roots[-1][1], 0.5)
				_roots.append([mid, mid + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(6.0, 14.0))])
		x += rng.randf_range(22.0, 48.0)
	# the back wall: rough stone blocks and cracks, inside the tunnel and down the shaft
	for i in 140:
		var at := _random_inside(rng)
		if at == Vector2.INF:
			continue
		_blocks.append(Rect2(at.round(), Vector2(float(rng.randi_range(6, 16)), float(rng.randi_range(4, 9)))))
	for i in 40:
		var at := _random_inside(rng)
		if at != Vector2.INF:
			_cracks.append([at, at + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(4.0, 12.0))])
	for i in 70:                                                   # ore glints in the back wall and the rim
		var at := _random_inside(rng)
		if at != Vector2.INF:
			_glints.append([at.round(), rng.randf() * TAU, GLINT[rng.randi() % GLINT.size()]])
	for lx: float in LANTERNS:
		for i in 6:
			_motes.append([lx, Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-20.0, 60.0)), rng.randf() * TAU])
	for i in 90:                                                   # the rubble that fills the crater later
		var w := float(rng.randi_range(8, 26))
		var h := float(rng.randi_range(6, 16))
		var p := Vector2(rng.randf_range(PLUG.position.x - 4.0, PLUG.end.x - w + 4.0), rng.randf_range(-6.0, PLUG.end.y - h))
		_rubble.append([Rect2(p.round(), Vector2(w, h)), STONE if rng.randf() < 0.55 else (STONE_SHADE if rng.randf() < 0.5 else EARTH_BAND)])


# a random point well inside the tunnel or the shaft (INF if it missed)
func _random_inside(rng: RandomNumberGenerator) -> Vector2:
	if rng.randf() < 0.75:
		var r := TUNNEL.grow(-10.0)
		return Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y - 6.0))
	var x := rng.randf_range(MOUTH.y + 20.0, TUNNEL.position.x - 10.0)
	var top := maxf(EARTH_TOP, _rail_y(x) - HEADROOM)
	var bottom := _rail_y(x) - 14.0
	if bottom - top < 16.0:
		return Vector2.INF
	return Vector2(x, rng.randf_range(top + 6.0, bottom - 6.0))


# the rails' height at x (straight lines between the points)
func _rail_y(x: float) -> float:
	for i in RAIL.size() - 1:
		var a: Vector2 = RAIL[i]
		var b: Vector2 = RAIL[i + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, clampf((x - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0))
	return (RAIL[-1] as Vector2).y


# the roof's height at x: the shaft's roof follows the rails down, then the tunnel's ceiling
func _roof_y(x: float) -> float:
	if x >= TUNNEL.position.x:
		return TUNNEL.position.y
	return maxf(PORTAL_TOP, _rail_y(x) - HEADROOM)        # from the tunnel mouth, following the rails down


func _lantern_y(x: float) -> float:
	return _roof_y(x) + 18.0


# the inside of the shaft and the tunnel, as one outline (clockwise from the mouth)
func _inside() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var end_x := PLUG.position.x if _crater else TUNNEL.end.x
	pts.append(Vector2(MOUTH.x, PORTAL_TOP))                  # the tunnel mouth in the mountain's foot
	var x := MOUTH.x + 10.0
	while x < TUNNEL.position.x:
		pts.append(Vector2(x, _roof_y(x)))
		x += 10.0
	pts.append(TUNNEL.position)
	pts.append(Vector2(end_x, TUNNEL.position.y))
	pts.append(Vector2(end_x, FLOOR_Y))
	x = 5520.0
	pts.append(Vector2(x, FLOOR_Y))
	while x > MOUTH.x + 10.0:
		x -= 10.0
		pts.append(Vector2(x, minf(_rail_y(x) + 10.0, FLOOR_Y)))
	pts.append(Vector2(MOUTH.x, 10.0))
	return _no_straight_runs(pts)


# drops points that sit on a straight line between their neighbours (Godot's polygon fill can trip on them)
func _no_straight_runs(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[(i - 1 + n) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		if absf((b - a).cross(c - b)) > 0.01:
			out.append(b)
	return out


func _process(delta: float):
	_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
	var depth := 0.0
	if player:
		var p := player.global_position
		if p.x >= UNDER.x and p.x <= UNDER.y:
			depth = clampf((p.y - DEPTH_FROM) / DEPTH_FADE, 0.0, 1.0)
	_depth = move_toward(_depth, depth, delta * 3.0)
	_modulate.color = Color.WHITE.lerp(DARK, _depth)
	var lit := _depth > 0.01
	for l: Array in _lights:
		var light: PointLight2D = l[0]
		light.enabled = lit and not (_crater and light.position.x >= PLUG.position.x)
		if light.enabled:                                          # a lantern's flame never quite holds still
			light.energy = l[1] * (0.9 + 0.08 * sin(_t * 9.0 + l[2]) + 0.04 * sin(_t * 23.0 + l[2] * 2.0))
	_player_light.enabled = lit
	if lit and player:
		_player_light.global_position = player.global_position + Vector2(0, -20)
		_player_light.energy = 0.6 * _depth
	var inside := _depth > 0.5
	if inside != _indoors:
		_indoors = inside
		get_tree().call_group("living_background", "set_indoors", inside)
		get_tree().call_group("foreground", "set_indoors", inside)
	if _crater:
		_crater_t += delta
	var cam := get_viewport().get_camera_2d()
	if cam:
		var cx := cam.get_screen_center_position().x
		if cx > EARTH_X.x - 300.0 and cx < EARTH_X.y + 300.0:
			_live.queue_redraw()


# ---------- what dynamite.gd calls ----------
func open_crater():
	_crater = true
	_crater_t = 0.0
	queue_redraw()


func fill_crater():
	_filled = true
	queue_redraw()


# ---------- drawing: the earth, the shaft and tunnel, supports and props ----------
func _draw():
	var open := _crater and not _filled
	# the earth (around the crater once it's blown, back over it once it's filled)
	if _crater:
		draw_rect(Rect2(EARTH_X.x, EARTH_TOP, PLUG.position.x - EARTH_X.x, EARTH_BOTTOM - EARTH_TOP), EARTH)
		draw_rect(Rect2(PLUG.end.x, EARTH_TOP, EARTH_X.y - PLUG.end.x, EARTH_BOTTOM - EARTH_TOP), EARTH)
		draw_rect(Rect2(PLUG.position.x, PLUG.end.y, PLUG.size.x, EARTH_BOTTOM - PLUG.end.y), EARTH)
	else:
		draw_rect(Rect2(EARTH_X.x, EARTH_TOP, EARTH_X.y - EARTH_X.x, EARTH_BOTTOM - EARTH_TOP), EARTH)
		draw_rect(Rect2(PLUG.position.x, 0, PLUG.size.x, EARTH_TOP), SURFACE_LOOK)   # the ground over the end
	draw_rect(Rect2(MOUTH.x, 0, MOUTH.y - MOUTH.x, EARTH_TOP), EARTH)  # under the rails at the mouth (the hole is drawn over it)
	var y := EARTH_TOP + 18.0
	while y < DETAIL_BOTTOM:                                       # strata
		draw_rect(Rect2(EARTH_X.x, y, EARTH_X.y - EARTH_X.x, 7), EARTH_BAND)
		draw_rect(Rect2(EARTH_X.x, y + 7.0, EARTH_X.y - EARTH_X.x, 1), EARTH_DARK)
		y += 31.0
	for s: Array in _stones:
		var r: Rect2 = s[0]
		if open and PLUG.intersects(r):
			continue
		draw_rect(r, STONE_SHADE if s[1] else STONE)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), EARTH_DARK)
	for root: Array in _roots:
		if not (open and PLUG.has_point(root[0])):
			draw_line(root[0], root[1], ROOT, 1.0)
	# the shaft and the tunnel: a rocky rim, then the back wall
	var inside := _inside()
	for rim in _clipped(Geometry2D.offset_polygon(inside, 4.0), open):
		draw_colored_polygon(rim, RIM)
	for rim in _clipped(Geometry2D.offset_polygon(inside, 1.0), open):
		draw_colored_polygon(rim, RIM_DARK)
	draw_colored_polygon(inside, WALL)
	for b: Rect2 in _blocks:
		if not (open and b.position.x >= PLUG.position.x):
			draw_rect(b, WALL_BLOCK)
			draw_rect(Rect2(b.position.x, b.end.y - 1.0, b.size.x, 1), WALL_CRACK)
	for c: Array in _cracks:
		draw_line(c[0], c[1], WALL_CRACK, 1.0)
	for f: Vector2 in ROCK_FLOORS:                                 # bare rock floor where there's no sand
		var to := minf(f.y, PLUG.position.x) if open else f.y
		if to > f.x:
			draw_rect(Rect2(f.x, FLOOR_Y, to - f.x, 2), ROCK_TOP)
	if open:
		_draw_crater()
	if _filled:
		_draw_rubble()
	for x: float in SUPPORTS:
		if not (open and x >= PLUG.position.x):
			_draw_support(x)
	for x: float in LANTERNS:
		if not (open and x >= PLUG.position.x):
			_draw_lantern(x)
	_draw_props()


# the rocky rim stays inside the mountain and the ground (it rims the tunnel mouth), not in the open crater
func _clipped(polys: Array, open: bool) -> Array:
	var right := PLUG.position.x if open else EARTH_X.y
	var top := PORTAL_TOP - 6.0                               # (round the tunnel mouth too)
	var keep := PackedVector2Array([Vector2(EARTH_X.x, top), Vector2(right, top), Vector2(right, EARTH_BOTTOM), Vector2(EARTH_X.x, EARTH_BOTTOM)])
	var out := []
	for poly in polys:
		out.append_array(Geometry2D.intersect_polygons(poly, keep))
	return out


# a timber frame: two posts holding a cap beam under the roof, with knee braces
func _draw_support(x: float):
	var top := _roof_y(x)
	var bottom := FLOOR_Y if x >= TUNNEL.position.x else _rail_y(x) + 8.0
	for side in [-14.0, 10.0]:
		var px: float = x + side
		draw_rect(Rect2(px, top, 4, bottom - top), TIMBER)
		draw_rect(Rect2(px, top, 1, bottom - top), TIMBER_LIGHT)
		draw_rect(Rect2(px + 3.0, top, 1, bottom - top), TIMBER_SHADE)
	draw_rect(Rect2(x - 18.0, top, 32, 5), TIMBER)
	draw_rect(Rect2(x - 18.0, top, 32, 1), TIMBER_LIGHT)
	draw_rect(Rect2(x - 18.0, top + 4.0, 32, 1), TIMBER_SHADE)
	draw_line(Vector2(x - 10.0, top + 5.0), Vector2(x - 2.0, top + 13.0), TIMBER_SHADE, 2.0)
	draw_line(Vector2(x + 10.0, top + 5.0), Vector2(x + 2.0, top + 13.0), TIMBER_SHADE, 2.0)


# a lantern on a chain under a support's cap beam (its flame is drawn live)
func _draw_lantern(x: float):
	var top := _roof_y(x) + 5.0
	var y := _lantern_y(x)
	draw_line(Vector2(x, top), Vector2(x, y - 4.0), IRON, 1.0)
	draw_rect(Rect2(x - 3.0, y - 4.0, 6, 1), IRON)
	draw_rect(Rect2(x - 3.0, y - 3.0, 6, 7), GLASS)
	draw_rect(Rect2(x - 3.0, y - 3.0, 1, 7), IRON)
	draw_rect(Rect2(x + 2.0, y - 3.0, 1, 7), IRON)
	draw_rect(Rect2(x - 3.0, y + 4.0, 6, 2), IRON)


# old mining gear by the crash site: a stack of crates, a barrel and a pickaxe
func _draw_props():
	_draw_crate(Rect2(6188, FLOOR_Y - 14.0, 16, 14))
	_draw_crate(Rect2(6204, FLOOR_Y - 12.0, 14, 12))
	_draw_crate(Rect2(6192, FLOOR_Y - 26.0, 13, 12))
	var b := Rect2(6224, FLOOR_Y - 15.0, 11, 15)                   # barrel
	draw_rect(b, CRATE)
	draw_rect(Rect2(b.position.x + b.size.x - 2.0, b.position.y, 2, b.size.y), CRATE_SHADE)
	for hoop in [3.0, 11.0]:
		draw_rect(Rect2(b.position.x, b.position.y + hoop, b.size.x, 1), IRON)
	draw_line(Vector2(6245, FLOOR_Y), Vector2(6252, FLOOR_Y - 20.0), TIMBER, 2.0)   # pickaxe
	draw_line(Vector2(6246, FLOOR_Y - 22.0), Vector2(6258, FLOOR_Y - 17.0), IRON, 2.0)


func _draw_crate(r: Rect2):
	draw_rect(r, CRATE)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), TIMBER_LIGHT)
	draw_rect(Rect2(r.end.x - 2.0, r.position.y, 2, r.size.y), CRATE_SHADE)
	draw_line(r.position + Vector2(1, 1), r.end - Vector2(2, 1), CRATE_SHADE, 1.0)


# the blown-open end: ragged earth teeth around the hole and a scorched floor
func _draw_crater():
	var rng := RandomNumberGenerator.new()
	rng.seed = 6400
	var y := EARTH_TOP
	while y < PLUG.end.y:                                          # the walls on either side
		var lt := float(rng.randi_range(2, 9))
		var rt := float(rng.randi_range(2, 9))
		if y >= TUNNEL.position.y:
			lt = 0.0                                               # the tunnel runs straight into it on the left
		draw_rect(Rect2(PLUG.position.x, y, lt, 6), EARTH)
		draw_rect(Rect2(PLUG.end.x - rt, y, rt, 6), EARTH)
		draw_rect(Rect2(PLUG.end.x - rt - 1.0, y, 1, 6), RIM)
		y += 6.0
	var x := PLUG.position.x
	while x < PLUG.end.x:                                          # scorched, cracked floor
		draw_rect(Rect2(x, FLOOR_Y - float(rng.randi_range(0, 2)), 6, 3), EARTH_DARK)
		x += 6.0


# rubble filling the crater back up to the ground
func _draw_rubble():
	draw_rect(Rect2(PLUG.position.x, 4.0, PLUG.size.x, PLUG.end.y - 4.0), EARTH_BAND)
	for r: Array in _rubble:
		var rect: Rect2 = r[0]
		draw_rect(rect, r[1])
		draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1), EARTH_DARK)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), ROCK_TOP if r[1] == STONE else RIM)


# ---------- drawing what moves ----------
func _draw_live():
	for x: float in LANTERNS:                                      # flames
		if _crater and not _filled and x >= PLUG.position.x:
			continue
		var y := _lantern_y(x)
		var f := int(_t * 12.0 + x) % 3
		_live.draw_rect(Rect2(x - 1.0, y - 1.0 - float(f % 2), 2, 3), FLAME[f])
		_live.draw_rect(Rect2(x - 1.0, y, 2, 1), FLAME[0])
	for m: Array in _motes:                                        # dust turning in the lantern light
		var lx: float = m[0]
		var o: Vector2 = m[1]
		var ph: float = m[2]
		var p := Vector2(lx + o.x + sin(_t * 0.4 + ph) * 8.0, _lantern_y(lx) + o.y + sin(_t * 0.3 + ph * 2.0) * 6.0)
		var a := 0.35 + 0.35 * sin(_t * 1.3 + ph)
		if a > 0.15:
			_live.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(MOTE, a))
	for g: Array in _glints:                                       # ore catching the light
		var tw := sin(_t * 2.0 + g[1])
		if tw > 0.82:
			var p: Vector2 = g[0]
			_live.draw_rect(Rect2(p, Vector2(1, 1)), g[2])
			if tw > 0.95:
				_live.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(g[2], 0.6))
				_live.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(g[2], 0.6))
	for i in DRIPS.size():                                         # a drop gathers, falls and splashes
		var d: Vector2 = DRIPS[i]
		var k := fmod(_t + i * 1.3, 2.6) / 2.6
		if k < 0.5:
			_live.draw_rect(Rect2(d.x, d.y, 1, 1 + roundf(k * 4.0)), WATER)
		elif k < 0.75:
			var fall := (k - 0.5) / 0.25
			_live.draw_rect(Rect2(d.x, lerpf(d.y + 2.0, FLOOR_Y - 2.0, fall * fall), 1, 2), WATER)
		else:
			var s := (k - 0.75) / 0.25
			_live.draw_rect(Rect2(d.x - 1.0 - roundf(s * 3.0), FLOOR_Y - 1.0 - roundf(s * 2.0), 1, 1), Color(WATER, 1.0 - s))
			_live.draw_rect(Rect2(d.x + 1.0 + roundf(s * 3.0), FLOOR_Y - 1.0 - roundf(s * 2.0), 1, 1), Color(WATER, 1.0 - s))
	if _crater and not _filled and _crater_t < 8.0:                # embers rising off the scorched floor
		for i in 14:
			var h := float(i) * 12.9898
			var life := fmod(_crater_t * 0.6 + fmod(h, 1.0), 1.0)
			var x := PLUG.position.x + fmod(h * 37.0, PLUG.size.x - 160.0) + 20.0
			var p := Vector2(x + sin(_t * 2.0 + h) * 4.0, FLOOR_Y - 4.0 - life * 90.0)
			_live.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(EMBER[i % EMBER.size()], 1.0 - life))
