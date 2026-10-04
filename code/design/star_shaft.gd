extends Node2D
# STAR SHAFT: Level 2's climb (Morgan's idea). A shaft too tall for a double jump, with a platform up on
# each side, and starfruits dropping off the two platforms in turn. Jump, hit one with an air Q and
# you're thrown across to the other side, where the next one drops in just in time: Q again, and
# again, zigzagging up, until the last throw lands you on top of the exit platform.
# Place it on the shaft's floor, in the middle. The level makes the walls: a platform on the left whose
# right edge is at x = -width/2 and one on the right whose left edge is at +width/2, both topped at
# y = -height. The starfruits (code/design/starfruit.gd) are its children, and ask it where to throw
# the player (next_target).

const Starfruit := preload("res://code/design/starfruit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")

const DROP_INSET := 28.0         # starfruits drop this far in from each wall
const GAIN := 100.0              # each bounce lifts the next starfruit this much higher than the last
const TOP_MARGIN := 50.0         # a bounce that would get the feet this close to the top lands them on it
const LAND := Vector2(24, 30)    # the last throw aims just past the exit platform's edge and over its top
const HANG := 1.1                # a starfruit dropped in for a bounce hangs still this long
const MAX_ALIVE := 4
const NEAR := Vector2(60, 40)    # a starfruit this close to where the next one should be is used instead

@export var width := 360.0
@export var height := 360.0
@export var interval := 1.4      # starfruits drop this often while the player is around, sides in turn
@export var exit_side := 1       # which top platform the climb ends on (-1 left, 1 right)
@export var active_range := 420.0

var player: Node2D = null
var _timer := 0.0
var _side := -1
var _t := 0.0
var _glint := [0.0, 0.0]         # each drop point twinkles brighter for a moment when one drops


func _physics_process(delta: float):
	_t += delta
	for i in 2:
		_glint[i] = maxf(_glint[i] - delta * 3.0, 0.0)
	queue_redraw()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return
	var d := player.global_position - global_position
	if absf(d.x) > active_range or d.y < -height - 240.0 or d.y > 120.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		if _alive() < MAX_ALIVE:
			_drop_at(Vector2(_side * (width / 2.0 - DROP_INSET), -height - 12.0), 0.0)
		_side = -_side


func _alive() -> int:
	var n := 0
	for c in get_children():
		if c.has_method("is_alive") and c.is_alive():
			n += 1
	return n


func _drop_at(at: Vector2, hang: float) -> Node2D:
	var f: Node2D = Starfruit.new()
	f.mode = "fall"
	f.position = at
	f.hang = hang
	add_child(f)
	f.sparkle_in()
	_glint[0 if at.x < 0.0 else 1] = 1.0
	return f


# a starfruit of this shaft was hit with an air Q: where to throw the player (their feet)
func next_target(fruit: Node2D, p: Node2D):
	var hit := to_local(fruit.global_position)
	var side := -signf(hit.x)                     # always across to the other side
	if side == 0.0:
		side = float(exit_side)
	var next_y := hit.y - GAIN
	# close enough to the top: this throw lands them on the exit platform, just past its edge
	if next_y + Starfruit.AIM_OFFSET.y <= -height + TOP_MARGIN:
		return to_global(Vector2(exit_side * (width / 2.0 + LAND.x), -height - LAND.y))
	# otherwise the next one drops in on the other side, right where the throw will reach
	var at := Vector2(side * (width / 2.0 - DROP_INSET), next_y)
	var next := _fruit_near(at)
	if next == null:
		next = _drop_at(at, HANG)
	else:
		next.hang = maxf(next.hang, HANG)
	return next.aim_point(p.global_position)


func _fruit_near(at: Vector2) -> Node2D:
	for c in get_children():
		if c.has_method("is_alive") and c.is_alive():
			var d: Vector2 = c.position - at
			if absf(d.x) <= NEAR.x and absf(d.y) <= NEAR.y:
				return c
	return null


# a little four-point twinkle at each drop point, brighter as one drops
func _draw():
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var at := Vector2(side * (width / 2.0 - DROP_INSET), -height - 12.0).round()
		var pulse := 0.5 + 0.5 * sin(_t * 4.0 + i * PI)
		var a := 0.3 + 0.3 * pulse + 0.4 * float(_glint[i])
		var reach := 2 + int(roundf(pulse + 2.0 * float(_glint[i])))
		draw_rect(Rect2(at, Vector2(1, 1)), Color(Pixel.WHITE, a))
		for k in range(1, reach + 1):
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(at + d * k, Vector2(1, 1)), Color(Pixel.MUSTARD, a * (1.0 - float(k) / (reach + 1))))
