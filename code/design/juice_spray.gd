extends Node2D
# Juice bursting out the far side of a cut: a fast jet, droplets that arc down and splat on the ground
# (little puddles that fade), chunks of fruit flesh and spiky skin that tumble and bounce, and a fine mist.
# Spawned by fruit_boss.gd's spray_juice(). BOOM's pixel style: square pixels, flat colours.
# Runs on game time, so a hit-freeze holds it for a moment before it flies.
# collect() (level 1's ending, blender_finish.gd, Morgan's idea): every drop, chunk and puddle lifts off the
# floor in turn and arcs into a target (the blender's jar), calling the receiver's take_drop(colour) as each
# arrives. It's in the group "juice_spray" so the blender can find it.
# PLACEHOLDER effect.

var color := Color(0.94, 0.77, 0.36)      # the fruit's juice
var aim := Vector2(1, -0.35).normalized() # which way it sprays (away from whoever cut it, leaning up)
var power := 1.0                          # 1 = a Q hit; bigger hits spray more, faster
var floor_y := INF                        # drops splat when they reach this height (global)
# true: a drop only splats at floor_y where there's solid ground there; anywhere else it falls on to the real ground
# below. For sprays off a Mango up on something narrow (a rock pillar's top): without it, every drop that flew past
# the edge left a puddle hanging in mid-air at that height, a dashed line across the sky (Morgan spotted it)
var check_ground := false

const SPLAT_LIFE := 2.0
const SPLAT_FADE := 0.6
const MAX_SPLATS := 40
const Z := 55                             # over everything, the finisher's dark screen too

enum Kind { DROP, CHUNK, MIST }

var _parts := []      # each: [pos, vel, size, colour, gravity, life, age, kind, bounced, own ground (local; INF: floor_y)]
var _splats := []     # each: [pos, width, colour, age]
var _suck := []       # collect(): each [from, delay, time, colour, size, control point, to, age]
var _receiver: Object = null


func _ready():
	z_index = Z
	add_to_group("juice_spray")
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


# everything still about (drops in the air, chunks, puddles) lifts off one by one over `over` seconds and arcs
# into `target` (global); the receiver's take_drop(colour) is called as each one lands. Returns how many.
func collect(target: Vector2, over: float, receiver: Object) -> int:
	_receiver = receiver
	var to := to_local(target)
	var items := []
	for p in _parts:
		if p[7] != Kind.MIST:
			items.append([p[0], p[3], p[2]])
	for s in _splats:
		items.append([s[0], s[2], Vector2(maxi(int(s[1]) - 1, 2), 2)])
	_parts = _parts.filter(func(p): return p[7] == Kind.MIST)
	_splats.clear()
	for it in items:
		var from: Vector2 = it[0]
		var ctrl := (from + to) / 2.0 + Vector2(randf_range(-20, 20), -randf_range(50, 100))   # up and over
		_suck.append([from, randf_range(0.0, over), randf_range(0.45, 0.7), it[1], it[2], ctrl, to, 0.0])
	return items.size()


func _px(lo: int, hi: int) -> Vector2:
	var s := randi_range(lo, hi)
	return Vector2(s, s)


func _cone(spread: float, lean := 0.0) -> Vector2:
	return (aim + Vector2(0, lean)).normalized().rotated(randf_range(-spread, spread))


func _add(direction: Vector2, speed: float, size: Vector2, col: Color, gravity: float, life: float, kind: Kind):
	_parts.append([Vector2.ZERO, direction * speed, size, col, gravity, life, 0.0, kind, false, INF])


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
		var g: float = ground if is_inf(p[9]) else p[9]
		if p[7] != Kind.MIST and p[0].y >= g and vel.y > 0.0:
			if check_ground and is_inf(p[9]):          # is there really ground here? if not, on down to it
				var below := _ground_below(global_position + Vector2(p[0].x, ground))
				p[9] = 1.0e9 if is_inf(below) else below - global_position.y    # (none: it falls till it's gone)
				if p[9] > g + 1.0:
					continue
				g = p[9]
			if p[7] == Kind.CHUNK and not p[8]:        # chunks bounce once
				p[0].y = g
				p[1] = Vector2(vel.x * 0.5, -vel.y * 0.35)
				p[8] = true
			else:
				if _splats.size() < MAX_SPLATS:        # drops leave a puddle; chunks lie where they land
					var width: int = randi_range(2, 5) if p[7] == Kind.DROP else int(p[2].x)
					_splats.append([Vector2(p[0].x, g), width, color.darkened(0.15) if p[7] == Kind.DROP else p[3], 0.0])
				p[6] = p[5]                              # gone
	_parts = _parts.filter(func(p): return p[6] < p[5])
	for s in _splats:
		s[3] += delta
	_splats = _splats.filter(func(s): return s[3] < SPLAT_LIFE)
	for s in _suck:                               # being collected: waiting its turn, then flying in
		s[7] += delta
		if s[7] >= s[1] + s[2]:
			if _receiver and is_instance_valid(_receiver):
				_receiver.take_drop(s[3])
	_suck = _suck.filter(func(s): return s[7] < s[1] + s[2])
	queue_redraw()
	if _parts.is_empty() and _splats.is_empty() and _suck.is_empty():
		queue_free()


# check_ground: where a drop at `at` (global) really lands: the first solid level body at or below it (a puddle
# sits 2px into it, like floor_y; on a quicksand's bed, up at the sand's surface). INF if there's none: it falls
# till it's gone.
func _ground_below(at: Vector2) -> float:
	var q := PhysicsRayQueryParameters2D.create(at + Vector2(0, -6), at + Vector2(0, 800))
	q.collision_mask = 1
	var skip: Array[RID] = []
	for i in 4:                                   # past anything that isn't level (a Mango, you)
		q.exclude = skip
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return INF
		if hit["collider"] is StaticBody2D:       # (AnimatableBody2D is one too)
			var y: float = hit["position"].y + 2.0
			if String(hit["collider"].name).begins_with("SandBed"):
				y -= 4.0                              # quicksand.gd's BAND: the surface stands 4px over its bed
			return y
		skip.append(hit["rid"])
	return INF


# where a collected bit is: still where it lay, then lifting off and swooping (quadratic curve) into the target
func _suck_pos(s: Array, at_age: float) -> Vector2:
	var k := clampf((at_age - float(s[1])) / float(s[2]), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var a: Vector2 = s[0]
	var c: Vector2 = s[5]
	var b: Vector2 = s[6]
	return a.lerp(c, k).lerp(c.lerp(b, k), k)


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
	for s in _suck:
		var c: Color = s[3]
		var size: Vector2 = s[4]
		var p := _suck_pos(s, s[7])
		if s[7] > s[1]:                           # in flight: a little trail behind it
			draw_rect(Rect2(_suck_pos(s, s[7] - 0.04).round(), Vector2(1, 1) * maxf(size.x - 1.0, 1.0)), Color(c, 0.5))
			size = Vector2(2, 2)
		draw_rect(Rect2(p.round(), size), c)
	for s in _splats:
		var c: Color = s[2]
		c.a = 1.0 - clampf((s[3] - (SPLAT_LIFE - SPLAT_FADE)) / SPLAT_FADE, 0.0, 1.0)
		var w: int = s[1]
		draw_rect(Rect2((s[0] as Vector2).round() + Vector2(-floorf(w / 2.0), -1), Vector2(w, 1)), c)
