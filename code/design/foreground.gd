extends Node2D
# Foreground: dark jungle silhouettes in front of everything, as if right next to the camera. Big leaves,
# ferns and grass rise from the bottom of the screen, vines and palm fronds hang from the top, and now and
# then a tree trunk sweeps past. They move PARALLAX times as fast as the level, so they read as close.
# They stay at the screen edges (the middle is left clear for the fight) and turn see-through whenever
# the player or an enemy is behind one.
# Jumping moves them too: they stay put in the world while the camera rises, so ground plants drop away
# and hanging ones slide down to show the rest of the plant above (a long stem, out of sight until then).
# Landing higher up, they settle back to the screen edges; going lower, they stay at the edges.
# Drop this node into a level (like LivingBackground) and set from_x / to_x to the level's ends.
# PLACEHOLDER art (scene/design/art/fg_*.png).

const ART := {
	"monstera": preload("res://scene/design/art/fg_monstera.png"),
	"fern": preload("res://scene/design/art/fg_fern.png"),
	"grass": preload("res://scene/design/art/fg_grass.png"),
	"vine": preload("res://scene/design/art/fg_vine.png"),
	"frond_top": preload("res://scene/design/art/fg_frond_top.png"),
	"trunk": preload("res://scene/design/art/fg_trunk.png"),
}
const BOTTOM := ["monstera", "fern", "grass", "monstera"]    # rising from the bottom edge
const TOP := ["vine", "frond_top", "vine"]                    # hanging from the top edge
const ABOVE := {"vine": "vine", "frond_top": "vine", "trunk": "trunk"}   # what grows above, stacked upward
const PARALLAX := 1.35                  # how much faster than the level they move
const BOTTOM_EVERY := Vector2(160, 300) # gap between bottom pieces (random, in level pixels)
const TOP_EVERY := Vector2(220, 420)
const TRUNK_EVERY := Vector2(900, 1500)
const SINK := 6.0                       # bottom pieces sink this far below the screen edge
const MAX_RISE := 192.0                 # a jump up to this high moves them (a double jump is about 185px)
const ABOVE_HEIGHT := 300               # at least this much plant above each hanging piece (> MAX_RISE * PARALLAX)
const SETTLE := 8.0                     # how fast they slide back to the edges after landing higher up
const TELEPORT := 64.0                  # a camera jump this big in one frame (a respawn) puts them straight back
const SEE_THROUGH := 0.3                # alpha when something is behind a piece
const FADE_SPEED := 6.0                 # alpha per second
const PLAYER_BOX := Rect2(-13, -40, 26, 40)
const ENEMY_BOX := Rect2(-20, -36, 40, 36)
const Z := 20

@export var from_x := 0.0
@export var to_x := 12000.0
@export var layout_seed := 1            # a different number gives a different layout

var player: Node2D = null
var _pieces: Array = []                 # each: [Sprite2D, anchor x, "bottom" / "top" / "trunk", art offset, solid rects, art size]
var _tall := {}                         # art name -> [texture, where the art sits in it, solid rects]
var _base_y := NAN                      # the camera's height when the player last stood on the ground
var _last_y := NAN
var _indoors := false                   # underground (the mine): the plants fade away


func _ready():
	add_to_group("foreground")       # the mine (mine_cave.gd) tells it when you're underground
	top_level = true
	z_index = Z
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_scatter(rng, BOTTOM, "bottom", BOTTOM_EVERY)
	_scatter(rng, TOP, "top", TOP_EVERY)
	_scatter(rng, ["trunk"], "trunk", TRUNK_EVERY)


func _scatter(rng: RandomNumberGenerator, names: Array, kind: String, every: Vector2):
	var x := from_x + rng.randf_range(0.0, every.y)
	while x < to_x:
		var art: String = names[rng.randi() % names.size()]
		var tall: Array = _tall_art(art)
		var s := Sprite2D.new()
		s.texture = tall[0]
		s.centered = false
		s.flip_h = rng.randf() < 0.5
		s.visible = false
		add_child(s)
		var at: Vector2 = tall[1]
		var solid: Array = tall[2]
		if s.flip_h:                                  # mirror where the art and its stem sit
			var w := float(s.texture.get_width())
			at.x = w - at.x - ART[art].get_width()
			solid = solid.map(func(r: Rect2): return Rect2(w - r.end.x, r.position.y, r.size.x, r.size.y))
		_pieces.append([s, x, kind, at, solid, ART[art].get_size()])
		x += rng.randf_range(every.x, every.y)


