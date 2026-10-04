extends Node2D
# THE WATERFALL (level 1's river, Morgan's call): a waterfall pours off a rock cliff into the near end of the
# shark's basin. Drain the basin (a charged W in its water, living_background.gd) and the falls fill it back
# up: `refill_delay` after it's empty, a surge rolls back in from this end (living_background's refill()),
# so you've that long to deal with the stranded shark (melon_shark.gd) and get out the far side before the
# water chases you down. Anything still in the basin when the water gets back is in deep water again.
# The falls pound down on whoever goes through them (Morgan's call): a burst of spray off you, your speed
# knocked out of you (no gallop, no double jump) and down you go into the water, so you can't gallop-jump
# the basin. Not when you're heading back out (or being thrown out by the shark).
# Place it on the bank at the basin's edge (origin on the bank's top, right at the edge). The falls pour
# just past it, into the basin; the cliff stands behind the bank. No collision. PLACEHOLDER art drawn in code.

@export var refill_delay := 2.0                   # seconds after the basin's drained before the water comes back
@export var refill_speed := 260.0                 # how fast the surge rolls in (a run keeps up, a sprint gets away)

const SURGE_SOUND := preload("res://sounds/dragon-studio-waves-crashing-397977.mp3")
const SURGE_DB := -2.0
const SPLASH_SOUND := preload("res://sounds/WATER_FOOTSTEP_freesound_community-splash-6213.mp3")
const SPLASH_DB := -2.0
const FORCE_DOWN := 560.0                         # the falls drive you down this fast
const FALLS_SLOW := 120.0                         # and you can't go faster than a walk through them
const PLAYER_BOX := Rect2(-13, -38, 26, 36)       # (fruit_minion.gd's, from the feet)
const FALLS := Vector2(6, 28)                     # the falls' sides (local x)
const TOP := -440.0                               # where they pour from (well off the top of the screen)
const FALL_SPEED := 260.0                         # the streaks running down them

const WATER := Color("3894b1")
const WATER_LIGHT := Color("72b8ce")
const WATER_SHADE := Color("2c7892")
const FOAM := Color("ecdfdb")
const ROCK := Color("4e3a28")
const ROCK_LIGHT := Color("6e553b")
const ROCK_WET := Color("33251a")
const STRATA := Color("443222")
const MOSS := Color("526e36")
const MOSS_LIGHT := Color("76964a")
const CLIFF := [Vector2(-74, 2), Vector2(-68, -70), Vector2(-76, -150), Vector2(-66, -250), Vector2(-72, -330),
	Vector2(-62, -446), Vector2(8, -446), Vector2(4, -360), Vector2(9, -280), Vector2(3, -200), Vector2(7, -120),
	Vector2(3, -40), Vector2(5, 2)]

var _lb: Node = null
var _w := {}
var _empty := 0.0                                 # how long the basin's been drained
var _sent := false                                # the surge is on its way (till the basin's full again)
var _t := 0.0
var _cliff := Node2D.new()
var _falls := Node2D.new()
var _foam := Node2D.new()
var _drops: Array = []                            # spray: [pos, vel, life, colour, size]
var _in := false                                  # the player's under the falls
var _surge_sound := AudioStreamPlayer.new()
var _splash_sound := AudioStreamPlayer.new()


func _ready():
	_cliff.z_index = -50                          # behind the bank
	_cliff.draw.connect(_draw_cliff)
	add_child(_cliff)
	_falls.z_index = -1                           # behind you (you can stand in them)
	_falls.draw.connect(_draw_falls)
	add_child(_falls)
	_foam.z_as_relative = false
	_foam.z_index = 4                             # the churn where they land, over the water
	_foam.draw.connect(_draw_foam)
	add_child(_foam)
	_surge_sound.stream = SURGE_SOUND
	_surge_sound.volume_db = SURGE_DB
	add_child(_surge_sound)
	_splash_sound.stream = SPLASH_SOUND
	_splash_sound.volume_db = SPLASH_DB
	add_child(_splash_sound)
	process_physics_priority = 1                  # after the player moves: what the falls do to you sticks


func _physics_process(delta: float):
	_t += delta
	if _w.is_empty():
		_lb = get_tree().get_first_node_in_group("living_background")
		if _lb == null or not _lb.has_method("water_region"):
			return
		_w = _lb.water_region(global_position.x + (FALLS.x + FALLS.y) / 2.0)
		if _w.is_empty():
			return
	# drained right out (both ends): after a moment, the water comes back
	var x0: float = _w["x0"]
	var x1: float = x0 + _w["n"]
	if not _w["draining"]:
		_sent = false
		_empty = 0.0
	elif not _sent and _w["dry0"] <= x0 + 2.0 and _w["dry1"] >= x1 - 2.0:
		_empty += delta
		if _empty >= refill_delay:
			_sent = true
			_lb.refill(_w, global_position.x < (x0 + x1) / 2.0, refill_speed)
			_surge_sound.play()
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		_pour_on(player, delta)
	# spray off where they land
	var land := _landing_y()
	if randf() < delta * 40.0:
		_drops.append([Vector2(randf_range(FALLS.x, FALLS.y), land), Vector2(randf_range(-70.0, 70.0), -randf_range(40.0, 140.0)),
			randf_range(0.3, 0.6), FOAM, 1.0])
	for d: Array in _drops:
		d[1].y += 500.0 * delta
		d[0] += d[1] * delta
		d[2] -= delta
	_drops = _drops.filter(func(d): return d[2] > 0.0)
	_falls.queue_redraw()
	_foam.queue_redraw()


