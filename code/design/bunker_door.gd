extends StaticBody2D
# THE BUNKER DOOR (Morgan's idea, 2026-10-09; a lifting metal door "same concept as level one", Morgan's
# call): the jelly factory's heavy shutter between the duel's room and the next part of the lab. It works like
# level 1's gates (tutorial_gate.gd). When DR. SPLICE is beaten and blasted off, lab_duel.gd calls unlock():
# its lamp goes from red to green with a beep. Then it opens as you come at it, so you see it go (Morgan's
# call, 2026-10-09; it used to be open already): it unlatches with a little drop and a hiss of steam from
# under it, then winches up into the wall above, clanking, with sparks off its rails and a rumble, its lamp
# flashing amber. It stays open. open() opens it straight away.
# Put it at its middle, on the floor. The wall above the doorway (from the ceiling down to 112px above the
# floor) is part of it, so you can't jump over the shutter. Its name starts with "Wall" so no grass grows.
# PLACEHOLDER look, drawn in code: a ribbed steel shutter with a hazard-striped bottom bar, rivets and two
# grips, in dark rails, under a steel wall section with hazard trim, B-02 stencilled on it and a lamp.

const Pixel := preload("res://code/design/pixel_font.gd")
const DOOR := Vector2(48, 112)       # the doorway the shutter fills
const RAIL := 4.0
const LINTEL_W := 60.0
const RISE_TIME := 0.7
const LET_THROUGH := 30.0            # its body lets you through once it's this far up
# unlocked, it opens about OPEN_LEAD seconds before you'd reach it at your speed, OPEN_NEAR..OPEN_FAR px away
# (at a gallop that's early enough for it to be up as you get there)
const OPEN_LEAD := 0.55
const OPEN_NEAR := 110.0
const OPEN_FAR := 280.0
const BEEP_SOUND := preload("res://sounds/sword/sword_hit_metal_01.wav")
const STEEL := Color("bcc6cf")
const STEEL_LIGHT := Color("dce3e9")
const STEEL_DARK := Color("8d99a4")
const RAIL_COL := Color("4f5963")
const WALL := Color("c9d2da")
const WALL_SEAM := Color("aab5bf")
const HAZARD := Color("f2c22e")
const HAZARD_DARK := Color("2a2a30")
const RED := Color("ff4a4a")
const AMBER := Color("ffb02e")
const GREEN := Color("5fe36a")
const RUMBLE_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")
const CLANK_SOUND := preload("res://sounds/sword/sword_hit_metal_02.wav")
const THUD_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const HISS_SOUND := preload("res://sounds/sword/sword_swoosh_02.wav")

signal opened

@export var height := 224.0          # floor to ceiling

var _lift := 0.0                     # how far the shutter is up (px)
var _unlocked := false               # beaten him: it opens as you come at it
var _opening := false
var _open := false
var _t := 0.0
var _clank_t := 0.0
var _shutter := CollisionShape2D.new()
var _front := Node2D.new()           # the wall section, drawn over the rising shutter
var _sparks: Array = []              # [position, velocity, age]
var _puffs: Array = []               # [position, velocity, radius, age, life]
var _snd := {}


func _ready():
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false
	z_index = -2                     # the shutter: behind you once it's up
	var shutter := RectangleShape2D.new()
	shutter.size = DOOR
	_shutter.shape = shutter
	_shutter.position = Vector2(0, -DOOR.y / 2.0)
	add_child(_shutter)
	var lintel := CollisionShape2D.new()               # the wall above the doorway
	var r := RectangleShape2D.new()
	r.size = Vector2(LINTEL_W, height - DOOR.y)
	lintel.shape = r
	lintel.position = Vector2(0, -DOOR.y - r.size.y / 2.0)
	add_child(lintel)
	_front.z_as_relative = false
	_front.z_index = 2
	_front.draw.connect(_draw_lintel)
	add_child(_front)
	for k in ["rumble", "clank", "thud", "hiss"]:
		var s := AudioStreamPlayer.new()
		s.max_polyphony = 3
		add_child(s)
		_snd[k] = s


func _sound(k: String, stream: AudioStream, pitch: float, db: float, from := 0.0):
	var s: AudioStreamPlayer = _snd[k]
	s.stream = stream
	s.pitch_scale = pitch
	s.volume_db = db
	s.play(from)


