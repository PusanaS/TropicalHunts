extends StaticBody2D
# Tutorial gate: closes the way out of a station until code/design/tutorial.gd calls open() (the station's
# test is passed). Then it unlatches with a little drop and winches up into the wall, with a puff of dust.
# Same art and placement as the gym's breakable gate (code/design/breakable_door.gd): feet on the floor,
# under a wall that ends 112px above the floor, so it hides in the wall once it's up. This one can't be broken.
# PLACEHOLDER art (scene/design/art/portcullis.png).

const TEXTURE: Texture2D = preload("res://scene/design/art/portcullis.png")  # 48x120, ground at y 112
const SIZE := Vector2(48, 112)                  # the doorway it blocks
const SPRITE_Y := -52.0                         # sprite centre when down (120 tall, 8 of it underground)
const RISE := 120.0                             # fully up inside the wall
const DIRT := [Color(0.38, 0.25, 0.13), Color(0.49, 0.43, 0.43)]

var _shape: CollisionShape2D
var _sprite: Sprite2D
var _open := false


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


func is_open() -> bool:
	return _open


# instant: already open when the scene starts (the player starts past it)
func open(instant := false):
	if _open:
		return
	_open = true
	_shape.set_deferred("disabled", true)
	if instant:
		_sprite.position.y = SPRITE_Y - RISE
		return
	var t := create_tween()
	t.tween_property(_sprite, "position:y", SPRITE_Y + 2.0, 0.06)
	t.tween_property(_sprite, "position:y", SPRITE_Y - RISE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_dust()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player._shake(3.0, 0.25)


func _dust():
	for side in [-1.0, 1.0]:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = 10
		p.lifetime = 0.5
		p.explosiveness = 0.9
		p.direction = Vector2(side, -0.6)
		p.spread = 30.0
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 90.0
		p.gravity = Vector2(0, 200)
		p.scale_amount_min = 2.0
		p.scale_amount_max = 2.0
		p.color = DIRT[0] if side < 0.0 else DIRT[1]
		p.position = Vector2(side * SIZE.x / 2.0, -2.0)
		p.z_index = 3
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true
