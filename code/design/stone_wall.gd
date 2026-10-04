extends StaticBody2D
# STONE WALL (Level 3): cooled lava blocking the way. Solid like the level, so galloping into it knocks
# you back, and Q or a normal W just clang off it (sparks, and you're pushed back a little). Only a charged
# smash (hold W, let go) whose reach covers it breaks it: it bursts into basalt chunks with glowing cracks.
# While you're charging W close enough, its cracks glow brighter: that's the hint.
# Place it with its feet on the floor (origin = bottom centre). Name it "WallStone..." in a scene so the
# living background puts no grass on it. PLACEHOLDER look, drawn in code.

signal shattered                                # it just broke

@export var size := Vector2(48, 112)

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const CLANG_SOUND := preload("res://sounds/sword/sword_clash_06.wav")     # the boss's armour clang
const CLANG_SOUND_DB := -6.0
const CLANG_SOUND_SKIP := 0.012
const CRASH_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const CRASH_SOUND_DB := -4.0
const PUSHBACK := 200.0                        # a clang knocks the player back this fast
const COLUMN := 8                              # the basalt columns are this many pixels wide
const PIECE := Vector2i(12, 14)                # chunk size when it breaks
const PIECE_GRAVITY := 900.0
const PIECE_LIFE := 2.0
const Z_FX := 3

const BASALT := Color("3a3540")
const BASALT_LIGHT := Color("4d4756")
const BASALT_DARK := Color("27232c")
const CRACK_DIM := Color("7a2a12")
const CRACK := [Pixel.RUST, Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE]   # dim to white-hot

var player: CharacterBody2D = null
var _names: Array = []
var _broken := false
var _texture: ImageTexture
var _cracks: Array[Vector2i] = []             # the glowing crack pixels (in the art)
var _glow := 0.0                               # 0..1: how close a charged smash is to breaking it
var _t := 0.0
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _shape: CollisionShape2D
var _pieces: Array = []                        # each: [Sprite2D, velocity, spin, age]
var _clang := AudioStreamPlayer.new()
var _crash := AudioStreamPlayer.new()


func _ready():
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	_shape.position = Vector2(0, -size.y / 2.0)
	add_child(_shape)
	_clang.stream = CLANG_SOUND
	_clang.volume_db = CLANG_SOUND_DB
	_clang.max_polyphony = 3
	add_child(_clang)
	_crash.stream = CRASH_SOUND
	_crash.volume_db = CRASH_SOUND_DB
	add_child(_crash)
	_build_art()


func _physics_process(delta: float):
	_t += delta
	_update_pieces(delta)
	if _broken:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	var s: String = _names[player.state]
	var d := player.global_position - global_position
	var radius: Vector2 = player.get_script().CHARGE_RADIUS
	var height: float = player.get_script().CHARGE_HEIGHT
	var near := absf(d.y + size.y / 2.0) <= height + size.y / 2.0
	var reach := lerpf(radius.x, radius.y, player.charge) + size.x / 2.0
	# the charged smash: the only thing that breaks it
	if s == "CHARGED_SMASH" and near and absf(d.x) <= reach:
		_shatter(signf(-d.x) if d.x != 0.0 else 1.0)
		return
	# charging close enough: the cracks glow brighter and brighter
	var target := 0.0
	if s == "HEAVY_CHARGE" and near and absf(d.x) <= radius.y + size.x / 2.0:
		target = 0.35 + 0.65 * player.charge if absf(d.x) <= reach else 0.3
	_glow = move_toward(_glow, target, delta * 4.0)
	_check_clang(s)
	queue_redraw()


# anything else that reaches it clangs off (once per swing, like the enemies' "new swing" rule)
func _check_clang(s: String):
	var ps: int = player.state
	var pt: float = player.state_time
	if ps != _last_state or pt < _last_time:
		_hit_this_swing = false
	_last_state = ps
	_last_time = pt
	if _hit_this_swing:
		return
	var box := Rect2(global_position + Vector2(-size.x / 2.0, -size.y), size)
	if EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		return
	_hit_this_swing = true
	_clang.play(CLANG_SOUND_SKIP)
	var side := signf(player.global_position.x - global_position.x)
	_sparks(Vector2(side * size.x / 2.0, -28.0), Pixel.MUSTARD, 8)
	if player.has_method("bounce_back") and s != "DASH_ATTACK_HEAVY_SLAM":
		player.bounce_back(global_position.x, PUSHBACK)


# ---------- breaking ----------
func _shatter(dir: float):
	_broken = true
	_shape.set_deferred("disabled", true)
	var top_left := Vector2(-size.x / 2.0, -size.y)
	var x := 0
	while x < int(size.x):
		var y := 0
		var w := mini(PIECE.x, int(size.x) - x)
		while y < int(size.y):
			var h := mini(PIECE.y + randi_range(-3, 3), int(size.y) - y)
			_piece(Rect2(x, y, w, h), top_left, dir)
			y += h
		x += w
	_sparks(Vector2(0, -size.y / 2.0), Pixel.ORANGE, 24)         # embers
	_sparks(Vector2(0, -size.y / 2.0), Pixel.MUSTARD, 12)
	_dust()
	_crash.play()
	EnemyKit.hitstop(get_tree(), 0.08)
	if player:
		player._shake(12.0, 0.35)
	get_tree().call_group("living_background", "burst", global_position, 6.0)
	shattered.emit()
	queue_redraw()


