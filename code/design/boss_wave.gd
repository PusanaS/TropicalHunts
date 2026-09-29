extends Node2D
# Shockwave from the boss's stomp. Runs along the floor until it hits a wall or runs out. Jump over it.
# PLACEHOLDER look.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const SHEET: Texture2D = preload("res://scene/design/art/boss_wave.png")   # 3 frames, 32x20 each
const FRAME := Vector2(32, 20)
const HURT_BOX := Rect2(-12, -14, 24, 14)
const MAX_DIST := 420.0

var direction := 1
var speed := 220.0
var _dist := 0.0
var _time := 0.0
var _player: CharacterBody2D = null


func _ready():
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func _physics_process(delta: float):
	_time += delta
	var step := direction * speed * delta
	# stop at walls (the ray skips the player)
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -6), global_position + Vector2(step + direction * 12.0, -6), 1)
	if _player:
		var skip: Array[RID] = [_player.get_rid()]
		q.exclude = skip
	if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
		queue_free()
		return
	position.x += step
	_dist += absf(step)
	if _dist >= MAX_DIST:
		queue_free()
		return
	if _player and is_instance_valid(_player):
		EnemyKit.hurt_player(_player, Rect2(global_position + HURT_BOX.position, HURT_BOX.size), global_position.x - direction * 20.0)
	queue_redraw()


func _draw():
	var frame := int(_time * 12.0) % 3
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(direction, 1))
	draw_texture_rect_region(SHEET, Rect2(-FRAME.x / 2, -FRAME.y, FRAME.x, FRAME.y), Rect2(frame * FRAME.x, 0, FRAME.x, FRAME.y))
