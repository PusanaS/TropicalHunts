extends Node2D
# Living background: add this node to a level scene (the gym has it as "LivingBackground").
# BOOM's pixel style: 1:1 pixels, flat colours with one shade tone, no outlines, fully opaque.
#  - sky and sun, then three parallax jungle layers: far volcano + canopy (with drifting clouds
#    and light shafts), palms, and flowering bushes
#  - grass and flowers on every floor: they sway in the wind and part around the player
#  - drifting leaves and pollen
#  - water in the open parts of "PitBed" bodies: waves, splashes, wading
#  - reactions: reaching top speed (the sonic boom), landings, heavy impacts and enemy hits send a
#    ripple through the grass and blow the leaves; the flash cuts a path through the grass
# Hides the scene's plain "Backdrop" while the game runs.
# Reads from the player: state, velocity, speed_level, is_on_floor(), and its script's State + SPEEDS.

const TILE := 960.0              # the parallax layers repeat every TILE pixels
const C0 := -72.0                # camera height when the player stands on a floor at y=0
const GUST_SPEED := 300.0        # how fast a shockwave ripple travels through the grass
const PART_R := 20.0             # grass this close to the player's feet parts around them
const WATER_DEPTH := 24.0
const WATER_BODIES := ["PitBed"]                            # water fills the open top of these
const SHALLOW_DEPTH := 3.0       # shallow stretches flooded on long floors: just over the feet
const SHALLOW_MIN_FLOOR := 480.0 # only floors at least this long get shallow water...
const SHALLOW_EVERY := 900.0     # ...about one stretch per this many pixels of floor
const SHALLOW_LEN := Vector2(140, 300)
# a W landing in water sends a wave rolling out both ways that hits enemies: [height, reach, damage]
const W_WAVES := {
	"ATTACK_HEAVY_SMASH": [18.0, 150.0, 2],
	"DASH_ATTACK_HEAVY_IMPACT": [22.0, 190.0, 3],
	"CHARGED_SMASH": [30.0, 260.0, 4],
}
const WAVE_SPEED := 260.0
const WAVE_W := 22.0             # width of the crest
const WAVE_PUSH := Vector2(220, -220)
const NO_GRASS := ["Wall", "Ceiling", "Monster", "PitBed"]  # no grass on bodies named like this
const LEAVES := 16
const POLLEN := 22
const WIND := 10.0
const WAVE := 900.0              # water: how fast ripples spread...
const TENSION := 20.0            # ...how hard the surface pulls back flat...
const DAMP := 2.5                # ...and how fast it calms down

