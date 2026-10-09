extends StaticBody2D
# A wooden barricade with a warning sign (level 1, before the mine cart; Morgan's call, replacing the
# portcullis gate): two posts, boards nailed across, an X brace, a striped board on top and a sign hung
# across it ("DANGER", "MINE CLOSED", "STAY AWAY"...): yellow-and-black danger signs (Morgan's call). Gallop into it and you blast straight through
# without losing speed (it breaks just before you touch it); any attack breaks it too. The boards, posts
# and sign fly on ahead, with splinters, dust and a crack, and the stumps stay. It's solid till then.
# Place it with its feet on the floor (origin = bottom centre). Like the ones in the mine (minecart.gd).
# PLACEHOLDER art drawn in code.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Achievements := preload("res://code/design/achievements.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const CRACK_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRACK_SOUND_DB := -6.0
const CRACK_SOUND_SKIP := 0.02       # the file starts with 20ms of silence

const SIZE := Vector2(28, 62)        # what blocks you
const BOARDS := [-54.0, -40.0, -26.0, -12.0]
const GALLOP_REACH := 24.0           # galloping this close breaks it before you touch it
const PLAYER_HALF_WIDTH := 13.0
const PIECE_GRAVITY := 900.0
const PIECE_LIFE := 4.0
const STUMP := 9.0                   # what's left of the posts
const WOOD := Color(0.55, 0.35, 0.18)
const WOOD_LIGHT := Color(0.69, 0.48, 0.26)
const WOOD_DARK := Color(0.38, 0.25, 0.13)
const NAIL := Color("4a3128")
const STRIPE_RED := Color("b3261e")   # marks the top board's piece (drawn with hazard stripes)
const SIGN := Color("f2c22e")        # danger yellow (Morgan's call)...
const SIGN_SHADE := Color("c99a18")
const SIGN_BLACK := Color("1d1a17")  # ...with black letters, border and hazard stripes
const HAZARD := 3.0                  # the width of each hazard stripe
const DUST := Color("8c8577")

@export var sign_text := "DANGER"

var player: CharacterBody2D = null
var _names: Array = []
var _top_speed := 4
var _broken := false
var _pieces: Array = []              # [pos, vel, angle, spin, size, colour, age, is the sign?]
var _shape: CollisionShape2D
var _crack := AudioStreamPlayer.new()


func _ready():
	add_to_group("barricade")
	collision_layer = 1
	collision_mask = 0
	z_index = -1                     # behind you (the flying pieces too)
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	_shape.shape = rect
	_shape.position = Vector2(0, -SIZE.y / 2.0)
	add_child(_shape)
	_crack.stream = CRACK_SOUND
	_crack.volume_db = CRACK_SOUND_DB
	add_child(_crack)


func _physics_process(delta: float):
	if not _pieces.is_empty():
		_update_pieces(delta)
		queue_redraw()
	if _broken:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
		var speeds: Array = player.get_script().SPEEDS
		_top_speed = speeds.size() - 1
	_check_hits()


func _check_hits():
	var dir := signf(global_position.x - player.global_position.x)   # you go through it away from where you are
	if dir == 0.0:
		dir = 1.0
	var box := Rect2(global_position + Vector2(-SIZE.x / 2.0, -SIZE.y), SIZE)
	if not EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		_break(dir, 1.0)
		return
	var dx := absf(global_position.x - player.global_position.x)
	if _names[player.state] == "CHARGED_SMASH":
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var charge: float = player.charge
		if dx <= lerpf(radius.x, radius.y, charge):
			_break(dir, 1.4)
			return
	# galloping into it: it breaks just before you touch it, so you keep your speed
	var level: int = player.speed_level
	if level >= _top_speed and signf(player.velocity.x) == dir and absf(player.global_position.y - global_position.y) < SIZE.y:
		if dx - SIZE.x / 2.0 - PLAYER_HALF_WIDTH < GALLOP_REACH:
			_break(dir, 1.6)