# you're going through the falls: spray bursts off you, and (unless you're heading back out) they drive you
# down into the water with your speed knocked out of you
func _pour_on(player: CharacterBody2D, delta: float):
	var p := player.global_position - global_position
	var body := Rect2(p + PLAYER_BOX.position, PLAYER_BOX.size)
	var under := body.end.x > FALLS.x and body.position.x < FALLS.y and body.position.y < _landing_y() and body.end.y > TOP
	if not under:
		if _in:                                   # coming out the other side: a last few drops
			_spray_off(p, 8, 1.0)
		_in = false
		return
	if not _in:
		_in = true
		_spray_off(p, 28, 1.6)
		_splash_sound.pitch_scale = randf_range(0.65, 0.8)
		_splash_sound.play()
	if randf() < delta * 60.0:                    # drumming on your head while you're in them
		_spray_off(p, 2, 0.8)
	var into := 1.0
	if not _w.is_empty():
		into = signf(_w["x0"] + _w["n"] / 2.0 - global_position.x)
	if player.velocity.x * into < -30.0:          # heading back out of the basin: they let you go
		return
	player.velocity.y = maxf(player.velocity.y, FORCE_DOWN)
	player.velocity.x = clampf(player.velocity.x, -FALLS_SLOW, FALLS_SLOW)
	player.speed_level = 0
	player.hold_time = 0.0
	if "air_jumps_left" in player:
		player.air_jumps_left = 0


# water bursting off the player's head and shoulders (p: their feet, local), flung out both sides
func _spray_off(p: Vector2, count: int, power: float):
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := p + Vector2(randf_range(-10.0, 10.0), -randf_range(26.0, 40.0))
		var v := Vector2(side * randf_range(40.0, 170.0), -randf_range(30.0, 160.0)) * power
		_drops.append([at, v, randf_range(0.35, 0.7), FOAM if i % 3 == 0 else WATER_LIGHT, 2.0 if i % 4 == 0 else 1.0])


# where the falls land (local y): the water's surface, or the bed once it's drained
func _landing_y() -> float:
	if _w.is_empty():
		return 16.0
	var x := global_position.x + (FALLS.x + FALLS.y) / 2.0
	var y: float = _w["level"] if _lb.wet_at(_w, x) else _w["bed"]
	return y - global_position.y


# ---------- drawing ----------
# the cliff: earthy rock with strata and moss, dark and wet down the side the water runs over
func _draw_cliff():
	var poly := PackedVector2Array(CLIFF)
	_cliff.draw_colored_polygon(poly, ROCK)
	var y := TOP
	while y < 0.0:
		var band := PackedVector2Array([Vector2(-90, y), Vector2(20, y), Vector2(20, y + 6.0), Vector2(-90, y + 6.0)])
		for part in Geometry2D.intersect_polygons(band, poly):
			_cliff.draw_colored_polygon(part, STRATA)
		y += 34.0
	for i in range(0, 5):                                     # lit down the left edge
		_cliff.draw_line(CLIFF[i] + Vector2(2, 0), CLIFF[i + 1] + Vector2(2, 0), ROCK_LIGHT, 3.0)
	for i in range(6, CLIFF.size() - 1):                      # wet and dark where the water runs
		_cliff.draw_line(CLIFF[i] + Vector2(-3, 0), CLIFF[i + 1] + Vector2(-3, 0), ROCK_WET, 6.0)
	for m in [Vector2(-60, -60), Vector2(-40, -150), Vector2(-62, -240), Vector2(-30, -330), Vector2(-50, -20)]:
		_cliff.draw_circle(m, 6.0, MOSS)
		_cliff.draw_circle(m + Vector2(-2, -2), 3.0, MOSS_LIGHT)


# the falls: a column of water with light streaks running down it, a darker edge each side
func _draw_falls():
	var land := _landing_y()
	var top := TOP
	var cam := get_viewport().get_camera_2d()
	if cam:                                                   # just the part on screen
		top = maxf(top, cam.get_screen_center_position().y - 150.0 - global_position.y)
	if land <= top:
		return
	for x in range(int(FALLS.x), int(FALLS.y)):
		var edge := x == int(FALLS.x) or x == int(FALLS.y) - 1
		_falls.draw_rect(Rect2(x, top, 1, land - top), WATER_SHADE if edge else WATER)
		if edge:
			continue
		var phase := float((x * 37) % 23)
		var y := top - fmod(top - _t * FALL_SPEED - phase * 7.0, 23.0)
		while y < land:                                       # streaks, each a few pixels long
			var streak := 3.0 + float((x * 5) % 4)
			_falls.draw_rect(Rect2(x, y, 1, minf(streak, land - y)), WATER_LIGHT if (x % 3) else FOAM)
			y += 23.0


# where they land: churning foam and spray
func _draw_foam():
	var land := _landing_y()
	for i in 7:
		var x := FALLS.x - 4.0 + i * 5.0 + roundf(sin(_t * 9.0 + i) * 1.5)
		var h := 2.0 + roundf(absf(sin(_t * 7.0 + i * 1.7)) * 3.0)
		_foam.draw_rect(Rect2(x, land - h, 4, h + 1.0), FOAM if i % 2 else WATER_LIGHT)
	for d: Array in _drops:
		var p: Vector2 = d[0]
		_foam.draw_rect(Rect2(p.round(), Vector2(d[4], d[4])), d[3])
