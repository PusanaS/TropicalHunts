extends CharacterBody2D
# COCONUT: Level 2's armoured fruit. It's hard and SOLID (collision layer 1, like the level), so the player
# can't walk through it, and galloping into it knocks them back like a wall. The Thunderclap flash never
# fires on it either: you smack into it instead. PLACEHOLDER look, drawn in code in BOOM's palette.
#
# Monster card
#   Moves:     "sit": sits in the way. "roll": once it sees you on its level, it rolls at you and keeps
#              rolling, bouncing off walls (and off you) and dropping off ledges.
#   Notices:   roll mode only: the player within sight_range at about its height.
#   Attack:    rolling into you. The warning: it wobbles for a moment before it sets off.
#   After:     it never stops rolling until it's broken.
#   Beaten by: heavy hits. Q (and the rolling slash) clang off and knock you back. A W (smash, leap slam,
#              air slam, charged smash, a W wave) cracks it; any hit after that breaks it. Or jump over it.
#   Touch:     solid. Sitting: harmless, it just blocks. Rolling: hurts.
#   Drops:     one juice drop (coconut water).
#   Animations BOOM and Violeta will need: IDLE (sitting), WOBBLE (about to roll), ROLL (spinning),
#              CLANG (a light hit bouncing off), CRACKED (idle and rolling, with a crack), BREAK (two halves
#              and a splash)

enum State { SIT, WOBBLE, ROLL, BROKEN }

@export var mode := "sit"                    # "sit" or "roll"
@export var sight_range := 260.0             # roll mode: starts rolling when the player is this close
@export var roll_speed := 230.0
@export var wobble_time := 0.35              # the warning before it rolls
@export var respawn_time := 0.0              # comes back after this long, 0 = stays broken (and is freed)
@export var juice_color := Color(0.86, 0.93, 0.95)    # coconut water

