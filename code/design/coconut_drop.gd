extends Node2D
# A palm in Level 2's coconut grove. Put it where its crown is (the top of the palm).
# With `drops` (on) it drops rolling coconuts: each one shakes loose (a TELL), drops to the floor below and
# rolls off in `dir`, already rolling, so it doesn't need to see the player. They only fall while the player
# is within active_range, at most max_alive at a time, and are freed once they're broken or have rolled far
# away. With gallop_breaks (on), galloping into them smashes them (coconut.gd; Morgan's call, 2026-10-09).
# Without `drops` it's just a palm, for the grove's look: no coconuts in its crown, so you can tell which ones
# drop them. `back` palms stand further back: darker, behind the grass.
# PLACEHOLDER look, drawn in code (Morgan wanted them lusher, 2026-10-09): a thick ringed trunk with a
# criss-cross bark pattern, flaring at its foot and curving out to `lean`; a full crown of long feathery
# fronds, the back ones darker and drooping, the front ones lighter; ferns round the foot; and coconuts (with
# their thin white outline) hanging under the crown. The crowns and ferns are baked into textures once, a few
# variants each, with three sway frames (and mirrored), so a grove of them costs next to nothing.

const Coconut := preload("res://code/design/coconut.gd")
const GREENS := [Color("2c3d1d"), Color("3d5428"), Color("526e36"), Color("76964a"), Color("9ab85a")]
const TRUNK := Color("624021")
const TRUNK_DARK := Color("4d321a")
const TRUNK_LIGHT := Color("7a5430")
const TELL := 0.4                        # the coconut shakes this long before it drops
const REGROW := 0.5                      # then a new one swells back in under the crown over this long
const NUTS := [Vector2(-9, 13), Vector2(9, 14)]   # where the two coconuts hang (their centres)
const HANG := -PI / 2.0                  # the coconuts hang upright, their eyes at the top (coconut.gd's OVAL)
const REDRAW_RANGE := 440.0              # only redrawn (swaying) while the player is this close: on screen
const BACK_TINT := Color(0.55, 0.5, 0.62)
const CROWN_SIZE := Vector2i(204, 128)
const CROWN_AT := Vector2i(102, 48)      # the crown's centre in its texture
const FERN_SIZE := Vector2i(96, 40)
const FERN_AT := Vector2i(48, 39)        # the fern's root in its texture
const VARIANTS := 4
const SWAY := [-2.0, 0.0, 2.0]           # the three sway frames: how far the frond tips lean
# the crown's fronds: [angle (degrees, 0 = right, 90 = up), length, droop, layer (0 back, 1 front), tone]
const FROND_SET := [
	[205.0, 48.0, 0.55, 0, 0], [-25.0, 50.0, 0.55, 0, 0],
	[188.0, 62.0, 0.6, 0, 1], [-8.0, 64.0, 0.6, 0, 1],
	[166.0, 72.0, 0.62, 0, 1], [14.0, 70.0, 0.62, 0, 1],
	[146.0, 66.0, 0.6, 0, 2], [34.0, 68.0, 0.6, 0, 2],
	[152.0, 58.0, 0.55, 1, 2], [28.0, 56.0, 0.55, 1, 2],
	[128.0, 46.0, 0.5, 1, 3], [52.0, 48.0, 0.5, 1, 3],
	[110.0, 34.0, 0.45, 1, 3], [72.0, 36.0, 0.45, 1, 3],
	[92.0, 24.0, 0.3, 1, 3],
]
const FERN_SET := [[172.0, 20.0], [152.0, 25.0], [132.0, 23.0], [112.0, 19.0], [92.0, 16.0], [72.0, 20.0],
	[50.0, 24.0], [28.0, 25.0], [8.0, 20.0]]

@export var drops := true                # drops coconuts (false: just a palm)
@export var back := false                # further back: darker, behind the grass
@export var fern := true                 # ferns round its foot
@export var interval := 2.2              # seconds between coconuts (each a little off, so the palms don't sync)
@export var dir := -1                    # the way they roll: -1 left, 1 right
@export var active_range := 900.0        # only drops while the player is this close (horizontally)
@export var max_alive := 3
@export var trunk := 96.0                # how far down the trunk goes (to the floor)
@export var lean := 0.0                  # where the trunk's foot is, sideways from under the crown (+ right)
@export var roll_speed := 230.0
@export var gallop_breaks := true        # galloping into its coconuts smashes them

static var _crowns := {}                 # "variant:frame:layer" -> texture
static var _ferns := {}                  # variant -> texture

