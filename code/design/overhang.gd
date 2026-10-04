extends StaticBody2D
# A wall of jungle earth hanging from above (level 1, just before the sand catapult; Morgan wanted it in
# theme): packed earth and stones, roots poking out of its sides, moss and grass along its underside, a
# few flowers, and vines hanging down that swing aside when you pass under them.
# With `standing` on it's a wall rising from the ground instead (level 1's surf wall, Morgan's call): earth
# with stone strata, roots and moss on its faces, a ragged grassy top with flowers, and vines hanging down
# both faces from the top.
# Put it on a StaticBody2D whose "Shape" child is a RectangleShape2D. Its plain "Look" polygon (what the
# editor shows) is hidden while the game runs.
# PLACEHOLDER art drawn in code, in the living background's day colours (BOOM's style: flat, one shade).

const EARTH := Color("4d321a")
const EARTH_LIGHT := Color("624021")
const STONE := Color("6e6250")
const STONE_SHADE := Color("564c40")
const ROOT := Color("624021")
const MOSS_SHADE := Color("526e36")
const MOSS := Color("76964a")
const MOSS_LIGHT := Color("a4bf68")
const FLOWERS := [Color("d36618"), Color("ccad4b"), Color("8d0e0e"), Color("ecdfdb")]
const DETAIL_DEPTH := 220.0          # stones are only scattered this far up from the bottom (above is off-screen)
const VINE_EVERY := Vector2(14, 24)
const VINE_LENGTH := Vector2(12, 34) # the passage under it is 60px: the longest brush your head
const SPRING := 60.0
const DAMP := 4.0
const PUSH := 420.0
const PLAYER_BOX := Rect2(-13, -40, 26, 40)
const FACE_VINES := 3                # standing: vines down each face...
const FACE_VINE_LENGTH := Vector2(60, 200)   # ...this long

@export var standing := false        # a wall rising from the ground (not hanging from above)

var player: CharacterBody2D = null
var _r := Rect2()                    # the wall, local
var _teeth := PackedFloat32Array()   # per column: how far above the bottom the earth stops (a ragged edge)
var _moss := PackedFloat32Array()    # per column: moss thickness
var _blades := PackedFloat32Array()  # per column: grass hanging below the edge (0 = none)
var _stones: Array = []              # [Rect2, shade?]
var _roots: Array = []               # [from, to] lines poking out of the sides and the underside
var _flowers: Array = []             # [pos, colour]
var _vines: Array = []               # [x, length, phase, bend, bend speed]
var _patches: Array = []             # standing: moss on its faces [Rect2, light?]
var _t := 0.0


