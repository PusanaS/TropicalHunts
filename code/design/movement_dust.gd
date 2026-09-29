extends Node2D
# Movement dust: puffs that make the player's movement feel weighty.
#   jump: a small puff where they left the ground      double jump: a ring under their feet
#   land: puffs out to both sides (bigger for a hard landing)
#   brake: a skid trail of dust kicked forward
#   gallop: see-through afterimages trailing behind
#   heavy smash / running slam: dust bursting along the ground
# Drop this node into any level (like LiveReload). It only watches the player; player.gd is untouched.
# PLACEHOLDER look, in BOOM's palette.

const PUFF: Texture2D = preload("res://scene/design/art/dust_puff.png")     # 6 frames, 16x16
const SMALL: Texture2D = preload("res://scene/design/art/dust_small.png")   # 4 frames, 8x8
const RING: Texture2D = preload("res://scene/design/art/dust_ring.png")     # 4 frames, 32x12

const HARD_LANDING := 520.0                     # falling faster than this (px/s) = the big landing puffs
const SKID_EVERY := {"BRAKE_LIGHT": 0.06, "BRAKE_HARD": 0.035}      # skid dust, seconds apart
const PUFF_TIME := 0.36
const SMALL_TIME := 0.28
const RING_TIME := 0.22
const GHOST_EVERY := 0.05                       # gallop afterimages
const GHOST_TIME := 0.2
const GHOST_TINT := Color(0.85, 0.9, 1.0, 0.45)

var player: CharacterBody2D = null
var _sprite: AnimatedSprite2D = null
var _names: Array = []
var _last := ""
var _prev_vy := 0.0
var _was_on_floor := true
var _skid_timer := 0.0
var _ghost_timer := 0.0


func _process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_names = player.get_script().State.keys()
	var s: String = _names[player.state]
	var on_floor := player.is_on_floor()
	var feet := player.global_position
	var dir := float(player.facing)
	if s != _last:
		_on_enter(s, feet, dir)

	if SKID_EVERY.has(s) and on_floor:
		_skid_timer -= delta
		if _skid_timer <= 0.0:
			_skid_timer = SKID_EVERY[s]
			var kick := Vector2(dir * randf_range(30.0, 70.0), -randf_range(10.0, 30.0))
			if s == "BRAKE_HARD" and randf() < 0.3:
				_puff(feet + Vector2(dir * 8.0, 0), kick, dir < 0.0)
			else:
				_small(feet + Vector2(dir * 6.0, 0), kick)
	if s == "GALLOP":
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_EVERY
			_ghost()

	_last = s
	_prev_vy = player.velocity.y
	_was_on_floor = on_floor


func _on_enter(s: String, feet: Vector2, dir: float):
	# a W impact in water makes a wave instead (living_background.gd), so no dust
	if s in ["DASH_ATTACK_HEAVY_IMPACT", "ATTACK_HEAVY_SMASH"] and _in_water(feet):
		return
	match s:
		"LAND":
			var hard := _prev_vy >= HARD_LANDING
			for side: float in [-1.0, 1.0]:
				_puff(feet + Vector2(side * 7.0, 0), Vector2(side * (70.0 if hard else 45.0), 0), side < 0.0)
				if hard:
					_puff(feet + Vector2(side * 14.0, 0), Vector2(side * 110.0, -10.0), side < 0.0, 0.06)
		"JUMP_RISE":
			if _was_on_floor:
				_small(feet, Vector2(0, -20))
				for side: float in [-1.0, 1.0]:
					_small(feet + Vector2(side * 5.0, 0), Vector2(side * 40.0, -5.0))
		"DOUBLE_JUMP":
			_ring(feet + Vector2(0, 6))
		"DASH_ATTACK_HEAVY_IMPACT":
			_ring(feet + Vector2(0, 4))
			for side: float in [-1.0, 1.0]:
				for k in 3:
					_puff(feet + Vector2(side * (8.0 + k * 10.0), 0), Vector2(side * (90.0 + k * 40.0), -k * 8.0), side < 0.0, k * 0.04)
		"ATTACK_HEAVY_SMASH":
			_puff(feet + Vector2(dir * 26.0, 0), Vector2(dir * 60.0, -10.0), dir < 0.0)


func _in_water(feet: Vector2) -> bool:
	var bg := get_tree().get_first_node_in_group("living_background")
	return bg != null and bg.in_water(feet)


func _puff(pos: Vector2, vel: Vector2, flip: bool, delay := 0.0):
	_spawn(PUFF, 6, 16.0, pos, vel, flip, PUFF_TIME, delay, 1)


func _small(pos: Vector2, vel: Vector2):
	_spawn(SMALL, 4, 8.0, pos, vel, randf() < 0.5, SMALL_TIME, 0.0, 1)


func _ring(pos: Vector2):
	_spawn(RING, 4, 12.0, pos, Vector2.ZERO, false, RING_TIME, 0.0, 1)


# one dust sprite: its frames play through while it drifts, then it's gone.
# The bottom of the frame sits at `pos`, so dust sits on the ground.
func _spawn(tex: Texture2D, frames: int, height: float, pos: Vector2, vel: Vector2, flip: bool, time: float, delay: float, z: int):
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = frames
	s.flip_h = flip
	s.offset = Vector2(0, -height / 2.0)
	s.z_index = z
	add_child(s)
	s.global_position = pos.round()
	var t := s.create_tween()
	if delay > 0.0:
		s.visible = false
		t.tween_interval(delay)
		t.tween_callback(s.show)
	t.tween_property(s, "frame", frames - 1, time).from(0)
	t.parallel().tween_property(s, "global_position", (pos + vel * time).round(), time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(s.queue_free)


# gallop: a see-through copy of the player's current frame that fades where it was
func _ghost():
	var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.texture = tex
	g.flip_h = _sprite.flip_h
	g.modulate = GHOST_TINT
	g.z_index = -1
	add_child(g)
	g.global_position = _sprite.global_position
	var t := g.create_tween()
	t.tween_property(g, "modulate:a", 0.0, GHOST_TIME)
	t.tween_callback(g.queue_free)
