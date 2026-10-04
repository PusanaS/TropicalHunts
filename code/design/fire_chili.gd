extends CharacterBody2D
# FIRE CHILI: Level 3's ground charger. While it charges it's on fire: the Thunderclap flash fizzles on it
# and running into it burns you, so galloping through a pack of chilis is the wrong answer. Counter the
# charge, or jump it and hit it while it's dizzy. PLACEHOLDER look, drawn in code in BOOM's palette.
#
# Monster card
#   Moves:     walks back and forth around where it was placed, turns at walls and ledges.
#   Notices:   the player in front (sight_range) or right behind it -> a little hop and a "!".
#   Attack:    the warning: it stomps on the spot while flames grow on its back (windup_time). Then it
#              charges flat along the ground, on fire, until it's gone charge_time or hits a wall or ledge.
#   After:     skids to a stop and is dizzy for a moment (dizzy_time) = the punish window.
#   Beaten by: any hit (1 hp). Q during the charge counters it (the counter chain cuts it in half).
#   Touch:     touching it hurts, except while it's dizzy. While it charges it's burning: the flash won't
#              fire on it, so galloping into it just burns you.
#   Drops:     one juice drop (chili).
#   Animations BOOM and Violeta will need: IDLE, WALK, NOTICE, RUN, WINDUP (stomping, flames growing),
#              CHARGE (on fire), SKID, DIZZY, DIE

enum State { IDLE, PATROL, NOTICE, CHASE, WINDUP, CHARGE, DIZZY, DEAD }

@export var walk_speed := 35.0
@export var chase_speed := 90.0
@export var patrol_range := 96.0       # how far it wanders from where it was placed
@export var sight_range := 180.0
@export var charge_range := 170.0      # starts the windup when the player is this close
@export var windup_time := 0.5         # the warning: stomping, flames growing
@export var charge_speed := 380.0
@export var charge_time := 0.8         # the longest a charge lasts
@export var dizzy_time := 0.9          # the punish window after a charge
@export var respawn_time := 0.0        # comes back after this long, 0 = stays dead
@export var juice_color := Color(0.85, 0.2, 0.12)

const NOTICE_TIME := 0.4
const IDLE_TIME := 0.8
const NOTICE_HOP := -110.0
const GIVE_UP_RANGE := 300.0
const BEHIND_SIGHT := 40.0
const SIGHT_HEIGHT := 48.0
const FLOOR_FRICTION := 900.0
const SKID_FRICTION := 900.0           # the skid after a charge
const HURTBOX := Rect2(-7, -22, 14, 22)
const TOUCH_BOX := Rect2(-6, -20, 12, 18)
const HITSTOP := 0.05
const JuiceDrop := preload("res://code/design/juice_drop.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const KILL_SOUND := preload("res://sounds/sword/sword_hit_flesh_01.wav")   # the Mango's kill sound
const KILL_SOUND_DB := -3.0
const KILL_SOUND_SKIP := 0.025
const DAMAGE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const DAMAGE_SOUND_DB := 0.0
const DAMAGE_SOUND_SKIP := 0.12
const CHARGE_SOUND := preload("res://sounds/sword/sword_swoosh_02.wav")   # the whoosh as it sets off
const CHARGE_SOUND_DB := -6.0

# 12 x 22, facing right, the bottom row on the ground. o outline, R red, S shade, h highlight, g/G stem,
# k brows and pupils, w eyes. It stands on its curled tip.
const ART := [
	".....gG.....",
	"....gggg....",
	"...ggGggGg..",
	"..oooooooo..",
	"..oRkRRkSo..",
	"..oRRkkRSo..",
	"..oRwkwkSo..",
	"..oRRRRRSo..",
	"..ohRRRRSo..",
	"..ohRRRRSo..",
	"..ohRRRRSo..",
	"..oRRRRRSo..",
	"..oRRRRRSo..",
	"...oRRRRSo..",
	"...oRRRRSo..",
	"....oRRRSo..",
	"....oRRSo...",
	".....oRSo...",
	".....oRo....",
	"....oRo.....",
	"...oRo......",
	"...oo.......",
]
const PALETTE := {
	"o": Pixel.INK, "R": Color("c0281c"), "S": Pixel.RED, "h": Pixel.ORANGE,
	"g": Pixel.GREEN, "G": Pixel.GREEN_DARK, "k": Pixel.INK, "w": Pixel.WHITE,
}
const FLAMES := [Pixel.RED, Pixel.ORANGE, Pixel.MUSTARD, Pixel.OFF_WHITE]

static var _texture: ImageTexture     # the art drawn once into a texture (shared by every chili)

var state: State = State.PATROL
var state_time := 0.0
var facing := 1
var hp := 1
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _names: Array = []
var _top_level := 4
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _charge_landed := false            # this charge already hit the player: too late to counter it
var _shape: CollisionShape2D
var _ledge: RayCast2D
var _kill_sound := AudioStreamPlayer.new()
var _damage_sound := AudioStreamPlayer.new()
var _charge_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 20)
	_shape.shape = rect
	_shape.position = Vector2(0, -10)
	add_child(_shape)
	_ledge = RayCast2D.new()
	_ledge.position = Vector2(8, -2)
	_ledge.target_position = Vector2(0, 12)
	add_child(_ledge)
	home = global_position
	for p in [[_kill_sound, KILL_SOUND, KILL_SOUND_DB], [_damage_sound, DAMAGE_SOUND, DAMAGE_SOUND_DB],
			[_charge_sound, CHARGE_SOUND, CHARGE_SOUND_DB]]:
		var s: AudioStreamPlayer = p[0]
		s.stream = p[1]
		s.volume_db = p[2]
		add_child(s)
	_set_state(State.PATROL)


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_names = player.get_script().State.keys()
		var speeds: Array = player.get_script().SPEEDS
		_top_level = speeds.size() - 1
		add_collision_exception_with(player)
		_ledge.add_exception(player)