func _ready():
	z_index = 1                      # the vines and grass hang in front of you as you pass under
	var look := get_node_or_null("Look") as CanvasItem
	if look:
		look.visible = false
	var shape_node := get_node_or_null("Shape") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		_r = Rect2(shape_node.position - size / 2.0, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x)
	if standing:
		_build_standing(rng)
		return
	var n := int(_r.size.x)
	_teeth.resize(n)
	_moss.resize(n)
	_blades.resize(n)
	var tooth := 2.0
	for i in n:
		tooth = clampf(tooth + rng.randf_range(-1.2, 1.2), 0.0, 5.0)      # a ragged, wandering edge
		_teeth[i] = roundf(tooth)
		_moss[i] = 2.0 + float(rng.randi() % 2)
		_blades[i] = float(rng.randi_range(1, 6)) if rng.randf() < 0.45 else 0.0
	for i in int(_r.size.x * DETAIL_DEPTH / 380.0):
		var w := float(rng.randi_range(2, 5))
		var p := Vector2(rng.randf_range(_r.position.x + 1.0, _r.end.x - w - 1.0), _r.end.y - rng.randf_range(10.0, DETAIL_DEPTH))
		_stones.append([Rect2(p.round(), Vector2(w, float(rng.randi_range(2, 3)))), rng.randf() < 0.4])
	for side in [-1.0, 1.0]:                                              # roots out of the sides
		var x := _r.position.x if side < 0.0 else _r.end.x
		var y := _r.end.y - rng.randf_range(8.0, 20.0)
		while y > _r.end.y - DETAIL_DEPTH:
			var out := rng.randf_range(3.0, 8.0)
			_roots.append([Vector2(x - side * 2.0, y), Vector2(x + side * out, y + rng.randf_range(2.0, 7.0))])
			y -= rng.randf_range(18.0, 40.0)
	for i in 5:                                                           # roots dangling from the underside
		var rx := rng.randf_range(_r.position.x + 6.0, _r.end.x - 6.0)
		_roots.append([Vector2(rx, _r.end.y - 3.0), Vector2(rx + rng.randf_range(-3.0, 3.0), _r.end.y + rng.randf_range(4.0, 9.0))])
	for i in 4:
		_flowers.append([Vector2(rng.randf_range(_r.position.x + 4.0, _r.end.x - 4.0), 0.0).round(), FLOWERS[i % FLOWERS.size()]])
	var vx := _r.position.x + rng.randf_range(4.0, 10.0)
	while vx < _r.end.x - 4.0:
		_vines.append([vx, rng.randf_range(VINE_LENGTH.x, VINE_LENGTH.y), rng.randf() * TAU, 0.0, 0.0])
		vx += rng.randf_range(VINE_EVERY.x, VINE_EVERY.y)


# the vines spring aside when you brush through them, then swing back
func _process(delta: float):
	_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var body := Rect2()
	if player:
		body = Rect2(to_local(player.global_position) + PLAYER_BOX.position, PLAYER_BOX.size)
	for v: Array in _vines:
		var acc := -float(v[3]) * SPRING - float(v[4]) * DAMP
		var vine := Rect2(float(v[0]) - 3.0, float(v[5]) if standing else _r.end.y, 6.0, float(v[1]))
		if player and vine.intersects(body):
			var dir := signf(player.velocity.x) if absf(player.velocity.x) > 5.0 else signf(float(v[0]) - body.get_center().x)
			acc += dir * PUSH
		v[4] = float(v[4]) + acc * delta
		v[3] = clampf(float(v[3]) + float(v[4]) * delta, -1.2, 1.2)
	queue_redraw()


func _draw():
	if _r.size.x <= 0.0:
		return
	if standing:
		_draw_standing()
		return
	var bottom := _r.end.y
	# the earth, its ragged underside, the moss on it and grass hanging off it
	draw_rect(Rect2(_r.position, Vector2(_r.size.x, _r.size.y - 8.0)), EARTH)
	for i in _teeth.size():
		var x := _r.position.x + i
		var edge := bottom - _teeth[i]
		var moss_top := edge - _moss[i]
		draw_rect(Rect2(x, bottom - 8.0, 1, moss_top - (bottom - 8.0)), EARTH)
		draw_rect(Rect2(x, moss_top, 1, _moss[i]), MOSS if i % 7 != 0 else MOSS_LIGHT)
		draw_rect(Rect2(x, edge - 1.0, 1, 1), MOSS_SHADE)
		if _blades[i] > 0.0:
			draw_rect(Rect2(x, edge, 1, _blades[i]), MOSS_SHADE if i % 3 == 0 else MOSS)
	for s: Array in _stones:
		var r: Rect2 = s[0]
		draw_rect(r, STONE_SHADE if s[1] else STONE)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), STONE_SHADE)
	for i in 6:                                                          # lighter clods of earth
		var cx := _r.position.x + fmod(i * 37.0 + 11.0, _r.size.x - 6.0)
		draw_rect(Rect2(cx, bottom - 30.0 - i * 27.0, 5, 2), EARTH_LIGHT)
	for root: Array in _roots:
		draw_line(root[0], root[1], ROOT, 1.0)
	for fl: Array in _flowers:
		var p: Vector2 = fl[0]
		var i := clampi(int(p.x - _r.position.x), 0, _teeth.size() - 1)
		var at := Vector2(p.x, bottom - _teeth[i] - 1.0)
		draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 2)), fl[1])
		draw_rect(Rect2(at + Vector2(0, 1), Vector2(1, 1)), FLOWERS[1] if fl[1] != FLOWERS[1] else FLOWERS[3])
	# vines: a stem with leaves on alternate sides, bent aside by you, swaying a little on their own
	for v: Array in _vines:
		var x0: float = v[0]
		var length: float = v[1]
		var phase: float = v[2]
		var bend: float = v[3]
		var i0 := clampi(int(x0 - _r.position.x), 0, _teeth.size() - 1)
		var top := bottom - _teeth[i0]
		for s in int(length):
			var k := s / length
			var off := roundf(bend * 10.0 * k * k + sin(_t * 1.3 + phase) * 0.8 * k)
			var p := Vector2(x0 + off, top + s)
			draw_rect(Rect2(p, Vector2(1, 1)), MOSS_SHADE)
			if s % 5 == 3:
				var side := -2.0 if int(s / 5.0) % 2 == 0 else 1.0
				draw_rect(Rect2(p + Vector2(side, 0), Vector2(2, 2)), MOSS)
				draw_rect(Rect2(p + Vector2(side, 0), Vector2(1, 1)), MOSS_LIGHT)
		var tip := Vector2(x0 + roundf(bend * 10.0 + sin(_t * 1.3 + phase) * 0.8), top + length)
		draw_rect(Rect2(tip + Vector2(-1, 0), Vector2(3, 3)), MOSS)


