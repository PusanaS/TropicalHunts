extends Node2D
# Living background: add this node to a level scene (the gym has it as "LivingBackground").
# BOOM's pixel style: 1:1 pixels, flat colours with one shade tone, no outlines, fully opaque.
#  - sky and sun, then six parallax layers, each slower the farther away it is: drifting clouds, the
#    volcano range, the far canopy (with light shafts), a row of distant trees, palms, and flowering
#    bushes. Farther layers are lighter and bluer.
#  - grass and flowers on every floor: they sway in the wind and part around the player
#  - drifting leaves and pollen
#  - water in the open parts of "PitBed" bodies: waves, splashes, wading
#  - lava in the open parts of "LavaBed" bodies: slow bubbles that pop and a glow over it, no wading
#    and no W waves. Hazards ask lava_at(pos).
#  - reactions: reaching top speed (the sonic boom), landings, heavy impacts and enemy hits send a
#    ripple through the grass and blow the leaves; the flash cuts a path through the grass
# A floor named "Shallow..." is flooded with shallow water end to end (otherwise shallows land at random).
# theme picks the look (same layers, different art):
#  - "day": the jungle at midday (the gym, Level 1)
#  - "sunset": a beach at sunset (Level 2): a big low sun sinking into the sea with a glitter path,
#    islands on the horizon, palm and dune silhouettes lit along their sun side, dune grass with warm
#    tips, golden motes, the first stars
#  - "volcano": night by an erupting volcano (Level 3): stars, a glowing crater with lava running down
#    its sides and a smoke plume lit from below, charred trees, rocks with glowing cracks, ash tufts,
#    ash falling and embers rising. "PitBed" is lava here too, and there's no shallow water.
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
const WAVE_SOUND := preload("res://sounds/WAVE_SOUND_universfield-water-splash-199583.mp3")
const WAVE_SOUND_DB := 0.0
const WAVE_SOUND_SKIP := 0.17    # the file starts with 0.17 s of near-silence, then swells as the wave rolls out
# a charged W in deep water drains the basin: a wall of water rolls out each way to its ends, pushing all
# the water along, and crashes out over the banks (Morgan's idea). Deep water has no gallop until then.
const DRAIN_SPEED := 420.0
const DRAIN_CREST := 22.0        # how far the wall of water stands above the water level (it grows as it gathers water)
const DRAIN_W := 40.0            # the wall's width: a steep front and a long slope down to the dry bed behind
# a drained basin can be flooded again (waterfall.gd calls refill()): a surge of water rolls back in from one
# end, shoving you along if it reaches you, and the basin is deep again behind it
const REFILL_CREST := 12.0       # how far the surge stands above the water level
const REFILL_W := 34.0           # its width: a steep front, sloping back down to the water level
const REFILL_SHOVE := 240.0      # it pushes you along this fast when it reaches you
# no grass (and no shallow water) on bodies named like this. Sand: quicksand floors. Crumble and Geyser:
# crumbling platforms and geyser vents (their collision is made in code). Board: boardwalk planks.
# Barricade: level 1's breakable barricades (grass on top would float once they're smashed).
const NO_GRASS := ["Wall", "Ceiling", "Monster", "PitBed", "Sand", "Lava", "Crumble", "Geyser", "Board", "Barricade"]
const LAVA_BODIES := ["LavaBed"]                            # lava fills the open top of these
const LEAVES := 16
const POLLEN := 22
const WIND := 10.0
const WAVE := 900.0              # water: how fast ripples spread...
const TENSION := 20.0            # ...how hard the surface pulls back flat...
const DAMP := 2.5                # ...and how fast it calms down
const PUFFS := 18                # volcano: smoke puffs in the plume