var _timer := 0.0
var _alive: Array = []
var _t := 0.0
var _phase := 0.0
var _tell := false
var _next := 0                           # which hanging coconut drops next
var _regrow: Array[float] = [0.0, 0.0]   # how long till each hanging coconut is back (0: it's there)
var _variant := 0
var _flip := 1.0
var _frame := 1
var _trunk_tex: ImageTexture
var _trunk_x := 0                        # where the crown's centre is across the trunk texture


func _ready():
	z_index = -3 if back else -1         # behind the player (back ones behind the grass too)
	if back:
		self_modulate = BACK_TINT
	_timer = randf_range(TELL, TELL + 0.6)        # the first one comes soon after you're in range
	_phase = fposmod(global_position.x * 0.013, TAU)
	var h := absi(int(global_position.x * 7.0 + trunk * 3.0))
	_variant = h % VARIANTS
	_flip = -1.0 if (h >> 2) % 2 == 1 else 1.0          # (the next bit after the variant's)
	_bake_trunk()


func _physics_process(delta: float):
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var near := player != null and absf(player.global_position.x - global_position.x) < REDRAW_RANGE
	var frame := clampi(roundi(sin(_t * 1.1 + _phase) * 1.4), -1, 1) + 1
	if _tell:
		frame = 2 * (int(_t * 20.0) % 2)              # the crown shakes as a coconut works loose
	if near and (frame != _frame or _tell or _regrow[0] > 0.0 or _regrow[1] > 0.0):
		queue_redraw()
	_frame = frame
	if not drops:
		return
	for i in 2:
		_regrow[i] = maxf(_regrow[i] - delta, 0.0)
	_alive = _alive.filter(func(c): return is_instance_valid(c))
	for c in _alive:
		if absf(c.global_position.x - global_position.x) > active_range * 1.5 or c.global_position.y > global_position.y + 1200.0:
			c.queue_free()
	_tell = false
	if player == null or absf(player.global_position.x - global_position.x) > active_range or _alive.size() >= max_alive:
		return
	_timer -= delta
	_tell = _timer <= TELL
	if _timer <= 0.0:
		_timer = interval * randf_range(0.8, 1.2)
		_drop()


func _drop():
	var c: CharacterBody2D = Coconut.new()
	c.roll_speed = roll_speed
	c.gallop_breaks = gallop_breaks
	c.start_rolling(float(dir), HANG)                 # (still upright as it falls, then it rolls)
	get_parent().add_child(c)
	var nut: Vector2 = NUTS[_next]
	c.global_position = global_position + nut + Vector2(0, Coconut.centre_height(HANG))    # (its origin: its bottom)
	_alive.append(c)
	_regrow[_next] = REGROW
	_next = 1 - _next


func _draw():
	if fern:
		draw_set_transform(Vector2(lean, trunk), 0.0, Vector2(_flip, 1.0))
		draw_texture(_fern(_variant % 2), -Vector2(FERN_AT))
		draw_set_transform(Vector2.ZERO)
	draw_texture(_trunk_tex, Vector2(-_trunk_x, 0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_flip, 1.0))
	draw_texture(_crown(_variant, _frame, 0), -Vector2(CROWN_AT))
	draw_set_transform(Vector2.ZERO)
	if drops:                                         # the coconuts, between the back fronds and the front
		for i in 2:
			var grow: float = 1.0 - _regrow[i] / REGROW
			if grow <= 0.05:
				continue
			var at: Vector2 = NUTS[i]
			if _tell and i == _next:
				at.x += roundf(sin(_t * 45.0) * 1.5)
			draw_set_transform(at.round(), HANG, Vector2(grow, grow))
			Coconut.draw_shell(self, false)
			draw_set_transform(Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_flip, 1.0))
	draw_texture(_crown(_variant, _frame, 1), -Vector2(CROWN_AT))
	draw_set_transform(Vector2.ZERO)