# ---------- standing: a wall rising from the ground ----------
func _build_standing(rng: RandomNumberGenerator):
	var n := int(_r.size.x)
	_teeth.resize(n)
	_moss.resize(n)
	_blades.resize(n)
	var bump := 2.0
	for i in n:
		bump = clampf(bump + rng.randf_range(-1.2, 1.2), 0.0, 4.0)        # a ragged top
		_teeth[i] = roundf(bump)                                           # earth rising over the top edge
		_moss[i] = 2.0 + float(rng.randi() % 2)
		_blades[i] = float(rng.randi_range(2, 7)) if rng.randf() < 0.55 else 0.0   # grass growing up
	for i in int(_r.size.x * _r.size.y / 380.0):                           # stones all the way down
		var w := float(rng.randi_range(2, 5))
		var p := Vector2(rng.randf_range(_r.position.x + 1.0, _r.end.x - w - 1.0), rng.randf_range(_r.position.y + 6.0, _r.end.y - 4.0))
		_stones.append([Rect2(p.round(), Vector2(w, float(rng.randi_range(2, 3)))), rng.randf() < 0.4])
	for side in [-1.0, 1.0]:
		var x := _r.position.x if side < 0.0 else _r.end.x
		var y := _r.position.y + rng.randf_range(10.0, 24.0)
		while y < _r.end.y - 6.0:                                          # roots out of both faces
			var out := rng.randf_range(3.0, 8.0)
			_roots.append([Vector2(x - side * 2.0, y), Vector2(x + side * out, y + rng.randf_range(2.0, 7.0))])
			y += rng.randf_range(20.0, 44.0)
		y = _r.position.y + rng.randf_range(20.0, 50.0)
		while y < _r.end.y - 10.0:                                         # moss clinging to the faces
			var h := float(rng.randi_range(4, 10))
			_patches.append([Rect2(x - (3.0 if side < 0.0 else 0.0), roundf(y), 3, h), rng.randf() < 0.4])
			y += rng.randf_range(30.0, 70.0)
		for i in FACE_VINES:                                               # vines hanging down the face from the top
			var vx := (_r.position.x - 1.0 - i * 2.0) if side < 0.0 else (_r.end.x + i * 2.0)
			_vines.append([vx, rng.randf_range(FACE_VINE_LENGTH.x, FACE_VINE_LENGTH.y), rng.randf() * TAU, 0.0, 0.0, _r.position.y - 1.0])
		y = _r.position.y + rng.randf_range(80.0, 140.0)
		while y < _r.end.y - 60.0:                                         # and shorter ones out of cracks lower down
			var vx := (_r.position.x - 1.0 - float(rng.randi_range(0, 3))) if side < 0.0 else (_r.end.x + float(rng.randi_range(0, 3)))
			_vines.append([vx, rng.randf_range(30.0, 90.0), rng.randf() * TAU, 0.0, 0.0, roundf(y)])
			y += rng.randf_range(90.0, 160.0)
	for i in 3:
		_flowers.append([Vector2(rng.randf_range(_r.position.x + 4.0, _r.end.x - 4.0), 0.0).round(), FLOWERS[i % FLOWERS.size()]])