const RADIUS := 11.0
const SIGHT_HEIGHT := 40.0
const FLOOR_FRICTION := 700.0
const HURTBOX := Rect2(-12, -24, 24, 25)      # where the player can hit it (a little over the shell)
const TOUCH_BOX := Rect2(-13, -24, 26, 26)    # rolling: touching this hurts
const ARMOR_PUSHBACK := 220.0                 # a light hit bouncing off knocks the player back (like the boss)
const HITSTOP_CRACK := 0.06
const HITSTOP_BREAK := 0.09
# hits that crack it (the rest clang off). Anything else hitting it through take_hit counts as heavy when it
# does 2 damage or more (the charged smash, W waves).
const HEAVY_MOVES := ["ATTACK_HEAVY_SMASH", "DASH_ATTACK_HEAVY_IMPACT", "DASH_ATTACK_HEAVY_SLAM", "CHARGED_SMASH"]
const JuiceDrop := preload("res://code/design/juice_drop.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const ARMOR_SOUND := preload("res://sounds/sword/sword_clash_06.wav")    # the boss's armour clang
const ARMOR_SOUND_DB := -6.0
const ARMOR_SOUND_SKIP := 0.012               # the clang gets loud 13ms in
const CRACK_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRACK_SOUND_DB := -9.0
const CRACK_SOUND_SKIP := 0.02                # the file starts with 20ms of silence
const SPLASH_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const SPLASH_SOUND_DB := -4.0
const SPLASH_SOUND_SKIP := 0.12               # 0.12 s of silence first

# placeholder palette: brown hairy shell, dark eyes, white flesh in the crack
const SHELL := Color("624021")
const SHELL_DARK := Color("4d321a")
const HAIR := Color("8a6338")
const FLESH := Pixel.OFF_WHITE

var state: State = State.SIT
var state_time := 0.0
var hp := 2                       # 2 = whole, 1 = cracked, 0 = broken (the combo HUD counts each drop)
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _names: Array = []
var _top_level := 4
var _dir := -1.0                  # which way it rolls
var _start_dir := 0.0             # coconut_drop.gd: set before it's added, so it rolls the moment it lands
var _walls_hit := 0               # a dropped coconut cracks open on its second wall (or it would roll forever)
var _spin := 0.0                  # how far round it has rolled (radians)
var _flash := 0.0
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _shape: CollisionShape2D
var _armor_sound := AudioStreamPlayer.new()
var _crack_sound := AudioStreamPlayer.new()
var _splash_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	collision_layer = 1           # solid like the level: the player can't pass, galloping into it knocks them back
	collision_mask = 1
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	_shape.shape = circle
	_shape.position = Vector2(0, -RADIUS)
	add_child(_shape)
	home = global_position
	for p in [[_armor_sound, ARMOR_SOUND, ARMOR_SOUND_DB], [_crack_sound, CRACK_SOUND, CRACK_SOUND_DB],
			[_splash_sound, SPLASH_SOUND, SPLASH_SOUND_DB]]:
		var s: AudioStreamPlayer = p[0]
		s.stream = p[1]
		s.volume_db = p[2]
		s.max_polyphony = 3
		add_child(s)
	if _start_dir != 0.0:
		_dir = signf(_start_dir)
		mode = "roll"
		_set_state(State.ROLL)


# coconut_drop.gd: drop it already rolling this way (call before adding it)
func start_rolling(dir: float):
	_start_dir = dir


# the flash only goes for enemies that are alive: while the player gallops this one isn't, so they
# smack into it instead (a solid body on layer 1 knocks a gallop back)
func is_alive() -> bool:
	if state == State.BROKEN:
		return false
	if player and player.speed_level >= _top_level:
		return false
	return true


func _set_state(s: State):
	state = s
	state_time = 0.0


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_names = player.get_script().State.keys()
		var speeds: Array = player.get_script().SPEEDS
		_top_level = speeds.size() - 1


func _physics_process(delta: float):
	state_time += delta
	_flash -= delta
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	if state == State.BROKEN:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		elif respawn_time <= 0.0 and state_time >= 1.0:
			queue_free()          # (waits a moment, so the combo counter sees its last hit)
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	if player:
		_check_player_attack()
		if state == State.BROKEN:
			return

	match state:
		State.SIT:
			velocity.x = move_toward(velocity.x, 0.0, FLOOR_FRICTION * delta)
			if mode == "roll" and _sees_player():
				_dir = signf(player.global_position.x - global_position.x)
				if _dir == 0.0:
					_dir = -1.0
				_set_state(State.WOBBLE)
		State.WOBBLE:
			velocity.x = 0.0
			if state_time >= wobble_time:
				_set_state(State.ROLL)
		State.ROLL:
			if is_on_floor():
				velocity.x = _dir * roll_speed

	move_and_slide()

	if state == State.ROLL:
		_spin += velocity.x / RADIUS * delta
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			if absf(c.get_normal().x) > 0.7 and c.get_normal().x * _dir < 0.0:
				if c.get_collider() == player:
					_hurt_player()           # it bounces off you either way
				else:
					_walls_hit += 1
					if _start_dir != 0.0 and _walls_hit >= 2:
						_break(false)
						break
				_dir = -_dir
				velocity.x = _dir * roll_speed
				break
		if state == State.ROLL:
			_hurt_player()
	queue_redraw()


func _sees_player() -> bool:
	if player == null:
		return false
	var d := player.global_position - global_position
	return absf(d.y) <= SIGHT_HEIGHT and absf(d.x) <= sight_range


func _hurt_player():
	if player == null:
		return
	var box := Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size)
	EnemyKit.hurt_player(player, box.grow(2.0), global_position.x)


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
	var heavy: bool = _names[ps] in HEAVY_MOVES
	if not heavy and hp >= 2 and player.has_method("bounce_back"):
		player.bounce_back(global_position.x, ARMOR_PUSHBACK)    # a light hit bounces off the shell
	_hit(heavy)


# from outside (the charged smash, W waves, the flash): 2 damage or more counts as heavy
func take_hit(damage: int, _push: Vector2):
	_hit(damage >= 2)


func _hit(heavy: bool):
	if state == State.BROKEN:
		return
	if hp >= 2 and not heavy:              # whole shell, light hit: clang
		_armor_sound.play(ARMOR_SOUND_SKIP)
		_flash = 0.06
		_burst(Pixel.OFF_WHITE, Vector2(0, -RADIUS), 7, 1.0)
		return
	hp -= 1
	if hp <= 0:
		_break()
		return
	# cracked: still solid, still rolling, but the next hit of any kind breaks it
	_crack_sound.play(CRACK_SOUND_SKIP)
	_flash = 0.08
	_burst(FLESH, Vector2(0, -RADIUS), 8, 2.0)
	EnemyKit.hitstop(get_tree(), HITSTOP_CRACK)
	if player:
		player._shake(4.0, 0.15)