func is_open() -> bool:
	return _open or _opening


# he's beaten: the lamp goes green with a beep, and it'll open as you come at it
func unlock():
	if _unlocked:
		return
	_unlocked = true
	_t = 0.0
	_sound("clank", BEEP_SOUND, 2.6, -8.0)
	_front.queue_redraw()


# unlatch (a little drop, a hiss of steam), then winch up into the wall
func open():
	if _opening or _open:
		return
	_opening = true
	_t = 0.0
	_sound("hiss", HISS_SOUND, 0.55, -6.0)
	_sound("thud", THUD_SOUND, 0.8, -12.0, 0.02)
	for i in 12:
		_puffs.append([Vector2(randf_range(-DOOR.x / 2.0, DOOR.x / 2.0), -2.0), Vector2(randf_range(-70.0, 70.0), randf_range(-30.0, -5.0)),
			randf_range(3.0, 6.0), 0.0, randf_range(0.5, 1.0)])
	_shake(3.0, 0.2)


func _physics_process(delta: float):
	if _unlocked and not _opening and not _open:
		_t += delta
		var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player:
			var away := absf(player.global_position.x - global_position.x)
			if away < clampf(absf(player.velocity.x) * OPEN_LEAD + 40.0, OPEN_NEAR, OPEN_FAR):
				open()
		if _t < 0.5:
			_front.queue_redraw()                        # (the lamp's blink as it unlocks)
	if _opening:
		_t += delta
		if _t < 0.08:
			_lift = -2.0 * (_t / 0.08)                    # the unlatching drop
		else:
			if not _snd["rumble"].playing and _lift < DOOR.y * 0.9:
				_sound("rumble", RUMBLE_SOUND, 1.4, -8.0)
			var k := clampf((_t - 0.08) / RISE_TIME, 0.0, 1.0)
			_lift = DOOR.y * (k * k * (3.0 - 2.0 * k))
			_clank_t -= delta
			if _clank_t <= 0.0 and k < 1.0:             # the winch's ratchet
				_clank_t = 0.07
				_sound("clank", CLANK_SOUND, randf_range(0.55, 0.7), -16.0)
				for side in [-1.0, 1.0]:                  # sparks off the rails
					_sparks.append([Vector2(side * DOOR.x / 2.0, -DOOR.y), Vector2(side * randf_range(20.0, 80.0), randf_range(-60.0, 20.0)), 0.0])
			if _lift > LET_THROUGH:
				_shutter.set_deferred("disabled", true)
			if k >= 1.0:
				_opening = false
				_open = true
				_snd["rumble"].stop()
				_sound("thud", THUD_SOUND, 0.7, -6.0, 0.02)
				_shake(4.0, 0.2)
				opened.emit()
	for sp: Array in _sparks:
		sp[2] += delta
		sp[1].y += 500.0 * delta
		sp[0] += sp[1] * delta
	_sparks = _sparks.filter(func(sp): return sp[2] < 0.35)
	for p: Array in _puffs:
		p[3] += delta
		p[0] += p[1] * delta
		p[1] *= exp(-2.5 * delta)
		p[2] += 8.0 * delta
	_puffs = _puffs.filter(func(p): return p[3] < p[4])
	if _opening or not _sparks.is_empty() or not _puffs.is_empty():
		queue_redraw()
		_front.queue_redraw()


func _shake(strength: float, time: float):
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("_shake"):
		player._shake(strength, time)