const LEAF_FRAMES := [
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(2, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(2, 0)],
	[Vector2(1, 0), Vector2(1, 1), Vector2(1, 2)],
	[Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
]

@export_enum("day", "sunset", "volcano") var theme := "day"   # the look (see the top)

# palette: greens from the fruit art, accents from BOOM's player sheet
var c_sky := [Color("72b8ce"), Color("8fc5d4"), Color("aed4dc"), Color("cfe2e1"), Color("ecdfdb")]
var c_sun := Color("f6efd8")
var c_cloud := Color("ecdfdb")
var c_cloud_shade := Color("d3dcda")
var c_mountain := Color("6aa3b3")
var c_mountain_shade := Color("5a91a2")
var c_far := Color("5e917d")
var c_far_shade := Color("4f7f6d")
var c_trees := Color("587f5a")
var c_trees_shade := Color("48694b")
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
# the themes' extra colours (the day doesn't use them, or they match the day's own)
var c_cloud_top := Color("ecdfdb")           # the top rows of a cloud
var c_grass := Color("76964a")               # grass blades: base, shade, the lighter kind, and the tip
var c_grass_shade := Color("526e36")
var c_grass_light := Color("a4bf68")
var c_grass_tip := Color("d08a4a")
var c_rim := Color("c86656")                 # sunset: warm light on the sun side; volcano: red glow
var c_rim_dim := Color("a8586a")
var c_sea_mid := Color("7a4876")
var c_sun_glow := [Color("f0a55a"), Color("f4bb68"), Color("f8d080")]   # outer to inner
var c_star := [Color("ecdfdb"), Color("cfe2e1")]
var c_lava := [Color("f6d24a"), Color("f2a23c"), Color("e8761e"), Color("b8401c"), Color("7a2016")]   # surface to bed
var c_lava_glow := Color("c2461c")
var c_crater := [Color("ffe27a"), Color("f6d24a"), Color("f2a23c"), Color("e8761e")]
var c_plume := [Color("7a2a22"), Color("5a2830"), Color("432c38"), Color("352a3a"), Color("2c2434")]   # lit to dark
var c_plume_lit := [Color("a8401e"), Color("8a3020")]
var c_crack := [Color("e0641e"), Color("f2b23c")]

var _sky_bands := [0.0, 0.26, 0.43, 0.56, 0.69]   # where each sky colour starts, top to bottom
var _mount_f := 0.05             # how fast the mountain layer moves with the camera
var _leaf_count := LEAVES
var _pollen_count := POLLEN
var _tips := 0                   # grass tips: 0 none, 1 on the lighter blades, 2 on every blade
var _peak := Vector2.ZERO        # volcano: the crater floor, in the mountain layer's tile
var _streaks := []               # volcano: lava running down its sides, each a list of pixels
var _stars := []                 # [x share of the screen, y share, phase, twinkle speed, big]
var _cam := Vector2.ZERO
var _horizon := 150.0            # sunset: where the sea meets the sky on screen (it follows the camera)
var _sky_fx: Node2D              # stars and the setting sun, redrawn every frame
var _fx_mount: Node2D            # volcano: the eruption, over the mountain layer
var _fx_far: Node2D              # sunset: the sun's glitter path on the sea

var _t := 0.0
var _sky: Node2D
var _sky_size := Vector2.ZERO
var _mountains: Node2D
var _far: Node2D
var _clouds: Node2D
var _shafts := []            # two phases of the light shafts, shown in turn so they shimmer
var _trees: Node2D
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
var _refills := []           # surges flooding a drained basin: {region, x, dir, speed, spray, shoved}
var _gusts := []             # [origin, start time, strength]

var _state_names: Array = []
var _last_state := ""
var _was_top := false
var _last_pos := Vector2.ZERO
var _has_last_pos := false
var _wade_timer := 0.0
var _enemy_hp := {}
var _wave_sound := AudioStreamPlayer.new()


func _ready():
	global_position = Vector2.ZERO
	add_to_group("living_background")     # other effects ask in_water() through this group
	_apply_theme()
	var backdrop := get_parent().get_node_or_null("Backdrop") as CanvasItem
	if backdrop:
		backdrop.visible = false

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	_sky = Node2D.new()
	_sky.draw.connect(_draw_sky.bind(_sky))
	sky_layer.add_child(_sky)
	if theme != "day":
		_sky_fx = Node2D.new()
		_sky_fx.draw.connect(_draw_sky_fx.bind(_sky_fx))
		sky_layer.add_child(_sky_fx)

	_mountains = _tiles(-100, _gen_mountains())
	if theme == "volcano":
		_fx_mount = _world_node(-100, _draw_mount_fx)
	_clouds = _tiles(-99, _gen_clouds())
	_far = _tiles(-98, _gen_far())
	if theme == "sunset":
		_fx_far = _world_node(-97, _draw_glitter)
	_shafts = [_tiles(-97, _gen_shafts(0)), _tiles(-97, _gen_shafts(1))]
	_trees = _tiles(-95, _gen_trees())
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
	_wave_sound.stream = WAVE_SOUND
	_wave_sound.volume_db = WAVE_SOUND_DB
	_wave_sound.max_polyphony = 2
	add_child(_wave_sound)
	process_physics_priority = 1          # the deep-water gallop lock runs after the player moves


func _process(delta):
	var dt := minf(delta, 0.05)
	_t += dt
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var cam := _camera_center(player)

	var screen := get_viewport().get_visible_rect().size
	if screen != _sky_size:
		_sky_size = screen
		_sky.queue_redraw()
	_cam = cam
	# speed (share of the camera's movement) and where the layer's base sits on screen
	_place(_mountains, _mount_f, cam, 0.0, 150.0)
	_place(_clouds, 0.08, cam, _t * 4.0, 60.0)
	_place(_far, 0.14, cam, 0.0, 160.0)
	for s in _shafts:
		_place(s, 0.2, cam, 0.0, 175.0)
	_shafts[0].visible = int(_t / 0.35) % 2 == 0
	_shafts[1].visible = not _shafts[0].visible
	_place(_trees, 0.25, cam, 0.0, 174.0)
	_place(_mid, 0.36, cam, 0.0, 190.0)
	_place(_near, 0.55, cam, 0.0, 205.0)
	if _sky_fx:
		_horizon = 150.0 + 0.14 * (C0 - cam.y)     # the sea layer's horizon (its top), on screen
		_sky_fx.queue_redraw()
	if _fx_mount:
		_place(_fx_mount, _mount_f, cam, 0.0, 150.0)
		_fx_mount.queue_redraw()
	if _fx_far:
		_fx_far.global_position = Vector2(cam.x - screen.x / 2.0, _far.global_position.y).round()
		_fx_far.queue_redraw()

	if player:
		_watch_player(player, dt)
	_watch_hits()
	_gusts = _gusts.filter(func(g): return (_t - g[1]) * GUST_SPEED < 360.0)

	_update_grass(cam, player, dt)
	_update_water(cam, dt)
	_update_waves(dt)
	_update_refills(dt, player)
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


# no galloping in deep water (Morgan's call): holding a direction tops out at the sprint, and a double
# tap's instant gallop becomes a sprint. Like the tutorial's locks, it holds down player.gd's own
# variables after the player moves each frame, so player.gd is untouched. Draining the basin lifts it.
func _physics_process(_delta):
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return
	var w := _water_under(player.global_position)
	if w.is_empty() or w["shallow"]:
		return
	var s: GDScript = player.get_script()
	var top: int = s.SPEEDS.size() - 1
	player.hold_time = minf(player.hold_time, s.TIME_TO_LEVEL_4 - 0.2)
	if player.speed_level >= top:
		player.speed_level = top - 1
		var sprint: float = s.SPEEDS[top - 1]
		player.velocity.x = clampf(player.velocity.x, -sprint, sprint)
		if player.state == s.State.GALLOP:
			player._set_state(s.State.SPRINT)


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
			if not w.is_empty() and st == "CHARGED_SMASH" and not w["shallow"] and not w["draining"]:
				_drain(pos, w)
			elif not w.is_empty():
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


# the flash's path through the grass, from code/flash_finish.gd (its dash moves the player over several
# frames, so the one-frame jump check in _watch_player doesn't see it)
func cut_path(x0: float, x1: float, y: float, dir: float):
	_slice(x0, x1, y, dir)


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
	if theme == "volcano":
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var spans := []
	for r in rects:
		var rect: Rect2 = r[0]
		var body_name: String = r[1]
		if body_name.begins_with("Shallow"):      # a floor named "Shallow...": flooded end to end (level 1's surf run)
			var sx0 := rect.position.x + 2.0
			var sx1 := rect.end.x - 2.0
			spans.append([sx0, sx1, rect.position.y])
			_water.append(_water_region(sx0, int(sx1 - sx0), rect.position.y - SHALLOW_DEPTH, rect.position.y, true))
			continue
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
	return {"x0": x0, "n": n, "level": level, "bed": bed, "h": h, "v": h.duplicate(), "visible": false, "shallow": shallow,
		"lava": false, "bub": [], "draining": false, "dry0": 0.0, "dry1": 0.0}   # [dry0, dry1): drained, no water


# is there water at x, or has a charged W drained it?
func _wet(w: Dictionary, x: float) -> bool:
	return x < w["dry0"] or x >= w["dry1"]


func _build_grass(rects: Array, shallows: Array):
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blades := []
	var step := Vector2(0.6, 1.4)     # gap from one blade to the next
	var flower := 0.015
	var front_h := Vector2i(5, 9)
	var back_h := Vector2i(8, 17)
	match theme:
		"sunset":                     # dune grass: a little sparser, hardly any flowers
			step = Vector2(0.9, 2.2)
			flower = 0.004
			back_h = Vector2i(7, 15)
		"volcano":                    # a few short ash tufts
			step = Vector2(3.0, 9.0)
			flower = 0.0
			front_h = Vector2i(3, 5)
			back_h = Vector2i(4, 9)
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
				var kind := 2 if rng.randf() < flower else (1 if rng.randf() < 0.25 else 0)
				var h := rng.randi_range(front_h.x, front_h.y) if front else rng.randi_range(back_h.x, back_h.y)
				blades.append([floorf(x), y, h, rng.randf() * TAU, (1 if front else 0) | (kind << 1), rng.randi() % c_flowers.size()])
			x += rng.randf_range(step.x, step.y)
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
		var base := c_grass_light if kind == 1 else c_grass
		var shade := c_grass if kind == 1 else c_grass_shade
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
		elif _tips == 2 or (_tips == 1 and kind == 1):     # sunset's warm tips, the volcano's embers
			n.draw_rect(Rect2(x + off, gy - h, 1, 1), c_grass_tip)


# ---------- water ----------
func _build_water(rects: Array):
	for r in rects:
		var body_name: String = r[1]
		var lava: bool = LAVA_BODIES.any(func(n): return body_name.begins_with(n)) \
			or (theme == "volcano" and WATER_BODIES.any(func(n): return body_name.begins_with(n)))
		if not lava and not WATER_BODIES.any(func(n): return body_name.begins_with(n)):
			continue
		var rect: Rect2 = r[0]
		var y := rect.position.y
		var start := -1
		for x in range(int(rect.position.x), int(rect.end.x) + 1):
			var open := x < int(rect.end.x) and not _covered(rects, Vector2(x + 0.5, y - 1.0), rect)
			if open and start < 0:
				start = x
			elif not open and start >= 0:
				var region := _water_region(float(start), x - start, y - WATER_DEPTH, y, false)
				region["lava"] = lava
				_water.append(region)
				start = -1


func _update_water(cam: Vector2, dt: float):
	for w in _water:
		var x0: float = w["x0"]
		var n: int = w["n"]
		w["visible"] = x0 + n > cam.x - 280.0 and x0 < cam.x + 280.0
		if not w["visible"]:
			continue
		if w["lava"]:
			_update_lava(w, dt)
			continue
		var h: Array = w["h"]
		var v: Array = w["v"]
		# only the stretch around the screen ripples (a long body of water would cost too much otherwise)
		var c0 := maxi(0, int(cam.x - 400.0 - x0))
		var c1 := mini(n, int(cam.x + 400.0 - x0))
		for c in range(c0, c1):
			var left: float = h[c - 1] if c > 0 else 0.0
			var right: float = h[c + 1] if c < n - 1 else 0.0
			v[c] += ((left + right - 2.0 * h[c]) * WAVE - h[c] * TENSION - v[c] * DAMP) * dt
		for c in range(c0, c1):
			h[c] += v[c] * dt
	for d in _drops:
		d[1].y += 520.0 * dt
		d[0] += d[1] * dt
		d[3] -= dt
	_drops = _drops.filter(func(d): return d[3] > 0.0)


func _water_contact(prev: Vector2, pos: Vector2, vel: Vector2, dt: float):
	for w in _water:
		if w["lava"]:
			continue
		var x0: float = w["x0"]
		var n: int = w["n"]
		if pos.x < x0 or pos.x >= x0 + n or not _wet(w, pos.x):
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


# other effects (dust) ask this so they can stay out of the water (lava isn't water)
func in_water(pos: Vector2) -> bool:
	return not _water_under(pos).is_empty()


# the deep water at x (not shallow, not lava), drained or not, or {}. The shark (melon_shark.gd) and the
# waterfall (waterfall.gd) watch their basin through this: "level", "bed", "x0", "n", "draining".
func water_region(x: float) -> Dictionary:
	for w in _water:
		if not w["lava"] and not w["shallow"] and x >= w["x0"] and x < w["x0"] + w["n"]:
			return w
	return {}


# is there water at x in this region (it isn't drained there)?
func wet_at(w: Dictionary, x: float) -> bool:
	return _wet(w, x)


# a splash at x on this region's surface (count drops, thrown up to `speed`), rippling the water
func splash(w: Dictionary, x: float, count: int, speed: float):
	_splash(x, w["level"], count, speed)
	var v: Array = w["v"]
	var col := int(x - w["x0"])
	for c in range(maxi(col - 8, 0), mini(col + 9, int(w["n"]))):
		v[c] += speed * 0.8


# hazards ask this: is this point at or below a lava surface, over that lava?
func lava_at(pos: Vector2) -> bool:
	for w in _water:
		if not w["lava"]:
			continue
		var x0: float = w["x0"]
		if pos.x >= x0 and pos.x < x0 + w["n"] and pos.y >= w["level"] - 1.0:
			return true
	return false


# the mine (mine_cave.gd) calls this as you go underground and come back up: no leaves or pollen drift
# about in a tunnel
func set_indoors(on: bool):
	_leaves_back.visible = not on
	_leaves_front.visible = not on


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
	_wave_sound.play(WAVE_SOUND_SKIP)
	var v: Array = w["v"]
	var col := int(pos.x - w["x0"])
	for c in range(maxi(col - 10, 0), mini(col + 11, int(w["n"]))):
		v[c] += 260.0


# a charged W in deep water: a wall of water rolls out each way to the basin's ends, leaving dry bed
# behind it, and crashes out over the banks. The basin stays empty, so you can gallop through it.
# It hits enemies like any W wave.
func _drain(pos: Vector2, w: Dictionary):
	var x0: float = w["x0"]
	var x1: float = x0 + w["n"]
	var depth: float = w["bed"] - w["level"]
	w["draining"] = true
	w["dry0"] = pos.x
	w["dry1"] = pos.x
	for dir in [-1.0, 1.0]:
		var reach: float = pos.x - x0 if dir < 0.0 else x1 - pos.x
		_waves.append({"x": pos.x, "y": w["bed"], "dir": dir, "t0": _t, "h": depth + DRAIN_CREST,
			"reach": maxf(reach, 1.0), "damage": W_WAVES["CHARGED_SMASH"][2], "hit": {}, "spray": 0.0,
			"speed": DRAIN_SPEED, "width": DRAIN_W, "depth": depth, "region": w, "crashed": false})
	_splash(pos.x, w["level"], 28, 260.0)
	_wave_sound.play(WAVE_SOUND_SKIP)


# a draining wall of water reaches the end of its basin: the last of the water goes and it crashes
# out over the bank
func _crash(wv: Dictionary, front: float, h: float):
	wv["crashed"] = true
	var w: Dictionary = wv["region"]
	var dir: float = wv["dir"]
	if dir < 0.0:
		w["dry0"] = w["x0"]
	else:
		w["dry1"] = w["x0"] + w["n"]
	var top: float = wv["y"] - h
	for i in 36:
		_drops.append([Vector2(front + randf_range(-6.0, 6.0), top + randf_range(0.0, h * 0.6)),
			Vector2(dir * randf_range(30.0, 220.0), -randf_range(140.0, 400.0)),
			c_foam if i % 3 == 0 else c_water_light, randf_range(0.6, 1.1), 2 if i % 4 == 0 else 1])
	_gust(Vector2(front, wv["y"]), 4.0)


# ---------- refilling a drained basin ----------
# a surge rolls back in from one end of a drained basin (waterfall.gd calls this once it's empty)
func refill(w: Dictionary, from_left: bool, speed: float):
	if not w.get("draining", false):
		return
	for r in _refills:
		if r["region"] == w:
			return
	var x: float = w["x0"] if from_left else w["x0"] + w["n"]
	_refills.append({"region": w, "x": x, "dir": 1.0 if from_left else -1.0, "speed": speed, "spray": 0.0, "shoved": false})


# the surge moves on: the water's back behind it. It shoves you along once if it reaches you on the bed.
# Once it reaches the far end, the basin is full again (and can be drained again).
func _update_refills(dt: float, player: CharacterBody2D):
	for r in _refills:
		var w: Dictionary = r["region"]
		var dir: float = r["dir"]
		r["x"] += dir * r["speed"] * dt
		var front: float = r["x"]
		if dir > 0.0:
			w["dry0"] = maxf(w["dry0"], front)
		else:
			w["dry1"] = minf(w["dry1"], front)
		var v: Array = w["v"]                       # the water just arrived still sloshing
		var col := int(front - w["x0"])
		for c in range(maxi(col - 6, 0), mini(col + 7, int(w["n"]))):
			v[c] += 600.0 * dt
		r["spray"] -= dt
		if r["spray"] <= 0.0:
			r["spray"] = 0.03
			_drops.append([Vector2(front + randf_range(-3.0, 3.0), w["level"] - REFILL_CREST),
				Vector2(dir * randf_range(30.0, 120.0), -randf_range(60.0, 180.0)), c_foam, randf_range(0.3, 0.6), 1])
		if player and not r["shoved"] and player.global_position.y >= w["level"] - 1.0 \
				and absf(player.global_position.x - front) < 10.0:
			r["shoved"] = true
			player.velocity.x = dir * maxf(REFILL_SHOVE, player.velocity.x * dir)
			_splash(player.global_position.x, w["level"], 18, 220.0)
		if w["dry0"] >= w["dry1"]:                  # full again
			w["draining"] = false
			w["dry0"] = 0.0
			w["dry1"] = 0.0
			r["done"] = true
			_gust(Vector2(front, w["level"]), 3.0)
	_refills = _refills.filter(func(r): return not r.get("done", false))


# the surge: a steep front of foaming water, sloping back down to the water level behind it
func _draw_refills(n: Node2D):
	for r in _refills:
		var w: Dictionary = r["region"]
		var dir: float = r["dir"]
		var front := roundf(r["x"])
		var level: float = w["level"]
		var bed: float = w["bed"]
		for i in int(REFILL_W):
			var u := i / REFILL_W
			var ch := roundf(REFILL_CREST * minf(u / 0.2, 1.0) * (1.0 - maxf(0.0, u - 0.2) / 0.8))
			var cx := front - dir * i
			if cx < w["x0"] or cx >= w["x0"] + w["n"]:
				continue
			var top := level - ch
			if u < 0.2:                             # the front face reaches right down to the bed
				n.draw_rect(Rect2(cx, top, 1, bed - top), c_water)
			elif ch >= 1.0:
				n.draw_rect(Rect2(cx, top, 1, ch + 1.0), c_water)
			n.draw_rect(Rect2(cx, top, 1, 1), c_foam if u < 0.5 else c_water_light)
			if u > 0.05 and u < 0.4:
				n.draw_rect(Rect2(cx, top + 1.0, 1, 1), c_foam)
		var peak := front - dir * roundf(REFILL_W * 0.2)
		for k in 3:                                 # the lip curling over
			n.draw_rect(Rect2(peak + dir * (k + 1), level - REFILL_CREST + k * 2, 1, 2), c_foam)


# how far the wave can roll before a wall stops it
func _wave_reach(player: CharacterBody2D, x: float, y: float, dir: float, reach: float) -> float:
	var from := Vector2(x, y - 6.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * reach, 0), 1, [player.get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return reach if hit.is_empty() else absf(hit["position"].x - x) - 2.0


# where the crest is now and how tall: rises fast, shrinks as it travels (a draining wall grows as it
# gathers the water instead), collapses at the end
func _wave_now(wv: Dictionary) -> Vector2:
	var age: float = _t - wv["t0"]
	var reach: float = wv["reach"]
	var speed: float = wv.get("speed", WAVE_SPEED)
	var travel := minf(age * speed, reach)
	var rise := clampf(age / 0.08, 0.0, 1.0)
	var collapse := 1.0 - clampf((age - reach / speed) / 0.25, 0.0, 1.0)
	var size := 1.0 + 0.3 * minf(travel / 400.0, 1.0) if wv.has("region") else 1.0 - 0.5 * travel / maxf(reach, 1.0)
	var h: float = wv["h"] * rise * collapse * size
	return Vector2(wv["x"] + wv["dir"] * travel, h)


func _update_waves(dt: float):
	for wv in _waves:
		var now := _wave_now(wv)
		var front := now.x
		var h := now.y
		var dir: float = wv["dir"]
		var y: float = wv["y"]
		var rolling: bool = (_t - wv["t0"]) * wv.get("speed", WAVE_SPEED) < wv["reach"]
		if wv.has("region"):
			# the water's gone from the crest's peak back
			var w: Dictionary = wv["region"]
			var edge: float = front - dir * DRAIN_W * 0.3
			if dir < 0.0:
				w["dry0"] = minf(w["dry0"], edge)
			else:
				w["dry1"] = maxf(w["dry1"], edge)
			if not rolling and not wv["crashed"]:
				_crash(wv, front, h)
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
	_waves = _waves.filter(func(wv): return _t - wv["t0"] < wv["reach"] / wv.get("speed", WAVE_SPEED) + 0.25)


func _draw_waves(n: Node2D):
	for wv in _waves:
		var now := _wave_now(wv)
		var front := now.x
		var h := roundf(now.y)
		if h < 1.0:
			continue
		var dir: float = wv["dir"]
		var y: float = wv["y"]
		var width: float = wv.get("width", WAVE_W)
		var draining: bool = wv.has("region")
		# the wash left behind, back to where it started (a draining wall leaves dry bed instead)
		var back := front - dir * width
		var wash := maxf(1.0, roundf(h * 0.2))
		var x0 := roundf(minf(wv["x"], back))
		var x1 := roundf(maxf(wv["x"], back))
		if x1 > x0 and not draining:
			n.draw_rect(Rect2(x0, y - wash, x1 - x0, wash), c_water)
			n.draw_rect(Rect2(x0, y - wash, x1 - x0, 1), c_water_light)
		# the crest: a steep front face, a foamy top, a longer slope behind (down to the bed when draining)
		var tail := 1.0 if draining else 0.7
		var depth: float = wv.get("depth", 0.0)
		for i in int(width):
			var u := i / width
			var ch := roundf(h * minf(u / 0.3, 1.0) * (1.0 - tail * maxf(0.0, u - 0.3) / 0.7))
			if ch < 1.0 or (draining and u < 0.3 and ch <= depth):     # under the water still ahead of it
				continue
			var cx := roundf(front - dir * i)
			n.draw_rect(Rect2(cx, y - ch, 1, ch), c_water)
			if draining and ch > 10.0:
				n.draw_rect(Rect2(cx, y - 6.0, 1, 6), c_water_shade)
			n.draw_rect(Rect2(cx, y - ch, 1, 1), c_water_light)
			if ch >= 4.0 and u > 0.12 and u < 0.55:
				n.draw_rect(Rect2(cx, y - ch, 1, 2), c_foam)
		# the lip curling over at the peak
		if h >= 6.0:
			var peak := roundf(front - dir * width * 0.3)
			for k in 3:
				n.draw_rect(Rect2(peak + dir * (k + 1), y - h + k * 2, 1, 2), c_foam)


# the water the player is standing in, if any
func _water_under(pos: Vector2) -> Dictionary:
	for w in _water:
		if w["lava"]:
			continue
		var x0: float = w["x0"]
		if pos.x >= x0 and pos.x < x0 + w["n"] and pos.y >= w["level"] - 1.0 and _wet(w, pos.x):
			return w
	return {}


func _draw_water():
	var n := _water_node
	for w in _water:
		if not w["visible"]:
			continue
		if w["lava"]:
			_draw_lava(n, w)
			continue
		var x0: float = w["x0"]
		var level: float = w["level"]
		var bed: float = w["bed"]
		var h: Array = w["h"]
		var v: Array = w["v"]
		var shallow: bool = w["shallow"]
		var c0 := maxi(0, int(_cam.x - 260.0 - x0))       # just the part on screen
		var c1 := mini(int(w["n"]), int(_cam.x + 260.0 - x0))
		for c in range(c0, c1):
			var x := x0 + c
			if not _wet(w, x):                              # drained by a charged W
				continue
			var sy := roundf(level + h[c] + sin(_t * 2.2 + x * 0.35) * 0.6)
			if shallow:
				sy = clampf(sy, level - 2.0, bed - 1.0)    # shallow water only ripples a little
			n.draw_rect(Rect2(x, sy, 1, bed - sy), c_water)
			if bed - sy > 10.0:
				n.draw_rect(Rect2(x, bed - 6.0, 1, 6), c_water_shade)
			var foam: bool = absf(v[c]) > 25.0 or posmod(int(x) * 7 + int(_t * 5.0), 41) == 0
			n.draw_rect(Rect2(x, sy, 1, 1), c_foam if foam else c_water_light)
	_draw_waves(n)
	_draw_refills(n)
	for d in _drops:
		var p: Vector2 = d[0]
		var s: float = d[4]
		n.draw_rect(Rect2(p.round(), Vector2(s, s)), d[2])


# ---------- lava ----------
# bubbles swell up and pop, throwing a few drops
func _update_lava(w: Dictionary, dt: float):
	var n: int = w["n"]
	var bub: Array = w["bub"]
	if bub.size() < 6 and randf() < dt * n / 160.0:
		bub.append([randi() % n, 0.0, randf_range(0.8, 1.6)])     # [column, age, life]
	for b in bub:
		b[1] += dt
		if b[1] >= b[2]:
			var x: float = w["x0"] + b[0]
			for i in 3:
				_drops.append([Vector2(x, w["level"] - 2.0), Vector2(randf_range(-30.0, 30.0), -randf_range(50.0, 110.0)),
					c_lava[i % 2], randf_range(0.4, 0.7), 1])
	w["bub"] = bub.filter(func(b): return b[1] < b[2])


# a slow, heavy surface with drifting dark crust and hot glints, darker deeper down, and a dithered glow
# over it that pulses
func _draw_lava(n: Node2D, w: Dictionary):
	var x0: float = w["x0"]
	var level: float = w["level"]
	var bed: float = w["bed"]
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var c0 := maxi(0, int(_cam.x - 260.0 - x0))       # just the part on screen
	var c1 := mini(int(w["n"]), int(_cam.x + 260.0 - x0))
	for c in range(c0, c1):
		var x := x0 + c
		var xi := int(x)
		var sy := roundf(level + sin(_t * 1.3 + x * 0.12) * 0.8 + sin(_t * 0.6 + x * 0.045) * 0.7)
		n.draw_rect(Rect2(x, sy, 1, bed - sy), c_lava[2])
		if bed - sy > 12.0:
			n.draw_rect(Rect2(x, bed - 9.0, 1, 6), c_lava[3])
			n.draw_rect(Rect2(x, bed - 3.0, 1, 3), c_lava[4])
		var crust := posmod(int(x * 0.5 + _t * 3.0), 23) < 3
		var glint := posmod(int(x * 3.0 + _t * 9.0), 41) < 2
		n.draw_rect(Rect2(x, sy, 1, 1), c_lava[3] if crust else (c_lava[0] if not glint else c_crater[0]))
		n.draw_rect(Rect2(x, sy + 1, 1, 1), c_lava[2] if crust else c_lava[1])
		if posmod(xi + int(_t * 4.0), 2) == 0:
			n.draw_rect(Rect2(x, sy - 1, 1, 1), c_lava_glow)
		if pulse > 0.35 and posmod(xi, 3) == posmod(int(_t * 2.0), 3):
			n.draw_rect(Rect2(x, sy - 2, 1, 1), c_lava_glow)
		if pulse > 0.75 and posmod(xi + 1, 5) == 0:
			n.draw_rect(Rect2(x, sy - 3, 1, 1), c_lava_glow)
	for b in w["bub"]:
		var bx: float = x0 + b[0]
		if bx < _cam.x - 260.0 or bx > _cam.x + 260.0:
			continue
		var r := int(1.0 + float(b[1]) / float(b[2]) * 3.0)
		for dy in r:
			var hw := r - 1 - dy
			n.draw_rect(Rect2(bx - hw, level - 1.0 - dy, 2 * hw + 1, 1), c_lava[0] if dy == r - 1 else c_lava[1])


# ---------- leaves and pollen ----------
func _update_particles(cam: Vector2, dt: float):
	var view := Rect2(cam - Vector2(300, 190), Vector2(600, 380))
	var first := _leaves.is_empty()
	var first_pollen := _pollen.is_empty()
	var volcano := theme == "volcano"     # leaves are ash flakes, pollen are embers rising from below
	while _leaves.size() < _leaf_count:
		var y := randf_range(view.position.y, view.end.y) if first else view.position.y + 2.0
		_leaves.append([Vector2(randf_range(view.position.x, view.end.x), y), Vector2.ZERO,
			randf() * TAU, randf() < 0.35, c_leaves[randi() % c_leaves.size()]])
	while _pollen.size() < _pollen_count:
		var y := randf_range(view.position.y, view.end.y)
		if volcano and not first_pollen:
			y = view.end.y - 2.0
		_pollen.append([Vector2(randf_range(view.position.x, view.end.x), y),
			Vector2.ZERO, randf() * TAU, c_pollen[randi() % c_pollen.size()]])
	for p in _leaves:
		var ph: float = p[2]
		var drift := Vector2(WIND + sin(_t * 1.9 + ph) * 16.0, 13.0 + cos(_t * 2.3 + ph) * 9.0)
		if volcano:
			drift = Vector2(WIND * 0.6 + sin(_t * 1.1 + ph) * 5.0, 9.0 + cos(_t * 1.6 + ph) * 3.0)
		p[0] += (drift + p[1]) * dt
		p[1] *= exp(-2.0 * dt)
	for p in _pollen:
		var ph: float = p[2]
		var drift := Vector2(WIND * 0.5 + sin(_t * 1.3 + ph) * 6.0, -5.0 + cos(_t * 1.7 + ph) * 4.0)
		if volcano:
			drift = Vector2(WIND * 0.3 + sin(_t * 2.3 + ph) * 9.0, -24.0 + cos(_t * 3.1 + ph) * 8.0)
		p[0] += (drift + p[1]) * dt
		p[1] *= exp(-2.0 * dt)
	_leaves = _leaves.filter(func(p): return view.has_point(p[0]))
	_pollen = _pollen.filter(func(p): return view.has_point(p[0]))


func _draw_leaves(front: bool):
	var n := _leaves_front if front else _leaves_back
	var volcano := theme == "volcano"
	for p in _leaves:
		if p[3] != front:
			continue
		var pos: Vector2 = p[0]
		var ph: float = p[2]
		if volcano:           # an ash flake turning over: one pixel, then two
			var w := 2 if posmod(int(_t * 3.0 + ph * 5.0), 3) == 0 else 1
			n.draw_rect(Rect2(pos.round(), Vector2(w, 1)), p[4])
			continue
		for px in LEAF_FRAMES[posmod(int(_t * 5.0 + ph * 4.0), 4)]:
			n.draw_rect(Rect2(pos.round() + px, Vector2(1, 1)), p[4])
	if not front:
		for p in _pollen:
			var pos: Vector2 = p[0]
			if volcano:       # embers flicker between hot and dim, and wink out now and then
				var f := sin(_t * 12.0 + float(p[2]) * 7.0)
				if f < -0.8:
					continue
				n.draw_rect(Rect2(pos.round(), Vector2(1, 1)), c_pollen[0] if f > 0.3 else p[3])
				continue
			n.draw_rect(Rect2(pos.round(), Vector2(1, 1)), p[3])


# ---------- the sky ----------
func _draw_sky(n: Node2D):
	var size := get_viewport().get_visible_rect().size
	var bands: Array = _sky_bands
	for b in bands.size():
		var y0 := roundf(bands[b] * size.y)
		var y1: float = size.y if b == bands.size() - 1 else roundf(bands[b + 1] * size.y)
		n.draw_rect(Rect2(0, y0, size.x, y1 - y0), c_sky[b])
		if b > 0:     # two dithered rows blend each band into the one above
			for x in range(0, int(size.x), 2):
				n.draw_rect(Rect2(x, y0, 1, 1), c_sky[b - 1])
				n.draw_rect(Rect2(x + 1, y0 + 1, 1, 1), c_sky[b - 1])
	if theme != "day":
		return                # the sunset's sun sinks with the horizon (_draw_sky_fx); the night has none
	var sun := Vector2(roundf(size.x * 0.78), 46)
	_disk_now(n, sun, 13, c_sun)
	for a in 36:
		var p := (sun + Vector2.from_angle(a * TAU / 36.0) * 17.0).round()
		n.draw_rect(Rect2(p, Vector2(1, 1)), c_sun)


# stars twinkling, and at sunset the big low sun: a stepped glow, then the disc, banded across its lower
# half. It sits on the horizon, and the sea layer (in front of the sky) hides its bottom: it's setting.
func _draw_sky_fx(n: Node2D):
	var size := get_viewport().get_visible_rect().size
	for st in _stars:
		var tw := sin(_t * float(st[3]) + float(st[2]))
		if tw < -0.3:
			continue
		var p := Vector2(roundf(float(st[0]) * size.x), roundf(float(st[1]) * size.y))
		n.draw_rect(Rect2(p, Vector2(1, 1)), c_star[0] if tw > 0.5 else c_star[1])
		if st[4] and tw > 0.8:         # the bright ones flare into a little cross
			n.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), c_star[1])
			n.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), c_star[1])
			n.draw_rect(Rect2(p, Vector2(1, 1)), c_star[0])
	if theme != "sunset":
		return
	var sun := Vector2(roundf(size.x * 0.72), roundf(_horizon - 4.0))
	var r := 24
	_disk_now(n, sun, r + 14, c_sun_glow[0])
	_disk_now(n, sun, r + 8, c_sun_glow[1])
	_disk_now(n, sun, r + 3, c_sun_glow[2])
	for dy in range(-r, r + 1):
		if dy > 3 and (posmod(dy - 4, 4) == 0 or (dy > 12 and posmod(dy, 2) == 0)):
			continue          # the bands: gaps that get closer together towards the bottom
		var w := int(sqrt(float(r * r - dy * dy)))
		n.draw_rect(Rect2(sun.x - w, sun.y + dy, 2 * w + 1, 1), c_sun)