func _set_state(s: State):
	state = s
	state_time = 0.0
	match s:
		State.NOTICE:
			_face_player()
			velocity.y = NOTICE_HOP
		State.CHARGE:
			_charge_landed = false
			_charge_sound.play()


# ---------- what other code asks ----------
# the player's counter (Q) catches it mid-charge, until the charge has hit them
func is_counterable() -> bool:
	return state == State.CHARGE and not _charge_landed


# the flash only goes for enemies that are alive: a burning chili isn't, while the player gallops,
# so the flash fizzles and they run into the fire instead
func is_alive() -> bool:
	if state == State.DEAD:
		return false
	if state == State.CHARGE and player and player.speed_level >= _top_level:
		return false
	return true


# ---------- every frame ----------
func _physics_process(delta: float):
	state_time += delta
	if state == State.DEAD:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		return
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	if not is_on_floor():
		velocity += get_gravity() * delta
	if player:
		_check_player_attack()
		if state == State.DEAD:
			return

	match state:
		State.IDLE:
			_brake(delta)
			if _sees_player():
				_set_state(State.NOTICE)
			elif state_time >= IDLE_TIME:
				facing = -facing
				_set_state(State.PATROL)
		State.PATROL:
			if _sees_player():
				_set_state(State.NOTICE)
			elif _blocked() or (global_position.x - home.x) * facing >= patrol_range:
				velocity.x = 0.0
				_set_state(State.IDLE)
			else:
				velocity.x = facing * walk_speed
		State.NOTICE:
			_brake(delta)
			if state_time >= NOTICE_TIME and is_on_floor():
				_set_state(State.CHASE)
		State.CHASE:
			_state_chase()
		State.WINDUP:
			_brake(delta)
			_face_player()
			if state_time >= windup_time:
				_set_state(State.CHARGE)
		State.CHARGE:
			velocity.x = facing * charge_speed
			if state_time >= charge_time or _blocked():
				velocity.x = facing * charge_speed * 0.5
				_skid_dust()
				_set_state(State.DIZZY)
		State.DIZZY:
			velocity.x = move_toward(velocity.x, 0.0, SKID_FRICTION * delta)
			if state_time >= dizzy_time:
				_set_state(State.CHASE)

	move_and_slide()
	_touch_player()
	queue_redraw()


func _state_chase():
	if player == null:
		_set_state(State.IDLE)
		return
	var d := player.global_position - global_position
	if absf(d.x) > GIVE_UP_RANGE or absf(d.y) > SIGHT_HEIGHT * 2.0:
		_set_state(State.IDLE)
		return
	_face_player()
	if absf(d.x) <= charge_range and is_on_floor():
		velocity.x = 0.0
		_set_state(State.WINDUP)
		return
	velocity.x = 0.0 if _blocked() else facing * chase_speed      # waits at a ledge


