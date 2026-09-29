extends Node2D
# Gallop meter: a small bar over the player that fills while they build up speed, so they can see
# when the gallop (full speed) will kick in. Dividers split it into walk | run | sprint, it's full
# at the gallop, flashes white when the gallop starts, then fades. Fades out when the player stops.
# Drop this node into any level (like LiveReload). It only watches the player; player.gd is untouched.
# PLACEHOLDER look.

const SIZE := Vector2(20, 3)                      # inside of the bar, in pixels
const OFFSET := Vector2(-10, -52)                 # top-left of the bar, from the player's feet
const FADE := 0.15                                # seconds to fade in or out
const FLASH_TIME := 0.3
const FRAME_COLOR := Color(0.21, 0.15, 0.36)      # the player's goggle purple
const EMPTY_COLOR := Color(0.12, 0.09, 0.2)
const FLASH_COLOR := Color(1, 1, 1)
# fill colour by speed level: -, walk (cream), run (scarf orange), sprint (gold)
const FILL := [Color(0.93, 0.87, 0.86), Color(0.93, 0.87, 0.86), Color(0.83, 0.4, 0.09), Color(0.94, 0.77, 0.36)]

var player: CharacterBody2D = null
var _times: Array = [1.0, 1.9, 3.0]              # hold time where run, sprint and gallop start
var _top := 4                                     # the gallop's speed level
var _level := 0
var _last_level := 0
var _fill := 0.0
var _alpha := 0.0
var _flash := 0.0


func _ready():
	z_index = 6


func _process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		var s: GDScript = player.get_script()
		_times = [s.TIME_TO_LEVEL_2, s.TIME_TO_LEVEL_3, s.TIME_TO_LEVEL_4]
		var speeds: Array = s.SPEEDS
		_top = speeds.size() - 1
	_level = player.speed_level
	if _level >= _top and _last_level < _top:
		_flash = FLASH_TIME                        # the gallop just started
	_last_level = _level
	var building := _level >= 1 and _level < _top
	if building:
		var hold: float = player.hold_time
		var full: float = _times[-1]
		_fill = clampf(hold / full, 0.0, 1.0)
	elif _level >= _top:
		_fill = 1.0
	_flash = maxf(_flash - delta, 0.0)
	var target := 1.0 if building or _flash > 0.0 else 0.0
	_alpha = move_toward(_alpha, target, delta / FADE)
	modulate.a = _alpha
	global_position = (player.global_position + OFFSET).round()   # whole pixels, so it stays crisp
	queue_redraw()


func _draw():
	if _alpha <= 0.0:
		return
	draw_rect(Rect2(-1, -1, SIZE.x + 2, SIZE.y + 2), FRAME_COLOR)
	draw_rect(Rect2(Vector2.ZERO, SIZE), EMPTY_COLOR)
	var color: Color = FLASH_COLOR if _flash > 0.0 else FILL[clampi(_level, 0, FILL.size() - 1)]
	draw_rect(Rect2(0, 0, roundf(SIZE.x * _fill), SIZE.y), color)
	# dividers where running and sprinting start
	var full: float = _times[-1]
	for i in _times.size() - 1:
		var t: float = _times[i]
		draw_rect(Rect2(roundf(SIZE.x * t / full), 0, 1, SIZE.y), FRAME_COLOR)