# sunset: the sun's glitter path on the sea, straight under the sun, widening towards you. Short
# strips that jump about, so it shimmers. (This node sits on the sea layer; its x is the screen's.)
func _draw_glitter():
	var n := _fx_far
	var size := get_viewport().get_visible_rect().size
	var cx := roundf(size.x * 0.72)
	for row in range(0, 44, 2):
		var y := -9.0 + row
		var hw := 3.0 + row * 0.7
		for k in 2 + row / 8:
			var h := posmod(row * 37 + k * 53 + int(_t * 7.0 + k), 97) / 97.0
			var x := roundf(cx - hw + h * 2.0 * hw)
			var w := 2 + posmod(row + k + int(_t * 3.0), 4)
			n.draw_rect(Rect2(x, y, w, 1), c_sun if posmod(row + k + int(_t * 5.0), 3) == 0 else c_sun_glow[2])


# volcano: the eruption, over the mountain layer (it moves with it): a smoke plume lit from below,
# the glowing crater, lava running down the sides, and lava bombs thrown up now and then.
# Only the copy of the tile that's near the screen gets drawn.
func _draw_mount_fx():
	var n := _fx_mount
	var size := get_viewport().get_visible_rect().size
	var left := _cam.x - size.x / 2.0
	for j in [-1, 0, 1]:
		var c := _peak + Vector2(j * TILE, 0)
		var sx := n.global_position.x + c.x - left
		if sx > -220.0 and sx < size.x + 220.0:
			_draw_eruption(n, c)


