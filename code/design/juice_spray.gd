extends Node2D
# Juice bursting out the far side of a cut: a fast jet, droplets that arc down and splat on the ground
# (little puddles that fade), chunks of fruit flesh and spiky skin that tumble and bounce, and a fine mist.
# Spawned by fruit_boss.gd's spray_juice(). BOOM's pixel style: square pixels, flat colours.
# Runs on game time, so a hit-freeze holds it for a moment before it flies.
# PLACEHOLDER effect.

var color := Color(0.94, 0.77, 0.36)      # the fruit's juice
var aim := Vector2(1, -0.35).normalized() # which way it sprays (away from whoever cut it, leaning up)
var power := 1.0                          # 1 = a Q hit; bigger hits spray more, faster
var floor_y := INF                        # drops splat when they reach this height (global)

const SPLAT_LIFE := 2.0
const SPLAT_FADE := 0.6
const MAX_SPLATS := 40
const Z := 55                             # over everything, the finisher's dark screen too

enum Kind { DROP, CHUNK, MIST }

var _parts := []      # each: [pos, vel, size, colour, gravity, life, age, kind, bounced]
var _splats := []     # each: [pos, width, colour, age]


func _ready():
	z_index = Z
	var light := color.lightened(0.35)
	var dark := color.darkened(0.3)
	var flesh := color.lightened(0.55)
	var skin := Color("624021")
	var fast := sqrt(power)
	for i in int(36 * power):             # the jet: a tight, fast stream
		_add(_cone(0.18), randf_range(380.0, 720.0) * fast, _px(1, 2), light if randf() < 0.5 else color,
			500.0, randf_range(0.2, 0.45), Kind.DROP)
	for i in int(70 * power):             # droplets: arc out and down, splat on the ground
		_add(_cone(0.7), randf_range(120.0, 460.0) * fast, _px(1, 3), [color, dark, light].pick_random(),
			900.0, 2.5, Kind.DROP)
	for i in int(10 * power):             # chunks of fruit flesh and spiky skin
		_add(_cone(0.9, -0.2), randf_range(100.0, 320.0) * fast, Vector2(randi_range(2, 4), randi_range(2, 4)),
			flesh if randf() < 0.65 else skin, 1100.0, 2.5, Kind.CHUNK)
	for i in int(24 * power):             # a fine mist hanging in the air
		_add(_cone(1.2), randf_range(30.0, 140.0), Vector2.ONE, light, 60.0, randf_range(0.3, 0.7), Kind.MIST)


func _px(lo: int, hi: int) -> Vector2:
	var s := randi_range(lo, hi)
	return Vector2(s, s)


func _cone(spread: float, lean := 0.0) -> Vector2:
	return (aim + Vector2(0, lean)).normalized().rotated(randf_range(-spread, spread))


func _add(direction: Vector2, speed: float, size: Vector2, col: Color, gravity: float, life: float, kind: Kind):
	_parts.append([Vector2.ZERO, direction * speed, size, col, gravity, life, 0.0, kind, false])


func _process(delta: float):
	var ground := floor_y - global_position.y
	for p in _parts:
		p[6] += delta
		var vel: Vector2 = p[1]
		vel.y += p[4] * delta
		if p[7] == Kind.MIST:
			vel *= maxf(1.0 - 3.0 * delta, 0.0)      # mist slows to a hang
		p[1] = vel
		p[0] += vel * delta
		if p[7] != Kind.MIST and p[0].y >= ground and vel.y > 0.0:
			if p[7] == Kind.CHUNK and not p[8]:        # chunks bounce once
				p[0].y = ground
				p[1] = Vector2(vel.x * 0.5, -vel.y * 0.35)
				p[8] = true
			else:
				if _splats.size() < MAX_SPLATS:        # drops leave a puddle; chunks lie where they land
					var width: int = randi_range(2, 5) if p[7] == Kind.DROP else int(p[2].x)
					_splats.append([Vector2(p[0].x, ground), width, color.darkened(0.15) if p[7] == Kind.DROP else p[3], 0.0])
				p[6] = p[5]                              # gone
	_parts = _parts.filter(func(p): return p[6] < p[5])
	for s in _splats:
		s[3] += delta
	_splats = _splats.filter(func(s): return s[3] < SPLAT_LIFE)
	queue_redraw()
	if _parts.is_empty() and _splats.is_empty():
		queue_free()


func _draw():
	for p in _parts:
		var c: Color = p[3]
		if p[7] == Kind.MIST:
			c.a = 1.0 - p[6] / p[5]
		var pos: Vector2 = p[0]
		draw_rect(Rect2(pos.round(), p[2]), c)
		var vel: Vector2 = p[1]
		if p[7] == Kind.DROP and vel.length() > 300.0:   # fast drops leave a short streak
			draw_rect(Rect2((pos - vel.normalized() * 2.0).round(), p[2]), c)
	for s in _splats:
		var c: Color = s[2]
		c.a = 1.0 - clampf((s[3] - (SPLAT_LIFE - SPLAT_FADE)) / SPLAT_FADE, 0.0, 1.0)
		var w: int = s[1]
		draw_rect(Rect2((s[0] as Vector2).round() + Vector2(-floorf(w / 2.0), -1), Vector2(w, 1)), c)
