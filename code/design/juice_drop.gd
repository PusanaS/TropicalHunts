extends Area2D
# What a fruit enemy leaves behind: one juice ingredient. The player picks it up by touching it.
# There is no inventory yet (and juice isn't decided), so it only shows "+1 <fruit>".
# PLACEHOLDER look: the real juice designs are Violeta's.

const SHOW_TIME := 0.8
const TEXTURE: Texture2D = preload("res://scene/design/art/juice_drop.png")

var fruit_name := "Mango"
var color := Color(1.0, 0.6, 0.1)

var _time := 0.0
var _picked_at := -1.0


func _ready():
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body):
	# the player is the only CharacterBody2D on layer 1; fruit enemies are on their own layer
	if _picked_at < 0.0 and body is CharacterBody2D:
		_picked_at = _time
		set_deferred("monitoring", false)


func _process(delta):
	_time += delta
	if _picked_at >= 0.0 and _time - _picked_at >= SHOW_TIME:
		queue_free()
	queue_redraw()


func _draw():
	if _picked_at >= 0.0:
		var t := (_time - _picked_at) / SHOW_TIME
		var text_color := Color(0.12, 0.14, 0.2, 1.0 - t)
		draw_string(ThemeDB.fallback_font, Vector2(-30, -8 - 20 * t), "+1 " + fruit_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, text_color)
		return
	# a bobbing drop of juice, moved in whole pixels so the pixel art stays crisp
	var bob := roundf(sin(_time * 4.0) * 1.5)
	draw_texture(TEXTURE, Vector2(-3, -5 + bob))
