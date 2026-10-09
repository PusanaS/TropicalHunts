extends StaticBody2D
# LAB GLASS (Morgan's call, 2026-10-09): a floor-to-ceiling glass wall in the jelly factory (jelly_lab.gd),
# after the jelly pool. Only a gallop gets through it: galloping at it (on the ground or bouncing off the
# jelly) shatters it just before you touch it, so you keep your speed, with a burst of glass shards flying on
# ahead of you, a short slow-motion beat, a crash and a shake. Slower than that it's just a wall.
# `locked`: it holds even a gallop (a small red light on its top track) until unlock() is called (the lab
# scientist's duel does, when he's beaten: the light turns green with a ting).
# Put it at its middle, on the floor, `height` up to the ceiling.
# PLACEHOLDER look, drawn in code: frosted glass with bright edges and slanting reflections, in metal tracks
# top and bottom; once broken, jagged bits stay in the tracks.

const THICK := 12.0
const GALLOP_REACH := 24.0
const PLAYER_HALF_WIDTH := 13.0
const SLOW := 0.35                   # the slow-motion beat as it shatters,
const SLOW_TIME := 0.35              # ...this long (real seconds)
const SHARDS := 46
const GLASS := Color(0.82, 0.94, 1.0, 0.38)
const EDGE := Color(1, 1, 1, 0.9)
const SHINE := Color(1, 1, 1, 0.45)
const TRACK := Color("b8c3cc")
const TRACK_DARK := Color("8d99a4")
const CRASH_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRASH_SKIP := 0.02
const CRASH_DB := -4.0
const TINKLE_SOUND := preload("res://sounds/sword/sword_clash_06.wav")    # (played high: glass)
const TINKLE_DB := -8.0
const LED_RED := Color("ff4a4a")
const LED_GREEN := Color("5fe36a")

@export var height := 224.0
@export var locked := false

var _broken := false
var _unlocked_t := -1.0
var _shards: Array = []              # [position, velocity, angle, spin, size, age]
var _player: CharacterBody2D = null
var _top := 4
var _shape := CollisionShape2D.new()
var _crash := AudioStreamPlayer.new()
var _tinkle := AudioStreamPlayer.new()


func _ready():
	z_index = 1                      # in front of you as you go through it
	var rect := RectangleShape2D.new()
	rect.size = Vector2(THICK, height)
	_shape.shape = rect
	_shape.position = Vector2(0, -height / 2.0)
	add_child(_shape)
	for p in [[_crash, CRASH_SOUND, CRASH_DB], [_tinkle, TINKLE_SOUND, TINKLE_DB]]:
		var s: AudioStreamPlayer = p[0]
		s.stream = p[1]
		s.volume_db = p[2]
		add_child(s)


func _physics_process(delta: float):
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if _player == null:
			return
		_top = _player.get_script().get_script_constant_map()["SPEEDS"].size() - 1
	if not _broken:
		var d := global_position.x - _player.global_position.x
		var dir := signf(_player.velocity.x)
		var heading := dir != 0.0 and signf(d) == dir
		var gap := absf(d) - THICK / 2.0 - PLAYER_HALF_WIDTH
		var reach := GALLOP_REACH + absf(_player.velocity.x) * delta
		var level_ok := _player.global_position.y <= global_position.y + 2.0 and _player.global_position.y > global_position.y - height
		if _player.speed_level >= _top and heading and gap < reach and level_ok and not locked:
			_shatter(dir)
	for s: Array in _shards:
		s[5] += delta
		s[1].y += 700.0 * delta
		s[0] += s[1] * delta
		if s[0].y > 0.0:                             # landing on the floor: a skid and a little bounce
			s[0].y = 0.0
			s[1] = Vector2(s[1].x * 0.5, -absf(s[1].y) * 0.25)
			s[3] *= 0.5
		s[2] += s[3] * delta
	_shards = _shards.filter(func(s): return s[5] < 1.6)
	if _unlocked_t >= 0.0:
		_unlocked_t += delta
	if not _shards.is_empty() or not _broken:
		queue_redraw()