func _draw_eruption(n: Node2D, c: Vector2):
	# the plume: puffs rise from the crater, drift with the wind and grow; the low ones are lit red
	var ages := []
	for k in PUFFS:
		ages.append([fmod(_t * 0.05 + float(k) / PUFFS, 1.0), k])
	ages.sort_custom(func(a, b): return a[0] > b[0])     # the highest (oldest) behind
	for a in ages:
		var age: float = a[0]
		var k: int = a[1]
		var p := Vector2(c.x + age * 70.0 + sin(age * 6.0 + k * 1.7) * 8.0 * age, c.y - 6.0 - age * 230.0).round()
		var r := int(5.0 + age * 20.0)
		var col: Color = c_plume[0] if age < 0.15 else (c_plume[1] if age < 0.35 else (c_plume[2] if age < 0.6 else c_plume[3 + k % 2]))
		_disk_now(n, p, r, col)
		if age < 0.5:          # the fire below lights its underside
			var w := int(sqrt(float(r * r - (r - 1) * (r - 1))))
			n.draw_rect(Rect2(p.x - w, p.y + r - 1, 2 * w + 1, 1), c_plume_lit[k % 2])
			w = int(sqrt(float(r * r - (r - 2) * (r - 2))))
			n.draw_rect(Rect2(p.x - w, p.y + r - 2, 2 * w + 1, 1), c_plume_lit[1])
	# lava running down the sides: bright pulses travel down each streak
	for i in _streaks.size():
		var pts: Array = _streaks[i]
		for q in pts.size():
			var p: Vector2 = pts[q] + Vector2(c.x - _peak.x, 0)
			if posmod(q * 5 + i * 3, 23) == 0:
				continue           # a cooled gap
			var k := posmod(q - int(_t * 14.0) + i * 4, 11)
			n.draw_rect(Rect2(p, Vector2(1, 1)), c_crater[1] if k < 2 else (c_crater[2] if k < 5 else c_crater[3]))
	# the crater: a pool of lava in the notch, flickering, with a glow over it
	var flick := posmod(int(_t * 10.0), 4)
	n.draw_rect(Rect2(c.x - 6, c.y, 13, 2), c_crater[flick % 2])
	n.draw_rect(Rect2(c.x - 4, c.y - 1, 9, 1), c_crater[0 if flick < 2 else 1])
	for g in 14:
		var gp := Vector2(c.x - 8 + posmod(g * 7 + int(_t * 6.0), 17), c.y - 2 - posmod(g * 5 + int(_t * 4.0), 7))
		n.draw_rect(Rect2(gp, Vector2(1, 1)), c_lava_glow if g % 3 else c_crater[3])
	# lava bombs arcing out of the crater
	for k in 6:
		var ph := fmod(_t * 0.45 + k * 0.29, 1.0)
		if ph > 0.4:
			continue
		var tt := ph / 0.4 * 1.4
		var vx := (k % 3 - 1) * 14.0 + 6.0 * sin(k * 2.3)
		var vy := 70.0 + 15.0 * cos(k * 1.7)
		var p := (c + Vector2(vx * tt, -(vy * tt - 0.5 * 110.0 * tt * tt))).round()
		n.draw_rect(Rect2(p, Vector2(2, 2)), c_crater[0])
		n.draw_rect(Rect2(p - Vector2(signf(vx), -1), Vector2(1, 1)), c_crater[3])


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