# ---------- the art, baked ----------
# the trunk, from the crown (0, 0) down to its foot (lean, trunk): rings that get wider going down, a sunlit
# side and a shaded one, a criss-cross bark pattern, and a flared foot
func _bake_trunk():
	var w_max := 16
	_trunk_x = (w_max >> 1) + maxi(0, -int(floorf(lean)))
	var img := Image.create(int(absf(lean)) + w_max + 2, int(trunk) + 2, false, Image.FORMAT_RGBA8)
	var y := 4
	var ring := 0
	while y < int(trunk):
		var k := float(y) / trunk
		var w := int(roundf(7.0 + 4.0 * k + 5.0 * clampf((float(y) - (trunk - 10.0)) / 10.0, 0.0, 1.0)))
		var cx := _trunk_x + int(roundf(lean * k * k))
		var x0 := cx - (w >> 1)
		var h := mini(5, int(trunk) - y)
		img.fill_rect(Rect2i(x0, y, w, h), TRUNK)
		img.fill_rect(Rect2i(x0, y, w, 1), TRUNK_DARK)                      # the ring
		if h > 1:
			img.fill_rect(Rect2i(x0, y + 1, 2, h - 1), TRUNK_LIGHT)          # the sunlit side
			img.fill_rect(Rect2i(x0 + w - 2, y + 1, 2, h - 1), TRUNK_DARK)   # the shaded side
		if h > 2:
			for bx in range(x0 + 2 + ring % 2 * 2, x0 + w - 2, 4):            # criss-cross bark
				img.set_pixel(bx, y + 2, TRUNK_DARK)
		y += 5
		ring += 1
	_trunk_tex = ImageTexture.create_from_image(img)


# one layer of a crown variant at one sway frame
static func _crown(variant: int, frame: int, layer: int) -> ImageTexture:
	var key := "%d:%d:%d" % [variant, frame, layer]
	if _crowns.has(key):
		return _crowns[key]
	var img := Image.create(CROWN_SIZE.x, CROWN_SIZE.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	for f: Array in FROND_SET:
		var a: float = f[0] + rng.randf_range(-7.0, 7.0)          # (each variant's fronds a little different)
		var length: float = f[1] * rng.randf_range(0.88, 1.08)
		var droop: float = f[2] + rng.randf_range(-0.12, 0.12)
		if int(f[3]) == layer:
			_frond(img, Vector2(CROWN_AT), a, length, droop, int(f[4]), SWAY[frame])
	if layer == 1:                                            # the frond bases, bunched in the middle
		for p: Vector2i in [Vector2i(-3, -1), Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
				Vector2i(2, -1), Vector2i(-2, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
				Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
			img.set_pixelv(CROWN_AT + p, GREENS[1] if p.y == 0 else GREENS[2])
	var tex := ImageTexture.create_from_image(img)
	_crowns[key] = tex
	return tex


# the ferns round a foot
static func _fern(variant: int) -> ImageTexture:
	if _ferns.has(variant):
		return _ferns[variant]
	var img := Image.create(FERN_SIZE.x, FERN_SIZE.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	for f: Array in FERN_SET:
		var root := Vector2(FERN_AT) + Vector2(rng.randf_range(-6.0, 6.0), 0)
		_frond(img, root, f[0] + rng.randf_range(-8.0, 8.0), f[1] * rng.randf_range(0.8, 1.15), 0.42, 1 + rng.randi() % 3, 0.0)
	var tex := ImageTexture.create_from_image(img)
	_ferns[variant] = tex
	return tex


# one frond into an image: a spine curving out from `root` at angle `a` (degrees) and drooping, with leaflets
# both sides hanging off it (longest in the middle), the upper ones in its tone, the lower ones a shade darker
# and the spine a shade lighter. sway leans its tip sideways
static func _frond(img: Image, root: Vector2, a: float, length: float, droop: float, tone: int, sway: float):
	var d := Vector2(cos(deg_to_rad(a)), -sin(deg_to_rad(a)))
	var steps := int(length * 1.3)
	var light: Color = GREENS[mini(tone + 1, GREENS.size() - 1)]
	var mid: Color = GREENS[tone]
	var dark: Color = GREENS[maxi(tone - 1, 0)]
	var last := root
	for s in steps + 1:
		var u := float(s) / steps
		var p := root + d * length * u + Vector2(sway * u * u, droop * length * u * u)
		var t := (p - last).normalized() if s > 0 else d
		last = p
		if u > 0.06:                                          # the leaflets, packed close: a full, feathery frond
			var n := Vector2(-t.y, t.x)
			var size := (3.0 + 9.0 * sin(PI * minf(u * 1.15, 1.0))) * minf(length / 50.0, 1.0)
			for side: float in [1.0, -1.0]:
				var ld: Vector2 = (n * side + t * 0.7 + Vector2(0, 0.9)).normalized()
				var lift := side * n.y < 0.0                  # the side facing up
				var reach := size * (0.75 if lift else 1.0)
				for j in range(1, int(reach) + 1):
					_put(img, p + ld * j, mid if lift else dark)
		_put(img, p, light)
		if u < 0.3:
			_put(img, p + Vector2(0, 1), mid)                # (thicker near the base)


static func _put(img: Image, p: Vector2, c: Color):
	var x := roundi(p.x)
	var y := roundi(p.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)