func _sees_player() -> bool:
	if player == null:
		return false
	var d := player.global_position - global_position
	if absf(d.y) > SIGHT_HEIGHT:
		return false
	if absf(d.x) <= BEHIND_SIGHT:
		return true
	return signf(d.x) == facing and absf(d.x) <= sight_range


func _face_player():
	if player and absf(player.global_position.x - global_position.x) > 2.0:
		facing = int(signf(player.global_position.x - global_position.x))


# wall or ledge straight ahead
func _blocked() -> bool:
	if is_on_wall() and get_wall_normal().x * facing < 0.0:
		return true
	_ledge.position.x = facing * 8.0
	_ledge.force_raycast_update()
	return is_on_floor() and not _ledge.is_colliding()


func _brake(delta: float):
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FLOOR_FRICTION * delta)


# ---------- getting hit ----------
# same "new swing" rule as the fruit minion: a new state, or the same one restarted
func _check_player_attack():
	var ps: int = player.state
	var pt: float = player.state_time
	if ps != _last_state or pt < _last_time:
		_hit_this_swing = false
	_last_state = ps
	_last_time = pt
	if _hit_this_swing:
		return
	var hit := EnemyKit.player_attack_hitting(player, _names, Rect2(global_position + HURTBOX.position, HURTBOX.size))
	if hit.is_empty():
		return
	_hit_this_swing = true
	take_hit(hit["damage"], hit["push"])


func take_hit(damage: int, _push: Vector2):
	if state == State.DEAD:
		return
	hp -= maxi(damage, 1)
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	if hp <= 0:
		if player and _names[player.state] != "GALLOP":
			_kill_sound.play(KILL_SOUND_SKIP)
		_die()


# killed by the counter: splits in two along the counter's slash (from a to b, in the world). Without a
# line it splits straight across the middle. The top half slides off down the cut, the bottom slumps.
func cut_in_half(dir: int, a := Vector2.INF, b := Vector2.INF):
	if state == State.DEAD:
		return
	hp = 0
	_spawn_halves(dir, a, b)
	_die()


func _die():
	_set_state(State.DEAD)
	velocity = Vector2.ZERO
	_shape.set_deferred("disabled", true)
	visible = false
	EnemyKit.hitstop(get_tree(), HITSTOP)
	_burst(juice_color, 18, 2.0)
	_burst(Pixel.ORANGE, 8, 1.0)              # the last of its fire
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = "Chili"
	drop.color = juice_color
	drop.position = get_parent().to_local(global_position + Vector2(0, -10))
	get_parent().add_child.call_deferred(drop)


func _respawn():
	global_position = home
	velocity = Vector2.ZERO
	hp = 1
	visible = true
	_shape.set_deferred("disabled", false)
	_set_state(State.PATROL)


# ---------- hurting the player ----------
func _touch_player():
	if player == null or state in [State.DIZZY, State.DEAD]:
		return
	var box := Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size)
	if EnemyKit.hurt_player(player, box, global_position.x) and state == State.CHARGE:
		_charge_landed = true


