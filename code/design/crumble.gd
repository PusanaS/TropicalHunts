extends StaticBody2D
# A platform that crumbles under you: stand on it and it shakes for a moment, then falls away, and comes
# back a little later. Origin at the middle of its top. Name it "Crumble..." in scenes (no grass grows on it).
#   look "wood"    old boardwalk planks (Level 2)
#   look "basalt"  a cooled crust floating on the lava (Level 3): its cracks glow brighter as it goes
# Keep moving and you're fine: that's the speed part. Stop on one and you drop.
# PLACEHOLDER look, drawn in code.

@export var width := 96.0
@export var look := "basalt"
@export var shake_time := 0.45
@export var respawn_time := 2.5

const THICK := 14.0
const LOOKS := {
	"wood": {"top": Color("b0784a"), "body": Color("8a5634"), "shade": Color("5e3a22"), "crack": Color("3a2416")},
	"basalt": {"top": Color("4a4250"), "body": Color("2e2834"), "shade": Color("1e1a22"), "crack": Color("ff7a1e")},
}

enum Mode { SOLID, SHAKING, FALLING, GONE }

var player: CharacterBody2D = null
var _mode := Mode.SOLID
var _t := 0.0
var _fall := 0.0                  # how far it has dropped
var _fall_v := 0.0
var _back := 1.0                  # fades back in after it returns
var _shape: CollisionShape2D


func _ready():
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, THICK)
	_shape.shape = rect
	_shape.position = Vector2(0, THICK / 2.0)
	add_child(_shape)


func _physics_process(delta: float):
	_t += delta
	_back = minf(_back + delta / 0.3, 1.0)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	match _mode:
		Mode.SOLID:
			if _stood_on():
				_set_mode(Mode.SHAKING)
		Mode.SHAKING:
			if _t >= shake_time:
				_set_mode(Mode.FALLING)
				_shape.set_deferred("disabled", true)
		Mode.FALLING:
			_fall_v += 900.0 * delta
			_fall += _fall_v * delta
			if _t >= 0.9:
				_set_mode(Mode.GONE)
		Mode.GONE:
			if _t >= respawn_time and not _someone_there():
				_set_mode(Mode.SOLID)
				_fall = 0.0
				_fall_v = 0.0
				_back = 0.0
				_shape.set_deferred("disabled", false)
	queue_redraw()


func _set_mode(m: Mode):
	_mode = m
	_t = 0.0


func _stood_on() -> bool:
	if player == null or not player.is_on_floor():
		return false
	var d := player.global_position - global_position
	return absf(d.x) <= width / 2.0 + 10.0 and absf(d.y) <= 3.0


# don't come back right where the player is standing or passing
func _someone_there() -> bool:
	if player == null:
		return false
	var d := player.global_position - global_position
	return absf(d.x) <= width / 2.0 + 14.0 and d.y > -44.0 and d.y < THICK + 4.0


func _draw():
	if _mode == Mode.GONE:
		return
	var c: Dictionary = LOOKS.get(look, LOOKS["basalt"])
	var a := _back
	var shake := Vector2.ZERO
	var heat := 0.35
	if _mode == Mode.SHAKING:
		shake = Vector2(roundf(randf_range(-1.0, 1.0)), 0)
		heat = 0.35 + 0.65 * _t / shake_time
	if _mode == Mode.FALLING:
		a *= 1.0 - clampf(_t / 0.9, 0.0, 1.0)
	# three chunks: they split apart as it falls
	var third := width / 3.0
	for i in 3:
		var x0 := -width / 2.0 + i * third
		var off := shake
		var spin := 0.0
		if _mode == Mode.FALLING:
			off = Vector2((i - 1) * _t * 26.0, _fall * (0.85 + i * 0.12))
			spin = (i - 1) * _t * 0.8
		draw_set_transform(off.round() + Vector2(x0 + third / 2.0, THICK / 2.0), spin)
		_draw_chunk(Rect2(-third / 2.0, -THICK / 2.0, third, THICK), c, a, heat, i)
		draw_set_transform(Vector2.ZERO)


func _draw_chunk(r: Rect2, c: Dictionary, a: float, heat: float, i: int):
	if look == "wood":
		draw_rect(r, Color(c["body"], a))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(c["top"], a))
		draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(c["shade"], a))
		for k in range(1, 3):            # plank seams and a nail each
			var y := r.position.y + k * 4.0
			draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(c["shade"], a))
		draw_rect(Rect2(r.position.x + 2, r.position.y + 3, 1, 1), Color(c["crack"], a))
		draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), Color(c["crack"], a))
		return
	# basalt: jagged underside, glowing cracks that brighten as it's about to go
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - 3)), Color(c["body"], a))
	var x := r.position.x
	while x < r.end.x:
		var h := 3.0 - float(absi(int(x) * 7 + i * 3) % 3)
		draw_rect(Rect2(x, r.end.y - 3, 2, h), Color(c["shade"], a))
		x += 2.0
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(c["top"], a))
	var glow := Color(c["crack"], a * heat)
	var cx := r.position.x + r.size.x * (0.3 + 0.4 * float((i * 5) % 3) / 2.0)
	for k in 5:
		draw_rect(Rect2(roundf(cx + k * (1 if k % 2 == 0 else -1)), r.position.y + 2 + k * 2, 1, 2), glow)
	draw_rect(Rect2(r.end.x - 1, r.position.y + 2, 1, r.size.y - 5), Color(c["shade"], a))