# by_player false: it cracked on a wall by itself (no freeze or shake, wherever the player is)
func _break(by_player := true):
	_set_state(State.BROKEN)
	velocity = Vector2.ZERO
	_shape.set_deferred("disabled", true)
	visible = false
	if by_player or (player and global_position.distance_to(player.global_position) < 400.0):
		_crack_sound.play(CRACK_SOUND_SKIP)
		_splash_sound.play(SPLASH_SOUND_SKIP)
	if by_player:
		EnemyKit.hitstop(get_tree(), HITSTOP_BREAK)
		if player:
			player._shake(7.0, 0.2)
	var away := signf(global_position.x - player.global_position.x) if player else _dir
	if away == 0.0:
		away = 1.0
	# the shell splits in two halves that fly off, spinning
	for side in [-1.0, 1.0]:
		_fly_half(side, Vector2(away * randf_range(60, 140) + side * 50.0, randf_range(-260, -180)), side * randf_range(8, 14))
	# and the coconut water bursts out
	_burst(juice_color, Vector2(0, -RADIUS), 22, 2.0)
	_burst(FLESH, Vector2(0, -RADIUS), 8, 2.0)
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = "Coconut"
	drop.color = juice_color
	drop.position = get_parent().to_local(global_position + Vector2(0, -12))
	get_parent().add_child.call_deferred(drop)


func _respawn():
	global_position = home
	velocity = Vector2.ZERO
	hp = 2
	_spin = 0.0
	visible = true
	_shape.set_deferred("disabled", false)
	_set_state(State.SIT)


func _burst(color: Color, offset: Vector2, amount: int, size: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 190.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.color = color
	p.position = get_parent().to_local(global_position + offset)
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


# one half of the shell (side -1 = left, 1 = right): a textured polygon that flies off, spins, lands where
# the coconut was and fades
func _fly_half(side: float, vel: Vector2, spin: float):
	var tex := _texture(false)
	var r := RADIUS + 0.5
	var poly := PackedVector2Array()
	var uv := PackedVector2Array()
	for k in 9:                            # round the half from top to bottom (the cut closes it)
		var p := Vector2(side * sin(PI * k / 8.0) * r, -cos(PI * k / 8.0) * r)
		poly.append(p)
		uv.append(p + Vector2(r, r))
	var piece := Polygon2D.new()
	piece.texture = tex
	piece.polygon = poly
	piece.uv = uv
	piece.z_index = 3
	get_parent().add_child(piece)
	var start := global_position + Vector2(side * 2.0, -RADIUS)
	piece.global_position = start
	var floor_y := global_position.y - 4.0
	var t := piece.create_tween()
	t.tween_method(func(time: float):
		var pos := start + vel * time + Vector2(0, 450.0 * time * time)
		piece.global_position = Vector2(pos.x, minf(pos.y, floor_y))
		piece.rotation = spin * minf(time, 0.6), 0.0, 1.2, 1.2)
	t.parallel().tween_property(piece, "modulate:a", 0.0, 0.4).set_delay(0.8)
	t.tween_callback(piece.queue_free)


# ---------- drawing ----------
static var _textures := {}             # cracked? -> the shell drawn once into a texture


# the shell as a pixel disk with its three "eyes", hairy fibres and shade (and a white crack once hit)
static func _texture(cracked: bool) -> ImageTexture:
	if _textures.has(cracked):
		return _textures[cracked]
	var r := int(RADIUS)
	var img := Image.create(2 * r + 1, 2 * r + 1, false, Image.FORMAT_RGBA8)
	for y in range(-r, r + 1):
		var w := int(sqrt(float(r * r - y * y)))
		for x in range(-w, w + 1):
			var edge := absi(x) == w or absi(y) == r
			var col := SHELL_DARK if edge else SHELL
			if not edge and posmod(x * 7 + y * 13, 5) == 0:
				col = HAIR                              # hairy fibres
			if y > r / 2:
				col = col.darkened(0.15)                # shade underneath
			for eye in [Vector2(-3, -5), Vector2(3, -5), Vector2(0, -1)]:
				if not edge and (Vector2(x, y) - eye).length() < 1.2:
					col = Pixel.INK                     # the three "eyes"
			if cracked and not edge and absi(x - roundi(sin(y * 1.3) * 1.5)) < 1:
				col = FLESH                             # the crack, white flesh showing
			img.set_pixel(x + r, y + r, col)
	var tex := ImageTexture.create_from_image(img)
	_textures[cracked] = tex
	return tex


func _draw():
	var angle := _spin
	if state == State.WOBBLE:
		angle = sin(state_time * 40.0) * 0.18
	var tex := _texture(hp < 2)
	draw_set_transform(Vector2(0, -RADIUS), angle)
	draw_texture(tex, -Vector2(RADIUS, RADIUS), Color(3, 3, 3) if _flash > 0.0 else Color.WHITE)
	draw_set_transform(Vector2.ZERO)