# the volcano and the hills around it
func _gen_mountains() -> Array:
	if theme == "sunset":
		return _gen_islands()
	if theme == "volcano":
		return _gen_volcano()
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var peak := rng.randf_range(250.0, 700.0)
	for x in int(TILE):
		var fx := float(x)
		var hills := 34.0 + 10.0 * sin(TAU * 2.0 * fx / TILE + 1.3) + 6.0 * sin(TAU * 5.0 * fx / TILE + 0.4)
		var volcano := minf(maxf(0.0, 96.0 - absf(fx - peak) * 0.6), 82.0)     # flat-topped cone
		var top := -roundf(maxf(hills, volcano))
		out.append([Rect2(x, top, 1, 420 - top), c_mountain_shade if fx > peak and volcano > hills else c_mountain])
	return out


# the far jungle canopy in front of the mountains
func _gen_far() -> Array:
	if theme == "sunset":
		return _gen_sea()
	var out := []
	for x in int(TILE):
		var fx := float(x)
		if theme == "volcano":    # jagged dark ridges, rimmed red by the eruption
			var ridge := -roundf(24.0 + 8.0 * sin(TAU * 3.0 * fx / TILE + 2.2) + 9.0 * absf(sin(TAU * 11.0 * fx / TILE + 0.5)) \
				+ 5.0 * absf(sin(TAU * 37.0 * fx / TILE)))
			out.append([Rect2(x, ridge, 1, 1), c_rim])
			out.append([Rect2(x, ridge + 1, 1, 10), c_far])
			out.append([Rect2(x, ridge + 11, 1, 420), c_far_shade])
			continue
		var canopy := -roundf(18.0 + 6.0 * sin(TAU * 3.0 * fx / TILE + 2.2) + 5.0 * absf(sin(TAU * 24.0 * fx / TILE)))
		out.append([Rect2(x, canopy, 1, 12), c_far])
		out.append([Rect2(x, canopy + 12, 1, 420), c_far_shade])
	return out


