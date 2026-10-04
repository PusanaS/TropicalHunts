extends Node2D
# A palm that drops rolling coconuts (Level 2). Put it where the coconuts should fall from (the top of the
# palm): each one drops to the floor below and rolls off in `dir`, already rolling, so it doesn't need to
# see the player. They only fall while the player is within active_range, at most max_alive at a time,
# and are freed once they're broken or have rolled far away.
# PLACEHOLDER look: a palm crown and trunk drawn in code.

const Coconut := preload("res://code/design/coconut.gd")
const FRONDS := Color("526e36")
const FRONDS_LIGHT := Color("76964a")
const TRUNK := Color("624021")
const TRUNK_DARK := Color("4d321a")

@export var interval := 2.2              # seconds between coconuts
@export var dir := -1                    # the way they roll: -1 left, 1 right
@export var active_range := 900.0        # only drops while the player is this close (horizontally)
@export var max_alive := 3
@export var trunk := 96.0                # how far down the trunk is drawn (to the floor)
@export var roll_speed := 230.0

var _timer := 0.0
var _alive: Array = []
var _sway := 0.0


func _ready():
	z_index = -1                 # behind the player
	_timer = interval * 0.5


func _physics_process(delta: float):
	_sway += delta
	queue_redraw()
	_alive = _alive.filter(func(c): return is_instance_valid(c))
	for c in _alive:
		if absf(c.global_position.x - global_position.x) > active_range * 1.5 or c.global_position.y > global_position.y + 1200.0:
			c.queue_free()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or absf(player.global_position.x - global_position.x) > active_range:
		return
	_timer -= delta
	if _timer <= 0.0 and _alive.size() < max_alive:
		_timer = interval
		_drop()


func _drop():
	var c: CharacterBody2D = Coconut.new()
	c.roll_speed = roll_speed
	c.start_rolling(float(dir))
	get_parent().add_child(c)
	c.global_position = global_position + Vector2(dir * 6.0, 4.0)
	_alive.append(c)


func _draw():
	# the trunk, leaning a little, in segments
	for i in int(trunk / 6.0):
		var y := 6.0 + i * 6.0
		var x := roundf(sin(y / trunk * 1.2) * 3.0)
		draw_rect(Rect2(x - 3, y, 6, 6), TRUNK if i % 2 == 0 else TRUNK_DARK)
	# the crown: fronds hanging out both ways, swaying a little
	var sway := roundf(sin(_sway * 1.5) * 1.0)
	for side in [-1.0, 1.0]:
		for k in 3:
			var reach := 14.0 + k * 5.0
			var droop := 3.0 + k * 3.0
			for t in int(reach):
				var x: float = side * t
				var y: float = -6.0 + k * 2.0 + droop * pow(float(t) / reach, 2.0) + sway * float(t) / reach
				draw_rect(Rect2(roundf(x), roundf(y), 2, 2), FRONDS_LIGHT if k == 1 else FRONDS)
	# coconuts waiting in the crown
	for x in [-4.0, 3.0]:
		draw_rect(Rect2(x - 2, -2, 5, 5), TRUNK_DARK)
		draw_rect(Rect2(x - 1, -1, 3, 3), TRUNK)