func _piece(region: Rect2, top_left: Vector2, dir: float):
	var piece := Sprite2D.new()
	piece.texture = _texture
	piece.region_enabled = true
	piece.region_rect = region
	piece.z_index = Z_FX
	add_child(piece)
	piece.position = top_left + region.position + region.size / 2.0
	var high := 1.0 - region.position.y / size.y                # the top flies higher
	var vel := Vector2(dir * randf_range(80.0, 280.0), -randf_range(60.0, 200.0) * (0.6 + high))
	_pieces.append([piece, vel, randf_range(-10.0, 10.0), 0.0])


# chunks fly, spin, bounce and skid on the floor (the wall's feet), then fade
func _update_pieces(delta: float):
	var alive: Array = []
	for p: Array in _pieces:
		var piece: Sprite2D = p[0]
		var vel: Vector2 = p[1]
		var spin: float = p[2]
		var age: float = float(p[3]) + delta
		vel.y += PIECE_GRAVITY * delta
		var pos := piece.position + vel * delta
		if pos.y > -4.0 and vel.y > 0.0:
			pos.y = -4.0
			vel = Vector2(vel.x * 0.5, -vel.y * 0.3)
			spin *= 0.5
		piece.position = pos
		piece.rotation += spin * delta
		if age > PIECE_LIFE - 0.5:
			piece.modulate.a = maxf(0.0, (PIECE_LIFE - age) / 0.5)
		if age >= PIECE_LIFE:
			piece.queue_free()
			continue
		p[1] = vel
		p[2] = spin
		p[3] = age
		alive.append(p)
	_pieces = alive


func _sparks(offset: Vector2, color: Color, amount: int):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 240.0
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.z_index = Z_FX
	p.position = offset
	p.finished.connect(p.queue_free)
	add_child(p)
	p.emitting = true


func _dust():
	for side in [-1.0, 1.0]:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.7
		p.explosiveness = 0.9
		p.direction = Vector2(side, -0.5)
		p.spread = 35.0
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 140.0
		p.gravity = Vector2(0, 150)
		p.scale_amount_min = 2.0
		p.scale_amount_max = 3.0
		p.color = Color(0.36, 0.33, 0.38)
		p.z_index = Z_FX
		p.position = Vector2(side * size.x / 2.0, -4.0)
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


# ---------- drawing ----------
# basalt columns (light left edge, dark right edge, staggered joints) with a few cracks running through,
# drawn once into a texture so the chunks can be cut from it
func _build_art():
	var w := int(size.x)
	var h := int(size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x) * 7.0 + absf(global_position.y))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var joints := []
	for c in ceili(float(w) / COLUMN):
		var js := []
		var y := rng.randi_range(4, 18)
		while y < h:
			js.append(y)
			y += rng.randi_range(14, 24)
		joints.append(js)
	for x in w:
		var c := x / COLUMN
		var in_col := x % COLUMN
		for y in h:
			var col := BASALT
			if in_col == 0:
				col = BASALT_LIGHT
			elif in_col == COLUMN - 1:
				col = BASALT_DARK
			if y in joints[c]:
				col = BASALT_DARK
			if x == 0 or x == w - 1 or y == 0:
				col = Pixel.INK
			img.set_pixel(x, y, col)
	# cracks: a few zigzags running down and across
	for k in 4:
		var p := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h / 2))
		for step in rng.randi_range(18, 40):
			if p.x <= 1 or p.x >= w - 2 or p.y <= 1 or p.y >= h - 2:
				break
			_cracks.append(p)
			img.set_pixel(p.x, p.y, CRACK_DIM)
			p += Vector2i(rng.randi_range(-1, 1), 1 if rng.randf() < 0.75 else 0)
	_texture = ImageTexture.create_from_image(img)


func _draw():
	if _broken:
		return
	var origin := Vector2(-size.x / 2.0, -size.y)
	draw_texture(_texture, origin)
	# the cracks glow, pulsing gently; a charge nearby makes them blaze
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var heat := clampf(0.25 + 0.2 * pulse + 0.75 * _glow, 0.0, 1.0)
	var col: Color = CRACK[clampi(int(heat * CRACK.size()), 0, CRACK.size() - 1)]
	for p in _cracks:
		draw_rect(Rect2(origin + Vector2(p), Vector2(1, 1)), col)
	if _glow > 0.5:                                  # hot enough: the glow spills around the cracks
		var spill := Color(Pixel.ORANGE, 0.35 * (_glow - 0.5) * 2.0)
		for i in range(0, _cracks.size(), 2):
			draw_rect(Rect2(origin + Vector2(_cracks[i]) + Vector2(1, 0), Vector2(1, 1)), spill)