# a row of distant broadleaf trees (round crowns of 3 blobs on thin trunks) over a band of undergrowth
func _gen_trees() -> Array:
	if theme == "sunset":
		return _gen_dune_palms()
	if theme == "volcano":
		return _gen_dead_trees()
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 9:
		var cx := rng.randf_range(0.0, TILE)
		var h := rng.randf_range(34.0, 58.0)
		var r := rng.randi_range(11, 17)
		out.append([Rect2(roundf(cx) - 1, -h, 2, h), c_trees_shade])
		_disk(out, cx - r * 0.7, -h + 5.0, r - 5, c_trees, c_trees_shade)
		_disk(out, cx + r * 0.8, -h + 4.0, r - 4, c_trees, c_trees_shade)
		_disk(out, cx, -h, r, c_trees, c_trees_shade)
	for x in int(TILE):
		var top := -roundf(12.0 + 4.0 * sin(TAU * 4.0 * x / TILE + 0.7) + 3.0 * absf(sin(TAU * 20.0 * x / TILE)))
		out.append([Rect2(x, top, 1, 8), c_trees])
		out.append([Rect2(x, top + 8, 1, 420), c_trees_shade])
	return out


func _gen_clouds() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	if theme == "sunset":     # long thin streaks: plum on top, pink, lit orange underneath
		for i in 7:
			var x := roundf(rng.randf_range(0.0, TILE))
			var y := roundf(rng.randf_range(-50.0, 0.0))
			var w := rng.randi_range(50, 110)
			out.append([Rect2(x + 10, y, w - 20, 1), c_cloud_top])
			out.append([Rect2(x + 3, y + 1, w - 6, 2), c_cloud])
			out.append([Rect2(x, y + 3, w, 2), c_cloud])
			out.append([Rect2(x + 4, y + 5, w - 8, 1), c_cloud_shade])
			out.append([Rect2(x + 12, y + 6, w - 24, 1), c_cloud_shade])
		return out
	for i in 6:
		var x := roundf(rng.randf_range(0.0, TILE))
		var y := roundf(rng.randf_range(-40.0, 10.0))
		var w := rng.randi_range(26, 54)
		out.append([Rect2(x + 8, y, w - 16, 2), c_cloud_top])
		out.append([Rect2(x + 2, y + 2, w - 4, 4), c_cloud])
		out.append([Rect2(x, y + 6, w, 4), c_cloud])
		out.append([Rect2(x + 2, y + 10, w - 4, 2), c_cloud_shade])
	return out