# the lock's light goes green (with a ting): a gallop gets through now
func unlock():
	if not locked:
		return
	locked = false
	_unlocked_t = 0.0
	_tinkle.pitch_scale = 2.4
	_tinkle.play()
	queue_redraw()


func _shatter(dir: float):
	_broken = true
	_shape.set_deferred("disabled", true)
	for i in SHARDS:
		var y := -randf() * height
		_shards.append([Vector2(randf_range(-3.0, 3.0), y),
			Vector2(dir * randf_range(120.0, 520.0), randf_range(-260.0, 60.0) - (y + height) * 0.2),
			randf() * TAU, randf_range(-14.0, 14.0), randf_range(2.0, 5.0), 0.0])
	_crash.pitch_scale = 1.5
	_crash.play(CRASH_SKIP)
	_tinkle.pitch_scale = 1.9
	_tinkle.play()
	if _player.has_method("_shake"):
		_player._shake(8.0, 0.25)
	Engine.time_scale = SLOW
	get_tree().create_timer(SLOW_TIME, true, false, true).timeout.connect(func():
		if Engine.time_scale == SLOW:
			Engine.time_scale = 1.0)


func _draw():
	draw_rect(Rect2(-THICK / 2.0 - 2.0, -height, THICK + 4.0, 4), TRACK)          # the tracks
	draw_rect(Rect2(-THICK / 2.0 - 2.0, -4, THICK + 4.0, 4), TRACK)
	draw_rect(Rect2(-THICK / 2.0 - 2.0, -1, THICK + 4.0, 1), TRACK_DARK)
	if not _broken:
		var led := LED_RED if locked else LED_GREEN                                 # the lock's light
		var blink := 1.0 if locked or _unlocked_t > 0.6 else (0.4 if int(_unlocked_t * 10.0) % 2 else 1.0)
		draw_rect(Rect2(-2, -height + 1.0, 4, 2), Color(led, blink))
		draw_rect(Rect2(-4, -height + 4.0, 8, 3), Color(led, 0.25 * blink))
		draw_rect(Rect2(-THICK / 2.0, -height + 4.0, THICK, height - 8.0), GLASS)
		draw_rect(Rect2(-THICK / 2.0, -height + 4.0, 1, height - 8.0), EDGE)
		draw_rect(Rect2(THICK / 2.0 - 1.0, -height + 4.0, 1, height - 8.0), Color(EDGE, 0.5))
		for k in 3:                                                                # slanting reflections
			var y := -height * (0.25 + k * 0.27)
			draw_line(Vector2(-THICK / 2.0 + 1.0, y), Vector2(THICK / 2.0 - 1.0, y - 10.0), SHINE, 1.0)
	else:
		for y0 in [-height + 4.0, -4.0]:                                         # jagged bits left in the tracks
			var down := 1.0 if y0 < -height / 2.0 else -1.0
			for k in 4:
				var x := -THICK / 2.0 + k * 3.0
				draw_primitive(PackedVector2Array([Vector2(x, y0), Vector2(x + 3.0, y0), Vector2(x + 1.5, y0 + down * (4.0 + (k * 5) % 7))]),
					PackedColorArray([GLASS, GLASS, GLASS]), PackedVector2Array())
	for s: Array in _shards:                                                       # the shards, flying and fading
		var a := clampf(1.6 - s[5], 0.0, 1.0)
		var r: float = s[4]
		var pts := PackedVector2Array()
		for k in 3:
			pts.append(s[0] + Vector2(r, 0).rotated(s[2] + k * TAU / 3.0 + (0.6 if k == 1 else 0.0)))
		draw_primitive(pts, PackedColorArray([Color(EDGE, a), Color(GLASS, a * 1.8), Color(GLASS, a * 1.8)]), PackedVector2Array())
