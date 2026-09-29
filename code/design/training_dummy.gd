extends Node2D
# Placeholder enemy for testing player attacks. Not solid, so you can run through it.
# Joins the "enemies" group and takes hits through take_hit(damage, push), same as the fruit minion.
# Turns white when hit, fades out when its hp runs out, and comes back after respawn_time.

@export var max_hp := 3
@export var respawn_time := 1.5

const SIZE := Vector2(24, 40)
const COLOR := Color(0.85, 0.35, 0.3)

var hp := 3
var hits := 0
var _flash := 0.0
var _respawn := 0.0


func _ready():
	add_to_group("enemies")
	hp = max_hp


func is_alive() -> bool:
	return hp > 0


func take_hit(damage: int, _push: Vector2):
	if hp <= 0:
		return
	hp = max(hp - damage, 0)
	hits += 1
	_flash = 0.12
	if hp == 0:
		_respawn = respawn_time
	queue_redraw()


func _process(delta):
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	if hp == 0:
		_respawn -= delta
		if _respawn <= 0.0:
			hp = max_hp
			queue_redraw()


func _draw():
	var body := Rect2(-SIZE.x / 2, -SIZE.y, SIZE.x, SIZE.y)
	if hp == 0:
		draw_rect(body, Color(COLOR, 0.25), false, 2.0)
		return
	draw_rect(body, Color.WHITE if _flash > 0.0 else COLOR)
	for i in max_hp:
		var pip := Rect2(-SIZE.x / 2 + i * 9, -SIZE.y - 8, 6, 4)
		draw_rect(pip, COLOR if i < hp else Color(COLOR, 0.25))