# the shutter in its rails (behind you); it rises up behind the wall section
func _draw():
	var half := DOOR.x / 2.0
	draw_rect(Rect2(-half - RAIL, -DOOR.y, RAIL, DOOR.y), RAIL_COL)                 # the rails
	draw_rect(Rect2(half, -DOOR.y, RAIL, DOOR.y), RAIL_COL)
	draw_rect(Rect2(-half - 1.0, -DOOR.y, 1, DOOR.y), STEEL_DARK)
	draw_rect(Rect2(half, -DOOR.y, 1, DOOR.y), STEEL_DARK)
	var bottom := -_lift
	var top := bottom - DOOR.y
	var shown_top := maxf(top, -DOOR.y - 20.0)                                    # (the rest is in the wall)
	if bottom > shown_top:
		draw_rect(Rect2(-half, shown_top, DOOR.x, bottom - shown_top), STEEL)
		var y := bottom - 14.0                                                    # its ribs
		while y > shown_top:
			draw_rect(Rect2(-half, y, DOOR.x, 1), STEEL_LIGHT)
			draw_rect(Rect2(-half, y + 1.0, DOOR.x, 1), STEEL_DARK)
			y -= 8.0
		if bottom - 12.0 > shown_top:                                             # the hazard-striped bottom bar
			draw_rect(Rect2(-half, bottom - 12.0, DOOR.x, 12), HAZARD_DARK)
			for x in range(0, int(DOOR.x), 8):
				draw_primitive(PackedVector2Array([Vector2(-half + x, bottom - 1.0), Vector2(-half + x + 4.0, bottom - 1.0),
					Vector2(-half + x + 8.0, bottom - 11.0), Vector2(-half + x + 4.0, bottom - 11.0)]),
					PackedColorArray([HAZARD, HAZARD, HAZARD, HAZARD]), PackedVector2Array())
			draw_rect(Rect2(-half, bottom - 12.0, DOOR.x, 1), STEEL_DARK)
		for gx: float in [-12.0, 8.0]:                                            # grips
			var gy := bottom - 30.0
			if gy > shown_top:
				draw_rect(Rect2(gx, gy, 5, 8), RAIL_COL)
				draw_rect(Rect2(gx + 1.0, gy + 1.0, 3, 6), STEEL_DARK)
		for rx: float in [-half + 3.0, half - 5.0]:                               # rivets
			var ry := bottom - 20.0
			while ry > shown_top + 2.0:
				draw_rect(Rect2(rx, ry, 2, 2), STEEL_DARK)
				ry -= 16.0
	for p: Array in _puffs:                                                       # steam from under it
		var k: float = p[3] / p[4]
		draw_circle(p[0], p[2], Color(1, 1, 1, 0.5 * (1.0 - k)))


# the wall over the doorway (in front, so the shutter rises up behind it): steel panels, hazard trim along
# its bottom edge, B-02 and the lamp; and the rails' sparks
func _draw_lintel():
	var ci := _front
	var w := LINTEL_W
	var top := -height
	var bot := -DOOR.y
	ci.draw_rect(Rect2(-w / 2.0, top, w, bot - top), WALL)
	var y := top + 24.0
	while y < bot - 10.0:
		ci.draw_rect(Rect2(-w / 2.0, y, w, 1), WALL_SEAM)
		y += 24.0
	ci.draw_rect(Rect2(-w / 2.0, top, 1, bot - top), WALL_SEAM)
	ci.draw_rect(Rect2(w / 2.0 - 1.0, top, 1, bot - top), WALL_SEAM)
	ci.draw_rect(Rect2(-w / 2.0, bot - 8.0, w, 8), HAZARD_DARK)                  # hazard trim
	for x in range(0, int(w), 8):
		ci.draw_primitive(PackedVector2Array([Vector2(-w / 2.0 + x, bot - 1.0), Vector2(-w / 2.0 + x + 4.0, bot - 1.0),
			Vector2(-w / 2.0 + x + 8.0, bot - 7.0), Vector2(-w / 2.0 + x + 4.0, bot - 7.0)]),
			PackedColorArray([HAZARD, HAZARD, HAZARD, HAZARD]), PackedVector2Array())
	for c: Array in Pixel.cells("B-02", Vector2(-10, bot - 30.0), 1):
		ci.draw_rect(c[0], RAIL_COL)
	var lamp := RED
	if _open:
		lamp = GREEN
	elif _opening:
		lamp = AMBER if int(_t * 8.0) % 2 == 0 else Color(AMBER, 0.35)
	elif _unlocked:
		lamp = GREEN if _t > 0.4 or int(_t * 10.0) % 2 == 0 else Color(GREEN, 0.3)   # (a quick blink as it unlocks)
	ci.draw_rect(Rect2(-4, bot - 46.0, 8, 4), lamp)
	ci.draw_rect(Rect2(-6, bot - 42.0, 12, 3), Color(lamp, 0.25))
	for sp: Array in _sparks:
		ci.draw_rect(Rect2(sp[0].round(), Vector2(1, 1)), Color(1.0, 0.9, 0.5, 1.0 - sp[2] / 0.35))
