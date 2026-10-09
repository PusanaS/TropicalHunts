extends Node
# THE GROUND (Morgan's call, 2026-10-09: the flat grey floors were sad): every plain floor in the scene gets earth
# painted on, drawn in code like the mountain (mountain.gd) and the overhanging walls (overhang.gd), in their
# colours. One tileable texture, made once: a dark band of topsoil right under the grass with roots hanging down
# from it, earth with wavy strata, pebbles, the odd shell and some grain, getting darker the deeper it goes. It's
# laid on each floor's own "Look" shape (so it fits any shape, slopes too), its top band along the floor's top,
# the pattern running on unbroken from one floor to the next (it's placed by world x).
# Which floors: StaticBody2Ds with no script of their own (the mountain, the walls and the like draw themselves)
# whose names start with one of FLOORS. Walls stay as they are. The living background adds this in the day theme.
# PLACEHOLDER art: BOOM's tiles would replace it.

const ENABLED := true            # (false: the floors stay plain grey, to compare)
const FLOORS := ["Floor", "Ledge", "Plateau", "Shallow", "Step", "PitBed", "Ramp"]
const W := 512
const H := 512
const TOPSOIL := Color("33251a")
const EARTH := Color("4e3a28")
const EARTH_LIGHT := Color("5c4430")
const STRATA := Color("443222")
const DEEP := Color("33251a")
const DEEPEST := Color("2a1e14")
const ROOT := Color("2a1e14")
const STONE := Color("6e6250")
const STONE_SHADE := Color("564c40")
const STONE_LIGHT := Color("8a7c66")
const SHELL := Color("e8d8c0")
const SHELL_SHADE := Color("c9a46a")
const MOSS := Color("526e36")



func _ready():
	_paint.call_deferred()


var _tex: ImageTexture = null


func _paint():
	var root := get_parent().get_parent() if get_parent() else null
	if root == null or not ENABLED:
		return
	_tex = ImageTexture.create_from_image(_make())   # (made fresh each time, about 14ms: a kept copy outlived
	                                                 # a live reload of the script, so changes didn't show)
	for body in root.find_children("*", "StaticBody2D", true, false):
		if body.get_script() != null:
			continue
		var name_text := String(body.name)
		if not FLOORS.any(func(p): return name_text.begins_with(p)):
			continue
		var look := body.get_node_or_null("Look") as Polygon2D
		if look and look.visible and look.polygon.size() >= 3:
			_lay(look)


# the texture on one floor's shape: across by world x (so neighbours line up), down from its own top
func _lay(look: Polygon2D):
	var top := INF
	for p in look.polygon:
		top = minf(top, p.y)
	var uv := PackedVector2Array()
	var gx := look.global_position.x
	for p in look.polygon:
		uv.append(Vector2(gx + p.x, p.y - top))
	look.texture = _tex
	look.uv = uv
	look.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	look.color = Color.WHITE


# the earth, W x H, tiling across (anything near the right edge wraps round to the left). Wide and deep so it
# doesn't visibly repeat (Morgan spotted the plateau's tall side starting over: it was 128 x 192). Strata all the
# way down past the tallest floor side (the plateau's, 256), and only well below anything on screen does it
# darken, in random speckles (a cliff face that got darker partway down looked wrong)
static func _make() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(EARTH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	img.fill_rect(Rect2i(0, 420, W, H - 420), DEEPEST)
	for y in range(300, 420):                              # the fade to deep earth, in speckles
		var deep := clampf((y - 300.0) / 70.0, 0.0, 1.0)
		var deepest := clampf((y - 360.0) / 60.0, 0.0, 1.0)
		for x in W:
			var r := rng.randf()
			if r < deepest * deepest:
				img.set_pixel(x, y, DEEPEST)
			elif r < deep * deep:
				img.set_pixel(x, y, DEEP)
	for band: Array in [[30, EARTH_LIGHT, 4, 0.0], [68, STRATA, 6, 1.7], [104, EARTH_LIGHT, 3, 3.1],
			[148, STRATA, 5, 0.6], [196, EARTH_LIGHT, 7, 2.3], [244, STRATA, 4, 4.2]]:     # strata
		for x in W:
			var u := TAU * x / W
			var y0: int = band[0] + roundi(sin(u * float(band[2]) + float(band[3])) * 2.0 + sin(u * 11.0 + band[3]) * 1.2)
			var thick := 4 + roundi(sin(u * 9.0 + float(band[3])) * 1.0 + sin(u * 17.0) * 0.6)
			for y in range(y0, y0 + thick):
				if y < H and img.get_pixel(x, y) == EARTH:
					img.set_pixel(x, y, band[1])
	for i in 1300:                                         # grain
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(6, 290)
		var base := img.get_pixel(x, y)
		img.set_pixel(x, y, base.darkened(0.18) if i % 2 else base.lightened(0.08))
	for i in 96:                                           # pebbles, and now and then a bigger rock
		var cx := rng.randi_range(0, W - 1)
		var cy := rng.randi_range(10, 270)
		var rx := rng.randi_range(1, 3) if i % 9 else rng.randi_range(4, 6)
		var ry := maxi(rx - rng.randi_range(0, 1), 1)
		for dy in range(-ry, ry + 1):
			for dx in range(-rx, rx + 1):
				if float(dx * dx) / float(rx * rx) + float(dy * dy) / float(ry * ry) <= 1.1:
					var c := STONE
					if dx + dy <= -rx:
						c = STONE_LIGHT
					elif dx + dy >= rx:
						c = STONE_SHADE
					_put(img, cx + dx, cy + dy, c)
	for i in 14:                                           # the odd shell
		var sx := rng.randi_range(0, W - 1)
		var sy := rng.randi_range(36, 250)
		for q: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, -1)]:
			_put(img, sx + q.x, sy + q.y, SHELL)
		_put(img, sx + 1, sy + 1, SHELL_SHADE)
		_put(img, sx, sy + 1, SHELL_SHADE)
	for x in W:                                            # the topsoil under the grass, a ragged lower edge
		var u := TAU * x / W
		var depth := 3 + (1 if sin(u * 24.0) + sin(u * 53.0) * 0.5 > 0.3 else 0)
		for y in depth:
			img.set_pixel(x, y, TOPSOIL)
		if rng.randf() < 0.1:
			img.set_pixel(x, depth, MOSS)
	for i in 34:                                           # roots hanging down from it, in clumps now and then
		var x := rng.randi_range(0, W - 1)
		var length := rng.randi_range(5, 20)
		for y in range(3, 3 + length):
			_put(img, x, y, ROOT)
			if rng.randf() < 0.35:
				x += rng.randi_range(-1, 1)
			if y == 5 + i % 4 and rng.randf() < 0.5:         # a side root
				var side := 1 if rng.randf() < 0.5 else -1
				for k in rng.randi_range(2, 6):
					_put(img, x + k * side, y + k, ROOT)
	return img


static func _put(img: Image, x: int, y: int, c: Color):
	if y >= 0 and y < H:
		img.set_pixel(posmod(x, W), y, c)
