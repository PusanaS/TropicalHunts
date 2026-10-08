extends CanvasLayer
# CINEMA BARS (Morgan's call, 2026-10-08): black bands slide in at the top and bottom of the screen whenever
# the player is held still for a cinematic moment (the cactus chain until the palm falls, the dynamite from
# lighting the fuse to the blast), so it reads as a cutscene and not as the controls breaking.
# Use: CinemaBars.set_on(get_tree(), true / false). One shared node, made on demand in the current scene.
# Real time, so slow motion and hit-freezes don't hold it up. Under the HUDs (layer 9): the timer, the combo
# counter and the prompts stay on top.

const HEIGHT := 26.0                  # each band, in game pixels (the screen is 480x270)
const SLIDE := 0.3                    # seconds to slide in or out

var target := 0.0                     # 1 in, 0 out
var _k := 0.0                         # how far in they are now
var _last := 0.0
var _canvas := Node2D.new()


static func set_on(tree: SceneTree, on: bool):
	var bars := tree.get_first_node_in_group("cinema_bars")
	if bars == null:
		if not on or tree.current_scene == null:
			return
		bars = load("res://code/design/cinema_bars.gd").new()
		tree.current_scene.add_child(bars)
	bars.target = 1.0 if on else 0.0


func _ready():
	add_to_group("cinema_bars")
	layer = 9
	_canvas.draw.connect(_draw_bars)
	add_child(_canvas)
	_last = _now()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta):
	var now := _now()
	var dt := minf(now - _last, 0.1)
	_last = now
	var k := move_toward(_k, target, dt / SLIDE)
	if k != _k:
		_k = k
		_canvas.queue_redraw()


func _draw_bars():
	if _k <= 0.0:
		return
	var screen := get_viewport().get_visible_rect().size
	var h := roundf(HEIGHT * (1.0 - (1.0 - _k) * (1.0 - _k)))      # quick in, easing to a stop
	_canvas.draw_rect(Rect2(0, 0, screen.x, h), Color.BLACK)
	_canvas.draw_rect(Rect2(0, screen.y - h, screen.x, h), Color.BLACK)
