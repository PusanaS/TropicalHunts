extends Area2D
# What a fruit enemy leaves behind: one juice ingredient. It hops out of the enemy, then flies to the
# player by itself and is picked up automatically (touching it works too).
# There is no inventory yet (and juice isn't decided), so it only shows "+1 <fruit>".
# PLACEHOLDER look: the real juice designs are Violeta's.

const SHOW_TIME := 0.8
const TEXTURE: Texture2D = preload("res://scene/design/art/juice_drop.png")
const POP := Vector2(60, -150)            # the little hop out of the enemy: random sideways, up
const POP_GRAVITY := 500.0
const HOME_DELAY := Vector2(0.25, 0.45)   # it hops for this long (random), then flies to the player
const HOME_ACCEL := 1400.0                # how hard it steers towards the player
const HOME_MAX_SPEED := 520.0
const COLLECT_DIST := 10.0
const PLAYER_MIDDLE := Vector2(0, -20)    # it flies to the middle of the player, not their feet

var fruit_name := "Mango"
var color := Color(1.0, 0.6, 0.1)

var _time := 0.0
var _picked_at := -1.0
var _vel := Vector2.ZERO
var _home_at := 0.3
var _player: Node2D = null


func _ready():
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_vel = Vector2(randf_range(-POP.x, POP.x), POP.y)
	_home_at = randf_range(HOME_DELAY.x, HOME_DELAY.y)


func _on_body_entered(body):
	# only the player picks it up (coconuts are solid, on the player's layer too)
	if body.is_in_group("player"):
		_collect()


func _collect():
	if _picked_at >= 0.0:
		return
	_picked_at = _time
	set_deferred("monitoring", false)


func _process(delta: float):
	_time += delta
	if _picked_at >= 0.0:
		if _time - _picked_at >= SHOW_TIME:
			queue_free()
	else:
		_fly(delta)
	queue_redraw()


func _fly(delta: float):
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _time < _home_at:
		_vel.y += POP_GRAVITY * delta          # the hop out of the enemy
		global_position += _vel * delta
		return
	if _player == null:
		return                                 # no player in this scene: just wait here
	var to := _player.global_position + PLAYER_MIDDLE - global_position
	if to.length() <= maxf(COLLECT_DIST, _vel.length() * delta):
		global_position = _player.global_position + PLAYER_MIDDLE
		_collect()
		return
	# steer towards the player, faster and faster: it curves in like it's pulled by a magnet
	_vel = _vel.move_toward(to.normalized() * HOME_MAX_SPEED, HOME_ACCEL * delta)
	global_position += _vel * delta


func _draw():
	if _picked_at >= 0.0:
		var t := (_time - _picked_at) / SHOW_TIME
		var text_color := Color(0.12, 0.14, 0.2, 1.0 - t)
		draw_string(ThemeDB.fallback_font, Vector2(-30, -8 - 20 * t), "+1 " + fruit_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, text_color)
		return
	# a bobbing drop of juice, moved in whole pixels so the pixel art stays crisp
	var bob := roundf(sin(_time * 4.0) * 1.5)
	draw_texture(TEXTURE, Vector2(-3, -5 + bob))
