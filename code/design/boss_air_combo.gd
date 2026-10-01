extends Node2D
# The air combo. When a hit knocks the boss up, the boss spawns this: the player leaps after it and
# the combo keeps going as long as the player keeps attacking.
#   Every hit knocks the boss up and away (Q a little, W a lot); it floats, slows, then starts to fall.
#   The player chases it, a moment behind, so each knock is easy to see.
#   Q = quick hit (1 damage), W = big hit (3 damage, a little slower). Presses during the launch count.
#   Stop attacking for COMBO_WINDOW seconds, or let it fall near the floor, and the combo drops.
#   Empty the boss's health mid-combo and it goes straight into the anime finisher (boss_finisher.gd).
# Like the finisher, it steers the player from outside for a while (player.gd is untouched).
# PLACEHOLDER effects: the real air attacks are BOOM's to animate.

const EnemyKit := preload("res://code/design/enemy_kit.gd")

const LAUNCH := Vector2(60, -300)         # the knock that starts it (away from the player, up)
const FLOAT_GRAVITY := 420.0              # floatier than normal, so it hangs between hits
const AIR_DRAG := 400.0                   # how fast the sideways push dies out
const MAX_HEIGHT := 400.0                 # it can't be knocked higher than this above the floor
const PLAYER_SPOT := Vector2(58, -36)     # where the player hangs, from the boss's feet
const FOLLOW := 14.0                      # how quickly the player catches up (higher = less lag)
const START_GRACE := 0.15                 # hits count after this long into the launch
const COMBO_WINDOW := 0.7                 # time allowed between hits before the combo drops
const MIN_HEIGHT := 24.0                  # the combo drops when it falls this close to the floor
# Q: quick slashes, thin slash line. W: winds up (sword raised back), then a big chop with a crescent slash.
const LIGHT := {"damage": 1, "gap": 0.16, "knock": Vector2(90, -220), "shake": 3.0,
	"anims": ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2"], "speed": 2.0, "windup": 0.0}
const HEAVY := {"damage": 3, "gap": 0.42, "knock": Vector2(160, -320), "shake": 9.0,
	"anims": ["DASH_ATTACK_HEAVY_IMPACT"], "speed": 1.6, "windup": 0.14, "windup_anim": "DASH_ATTACK_HEAVY_WINDUP"}
const SLASH_COLOR := Color(1.0, 0.97, 0.88)

var boss: CharacterBody2D
var player: CharacterBody2D

var _psprite: AnimatedSprite2D
var _side := 1.0            # which side of the boss the player is on
var _floor_y := 0.0
var _vel := Vector2.ZERO    # the boss's motion while the combo runs
var _time := 0.0
var _since_hit := 0.0
var _cooldown := 0.0
var _buffer: Dictionary = {}
var _pending: Dictionary = {}      # a W that is winding up
var _pending_left := 0.0
var _anim_i := 0
var _done := false


func _ready():
	_psprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_side = signf(player.global_position.x - boss.global_position.x)
	if _side == 0.0:
		_side = 1.0
	_floor_y = _find_floor()
	EnemyKit.protect_player(1.0)
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.facing = int(-_side)
	_psprite.flip_h = -_side < 0.0
	_psprite.speed_scale = 1.0
	_psprite.play("DOUBLE_JUMP")
	# the launch: the boss flies up and away, the player leaps after it
	_vel = Vector2(-_side * LAUNCH.x, LAUNCH.y)
	_shake(6.0, 0.2)


func _process(delta: float):
	if _done:
		return
	EnemyKit.protect_player(0.3)
	# remember a press even if it comes during the launch or a slower hit
	if Input.is_action_just_pressed("attack_heavy"):
		_buffer = HEAVY
	elif Input.is_action_just_pressed("attack_light"):
		_buffer = LIGHT

	_time += delta
	_since_hit += delta
	_cooldown -= delta
	_move_boss(delta)
	_follow(delta)
	if not _pending.is_empty():
		_pending_left -= delta
		if _pending_left <= 0.0:
			var wound := _pending
			_pending = {}
			_strike(wound)
			if _done:
				return
	if _time >= START_GRACE and not _buffer.is_empty() and _cooldown <= 0.0 and _pending.is_empty():
		var kind := _buffer
		_buffer = {}
		_hit(kind)
		if _done:
			return
	if _since_hit >= COMBO_WINDOW or (_vel.y > 0.0 and _floor_y - boss.global_position.y <= MIN_HEIGHT):
		_drop()


func _move_boss(delta: float):
	_vel.y += FLOAT_GRAVITY * delta
	_vel.x = move_toward(_vel.x, 0.0, AIR_DRAG * delta)
	if _vel.x != 0.0 and _wall_ahead(signf(_vel.x)):
		_vel.x = 0.0
	var p := boss.global_position + _vel * delta
	p.y = clampf(p.y, _floor_y - MAX_HEIGHT, _floor_y)
	if p.y <= _floor_y - MAX_HEIGHT:
		_vel.y = maxf(_vel.y, 0.0)
	boss.global_position = p


# the player chases their spot next to the boss, a moment behind
func _follow(delta: float):
	var spot := boss.global_position + Vector2(_side * PLAYER_SPOT.x, PLAYER_SPOT.y)
	player.global_position = player.global_position.lerp(spot, 1.0 - exp(-FOLLOW * delta))


func _hit(kind: Dictionary):
	_since_hit = 0.0
	_cooldown = kind["gap"]
	if kind["windup"] > 0.0:
		# W: raise the sword first; the blow lands when the windup is over
		_psprite.speed_scale = 1.0
		_psprite.play(kind["windup_anim"])
		_pending = kind
		_pending_left = kind["windup"]
		return
	_strike(kind)


func _strike(kind: Dictionary):
	var anims: Array = kind["anims"]
	_psprite.play(anims[_anim_i % anims.size()])
	_psprite.speed_scale = kind["speed"]
	_anim_i += 1
	# knocked up and away from the player; the player will chase it
	var knock: Vector2 = kind["knock"]
	_vel = Vector2(-_side * knock.x, knock.y)
	var center := boss.global_position + Vector2(0, -40)
	if kind["damage"] >= 3:
		_slash_arc(center)
		_burst(center)
	else:
		var d := Vector2.from_angle(randf() * PI)
		_streak(center - d * 36.0, center + d * 36.0, 2.0, 0.1)
	_shake(kind["shake"], 0.1)
	if player.has_method("play_swing_sound"):
		player.play_swing_sound(kind["damage"] >= 3)    # the same Q / W sounds as on the ground
	var emptied: bool = boss.combo_hit(kind["damage"])
	if emptied:
		# the finisher takes the player over from here (or, with the finisher off, it just dies)
		_done = true
		boss.combo_finished()
		if not boss.finisher:
			_release()
		queue_free()


func _drop():
	_done = true
	boss.drop_from_combo(Vector2(_vel.x, maxf(_vel.y, 0.0)))
	_release()
	queue_free()


# give the player back: they fall from where they are
func _release():
	_psprite.speed_scale = 1.0
	player.set_physics_process(true)
	player.velocity = Vector2.ZERO
	if player.has_method("_set_state"):
		player._set_state(player.get_script().State.JUMP_FALL)


func _wall_ahead(dir: float) -> bool:
	var from := boss.global_position + Vector2(0, -40)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * 44.0, 0), 1)
	var skip: Array[RID] = [boss.get_rid(), player.get_rid()]
	q.exclude = skip
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _find_floor() -> float:
	var from := boss.global_position + Vector2(0, -4)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 600), 1)
	var skip: Array[RID] = [boss.get_rid(), player.get_rid()]
	q.exclude = skip
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return boss.global_position.y
	return float(hit["position"].y)


