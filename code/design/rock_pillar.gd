extends StaticBody2D
# A sandstone rock pillar (level 1's quicksand desert, Morgan's call): a weathered tower standing up out of
# the sand, layered orange and tan, pinched in at the middle and capped with a darker flat rock, the kind
# you see in deserts. Mangos nap on top of them (in a cactus's `nappers`), up where its high-lobbed
# spikes still reach them.
# Its collision is made here: a column `height` tall, its feet on the floor (the quicksand hides its foot).
# Name it "Sand..." so no grass grows on it. PLACEHOLDER art drawn in code.
# crumble(dir) smashes it (the falling palm does, palm_bridge.gd): it bursts into chunks of rock that sink
# into the sand, leaving a broken stub, and you can pass where it stood.

@export var height := 64.0
@export var width := 24.0

const ROCK := Color("c98a4b")
const ROCK_LIGHT := Color("e0aa6a")      # lit from the left
const ROCK_SHADE := Color("9a6232")
const BAND := Color("b47438")            # strata
const CAP := Color("7a4a26")             # the harder cap rock on top
const CAP_LIGHT := Color("a0683a")
const CRACK := Color("6a3e1e")
const DUST := Color("d39b4a")
const CHUNK_GRAVITY := 700.0
const CHUNK_LIFE := 1.4
const STUB := 8.0                        # what's left standing
const SAND_TOP := -4.0                   # (the quicksand's surface: chunks land on it and sink)

var crumbled := false

var _wobble := PackedFloat32Array()      # each 4px row a touch wider or narrower: weathered
var _cracks: Array = []                  # [PackedVector2Array]
var _shape := CollisionShape2D.new()
var _chunks: Array = []                  # rock flying off: [pos, vel, size, colour, age]


func _ready():
	add_to_group("rock_pillar")
	collision_layer = 1
	collision_mask = 0
	z_index = -2                         # behind the Mango napping on it, and behind you
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	_shape.shape = rect
	_shape.position = Vector2(0, -height / 2.0)
	add_child(_shape)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x)
	for i in int(height / 4.0) + 1:
		_wobble.append(float(rng.randi_range(-1, 1)))
	for i in 2:
		var x := rng.randf_range(-width * 0.25, width * 0.25)
		var y := rng.randf_range(-height * 0.8, -height * 0.3)
		var line := PackedVector2Array([Vector2(x, y)])
		for k in 3:
			y += rng.randf_range(4.0, 9.0)
			x += rng.randf_range(-2.0, 2.0)
			line.append(Vector2(x, y).round())
		_cracks.append(line)


# smashed: chunks of rock fly off the way it was hit, a puff of dust, and only a stub is left
func crumble(dir: float):
	if crumbled:
		return
	crumbled = true
	_shape.set_deferred("disabled", true)
	for i in int(height / 5.0) + 6:
		var y := -randf_range(STUB, height)
		var col: Color = CAP if y < -height + 7.0 else [ROCK, ROCK_LIGHT, ROCK_SHADE, BAND][i % 4]
		_chunks.append([Vector2(randf_range(-width / 2.0, width / 2.0), y),
			Vector2(dir * randf_range(40.0, 200.0) + randf_range(-60.0, 60.0), -randf_range(40.0, 220.0)),
			roundf(randf_range(3.0, 7.0)), col, 0.0])
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width / 2.0, height / 2.0)
	p.direction = Vector2(dir, -1.0)
	p.spread = 60.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	p.color = DUST
	p.position = Vector2(0, -height / 2.0)
	p.finished.connect(p.queue_free)
	add_child(p)
	p.emitting = true
	queue_redraw()


func _physics_process(delta: float):
	if _chunks.is_empty():
		return
	for c: Array in _chunks:
		c[4] += delta
		c[1].y += CHUNK_GRAVITY * delta
		c[0] += c[1] * delta
		if c[0].y > SAND_TOP and c[1].y > 0.0:           # lands on the sand, bounces a little
			c[0].y = SAND_TOP
			c[1] = Vector2(c[1].x * 0.4, -c[1].y * 0.25)
	_chunks = _chunks.filter(func(c): return c[4] < CHUNK_LIFE)
	queue_redraw()


func _draw():
	if crumbled:
		_draw_rubble()
		return
	var rows := int(height / 4.0)
	for i in rows + 1:
		var y := -height + 6.0 + i * 4.0                            # below the cap
		var k := float(i) / float(maxi(rows, 1))                  # 0 at the top, 1 at the foot
		var w := roundf(width * (0.85 - 0.25 * sin(k * PI * 0.8) + 0.45 * k * k) + _wobble[mini(i, _wobble.size() - 1)])
		var x := -roundf(w / 2.0)
		draw_rect(Rect2(x, y, w, 4), ROCK)
		draw_rect(Rect2(x, y, 2, 4), ROCK_LIGHT)
		draw_rect(Rect2(x + w - 3.0, y, 3, 4), ROCK_SHADE)
		if i % 3 == 1:
			draw_rect(Rect2(x + 1.0, y + 3.0, w - 2.0, 1), BAND)
	for c: PackedVector2Array in _cracks:
		draw_polyline(c, CRACK, 1.0)
	# the cap rock: flat, darker, overhanging the column; its top is what the Mango sleeps on
	var cw := roundf(width * 1.3)
	draw_rect(Rect2(-cw / 2.0, -height, cw, 7), CAP)
	draw_rect(Rect2(-cw / 2.0, -height, cw, 1), CAP_LIGHT)
	draw_rect(Rect2(-cw / 2.0 + 1.0, -height + 6.0, cw - 2.0, 1), CRACK)


# the broken stub (jagged on top) and the chunks still flying
func _draw_rubble():
	var w := roundf(width * 1.3)
	for i in int(w / 2.0):
		var h := STUB - float((i * 7) % 4)
		draw_rect(Rect2(-w / 2.0 + i * 2.0, -h, 2, h), ROCK if i % 3 else ROCK_SHADE)
		draw_rect(Rect2(-w / 2.0 + i * 2.0, -h, 2, 1), ROCK_LIGHT)
	for c: Array in _chunks:
		var col: Color = c[3]
		var a := clampf((CHUNK_LIFE - float(c[4])) / 0.4, 0.0, 1.0)
		var size: float = c[2]
		draw_rect(Rect2((c[0] as Vector2).round() - Vector2(size, size) / 2.0, Vector2(size, size)), Color(col, a))
		draw_rect(Rect2((c[0] as Vector2).round() - Vector2(size, size) / 2.0, Vector2(size, 1)), Color(ROCK_LIGHT, a))