# diagonal light shafts: sparse opaque pixels. Phase 0 and 1 use opposite pixels, shown in turn.
func _gen_shafts(phase: int) -> Array:
	var out := []
	if theme == "volcano":
		return out            # no sunlight at night
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for s in (3 if theme == "sunset" else 4):     # sunset: fewer, warm god-rays
		var sx := rng.randf_range(0.0, TILE)
		for y in range(-150, 30, 2):
			for w in 10:
				var x := int(sx + (y + 150) * 0.4) + w
				if posmod(x + int(floorf(y / 2.0)), 4) == phase * 2:
					out.append([Rect2(x, y, 1, 1), c_shaft])
	return out


func _gen_mid() -> Array:
	if theme == "volcano":
		return _gen_burnt_palms()
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
	if theme == "sunset":     # (the palms' trunks are lit on their sun side: c_trunk_shade is the rim light)
		for x in int(TILE):   # a dune ridge in front of the trunks, its crest catching the light
			var top := -roundf(10.0 + 4.0 * sin(TAU * 3.0 * x / TILE + 2.0) + 3.0 * absf(sin(TAU * 9.0 * x / TILE)))
			out.append([Rect2(x, top, 1, 1), c_rim])
			out.append([Rect2(x, top + 1, 1, 10), c_mid])
			out.append([Rect2(x, top + 11, 1, 420), c_mid_shade])
		return out
	for x in int(TILE):   # jungle band in front of the trunks
		var top := -roundf(22.0 + 7.0 * sin(TAU * 3.0 * x / TILE + 2.0) + 6.0 * absf(sin(TAU * 30.0 * x / TILE)))
		out.append([Rect2(x, top, 1, 18), c_mid])
		out.append([Rect2(x, top + 18, 1, 420), c_mid_shade])
	return out


func _gen_near() -> Array:
	if theme == "volcano":
		return _gen_lava_rocks()
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


# ---------- the sunset's and the volcano's own layers ----------
# sunset: islands far out on the sea, low humps with open water between them (the sea layer covers
# their feet). Lit on the sun's side.
func _gen_islands() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var isles := []
	for i in 5:
		isles.append([rng.randf_range(0.0, TILE), rng.randf_range(40.0, 120.0), rng.randf_range(8.0, 26.0)])
	isles.append([rng.randf_range(0.0, TILE), 70.0, 44.0])      # one with a peak
	for x in int(TILE):
		var top := 0.0
		var lit := true
		for isle in isles:
			var dx := wrapf(x - float(isle[0]), -TILE / 2.0, TILE / 2.0)
			var hw: float = isle[1]
			if absf(dx) < hw:
				var hgt: float = float(isle[2]) * pow(1.0 - pow(dx / hw, 2.0), 0.7) + sin(x * 0.21 + float(isle[0])) * 1.2
				if hgt > top:
					top = hgt
					lit = dx > 0.0
		if top >= 1.0:
			var t := roundf(top)
			out.append([Rect2(x, -t, 1, 420 + t), c_mountain if lit else c_mountain_shade])
	return out


# sunset: the sea out to the horizon, gold and pink near it, deep purple-blue closer in, with streaks
# of light on the swell. The sun's glitter path is drawn every frame (_draw_glitter).
func _gen_sea() -> Array:
	var out := []
	out.append([Rect2(0, -10, TILE, 1), c_sun_glow[1]])        # the horizon catches the light
	out.append([Rect2(0, -9, TILE, 3), c_far])
	out.append([Rect2(0, -6, TILE, 5), c_sea_mid])
	out.append([Rect2(0, -1, TILE, 421), c_far_shade])
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for i in 60:
		var y := roundf(rng.randf_range(-8.0, 24.0))
		var col: Color = c_sun_glow[0] if y < -5.0 else (c_far if y < 4.0 else c_sea_mid)
		out.append([Rect2(roundf(rng.randf_range(0.0, TILE)), y, rng.randi_range(3, 10), 1), col])
	return out


# sunset: a few distant palms on a low dune, dark against the sea, their sun side lit
func _gen_dune_palms() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 6:
		var px := rng.randf_range(0.0, TILE)
		var h := rng.randf_range(28.0, 46.0)
		var lean := rng.randf_range(-10.0, 10.0)
		for y in int(h):
			var q := y / h
			var x := roundf(px + lean * q * q)
			out.append([Rect2(x, -y, 1, 1), c_trees])
			out.append([Rect2(x + 1, -y, 1, 1), c_rim_dim])
		var crown := Vector2(px + lean, -h)
		for f in 5:
			var dir := Vector2.from_angle(lerpf(-PI * 0.95, -PI * 0.05, f / 4.0))
			var length := rng.randf_range(9.0, 14.0)
			for s in int(length):
				var q := s / length
				out.append([Rect2((crown + dir * s + Vector2(0, q * q * 8.0)).round(), Vector2(1, 1)), c_trees_shade])
	for x in int(TILE):
		var top := -roundf(6.0 + 3.0 * sin(TAU * 2.0 * x / TILE + 0.7) + 2.0 * sin(TAU * 5.0 * x / TILE))
		out.append([Rect2(x, top, 1, 1), c_rim_dim])
		out.append([Rect2(x, top + 1, 1, 420), c_trees])
	return out


# volcano: a big volcano close behind, between jagged hills. This is the rock; its crater, lava and
# plume are drawn every frame (_draw_eruption). Its crater sits at a fixed spot so it stays on screen
# through a whole level (this layer barely moves). The side away from the fire is darker.
func _gen_volcano() -> Array:
	var out := []
	var peak := 200.0
	var cone_top := 116.0
	for x in int(TILE):
		var fx := float(x)
		var hills := 44.0 + 12.0 * sin(TAU * 2.0 * fx / TILE + 1.3) + 7.0 * sin(TAU * 7.0 * fx / TILE + 0.4) \
			+ 5.0 * absf(sin(TAU * 19.0 * fx / TILE))
		var d := absf(wrapf(fx - peak, -TILE / 2.0, TILE / 2.0))
		var cone := _cone(d)
		var top := roundf(maxf(hills, cone))
		var on_cone := cone > hills
		out.append([Rect2(x, -top, 1, 420 + top), c_mountain_shade if on_cone and fx > peak else c_mountain])
		out.append([Rect2(x, -top, 1, 1), c_rim if on_cone and d < 50.0 else c_rim_dim])
	_peak = Vector2(peak, -roundf(_cone(0.0)) + 1.0)
	# lava streaks: down the slope from the crater's rim, until the hills hide the cone
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for s in 4:
		var dir := -1.0 if s % 2 == 0 else 1.0
		var start := rng.randf_range(4.0, 9.0)
		var length := rng.randf_range(40.0, 90.0)
		var wob := rng.randf() * TAU
		var pts := []
		for i in int(length):
			var d := start + i
			var fx := peak + dir * d
			var hills := 44.0 + 12.0 * sin(TAU * 2.0 * fx / TILE + 1.3) + 7.0 * sin(TAU * 7.0 * fx / TILE + 0.4) \
				+ 5.0 * absf(sin(TAU * 19.0 * fx / TILE))
			if _cone(d) < hills + 2.0:
				break
			pts.append(Vector2(roundf(fx), -roundf(_cone(d)) + 1.0 + roundf(absf(sin(i * 0.2 + wob)) * 2.0)))
		_streaks.append(pts)
	return out