# ---------- effects ----------
func _burst(color: Color, amount: int, size: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.color = color
	p.position = get_parent().to_local(global_position + Vector2(0, -12))
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


func _skid_dust():
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.4
	p.explosiveness = 0.8
	p.direction = Vector2(-facing, -0.4)
	p.spread = 30.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 2.0
	p.color = Color(0.49, 0.43, 0.43)
	p.position = get_parent().to_local(global_position + Vector2(0, -2))
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


# the two halves, cut along the line from a to b: textured polygons, like the Mango's
func _spawn_halves(dir: int, a: Vector2, b: Vector2):
	var tex := _art_texture()
	var rect := Rect2(-6, -22, 12, 22)
	var la := Vector2(-10, -11)
	var lb := Vector2(10, -11)
	if a != Vector2.INF and b != Vector2.INF and a != b:
		la = to_local(a)
		lb = to_local(b)
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var halves := _split(corners, la, lb)
	var along := (lb - la).normalized()
	if along.y < 0.0 or (along.y == 0.0 and along.x * dir < 0.0):
		along = -along
	var top_index := 0 if _centroid(halves[0]).y < _centroid(halves[1]).y else 1
	for i in 2:
		var pts: Array[Vector2] = halves[i]
		if pts.size() < 3:
			continue
		var c := _centroid(pts)
		var poly := PackedVector2Array()
		var uv := PackedVector2Array()
		for p in pts:
			poly.append(p - c)
			var u := rect.end.x - p.x if facing < 0 else p.x - rect.position.x
			uv.append(Vector2(u, p.y - rect.position.y))
		var piece := Polygon2D.new()
		piece.texture = tex
		piece.polygon = poly
		piece.uv = uv
		get_parent().add_child(piece)
		piece.global_position = to_global(c)
		var top := i == top_index
		var slide := along * (14.0 if top else -3.0) + Vector2(0, -2 if top else 3)
		var t := piece.create_tween().set_parallel()
		t.tween_property(piece, "position", piece.position + slide, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(piece, "rotation", signf(along.x) * (0.6 if top else -0.15), 0.35)
		t.tween_property(piece, "modulate:a", 0.0, 0.25).set_delay(0.35)
		t.chain().tween_callback(piece.queue_free)


func _split(poly: Array[Vector2], a: Vector2, b: Vector2) -> Array:
	var one: Array[Vector2] = []
	var other: Array[Vector2] = []
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var sp := (b - a).cross(p - a)
		var sq := (b - a).cross(q - a)
		if sp >= 0.0:
			one.append(p)
		if sp <= 0.0:
			other.append(p)
		if (sp > 0.0 and sq < 0.0) or (sp < 0.0 and sq > 0.0):
			var x := p.lerp(q, sp / (sp - sq))
			one.append(x)
			other.append(x)
	return [one, other]


func _centroid(pts: Array[Vector2]) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1.0)


# ---------- drawing ----------
static func _art_texture() -> ImageTexture:
	if _texture:
		return _texture
	var img := Image.create(12, ART.size(), false, Image.FORMAT_RGBA8)
	for row in ART.size():
		var line: String = ART[row]
		for col in line.length():
			if line[col] != ".":
				img.set_pixel(col, row, PALETTE[line[col]])
	_texture = ImageTexture.create_from_image(img)
	return _texture


func _draw():
	var hop := 0.0
	if state == State.WINDUP:
		hop = -absf(sin(state_time * 30.0)) * 2.0           # stomping on the spot
	var lean := 0.0
	if state == State.CHARGE:
		lean = facing * 0.25                                # leaning into the charge
	elif state == State.DIZZY:
		lean = sin(state_time * 14.0) * 0.12                # wobbling
	draw_set_transform(Vector2(0, hop), lean, Vector2(facing, 1))
	draw_texture(_art_texture(), Vector2(-6, -ART.size()), Color.WHITE)
	draw_set_transform(Vector2.ZERO)
	# flames on its back: growing through the windup, roaring through the charge
	var fire := 0.0
	if state == State.WINDUP:
		fire = clampf(state_time / windup_time, 0.0, 1.0)
	elif state == State.CHARGE:
		fire = 1.0
	if fire > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		for i in int(6 + 10 * fire):
			var k := float(i) * 1.7
			var x := -facing * (3.0 + fmod(k * 3.1, 7.0)) + sin(t * 20.0 + k) * 1.5
			var rise := fmod(t * 40.0 + k * 9.0, 14.0 * fire + 2.0)
			var y := -14.0 - rise + fmod(k * 5.0, 6.0)
			var col: Color = FLAMES[clampi(int(rise / (14.0 * fire + 2.0) * FLAMES.size()), 0, FLAMES.size() - 1)]
			draw_rect(Rect2(roundf(x), roundf(y), 1, 2 if rise < 4.0 else 1), col)
	if state == State.NOTICE:                                 # the "!"
		var cs := Pixel.cells("!", Vector2(-1, -ART.size() - 12), 1)
		Pixel.draw_cells(self, cs, [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD])
	if state == State.DIZZY:                                  # little stars going round
		for i in 2:
			var a := state_time * 7.0 + i * PI
			var p := Vector2(cos(a) * 6.0, -ART.size() - 4.0 + sin(a) * 2.0).round()
			draw_rect(Rect2(p, Vector2(1, 1)), Pixel.MUSTARD)