func _streak(a: Vector2, b: Vector2, width: float, fade := 0.14):
	_fading_line(PackedVector2Array([to_local(a), to_local(b)]), width, fade)


# W: a big crescent slash across the boss
func _slash_arc(center: Vector2):
	var pts := PackedVector2Array()
	for i in 11:
		var a := lerpf(-2.4, 0.5, i / 10.0)
		pts.append(to_local(center + Vector2(cos(a) * -_side * 52.0, sin(a) * 52.0)))
	_fading_line(pts, 7.0, 0.22)


func _fading_line(points: PackedVector2Array, width: float, fade: float):
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = SLASH_COLOR
	line.z_index = 5
	add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "width", 0.0, fade)
	t.tween_callback(line.queue_free)


# W: a burst of sparks where the big blow lands
func _burst(at: Vector2):
	var s := CPUParticles2D.new()
	s.one_shot = true
	s.amount = 12
	s.lifetime = 0.3
	s.explosiveness = 1.0
	s.spread = 180.0
	s.initial_velocity_min = 120.0
	s.initial_velocity_max = 240.0
	s.gravity = Vector2.ZERO
	s.scale_amount_min = 3.0
	s.scale_amount_max = 3.0
	s.color = SLASH_COLOR
	s.position = to_local(at)
	s.z_index = 5
	s.finished.connect(s.queue_free)
	add_child(s)
	s.emitting = true


func _shake(strength: float, seconds: float):
	if player.has_method("_shake"):
		player._shake(strength, seconds)
