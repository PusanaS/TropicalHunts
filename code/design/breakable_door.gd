extends StaticBody2D
# A wooden portcullis with iron spikes dug into the ground (the boss room entrance in the gym).
# Any attack that reaches it, or galloping into it, shatters it so the player bursts straight through
# (galloping breaks it just before contact, so they keep full speed, with a moment of slow motion).
# The pieces are cut from its own beams and fly the way the player is going, then bounce, skid and fade.
# A moment later a new portcullis slams down out of the wall above (its spike tips show under the wall
# while it waits). It holds while anyone is standing in the doorway.
# Place it with its feet on the floor, under a wall that ends DOORWAY_HEIGHT above the floor: the
# gate is drawn behind the wall and the floor, so it hides in the wall and its spike tips in the ground.
# PLACEHOLDER art (scene/design/art/portcullis.png).

enum Mode { DOWN, OPEN, DROPPING }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const TEXTURE: Texture2D = preload("res://scene/design/art/portcullis.png")  # 48x120, ground at y 112
const PUFF: Texture2D = preload("res://scene/design/art/dust_puff.png")      # 6 frames, 16x16
# sped up 2.24x (same pitch) so it lasts 1.2 s, as long as the gallop slow motion (SLOWMO)
const CRASH_SOUND := preload("res://sounds/MATRIX_freesound_community-the-matrix-trinity-jump-sound-fx-plain-single-77358_fast.wav")

const SIZE := Vector2(48, 112)                  # the doorway it blocks
const SPRITE_Y := -52.0                         # sprite centre when down (120 tall, 8 of it underground)
const BEAMS := [Vector2i(0, 7), Vector2i(14, 7), Vector2i(27, 7), Vector2i(41, 7)]   # x, width in the art
const BARS := [6, 36, 66, 94]                   # crossbar top rows in the art (5 tall)
const PLAYER_HALF_WIDTH := 13.0
const GALLOP_REACH := 28.0                      # galloping this close smashes it before contact
const DROP_ACCEL := 2600.0                      # the new gate falls faster and faster
const PIECE_GRAVITY := 900.0
const PIECE_LIFE := 2.0
# gallop smash: the whole game slows right down, holds, then eases back (real seconds, time scale)
const SLOWMO := [[0.0, 0.2], [0.9, 0.4], [1.05, 0.65], [1.2, 1.0]]
const SPLINTERS := [Color(0.69, 0.48, 0.26), Color(0.55, 0.35, 0.18), Color(0.38, 0.25, 0.13)]
const DIRT := [Color(0.38, 0.25, 0.13), Color(0.49, 0.43, 0.43)]
const Z_FX := 3

@export var reseal_time := 1.0                  # a new gate drops this long after it breaks (0 = stays open)
@export var gallop_only := false                # only galloping into it breaks it, not attacks (the tutorial's DOUBLE TAP gate)

signal shattered                                # it just broke (the tutorial listens for this)

var player: CharacterBody2D = null
var _names: Array = []
var _top_speed := 4
var _mode: Mode = Mode.DOWN
var _open_time := 0.0
var _raised := 0.0                              # how far up in the wall the gate is (0 = down)
var _drop_speed := 0.0
var _shape: CollisionShape2D
var _sprite: Sprite2D
var _pieces: Array = []                         # each: [Sprite2D, velocity, spin, age]
var _crash_sound := AudioStreamPlayer.new()