# The art with what grows above it stacked on top (for hanging pieces and trunks), built once per art.
# Returns [texture, where the art's top-left sits in it, its solid parts as rects].
func _tall_art(art_name: String) -> Array:
	if _tall.has(art_name):
		return _tall[art_name]
	var tex: Texture2D = ART[art_name]
	var result := [tex, Vector2.ZERO, [Rect2(Vector2.ZERO, tex.get_size())]]
	if ABOVE.has(art_name):
		var art := tex.get_image()
		art.convert(Image.FORMAT_RGBA8)
		var stem: Image = ART[ABOVE[art_name]].get_image()
		stem.convert(Image.FORMAT_RGBA8)
		if ABOVE[art_name] == "vine":
			_trim_leaf(stem)
		var sw := stem.get_width()
		var sh := stem.get_height()
		var copies := ceili(float(ABOVE_HEIGHT) / sh)
		var above := copies * sh
		# line the stem's bottom up with where the art's own stem leaves its top edge
		var join: int = 0 if ABOVE[art_name] == art_name else _darkest_x(art, 0) - _darkest_x(stem, sh - 1)
		var left := mini(0, join)
		var img := Image.create_empty(maxi(art.get_width(), join + sw) - left, above + art.get_height(), false, Image.FORMAT_RGBA8)
		for i in copies:
			img.blend_rect(stem, Rect2i(0, 0, sw, sh), Vector2i(join - left, i * sh))
		img.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i(-left, above))
		var at := Vector2(-left, above)
		result = [ImageTexture.create_from_image(img), at, [Rect2(at, tex.get_size()), Rect2(join - left, 0, sw, above)]]
	_tall[art_name] = result
	return result


# The vine art ends partway into a new leaf. Stacked, that stub would sit loose against the next copy,
# so its last two rows keep only the stem.
func _trim_leaf(img: Image):
	for y in [img.get_height() - 2, img.get_height() - 1]:
		var x0 := _darkest_x(img, y)
		for x in img.get_width():
			if x < x0 or x > x0 + 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


# x of the darkest pixel on a row: where a stem crosses it
func _darkest_x(img: Image, y: int) -> int:
	var best := 0
	var dark := INF
	for x in img.get_width():
		var c := img.get_pixel(x, y)
		if c.a > 0.5 and c.get_luminance() < dark:
			dark = c.get_luminance()
			best = x
	return best


func _process(delta: float):
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
	var view := get_viewport().get_visible_rect().size / cam.zoom
	var center := cam.get_screen_center_position()
	var left := center.x - view.x / 2.0
	var top := center.y - view.y / 2.0
	var bottom := center.y + view.y / 2.0
	var lift := _lift(center.y, delta)
	var boxes := _boxes()
	for p: Array in _pieces:
		var s: Sprite2D = p[0]
		var anchor: float = p[1]
		var kind: String = p[2]
		var at: Vector2 = p[3]
		var size: Vector2 = p[5]
		# close to the camera: it moves PARALLAX times as fast as the level
		var x := center.x + (anchor - center.x) * PARALLAX - size.x / 2.0
		var y := top - 4.0 + lift                        # "top": hangs from the top edge
		if kind == "bottom":
			y = bottom - size.y + SINK + lift
		elif kind == "trunk":
			y = center.y - size.y / 2.0 + lift            # tall enough to span the whole screen
		var pos := (Vector2(x, y) - at).round()
		if pos.x + s.texture.get_width() < left - 8.0 or pos.x > left + view.x + 8.0:
			s.visible = false
			continue
		s.visible = true
		s.global_position = pos
		var target := SEE_THROUGH if _something_behind(pos, p[4], boxes) else 1.0
		if _indoors:
			target = 0.0                 # underground: no jungle at the screen's edges
		s.modulate.a = move_toward(s.modulate.a, target, FADE_SPEED * delta)


# How far down the screen the plants have moved because the camera rose above where the player last
# stood (a jump). Like the level, they stay put in the world, only moving PARALLAX times as fast.
func _lift(cam_y: float, delta: float) -> float:
	if is_nan(_base_y) or absf(cam_y - _last_y) > TELEPORT:
		_base_y = cam_y
	_last_y = cam_y
	var body := player as CharacterBody2D
	if body and body.is_on_floor():
		_base_y = lerpf(_base_y, cam_y, 1.0 - exp(-SETTLE * delta))  # landed higher up: settle back
	_base_y = clampf(_base_y, cam_y, cam_y + MAX_RISE)              # gone lower: they stay at the edges
	return (_base_y - cam_y) * PARALLAX


# The player's and enemies' boxes this frame
func _boxes() -> Array:
	var boxes := []
	if player:
		boxes.append(Rect2(player.global_position + PLAYER_BOX.position, PLAYER_BOX.size))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and e.visible:
			boxes.append(Rect2(e.global_position + ENEMY_BOX.position, ENEMY_BOX.size))
	return boxes


func _something_behind(pos: Vector2, solid: Array, boxes: Array) -> bool:
	for r: Rect2 in solid:
		var area := Rect2(pos + r.position, r.size)
		for b: Rect2 in boxes:
			if area.intersects(b):
				return true
	return false


# the mine (mine_cave.gd) calls this as you go underground and come back up
func set_indoors(on: bool):
	_indoors = on