# the volcano's height d pixels from its middle: a cone with a notch for the crater
func _cone(d: float) -> float:
	var h := minf(maxf(0.0, 124.0 - d * 0.72), 116.0)
	if d < 8.0:
		h -= (8.0 - d) * 0.7
	return h


# volcano: a row of charred dead trees with bare broken branches, over a band of rubble
func _gen_dead_trees() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 10:
		var tx := roundf(rng.randf_range(0.0, TILE))
		var h := roundf(rng.randf_range(26.0, 52.0))
		out.append([Rect2(tx, -h, 2, h), c_trees])
		for b in rng.randi_range(2, 3):
			var by := -roundf(rng.randf_range(h * 0.45, h * 0.9))
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var length := rng.randi_range(6, 13)
			var bx := tx + (2.0 if side > 0.0 else -1.0)
			for k in length:
				out.append([Rect2(bx + side * k, by - roundf(k * 0.8), 1, 1), c_trees])
			out.append([Rect2(bx + side * length, by - roundf(length * 0.8) - 2.0, 1, 2), c_trees])   # a twig
	for x in int(TILE):
		var top := -roundf(9.0 + 3.0 * sin(TAU * 4.0 * x / TILE + 0.7) + 4.0 * absf(sin(TAU * 23.0 * x / TILE)))
		out.append([Rect2(x, top, 1, 420), c_trees_shade])
		if posmod(x * 13, 97) == 0:
			out.append([Rect2(x, top, 1, 1), c_rim])        # an ember glinting in the rubble
	return out


# volcano: burnt palms, bare trunks with a few broken fronds hanging down, over a rocky ridge
func _gen_burnt_palms() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for i in 4:
		var px := rng.randf_range(0.0, TILE)
		var h := rng.randf_range(70.0, 120.0)
		var lean := rng.randf_range(-24.0, 24.0)
		for y in int(h):
			var q := y / h
			var x := roundf(px + lean * q * q)
			out.append([Rect2(x, -y, 2, 1), c_trunk])
			if posmod(y, 7) == 0:
				out.append([Rect2(x - 1, -y, 1, 1), c_trunk_shade])     # charred notches
		var crown := Vector2(px + lean, -h)
		for f in 4:
			var dir := Vector2.from_angle(lerpf(-PI * 0.85, -PI * 0.15, f / 3.0))
			var length := rng.randf_range(8.0, 18.0)
			for s in int(length):
				var q := s / length
				out.append([Rect2((crown + dir * s + Vector2(0, q * q * 26.0)).round(), Vector2(1, 2)), c_mid])
	for x in int(TILE):
		var top := -roundf(18.0 + 6.0 * sin(TAU * 3.0 * x / TILE + 2.0) + 5.0 * absf(sin(TAU * 17.0 * x / TILE)))
		out.append([Rect2(x, top, 1, 420), c_mid_shade])
		out.append([Rect2(x, top, 1, 1), c_mid])
		if posmod(x * 31, 113) == 0:
			out.append([Rect2(x, top + 2, 1, 1), c_crack[0]])
	return out


# volcano: dark rocks close by, split with cracks glowing from inside
func _gen_lava_rocks() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	out.append([Rect2(0, 4, TILE, 420), c_near_shade])
	for i in 22:
		var cx := rng.randf_range(0.0, TILE)
		var cy := rng.randf_range(-2.0, 8.0)
		var r := rng.randi_range(8, 18)
		_disk(out, cx, cy, r, c_near, c_near_shade)
		if rng.randf() < 0.7:
			var p := Vector2(cx + rng.randf_range(-r * 0.4, r * 0.4), cy - r * 0.6)
			for k in rng.randi_range(4, 8):
				out.append([Rect2(p.round(), Vector2(1, 1)), c_crack[1] if k % 3 == 1 else c_crack[0]])
				p += Vector2(rng.randi_range(-1, 1), 1)
	return out


# ---------- themes ----------
# sets the palette and the theme's settings before anything is generated. The day keeps the colours
# declared at the top.
func _apply_theme():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	match theme:
		"sunset":
			c_sky = [Color("35275b"), Color("5b2d6b"), Color("923a6a"), Color("cf5a5e"), Color("ec8a4e"), Color("f3b65c")]
			_sky_bands = [0.0, 0.17, 0.3, 0.41, 0.49, 0.54]
			c_sun = Color("fbe6a6")
			c_sun_glow = [Color("f0a55a"), Color("f4bb68"), Color("f8d080")]
			c_star = [Color("ecdfdb"), Color("f8d8b0")]
			c_cloud_top = Color("7a4374")
			c_cloud = Color("c8607a")
			c_cloud_shade = Color("f2a462")
			c_mountain = Color("6b3d6d")              # islands
			c_mountain_shade = Color("5a3060")
			c_far = Color("b85f72")                   # the sea, pink near the horizon...
			c_sea_mid = Color("7a4876")
			c_far_shade = Color("4f3a72")             # ...deep purple-blue closer in
			c_trees = Color("3f2d55")
			c_trees_shade = Color("33244a")
			c_rim = Color("c86656")
			c_rim_dim = Color("a8586a")
			c_shaft = Color("f0b070")
			c_mid = Color("2d2142")
			c_mid_shade = Color("251b38")
			c_trunk = Color("2b1f3d")
			c_trunk_shade = Color("c86656")           # the palms' trunks: lit along their sun side
			c_near = Color("241b34")
			c_near_shade = Color("1c152b")
			c_flowers = [Color("c86656"), Color("e89a5a"), Color("f3b65c")]   # warm glints on the shrubs
			c_grass = Color("4d4632")
			c_grass_shade = Color("3a2f3a")
			c_grass_light = Color("6b5a3a")
			c_grass_tip = Color("d08a4a")
			_tips = 2
			c_leaves = [Color("3a2a40"), Color("5a3a50"), Color("8e4a5e")]
			_leaf_count = 6
			c_pollen = [Color("f3b65c"), Color("fbe6a6")]                     # golden motes
			c_water = Color("3d3f7a")
			c_water_light = Color("eb9a62")
			c_water_shade = Color("2c2d5e")
			c_foam = Color("f8d8b0")
			for i in 14:      # the first stars, high up
				_stars.append([rng.randf(), rng.randf_range(0.02, 0.2), rng.randf() * TAU, rng.randf_range(1.0, 2.5), i < 3])
		"volcano":
			c_sky = [Color("0e0a1c"), Color("160f28"), Color("22122e"), Color("3a1328"), Color("5a1a1e"), Color("7a2418")]
			_sky_bands = [0.0, 0.2, 0.33, 0.43, 0.5, 0.55]
			c_star = [Color("ecdfdb"), Color("cfb8b0")]
			c_cloud_top = Color("2a2030")             # smoke drifting by, lit red underneath
			c_cloud = Color("382a36")
			c_cloud_shade = Color("6e2820")
			c_mountain = Color("2a1d2c")
			c_mountain_shade = Color("1e1522")
			c_rim = Color("8c2a1e")
			c_rim_dim = Color("3a1f2a")
			_mount_f = 0.03
			c_far = Color("1e1526")
			c_far_shade = Color("160f1d")
			c_trees = Color("1c1420")
			c_trees_shade = Color("140e17")
			c_mid = Color("231a22")
			c_mid_shade = Color("1a1219")
			c_trunk = Color("1a1218")
			c_trunk_shade = Color("120c12")
			c_near = Color("221a22")
			c_near_shade = Color("181218")
			c_grass = Color("5e5860")                 # ash tufts...
			c_grass_shade = Color("433e46")
			c_grass_light = Color("7e7880")
			c_grass_tip = Color("e0641e")             # ...the lighter ones lit by embers
			_tips = 1
			c_leaves = [Color("8a8088"), Color("6a6370"), Color("b0a8a8")]   # ash
			_leaf_count = 24
			c_pollen = [Color("ffd86a"), Color("f2b23c"), Color("e8761e")]   # embers
			_pollen_count = 18
			for i in 70:
				_stars.append([rng.randf(), rng.randf_range(0.02, 0.5), rng.randf() * TAU, rng.randf_range(1.0, 3.0), i < 6])