func _ready():
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	_shape.shape = rect
	_shape.position = Vector2(0, -SIZE.y / 2.0)
	add_child(_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURE
	_sprite.position = Vector2(0, SPRITE_Y)
	_sprite.z_index = -1                        # behind the wall and the floor
	add_child(_sprite)
	_crash_sound.stream = CRASH_SOUND
	add_child(_crash_sound)


func _physics_process(delta: float):
	_update_pieces(delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
		var speeds: Array = player.get_script().SPEEDS
		_top_speed = speeds.size() - 1
	match _mode:
		Mode.DOWN:
			_check_hits()
		Mode.OPEN:
			_open_time += delta
			if reseal_time > 0.0 and _open_time >= reseal_time:
				_mode = Mode.DROPPING
				_drop_speed = 0.0
		Mode.DROPPING:
			if _doorway_clear():
				_drop_speed += DROP_ACCEL * delta
				_raised = maxf(_raised - _drop_speed * delta, 0.0)
			else:
				_drop_speed = 0.0                   # someone's in the doorway: wait
			_sprite.position.y = SPRITE_Y - _raised
			if _raised <= 0.0:
				_landed()


func _check_hits():
	# the player goes through the gate away from where they are
	var dir := signf(global_position.x - player.global_position.x)
	if dir == 0.0:
		dir = 1.0
	var box := Rect2(global_position + Vector2(-SIZE.x / 2.0, -SIZE.y), SIZE)
	if not gallop_only and not EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		_shatter(dir, false)
		return
	var dx := absf(global_position.x - player.global_position.x)
	var s: String = _names[player.state]
	if s == "CHARGED_SMASH" and not gallop_only:
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var charge: float = player.charge
		if dx <= lerpf(radius.x, radius.y, charge):
			_shatter(dir, true)
			return
	# galloping into it: break it just before contact, so the player keeps their speed
	var level: int = player.speed_level
	if level >= _top_speed and signf(player.velocity.x) == dir and absf(player.global_position.y - global_position.y) < SIZE.y:
		if dx - SIZE.x / 2.0 - PLAYER_HALF_WIDTH < GALLOP_REACH:
			_shatter(dir, true)


func _doorway_clear() -> bool:
	var reach := SIZE.x / 2.0 + PLAYER_HALF_WIDTH
	if absf(player.global_position.x - global_position.x) < reach and player.global_position.y > global_position.y - SIZE.y:
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is CharacterBody2D) or ("hp" in e and e.hp <= 0):
			continue                                  # dead enemies waiting to respawn don't block it
		if absf(e.global_position.x - global_position.x) < SIZE.x / 2.0 + 30.0:
			return false
	return true


# ---------- breaking ----------
func _shatter(dir: float, big: bool):
	_mode = Mode.OPEN
	_open_time = 0.0
	_shape.set_deferred("disabled", true)
	var power := 1.6 if big else 1.0
	var top_left := Vector2(-SIZE.x / 2.0, SPRITE_Y - TEXTURE.get_height() / 2.0)
	# beams break into chunks (the buried spike tips stay in the ground)...
	for b: Vector2i in BEAMS:
		var y := 0
		while y < 110:
			var h := mini(randi_range(10, 18), 110 - y)
			_piece(Rect2(b.x, y, b.y, h), top_left, dir, power)
			y += h
	# ...and the crossbars between the beams fly too
	for i in BEAMS.size() - 1:
		var left: Vector2i = BEAMS[i]
		var right: Vector2i = BEAMS[i + 1]
		for by: int in BARS:
			_piece(Rect2(left.x + left.y, by, right.x - left.x - left.y, 5), top_left, dir, power)
	_impact_flash()
	_crash_sound.play()
	_splinters(dir, power)
	for i in 8:
		var side := dir if i < 5 else -dir
		_puff(Vector2(side * randf_range(4.0, 20.0), 0), Vector2(side * randf_range(60.0, 180.0) * power, -randf_range(0.0, 30.0)), i * 0.03)
	get_tree().call_group("living_background", "burst", global_position, 7.0 if big else 4.0)
	_shake(12.0 if big else 8.0, 0.35)
	if big:
		_slow_motion()                           # the player bursts through in slow motion...
		_player_in_front()                       # ...in front of the dust and debris, not hidden by it
	else:
		EnemyKit.hitstop(get_tree(), 0.08)
	# the next gate is already waiting up in the wall: only its spike tips show
	_raised = SIZE.y
	_sprite.position.y = SPRITE_Y - _raised
	shattered.emit()


# steps through SLOWMO on real-time timers (bound to Engine, so they still run if the gate is freed)
func _slow_motion():
	for step: Array in SLOWMO:
		var at: float = step[0]
		var scale_to: float = step[1]
		if at <= 0.0:
			Engine.time_scale = scale_to
		else:
			get_tree().create_timer(at, true, false, true).timeout.connect(Callable(Engine, "set").bind("time_scale", scale_to))


# draws the player over the flash, planks and dust until the slow motion is over, then puts them back
func _player_in_front():
	var before := player.z_index
	player.z_index = Z_FX + 2
	var last: Array = SLOWMO[-1]
	var until: float = last[0]
	get_tree().create_timer(until + 0.2, true, false, true).timeout.connect(_player_back.bind(before))


func _player_back(before: int):
	if is_instance_valid(player):
		player.z_index = before


func _piece(region: Rect2, top_left: Vector2, dir: float, power: float):
	var piece := Sprite2D.new()
	piece.texture = TEXTURE
	piece.region_enabled = true
	piece.region_rect = region
	piece.z_index = Z_FX
	add_child(piece)
	piece.position = top_left + region.position + region.size / 2.0
	var vel := Vector2(dir * randf_range(120.0, 320.0) * power, -randf_range(60.0, 280.0) * power)
	_pieces.append([piece, vel, randf_range(-12.0, 12.0), 0.0])


# ---------- the new gate slams down ----------
func _landed():
	_mode = Mode.DOWN
	_raised = 0.0
	_sprite.position.y = SPRITE_Y
	_shape.set_deferred("disabled", false)
	_shake(7.0, 0.25)
	# the spikes bite into the ground: dirt flies and dust puffs out both ways
	for b: Vector2i in BEAMS:
		_dirt(Vector2(-SIZE.x / 2.0 + b.x + b.y / 2.0, 0))
	for side: float in [-1.0, 1.0]:
		_puff(Vector2(side * 20.0, 0), Vector2(side * 90.0, -10.0), 0.0)
		_puff(Vector2(side * 30.0, 0), Vector2(side * 140.0, -20.0), 0.05)
	get_tree().call_group("living_background", "burst", global_position, 3.0)


# ---------- effects ----------
# a white flash in the gate's shape
func _impact_flash():
	var flash := Polygon2D.new()
	var half := SIZE.x / 2.0
	flash.polygon = PackedVector2Array([Vector2(-half, -SIZE.y), Vector2(half, -SIZE.y), Vector2(half, 0), Vector2(-half, 0)])
	flash.color = Color(1, 1, 1, 0.9)
	flash.z_index = Z_FX + 1
	add_child(flash)
	var t := flash.create_tween()
	t.tween_property(flash, "color:a", 0.0, 0.12)
	t.tween_callback(flash.queue_free)


func _splinters(dir: float, power: float):
	for color: Color in SPLINTERS:
		var p := _particles(color, 12, Vector2(0, -SIZE.y / 2.0))
		p.direction = Vector2(dir, -0.5)
		p.spread = 55.0
		p.initial_velocity_min = 150.0 * power
		p.initial_velocity_max = 380.0 * power
		p.emitting = true


func _dirt(at: Vector2):
	for color: Color in DIRT:
		var p := _particles(color, 5, at)
		p.direction = Vector2.UP
		p.spread = 40.0
		p.initial_velocity_min = 60.0
		p.initial_velocity_max = 160.0
		p.emitting = true


func _particles(color: Color, amount: int, at: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.gravity = Vector2(0, 800)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.z_index = Z_FX
	p.position = at
	p.finished.connect(p.queue_free)
	add_child(p)
	return p


# a dust puff at 2x (whole pixels), bottom on the floor; frames play while it drifts
func _puff(offset: Vector2, vel: Vector2, delay: float):
	var s := Sprite2D.new()
	s.texture = PUFF
	s.hframes = 6
	s.scale = Vector2(2, 2)
	s.offset = Vector2(0, -8)
	s.flip_h = vel.x < 0.0
	s.z_index = Z_FX
	add_child(s)
	s.position = offset
	var t := s.create_tween()
	if delay > 0.0:
		s.visible = false
		t.tween_interval(delay)
		t.tween_callback(s.show)
	t.tween_property(s, "frame", 5, 0.45).from(0)
	t.parallel().tween_property(s, "position", (offset + vel * 0.45).round(), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(s.queue_free)


func _shake(strength: float, seconds: float):
	if player and player.has_method("_shake"):
		player._shake(strength, seconds)


# pieces fly, spin, bounce and skid on the floor (the gate's feet), then fade
func _update_pieces(delta: float):
	var alive: Array = []
	for p: Array in _pieces:
		var piece: Sprite2D = p[0]
		var vel: Vector2 = p[1]
		var spin: float = p[2]
		var age: float = float(p[3]) + delta
		vel.y += PIECE_GRAVITY * delta
		var pos := piece.position + vel * delta
		if pos.y > -3.0 and vel.y > 0.0:
			pos.y = -3.0
			vel = Vector2(vel.x * 0.55, -vel.y * 0.3)
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