# it flies apart the way you're going: boards, posts snapped at the stumps, the striped board and the sign
func _break(dir: float, power: float):
	_broken = true
	var all := true                  # every warning sign down: YOU CAN'T TELL ME WHERE TO GO (Morgan's call)
	for b in get_tree().get_nodes_in_group("barricade"):
		if not b._broken:
			all = false
	if all:
		Achievements.unlock(get_tree(), "signs")
	_shape.set_deferred("disabled", true)
	var base := Vector2(dir * 200.0 * power, 0)
	for by: float in BOARDS:
		_piece(Vector2(randf_range(-4.0, 4.0), by + 3.0), base + Vector2(dir * randf_range(-40.0, 160.0), -randf_range(80.0, 300.0)), Vector2(26, 5), WOOD)
	for px in [-9.0, 9.0]:
		_piece(Vector2(px, -STUMP - 26.0), base * 0.6 + Vector2(dir * randf_range(-20.0, 80.0), -randf_range(120.0, 260.0)), Vector2(4, 52), WOOD_DARK)
	_piece(Vector2(0, -59.0), base + Vector2(dir * randf_range(0.0, 100.0), -randf_range(200.0, 340.0)), Vector2(28, 6), STRIPE_RED)
	var sign_r := _sign_rect()
	_pieces.append([sign_r.get_center(), base * 0.8 + Vector2(dir * randf_range(20.0, 120.0), -randf_range(160.0, 300.0)),
		0.0, randf_range(-10.0, 10.0) * dir, sign_r.size, SIGN, 0.0, true])
	_splinters(Vector2(0, -30), Vector2(dir, -0.5).normalized(), power)
	for i in 4:
		_puff(Vector2(randf_range(-10.0, 10.0), 0), Vector2(dir * randf_range(30.0, 110.0), -randf_range(0.0, 20.0)))
	EnemyKit.hitstop(get_tree(), 0.04)
	if player and player.has_method("_shake"):
		player._shake(6.0, 0.15)
	_crack.pitch_scale = randf_range(0.9, 1.15)
	_crack.play(CRACK_SOUND_SKIP)
	queue_redraw()


func _piece(at: Vector2, vel: Vector2, size: Vector2, color: Color):
	_pieces.append([at, vel, randf() * TAU, randf_range(-14.0, 14.0), size, color, 0.0, false])


func _update_pieces(delta: float):
	for p: Array in _pieces:
		p[6] += delta
		p[1].y += PIECE_GRAVITY * delta
		p[0] += p[1] * delta
		p[2] += p[3] * delta
		var s: Vector2 = p[4]
		var rest := minf(s.x, s.y) / 2.0
		if p[0].y > -rest and p[1].y > 0.0:          # bounce and skid on the floor
			p[0].y = -rest
			p[1].y *= -0.3
			p[1].x *= 0.6
			p[3] *= 0.5
	_pieces = _pieces.filter(func(p): return p[6] < PIECE_LIFE)


func _splinters(at: Vector2, dir: Vector2, power: float):
	for color: Color in [WOOD_LIGHT, WOOD, WOOD_DARK]:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = int(12 * power)
		p.lifetime = 0.8
		p.explosiveness = 1.0
		p.gravity = Vector2(0, 800)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.0
		p.color = color
		p.z_as_relative = false
		p.z_index = 4                # in front of you
		p.position = at
		p.direction = dir
		p.spread = 50.0
		p.initial_velocity_min = 120.0 * power
		p.initial_velocity_max = 300.0 * power
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


func _puff(at: Vector2, vel: Vector2):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.5
	p.explosiveness = 0.9
	p.gravity = Vector2(0, -20)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.0
	p.color = DUST
	p.position = at
	p.direction = vel.normalized()
	p.spread = 30.0
	p.initial_velocity_min = vel.length() * 0.5
	p.initial_velocity_max = vel.length()
	p.finished.connect(p.queue_free)
	add_child(p)
	p.emitting = true