const LEAF_FRAMES := [
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(2, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(2, 0)],
	[Vector2(1, 0), Vector2(1, 1), Vector2(1, 2)],
	[Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
]

# palette: greens from the fruit art, accents from BOOM's player sheet
var c_sky := [Color("72b8ce"), Color("8fc5d4"), Color("aed4dc"), Color("cfe2e1"), Color("ecdfdb")]
var c_sun := Color("f6efd8")
var c_cloud := Color("ecdfdb")
var c_cloud_shade := Color("d3dcda")
var c_mountain := Color("6aa3b3")
var c_mountain_shade := Color("5a91a2")
var c_far := Color("5e917d")
var c_far_shade := Color("4f7f6d")
var c_shaft := Color("eaf0d6")
var c_mid := Color("526e36")
var c_mid_shade := Color("3c522a")
var c_near := Color("76964a")
var c_near_shade := Color("526e36")
var c_light_green := Color("a4bf68")
var c_trunk := Color("624021")
var c_trunk_shade := Color("4d321a")
var c_flowers := [Color("8d0e0e"), Color("d36618"), Color("ccad4b"), Color("ecdfdb")]
var c_leaves := [Color("76964a"), Color("a4bf68"), Color("ccad4b"), Color("d36618")]
var c_pollen := [Color("ccad4b"), Color("ecdfdb")]
var c_water := Color("3894b1")
var c_water_light := Color("72b8ce")
var c_water_shade := Color("2c7892")
var c_foam := Color("ecdfdb")

var _t := 0.0
var _sky: Node2D
var _sky_size := Vector2.ZERO
var _far: Node2D
var _clouds: Node2D
var _shafts := []            # two phases of the light shafts, shown in turn so they shimmer
var _mid: Node2D
var _near: Node2D
var _grass_back: Node2D
var _grass_front: Node2D
var _water_node: Node2D
var _leaves_back: Node2D
var _leaves_front: Node2D

# grass blades, sorted by x
var _gx := PackedFloat32Array()
var _gy := PackedFloat32Array()
var _gh := PackedInt32Array()
var _gph := PackedFloat32Array()
var _gflag := PackedInt32Array()     # bit 0 = in front of the player, bits 1+ = 0 grass, 1 light grass, 2 flower
var _gcol := PackedInt32Array()      # flower colour
var _gbend := PackedFloat32Array()
var _gvel := PackedFloat32Array()
var _vis0 := 0
var _vis1 := 0

var _water := []             # {x0, n, level, bed, h, v, visible}
var _leaves := []            # [pos, impulse, phase, front, colour]
var _pollen := []            # [pos, impulse, phase, colour]
var _drops := []             # water splash drops: [pos, vel, colour, life, size]
var _waves := []             # {x, y, dir, t0, h, reach, damage, hit, spray}
var _gusts := []             # [origin, start time, strength]

var _state_names: Array = []
var _last_state := ""
var _was_top := false
var _last_pos := Vector2.ZERO
var _has_last_pos := false
var _wade_timer := 0.0
var _enemy_hp := {}


func _ready():
	global_position = Vector2.ZERO
	add_to_group("living_background")     # other effects ask in_water() through this group
	var backdrop := get_parent().get_node_or_null("Backdrop") as CanvasItem
	if backdrop:
		backdrop.visible = false

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	_sky = Node2D.new()
	_sky.draw.connect(_draw_sky.bind(_sky))
	sky_layer.add_child(_sky)

	_far = _tiles(-100, _gen_far())
	_clouds = _tiles(-99, _gen_clouds())
	_shafts = [_tiles(-98, _gen_shafts(0)), _tiles(-98, _gen_shafts(1))]
	_mid = _tiles(-90, _gen_mid())
	_near = _tiles(-80, _gen_near())

	var rects := _level_rects()
	var shallows := _build_shallows(rects)
	_build_grass(rects, shallows)
	_build_water(rects)
	_leaves_back = _world_node(-3, _draw_leaves.bind(false))
	_grass_back = _world_node(-2, _draw_grass.bind(false))
	_grass_front = _world_node(2, _draw_grass.bind(true))
	_water_node = _world_node(2, _draw_water)
	_leaves_front = _world_node(3, _draw_leaves.bind(true))


func _process(delta):
	var dt := minf(delta, 0.05)
	_t += dt
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var cam := _camera_center(player)

	var screen := get_viewport().get_visible_rect().size
	if screen != _sky_size:
		_sky_size = screen
		_sky.queue_redraw()
	_place(_far, 0.12, cam, 0.0, 165.0)
	_place(_clouds, 0.05, cam, _t * 4.0, 60.0)
	for s in _shafts:
		_place(s, 0.2, cam, 0.0, 175.0)
	_shafts[0].visible = int(_t / 0.35) % 2 == 0
	_shafts[1].visible = not _shafts[0].visible
	_place(_mid, 0.3, cam, 0.0, 185.0)
	_place(_near, 0.55, cam, 0.0, 205.0)

	if player:
		_watch_player(player, dt)
	_watch_hits()
	_gusts = _gusts.filter(func(g): return (_t - g[1]) * GUST_SPEED < 360.0)

	_update_grass(cam, player, dt)
	_update_water(cam, dt)
	_update_waves(dt)
	_update_particles(cam, dt)
	for n in [_grass_back, _grass_front, _water_node, _leaves_back, _leaves_front]:
		n.queue_redraw()


func _camera_center(player: Node2D) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return cam.get_screen_center_position()
	return player.global_position + Vector2(0, -72) if player else Vector2.ZERO


# a parallax layer: moves `f` as fast as the camera (plus a sideways drift), content drawn as 3 tiles
func _place(layer: Node2D, f: float, cam: Vector2, drift: float, horizon_on_screen: float):
	var scroll := cam.x * f - drift
	var k := floorf(scroll / TILE)
	var base := horizon_on_screen - 135.0 + C0 * f
	layer.global_position = Vector2(cam.x - scroll + k * TILE, cam.y * (1.0 - f) + base).round()


# ---------- reacting to the player and to hits ----------
func _watch_player(player: CharacterBody2D, dt: float):
	if _state_names.is_empty():
		_state_names = player.get_script().State.keys()
	var pos := player.global_position
	var st: String = _state_names[player.state]
	if st != _last_state:
		match st:
			"LAND": _gust(pos, 1.5)
			"ATTACK_HEAVY_SMASH": _gust(pos, 3.0)
			"DASH_ATTACK_HEAVY_IMPACT": _gust(pos, 5.0)
			"CHARGED_SMASH": _gust(pos, 7.0)
		if W_WAVES.has(st):
			var w := _water_under(pos)
			if not w.is_empty():
				_make_wave(player, pos, w, W_WAVES[st])
		_last_state = st
	# the sonic boom: reaching the top speed level on the ground
	var top: int = player.get_script().SPEEDS.size() - 1
	var at_top: bool = player.speed_level >= top and player.is_on_floor()
	if at_top and not _was_top:
		_gust(pos, 5.0)
		var w := _water_under(pos)
		if not w.is_empty():        # breaking the sound barrier in water: a huge burst
			_splash(pos.x, w["level"], 28, 280.0)
	_was_top = at_top
	if _has_last_pos:
		# the flash moves the player a long way in one frame: cut a path through the grass
		if absf(pos.x - _last_pos.x) > 60.0 and absf(pos.y - _last_pos.y) < 20.0:
			_slice(_last_pos.x, pos.x, pos.y, signf(pos.x - _last_pos.x))
		_water_contact(_last_pos, pos, player.velocity, dt)
	_last_pos = pos
	_has_last_pos = true


func _watch_hits():
	var seen := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		var hp = e.get("hp")
		if hp == null or not (e is Node2D):
			continue
		var id: int = e.get_instance_id()
		seen[id] = true
		if _enemy_hp.has(id) and hp < _enemy_hp[id]:
			_gust(e.global_position, 2.5)
		_enemy_hp[id] = hp
	for id in _enemy_hp.keys():
		if not seen.has(id):
			_enemy_hp.erase(id)


# a shockwave ring: grass bends away as it passes, leaves and pollen get blown away
func _gust(origin: Vector2, strength: float):
	if _gusts.size() >= 12:
		_gusts.pop_front()
	_gusts.append([origin, _t, strength])
	for p in _leaves + _pollen:
		var d: Vector2 = p[0] - origin
		var dist := d.length()
		if dist < 200.0 and dist > 0.0:
			p[1] += d / dist * strength * 30.0 * (1.0 - dist / 200.0)


func _slice(x0: float, x1: float, y: float, dir: float):
	for i in range(_gx.bsearch(minf(x0, x1)), _gx.bsearch(maxf(x0, x1))):
		if absf(_gy[i] - y) < 20.0:
			_gvel[i] += dir * 140.0


# ---------- grass ----------
func _level_rects() -> Array:
	var out := []
	for body in get_parent().find_children("*", "StaticBody2D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape2D and cs.shape is RectangleShape2D:
				var size: Vector2 = cs.shape.size
				out.append([Rect2(cs.global_position - size / 2.0, size), String(body.name)])
	return out


func _covered(rects: Array, p: Vector2, own: Rect2) -> bool:
	for r in rects:
		var rect: Rect2 = r[0]
		if rect != own and rect.has_point(p):
			return true
	return false


# shallow water: a few stretches of the long floors flooded just over the feet. Returns [x0, x1, y].
func _build_shallows(rects: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var spans := []
	for r in rects:
		var rect: Rect2 = r[0]
		var body_name: String = r[1]
		if rect.size.x < SHALLOW_MIN_FLOOR or NO_GRASS.any(func(n): return body_name.begins_with(n)):
			continue
		var y := rect.position.y
		for k in maxi(1, int(rect.size.x / SHALLOW_EVERY)):
			var length := roundf(rng.randf_range(SHALLOW_LEN.x, SHALLOW_LEN.y))
			var x0 := roundf(rng.randf_range(rect.position.x + 60.0, rect.end.x - 60.0 - length))
			var x1 := x0 + length
			var clear := true
			for s in spans:          # keep stretches apart
				if s[2] == y and x0 < s[1] + 40.0 and x1 > s[0] - 40.0:
					clear = false
			var sx := x0
			while clear and sx <= x1:  # nothing standing in it
				if _covered(rects, Vector2(sx, y - 1.0), rect):
					clear = false
				sx += 4.0
			if clear:
				spans.append([x0, x1, y])
				_water.append(_water_region(x0, int(length), y - SHALLOW_DEPTH, y, true))
	return spans


func _water_region(x0: float, n: int, level: float, bed: float, shallow: bool) -> Dictionary:
	var h := []
	h.resize(n)
	h.fill(0.0)
	return {"x0": x0, "n": n, "level": level, "bed": bed, "h": h, "v": h.duplicate(), "visible": false, "shallow": shallow}


func _build_grass(rects: Array, shallows: Array):
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blades := []
	for r in rects:
		var rect: Rect2 = r[0]
		var body_name: String = r[1]
		if NO_GRASS.any(func(n): return body_name.begins_with(n)):
			continue
		var y := rect.position.y
		# only blocks sitting right on this top can cover it: check against those
		var blockers := rects.filter(func(o): return o[0] != rect \
			and o[0].position.y <= y - 1.0 and o[0].end.y > y - 1.0 \
			and o[0].end.x > rect.position.x and o[0].position.x < rect.end.x)
		var wet := shallows.filter(func(s): return s[2] == y and s[1] > rect.position.x and s[0] < rect.end.x)
		var x := rect.position.x + rng.randf_range(0.5, 1.5)
		while x < rect.end.x - 1.0:
			var dry: bool = not wet.any(func(s): return x >= s[0] - 1.0 and x <= s[1] + 1.0)
			if dry and not _covered(blockers, Vector2(x, y - 1.0), rect):
				var front := rng.randf() < 0.2
				var kind := 2 if rng.randf() < 0.015 else (1 if rng.randf() < 0.25 else 0)
				var h := rng.randi_range(5, 9) if front else rng.randi_range(8, 17)
				blades.append([floorf(x), y, h, rng.randf() * TAU, (1 if front else 0) | (kind << 1), rng.randi() % c_flowers.size()])
			x += rng.randf_range(0.6, 1.4)
	blades.sort_custom(func(a, b): return a[0] < b[0])
	for b in blades:
		_gx.append(b[0])
		_gy.append(b[1])
		_gh.append(b[2])
		_gph.append(b[3])
		_gflag.append(b[4])
		_gcol.append(b[5])
		_gbend.append(0.0)
		_gvel.append(0.0)


func _update_grass(cam: Vector2, player: CharacterBody2D, dt: float):
	_vis0 = _gx.bsearch(cam.x - 260.0)
	_vis1 = _gx.bsearch(cam.x + 260.0)
	var feet := player.global_position if player else Vector2(1e9, 1e9)
	var vx := player.velocity.x if player else 0.0
	for i in range(_vis0, _vis1):
		var x := _gx[i]
		var gy := _gy[i]
		var target := sin(_t * 1.2 + x * 0.03 + _gph[i]) * 0.7    # a barely-there breeze: tips shift a pixel now and then
		var dx := x - feet.x
		if absf(dx) < PART_R and absf(gy - feet.y) < 18.0:
			var near := 1.0 - absf(dx) / PART_R
			var side := 1.0 if dx >= 0.0 else -1.0
			# parts away from the feet, and gets brushed hard along the way you're running
			target += side * near * 4.0 + signf(vx) * near * minf(absf(vx) / 40.0, 12.0)
		for g in _gusts:
			var origin: Vector2 = g[0]
			var ring: float = (_t - g[1]) * GUST_SPEED
			var k := 1.0 - absf(Vector2(x, gy).distance_to(origin) - ring) / 16.0
			if k > 0.0:
				target += (1.0 if x >= origin.x else -1.0) * g[2] * k
		_gvel[i] += (target - _gbend[i]) * 140.0 * dt
		_gvel[i] *= exp(-2.5 * dt)          # springy: swings back and forth for about a second after you pass
		_gbend[i] = clampf(_gbend[i] + _gvel[i] * dt, -14.0, 14.0)


func _draw_grass(front: bool):
	var n := _grass_front if front else _grass_back
	for i in range(_vis0, _vis1):
		var flag := _gflag[i]
		if ((flag & 1) == 1) != front:
			continue
		var kind := flag >> 1
		var x := _gx[i]
		var gy := _gy[i]
		var h := _gh[i]
		var base := c_light_green if kind == 1 else c_near
		var shade := c_near if kind == 1 else c_near_shade
		# the blade bottom to top, merged into strips wherever the bend and colour stay the same
		var bend := _gbend[i]
		var start := 0
		var off := roundf(bend * pow(1.0 / h, 1.6))
		var run_off := off
		var run_col := shade
		for j in range(1, h + 1):
			var col := run_col
			if j < h:
				off = roundf(bend * pow((j + 1.0) / h, 1.6))
				col = shade if j * 3 < h else base
			if j == h or off != run_off or col != run_col:
				n.draw_rect(Rect2(x + run_off, gy - j, 1, j - start), run_col)
				start = j
				run_off = off
				run_col = col
		if kind == 2:
			n.draw_rect(Rect2(x + off - 1.0, gy - h - 2.0, 3, 2), c_flowers[_gcol[i]])


# ---------- water ----------
func _build_water(rects: Array):
	for r in rects:
		if not WATER_BODIES.has(r[1]):
			continue
		var rect: Rect2 = r[0]
		var y := rect.position.y
		var start := -1
		for x in range(int(rect.position.x), int(rect.end.x) + 1):
			var open := x < int(rect.end.x) and not _covered(rects, Vector2(x + 0.5, y - 1.0), rect)
			if open and start < 0:
				start = x
			elif not open and start >= 0:
				_water.append(_water_region(float(start), x - start, y - WATER_DEPTH, y, false))
				start = -1


func _update_water(cam: Vector2, dt: float):
	for w in _water:
		var x0: float = w["x0"]
		var n: int = w["n"]
		w["visible"] = x0 + n > cam.x - 280.0 and x0 < cam.x + 280.0
		if not w["visible"]:
			continue
		var h: Array = w["h"]
		var v: Array = w["v"]
		for c in n:
			var left: float = h[c - 1] if c > 0 else 0.0
			var right: float = h[c + 1] if c < n - 1 else 0.0
			v[c] += ((left + right - 2.0 * h[c]) * WAVE - h[c] * TENSION - v[c] * DAMP) * dt
		for c in n:
			h[c] += v[c] * dt
	for d in _drops:
		d[1].y += 520.0 * dt
		d[0] += d[1] * dt
		d[3] -= dt
	_drops = _drops.filter(func(d): return d[3] > 0.0)


func _water_contact(prev: Vector2, pos: Vector2, vel: Vector2, dt: float):
	for w in _water:
		var x0: float = w["x0"]
		var n: int = w["n"]
		if pos.x < x0 or pos.x >= x0 + n:
			continue
		var level: float = w["level"]
		var v: Array = w["v"]
		var col := int(pos.x - x0)
		if prev.y < level and pos.y >= level:          # jumping in
			_splash(pos.x, level, 16, maxf(vel.y * 0.5, 120.0))
			for c in range(maxi(col - 6, 0), mini(col + 7, n)):
				v[c] += vel.y * 0.6
		elif prev.y >= level and pos.y < level:        # jumping out
			_splash(pos.x, level, 6, 90.0)
		elif pos.y > level and absf(vel.x) > 30.0:     # running through it: the faster, the bigger the spray
			var speed := absf(vel.x)
			var fast := clampf(speed / 600.0, 0.0, 1.0)
			_wade_timer -= dt
			v[col] += signf(vel.x) * 400.0 * dt
			if _wade_timer <= 0.0:
				_wade_timer = lerpf(0.09, 0.025, fast)
				_spray(pos.x, level, signf(vel.x), speed, 2 + int(speed / 90.0))


# a big splash straight up (jumping in, the sonic boom)
func _splash(x: float, y: float, count: int, speed: float):
	for i in count:
		var vel := Vector2(randf_range(-60.0, 60.0), -randf_range(speed * 0.5, speed))
		_drops.append([Vector2(x + randf_range(-4.0, 4.0), y), vel, c_foam if i % 3 == 0 else c_water_light,
			randf_range(0.5, 0.9), 2 if i % 4 == 0 else 1])


# spray kicked up by running through water: mostly thrown up and behind, a rooster tail at a gallop
func _spray(x: float, y: float, dir: float, speed: float, count: int):
	for i in count:
		var back := randf() < 0.75
		var vx := (-dir if back else dir) * randf_range(20.0, 60.0 + speed * 0.25)
		var vy := -randf_range(60.0, 90.0 + speed * 0.35)
		_drops.append([Vector2(x - dir * randf_range(0.0, 6.0), y), Vector2(vx, vy),
			c_foam if i % 3 == 0 else c_water_light, randf_range(0.35, 0.7), 2 if speed > 400.0 and i % 3 == 1 else 1])


# other effects (dust) ask this so they can stay out of the water
func in_water(pos: Vector2) -> bool:
	return not _water_under(pos).is_empty()


# other effects call this for a big moment (like the boss door shattering): a shockwave through
# the grass and leaves, and a splash if it happens in water. Strength ~2 small, 5 big, 7 huge.
func burst(pos: Vector2, strength: float):
	_gust(pos, strength)
	var w := _water_under(pos)
	if not w.is_empty():
		_splash(pos.x, w["level"], int(strength * 3.0), 60.0 + strength * 30.0)


# ---------- the W wave ----------
func _make_wave(player: CharacterBody2D, pos: Vector2, w: Dictionary, params: Array):
	var shallow: bool = w["shallow"]
	var y: float = w["bed"] if shallow else w["level"]     # rolls along the floor, or on top of deep water
	for dir in [-1.0, 1.0]:
		_waves.append({"x": pos.x, "y": y, "dir": dir, "t0": _t, "h": params[0],
			"reach": _wave_reach(player, pos.x, y, dir, params[1]), "damage": params[2], "hit": {}, "spray": 0.0})
	_splash(pos.x, w["level"], 20, 220.0)
	var v: Array = w["v"]
	var col := int(pos.x - w["x0"])
	for c in range(maxi(col - 10, 0), mini(col + 11, int(w["n"]))):
		v[c] += 260.0


# how far the wave can roll before a wall stops it
func _wave_reach(player: CharacterBody2D, x: float, y: float, dir: float, reach: float) -> float:
	var from := Vector2(x, y - 6.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * reach, 0), 1, [player.get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return reach if hit.is_empty() else absf(hit["position"].x - x) - 2.0


# where the crest is now and how tall: rises fast, shrinks as it travels, collapses at the end
func _wave_now(wv: Dictionary) -> Vector2:
	var age: float = _t - wv["t0"]
	var reach: float = wv["reach"]
	var travel := minf(age * WAVE_SPEED, reach)
	var rise := clampf(age / 0.08, 0.0, 1.0)
	var collapse := 1.0 - clampf((age - reach / WAVE_SPEED) / 0.25, 0.0, 1.0)
	var h: float = wv["h"] * rise * collapse * (1.0 - 0.5 * travel / maxf(reach, 1.0))
	return Vector2(wv["x"] + wv["dir"] * travel, h)


func _update_waves(dt: float):
	for wv in _waves:
		var now := _wave_now(wv)
		var front := now.x
		var h := now.y
		var dir: float = wv["dir"]
		var y: float = wv["y"]
		var rolling: bool = (_t - wv["t0"]) * WAVE_SPEED < wv["reach"]
		if not rolling or h < 4.0:
			continue
		# spray flying off the crest
		wv["spray"] -= dt
		if wv["spray"] <= 0.0:
			wv["spray"] = 0.03
			for i in 2:
				_drops.append([Vector2(front - dir * randf_range(3.0, 9.0), y - h), Vector2(dir * randf_range(40.0, 120.0), -randf_range(60.0, 160.0)),
					c_foam if i == 0 else c_water_light, randf_range(0.3, 0.6), 1])
		# hit each enemy once as the crest reaches it
		var hit: Dictionary = wv["hit"]
		for e in get_tree().get_nodes_in_group("enemies"):
			if not (e is Node2D) or not e.has_method("take_hit"):
				continue
			var id: int = e.get_instance_id()
			var hp = e.get("hp")
			if hit.has(id) or (hp != null and hp <= 0):
				continue
			var ep: Vector2 = e.global_position
			if absf(ep.x - front) < 14.0 and ep.y > y - 48.0 and ep.y < y + 12.0:
				hit[id] = true
				e.take_hit(wv["damage"], Vector2(dir * WAVE_PUSH.x, WAVE_PUSH.y))
	_waves = _waves.filter(func(wv): return _t - wv["t0"] < wv["reach"] / WAVE_SPEED + 0.25)


func _draw_waves(n: Node2D):
	for wv in _waves:
		var now := _wave_now(wv)
		var front := now.x
		var h := roundf(now.y)
		if h < 1.0:
			continue
		var dir: float = wv["dir"]
		var y: float = wv["y"]
		# the wash left behind, back to where it started
		var back := front - dir * WAVE_W
		var wash := maxf(1.0, roundf(h * 0.2))
		var x0 := roundf(minf(wv["x"], back))
		var x1 := roundf(maxf(wv["x"], back))
		if x1 > x0:
			n.draw_rect(Rect2(x0, y - wash, x1 - x0, wash), c_water)
			n.draw_rect(Rect2(x0, y - wash, x1 - x0, 1), c_water_light)
		# the crest: a steep front face, a foamy top, a longer slope behind
		for i in int(WAVE_W):
			var u := i / WAVE_W
			var ch := roundf(h * minf(u / 0.3, 1.0) * (1.0 - 0.7 * maxf(0.0, u - 0.3) / 0.7))
			if ch < 1.0:
				continue
			var cx := roundf(front - dir * i)
			n.draw_rect(Rect2(cx, y - ch, 1, ch), c_water)
			n.draw_rect(Rect2(cx, y - ch, 1, 1), c_water_light)
			if ch >= 4.0 and u > 0.12 and u < 0.55:
				n.draw_rect(Rect2(cx, y - ch, 1, 2), c_foam)
		# the lip curling over at the peak
		if h >= 6.0:
			var peak := roundf(front - dir * WAVE_W * 0.3)
			for k in 3:
				n.draw_rect(Rect2(peak + dir * (k + 1), y - h + k * 2, 1, 2), c_foam)


# the water the player is standing in, if any
func _water_under(pos: Vector2) -> Dictionary:
	for w in _water:
		var x0: float = w["x0"]
		if pos.x >= x0 and pos.x < x0 + w["n"] and pos.y >= w["level"] - 1.0:
			return w
	return {}


func _draw_water():
	var n := _water_node
	for w in _water:
		if not w["visible"]:
			continue
		var x0: float = w["x0"]
		var level: float = w["level"]
		var bed: float = w["bed"]
		var h: Array = w["h"]
		var v: Array = w["v"]
		var shallow: bool = w["shallow"]
		for c in int(w["n"]):
			var x := x0 + c
			var sy := roundf(level + h[c] + sin(_t * 2.2 + x * 0.35) * 0.6)
			if shallow:
				sy = clampf(sy, level - 2.0, bed - 1.0)    # shallow water only ripples a little
			n.draw_rect(Rect2(x, sy, 1, bed - sy), c_water)
			if bed - sy > 10.0:
				n.draw_rect(Rect2(x, bed - 6.0, 1, 6), c_water_shade)
			var foam: bool = absf(v[c]) > 25.0 or posmod(int(x) * 7 + int(_t * 5.0), 41) == 0
			n.draw_rect(Rect2(x, sy, 1, 1), c_foam if foam else c_water_light)
	_draw_waves(n)
	for d in _drops:
		var p: Vector2 = d[0]
		var s: float = d[4]
		n.draw_rect(Rect2(p.round(), Vector2(s, s)), d[2])


# ---------- leaves and pollen ----------
func _update_particles(cam: Vector2, dt: float):
	var view := Rect2(cam - Vector2(300, 190), Vector2(600, 380))
	var first := _leaves.is_empty()
	while _leaves.size() < LEAVES:
		var y := randf_range(view.position.y, view.end.y) if first else view.position.y + 2.0
		_leaves.append([Vector2(randf_range(view.position.x, view.end.x), y), Vector2.ZERO,
			randf() * TAU, randf() < 0.35, c_leaves[randi() % c_leaves.size()]])
	while _pollen.size() < POLLEN:
		_pollen.append([Vector2(randf_range(view.position.x, view.end.x), randf_range(view.position.y, view.end.y)),
			Vector2.ZERO, randf() * TAU, c_pollen[randi() % c_pollen.size()]])
	for p in _leaves:
		var ph: float = p[2]
		p[0] += (Vector2(WIND + sin(_t * 1.9 + ph) * 16.0, 13.0 + cos(_t * 2.3 + ph) * 9.0) + p[1]) * dt
		p[1] *= exp(-2.0 * dt)
	for p in _pollen:
		var ph: float = p[2]
		p[0] += (Vector2(WIND * 0.5 + sin(_t * 1.3 + ph) * 6.0, -5.0 + cos(_t * 1.7 + ph) * 4.0) + p[1]) * dt
		p[1] *= exp(-2.0 * dt)
	_leaves = _leaves.filter(func(p): return view.has_point(p[0]))
	_pollen = _pollen.filter(func(p): return view.has_point(p[0]))


func _draw_leaves(front: bool):
	var n := _leaves_front if front else _leaves_back
	for p in _leaves:
		if p[3] != front:
			continue
		var pos: Vector2 = p[0]
		var ph: float = p[2]
		for px in LEAF_FRAMES[posmod(int(_t * 5.0 + ph * 4.0), 4)]:
			n.draw_rect(Rect2(pos.round() + px, Vector2(1, 1)), p[4])
	if not front:
		for p in _pollen:
			var pos: Vector2 = p[0]
			n.draw_rect(Rect2(pos.round(), Vector2(1, 1)), p[3])


# ---------- the sky ----------
func _draw_sky(n: Node2D):
	var size := get_viewport().get_visible_rect().size
	var bands := [0.0, 0.26, 0.43, 0.56, 0.69]            # where each sky colour starts, top to bottom
	for b in bands.size():
		var y0 := roundf(bands[b] * size.y)
		var y1: float = size.y if b == bands.size() - 1 else roundf(bands[b + 1] * size.y)
		n.draw_rect(Rect2(0, y0, size.x, y1 - y0), c_sky[b])
		if b > 0:     # two dithered rows blend each band into the one above
			for x in range(0, int(size.x), 2):
				n.draw_rect(Rect2(x, y0, 1, 1), c_sky[b - 1])
				n.draw_rect(Rect2(x + 1, y0 + 1, 1, 1), c_sky[b - 1])
	var sun := Vector2(roundf(size.x * 0.78), 46)
	_disk_now(n, sun, 13, c_sun)
	for a in 36:
		var p := (sun + Vector2.from_angle(a * TAU / 36.0) * 17.0).round()
		n.draw_rect(Rect2(p, Vector2(1, 1)), c_sun)


func _disk_now(n: Node2D, center: Vector2, r: int, col: Color):
	for dy in range(-r, r + 1):
		var w := int(sqrt(float(r * r - dy * dy)))
		n.draw_rect(Rect2(center.x - w, center.y + dy, 2 * w + 1, 1), col)


# ---------- parallax layers: generated once, drawn as three copies of one tile ----------
func _tiles(z: int, rects: Array) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.draw.connect(_draw_tiles.bind(n, rects))
	add_child(n)
	return n


func _world_node(z: int, draw_fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.draw.connect(draw_fn)
	add_child(n)
	return n


func _draw_tiles(n: Node2D, rects: Array):
	for j in [-1, 0, 1]:
		var shift := Vector2(j * TILE, 0)
		for r in rects:
			var rect: Rect2 = r[0]
			n.draw_rect(Rect2(rect.position + shift, rect.size), r[1])


# a filled pixel disk, the lower part in the shade tone
func _disk(out: Array, cx: float, cy: float, r: int, base: Color, shade: Color):
	for dy in range(-r, r + 1):
		var w := int(sqrt(float(r * r - dy * dy)))
		out.append([Rect2(roundf(cx) - w, roundf(cy) + dy, 2 * w + 1, 1), base if dy * 3 < r else shade])


func _gen_far() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var peak := rng.randf_range(250.0, 700.0)
	for x in int(TILE):
		var fx := float(x)
		var hills := 34.0 + 10.0 * sin(TAU * 2.0 * fx / TILE + 1.3) + 6.0 * sin(TAU * 5.0 * fx / TILE + 0.4)
		var volcano := minf(maxf(0.0, 96.0 - absf(fx - peak) * 0.6), 82.0)     # flat-topped cone
		var top := -roundf(maxf(hills, volcano))
		var canopy := -roundf(18.0 + 6.0 * sin(TAU * 3.0 * fx / TILE + 2.2) + 5.0 * absf(sin(TAU * 24.0 * fx / TILE)))
		if top < canopy:
			out.append([Rect2(x, top, 1, canopy - top), c_mountain_shade if fx > peak and volcano > hills else c_mountain])
		out.append([Rect2(x, canopy, 1, 12), c_far])
		out.append([Rect2(x, canopy + 12, 1, 420), c_far_shade])
	return out


func _gen_clouds() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 6:
		var x := roundf(rng.randf_range(0.0, TILE))
		var y := roundf(rng.randf_range(-40.0, 10.0))
		var w := rng.randi_range(26, 54)
		out.append([Rect2(x + 8, y, w - 16, 2), c_cloud])
		out.append([Rect2(x + 2, y + 2, w - 4, 4), c_cloud])
		out.append([Rect2(x, y + 6, w, 4), c_cloud])
		out.append([Rect2(x + 2, y + 10, w - 4, 2), c_cloud_shade])
	return out


# diagonal light shafts: sparse opaque pixels. Phase 0 and 1 use opposite pixels, shown in turn.
func _gen_shafts(phase: int) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for s in 4:
		var sx := rng.randf_range(0.0, TILE)
		for y in range(-150, 30, 2):
			for w in 10:
				var x := int(sx + (y + 150) * 0.4) + w
				if posmod(x + int(floorf(y / 2.0)), 4) == phase * 2:
					out.append([Rect2(x, y, 1, 1), c_shaft])
	return out


func _gen_mid() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for i in 5:           # palms
		var px := rng.randf_range(0.0, TILE)
		var h := rng.randf_range(90.0, 140.0)
		var lean := rng.randf_range(-30.0, 30.0)
		for y in int(h):
			var q := y / h
			var x := roundf(px + lean * q * q)
			out.append([Rect2(x, -y, 3, 1), c_trunk])
			out.append([Rect2(x + 2, -y, 1, 1), c_trunk_shade])
		var crown := Vector2(px + lean, -h)
		for f in 7:
			var dir := Vector2.from_angle(lerpf(-PI * 0.95, -PI * 0.05, f / 6.0))
			var length := rng.randf_range(22.0, 34.0)
			for s in int(length):
				var q := s / length
				var p := crown + dir * s + Vector2(0, q * q * 20.0)       # fronds droop at the tips
				out.append([Rect2(p.round(), Vector2(2, 2)), c_mid if f % 2 == 0 else c_mid_shade])
		for c in 3:
			out.append([Rect2((crown + Vector2(c * 3 - 4, 2)).round(), Vector2(2, 2)), c_trunk])
	for x in int(TILE):   # jungle band in front of the trunks
		var top := -roundf(22.0 + 7.0 * sin(TAU * 3.0 * x / TILE + 2.0) + 6.0 * absf(sin(TAU * 30.0 * x / TILE)))
		out.append([Rect2(x, top, 1, 18), c_mid])
		out.append([Rect2(x, top + 18, 1, 420), c_mid_shade])
	return out


func _gen_near() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	out.append([Rect2(0, 4, TILE, 420), c_near_shade])
	for i in 26:          # bushes, some with flowers
		var cx := rng.randf_range(0.0, TILE)
		var cy := rng.randf_range(-4.0, 6.0)
		var r := rng.randi_range(9, 20)
		_disk(out, cx, cy, r, c_near, c_near_shade)
		if rng.randf() < 0.6:
			for k in rng.randi_range(1, 3):
				var p := Vector2(cx, cy) + Vector2.from_angle(rng.randf_range(-PI * 0.9, -PI * 0.1)) * (r - 3)
				out.append([Rect2(p.round(), Vector2(2, 2)), c_flowers[rng.randi() % c_flowers.size()]])
	return out