func _draw_standing():
	var top := _r.position.y
	draw_rect(_r, EARTH)
	var y := top + 14.0
	while y < _r.end.y - 4.0:                                              # strata
		draw_rect(Rect2(_r.position.x, y, _r.size.x, 3), EARTH_LIGHT)
		draw_rect(Rect2(_r.position.x, y + 3.0, _r.size.x, 1), STONE_SHADE)
		y += 30.0
	for st: Array in _stones:
		var r: Rect2 = st[0]
		draw_rect(r, STONE_SHADE if st[1] else STONE)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), STONE_SHADE)
	for root: Array in _roots:
		draw_line(root[0], root[1], ROOT, 1.0)
	for pt: Array in _patches:
		var r: Rect2 = pt[0]
		draw_rect(r, MOSS_LIGHT if pt[1] else MOSS)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), MOSS_SHADE)
	# the ragged top: earth bumps, a mossy cap, grass growing up out of it
	for i in _teeth.size():
		var x := _r.position.x + i
		var crest := top - _teeth[i]
		draw_rect(Rect2(x, crest, 1, _teeth[i] + 1.0), EARTH)
		var cap := crest - _moss[i]
		draw_rect(Rect2(x, cap, 1, _moss[i]), MOSS if i % 7 != 0 else MOSS_LIGHT)
		draw_rect(Rect2(x, crest, 1, 1), MOSS_SHADE)
		if _blades[i] > 0.0:
			draw_rect(Rect2(x, cap - _blades[i], 1, _blades[i]), MOSS_SHADE if i % 3 == 0 else MOSS)
	for fl: Array in _flowers:
		var p: Vector2 = fl[0]
		var i := clampi(int(p.x - _r.position.x), 0, _teeth.size() - 1)
		var at := Vector2(p.x, top - _teeth[i] - _moss[i] - 4.0)
		draw_rect(Rect2(at + Vector2(0, 2), Vector2(1, 2)), MOSS_SHADE)
		draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 2)), fl[1])
		draw_rect(Rect2(at, Vector2(1, 1)), FLOWERS[1] if fl[1] != FLOWERS[1] else FLOWERS[3])
	# vines down both faces, swaying a little and springing aside if you brush them
	for v: Array in _vines:
		var x0: float = v[0]
		var length: float = v[1]
		var phase: float = v[2]
		var bend: float = v[3]
		var anchor: float = v[5]
		for s in int(length):
			var k := s / length
			var off := roundf(bend * 10.0 * k * k + sin(_t * 1.1 + phase) * 1.0 * k)
			var p := Vector2(x0 + off, anchor + s)
			draw_rect(Rect2(p, Vector2(1, 1)), MOSS_SHADE)
			if s % 6 == 4:
				var side := -2.0 if int(s / 6.0) % 2 == 0 else 1.0
				draw_rect(Rect2(p + Vector2(side, 0), Vector2(2, 2)), MOSS)
				draw_rect(Rect2(p + Vector2(side, 0), Vector2(1, 1)), MOSS_LIGHT)
		var tip := Vector2(x0 + roundf(bend * 10.0 + sin(_t * 1.1 + phase) * 1.0), anchor + length)
		draw_rect(Rect2(tip + Vector2(-1, 0), Vector2(3, 3)), MOSS)