# the sign: a pale plank as wide as its words, hung across the boards
func _sign_rect() -> Rect2:
	var w := Pixel.width(sign_text, 1) + 8.0
	return Rect2(-w / 2.0, -38.0, w, 13)


func _draw():
	if not _broken:
		_draw_whole()
	else:
		for px in [-11.0, 7.0]:                                     # the stumps, jagged
			draw_rect(Rect2(px, -STUMP, 4, STUMP), WOOD_DARK)
			draw_rect(Rect2(px, -STUMP - 2.0, 2, 2), WOOD_LIGHT)
	for p: Array in _pieces:
		var a := 1.0 - clampf((float(p[6]) - (PIECE_LIFE - 0.8)) / 0.8, 0.0, 1.0)
		var s: Vector2 = p[4]
		draw_set_transform(p[0], p[2])
		if p[7]:                                                    # the sign tumbles whole, words and all
			_draw_sign(Rect2(-s / 2.0, s), a)
		elif p[5] == STRIPE_RED:                                    # the hazard-striped top board
			_draw_hazard(Rect2(-s / 2.0, s), a)
		else:
			draw_rect(Rect2(-s / 2.0, s), Color(p[5], a))
			draw_rect(Rect2(-s.x / 2.0, -s.y / 2.0, s.x, 1), Color(WOOD_LIGHT, a))
	draw_set_transform(Vector2.ZERO)


func _draw_whole():
	for px in [-11.0, 7.0]:                                         # the posts
		draw_rect(Rect2(px, -62.0, 4, 62), WOOD_DARK)
		draw_rect(Rect2(px, -62.0, 1, 62), WOOD)
	for by: float in BOARDS:                                        # boards nailed across
		draw_rect(Rect2(-14.0, by, 28, 6), WOOD)
		draw_rect(Rect2(-14.0, by, 28, 1), WOOD_LIGHT)
		draw_rect(Rect2(-14.0, by + 5.0, 28, 1), WOOD_DARK)
		draw_rect(Rect2(-10.0, by + 2.0, 1, 1), NAIL)
		draw_rect(Rect2(9.0, by + 2.0, 1, 1), NAIL)
	draw_line(Vector2(-12, -50), Vector2(12, -10), WOOD_DARK, 2.0)  # the X brace
	draw_line(Vector2(12, -50), Vector2(-12, -10), WOOD_DARK, 2.0)
	_draw_hazard(Rect2(-14.0, -62.0, 28, 6))                         # the board on top: hazard stripes
	_draw_sign(_sign_rect())


# the danger sign: yellow, a black border, hazard stripes at both ends, black letters
func _draw_sign(r: Rect2, a := 1.0):
	draw_rect(r.grow(1.0), Color(SIGN_BLACK, a))
	draw_rect(r, Color(SIGN, a))
	draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), Color(SIGN_SHADE, a))
	_draw_hazard(Rect2(r.position.x, r.position.y, 5, r.size.y), a)
	_draw_hazard(Rect2(r.end.x - 5.0, r.position.y, 5, r.size.y), a)
	var w := Pixel.width(sign_text, 1)
	for c in Pixel.cells(sign_text, Vector2(roundf(r.get_center().x - w / 2.0), r.position.y + 3.0), 1):
		draw_rect(c[0], Color(SIGN_BLACK, a))


# diagonal black-and-yellow hazard stripes filling a rect
func _draw_hazard(r: Rect2, a := 1.0):
	draw_rect(r, Color(SIGN, a))
	var x := r.position.x - r.size.y
	while x < r.end.x:
		for row in int(r.size.y):
			var px := x + row                                       # each stripe leans one pixel per row
			var from := maxf(px, r.position.x)
			var to := minf(px + HAZARD, r.end.x)
			if to > from:
				draw_rect(Rect2(from, r.position.y + row, to - from, 1), Color(SIGN_BLACK, a))
		x += HAZARD * 2.0
