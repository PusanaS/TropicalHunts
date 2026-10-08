extends Node2D
# QUICKSAND: a place where you can't just gallop (the professor's idea). Put it on a floor: origin at the
# left end of the sand, on the floor's top. The floor right under it should be its own body named
# "SandBed..." so no grass grows through it. look: "sand" (golden, Level 1) or "ash" (a hot ash bog, Level 3).
# While you stand in it:
#   - you can't run: you trudge, and speed never builds up (no run, sprint or gallop, so no flash either)
#   - running or galloping into it stops you dead in a spray of sand
#   - jumping out of it is weaker (your double jump still works), weaker still the deeper you've sunk
#   - stand still and it swallows you: you sink fast, the sand closes over your head in BURY_TIME and
#     you're sent back to the last checkpoint (in a scene without a level, it spits you back out).
#     Keep moving and you trudge on near the surface: moving digs you back up.
# Enemies aren't slowed: they know the ground. That's when the counter shines.
# PLACEHOLDER look, drawn in code.

@export var width := 480.0
@export var look := "sand"

const TRUDGE := 70.0              # top speed in it
const JUMP_SCALE := 0.72          # jumping out of it only gets this much of the jump
const STUCK_SPEED := 200.0        # arriving faster than this stops you dead
const SINK_MAX := 9.0             # how far you sink while trudging along (pixels)
const BURY_DEPTH := 44.0          # this deep and the sand has closed over your head
const BURY_TIME := 1.6            # standing still this long buries you
const DIG_OUT := 40.0             # moving digs you back up this fast (pixels a second)
const WARN_AT := 0.35             # this far down (of BURY_DEPTH): shudders, sand flicks up
const JUMP_SCALE_DEEP := 0.45     # the jump out when you're almost buried
const FILL := BURY_DEPTH + 8.0    # how far below the surface the sand is drawn (covers you when buried)
const BAND := 4.0                 # the surface stands this high over the floor (feet always a bit under)
const DRAIN_EVERY := 140.0        # a whirl that pulls the surface in, about this far apart
const LOOKS := {
	"sand": {"top": Color("efcf86"), "body": Color("d39b4a"), "shade": Color("a8722f"), "swirl": Color("f6e2ad"), "speck": Color("7a5225")},
	"ash": {"top": Color("9a94a2"), "body": Color("625b6b"), "shade": Color("443e4c"), "swirl": Color("bdb6c4"), "speck": Color("ff8a2a")},
}


var player: CharacterBody2D = null
var _was_on := false
var _sink := 0.0
var _t := 0.0
var _bits := []                   # sand flying: [pos (local), vel, life]
var _bubbles := []                # [x, start time]
var _warn_t := 0.0                # time to the next shudder while you're sinking deep
var _sprite: AnimatedSprite2D = null
var _sprite_y := 0.0              # the player sprite's normal height; it's lowered by _sink as you sink
var _lowered := false


func _ready():
	add_to_group("quicksand")     # (sand_serpent.gd's bite calls sink_player)
	z_index = 3                   # in front of the player's feet, so they look sunk in
	process_physics_priority = 10 # after the player has moved this frame


func _physics_process(delta: float):
	_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_sprite_y = _sprite.position.y
	var feet := player.global_position - global_position
	var inside := feet.x >= 0.0 and feet.x <= width and absf(feet.y) <= 6.0
	# (something holding you still, like the cactus chain, pauses your physics: the sand waits too)
	var on := inside and player.is_on_floor() and player.is_physics_processing()
	if on:
		if not _was_on and absf(player.velocity.x) > STUCK_SPEED:
			_stuck(feet, signf(player.velocity.x))
		player.speed_level = mini(player.speed_level, 1)
		player.hold_time = 0.0
		player.velocity.x = clampf(player.velocity.x, -TRUDGE, TRUDGE)
		var still := absf(player.velocity.x) < 5.0
		if still:                                     # standing still: it swallows you
			_sink = move_toward(_sink, BURY_DEPTH, BURY_DEPTH / BURY_TIME * delta)
		else:                                         # moving: you dig back up to trudging depth
			_sink = move_toward(_sink, SINK_MAX * 0.4, (DIG_OUT if _sink > SINK_MAX else 30.0) * delta)
		_sinking(feet, delta)
		if _sink >= BURY_DEPTH:
			_buried(feet)
			on = false                                # you're out of it now (sent back, or spat out)
	else:
		if _was_on and not player.is_on_floor() and player.velocity.y < -150.0:
			# jumped out: the sand holds you back, more the deeper you were
			player.velocity.y *= lerpf(JUMP_SCALE, JUMP_SCALE_DEEP, clampf(_sink / BURY_DEPTH, 0.0, 1.0))
			_spray(feet, 0.0, 6)
		_sink = move_toward(_sink, 0.0, 220.0 * delta)   # out of it: you pop back up quickly
	_was_on = on
	# you sink INTO the sand: the sprite goes down and the sand (drawn in front of you) hides what's under.
	# Only the picture moves; your body stays on the floor. Leaves the sprite alone once you're out.
	if _sink > 0.0 or _lowered:
		_sprite.position.y = _sprite_y + roundf(_sink)
		_lowered = _sink > 0.0
	if randf() < delta * width / 260.0:           # bubbles rise and pop now and then
		_bubbles.append([randf_range(4.0, width - 4.0), _t])
	_bubbles = _bubbles.filter(func(b): return _t - b[1] < 0.6)
	for b in _bits:
		b[0] += b[1] * delta
		b[1].y += 500.0 * delta
		b[2] -= delta
	_bits = _bits.filter(func(b): return b[2] > 0.0)
	queue_redraw()


# something dragged you down (a snake fruit's bite): you're this deep at once, if you're in this sand.
# Keep moving to dig out; standing still buries you the rest of the way.
func sink_player(depth: float):
	if player == null or not is_instance_valid(player):
		return
	var feet := player.global_position - global_position
	if feet.x < 0.0 or feet.x > width or absf(feet.y) > 6.0:
		return
	_sink = maxf(_sink, depth)
	_spray(feet, 0.0, 12)


# deep in it: shudders (faster and faster) and sand flicking up around you
func _sinking(feet: Vector2, delta: float):
	var depth := _sink / BURY_DEPTH
	if depth < WARN_AT:
		_warn_t = 0.0
		return
	_warn_t -= delta
	if _warn_t <= 0.0:
		_warn_t = lerpf(0.35, 0.12, depth)
		if player.has_method("_shake"):
			player._shake(1.0 + 3.0 * depth, 0.1)
		_spray(Vector2(feet.x, -BAND - _sink + 2.0), 0.0, 2)


# the sand has closed over your head: back to the last checkpoint (no level here: it spits you out)
func _buried(feet: Vector2):
	_spray(Vector2(feet.x, -BAND - _sink), 0.0, 16)
	_sink = 0.0
	_was_on = false
	if get_tree().get_first_node_in_group("level"):
		get_tree().call_group("level", "respawn_player")
	else:
		player.velocity = Vector2(0, -320)


# came in running: stopped dead, sand everywhere
func _stuck(feet: Vector2, dir: float):
	player.velocity.x *= 0.1
	player._shake(4.0, 0.15)
	_spray(feet, dir, 14)


func _spray(feet: Vector2, dir: float, count: int):
	for i in count:
		var v := Vector2(dir * randf_range(30, 140) + randf_range(-40, 40), randf_range(-160, -60))
		_bits.append([feet + Vector2(randf_range(-6, 6), -2), v, randf_range(0.3, 0.55)])


func _draw():
	var c: Dictionary = LOOKS.get(look, LOOKS["sand"])
	var px := -1000.0
	if player and is_instance_valid(player):
		px = player.global_position.x - global_position.x
	# below the surface: the sand you sink into. It's drawn in front of you, so as your sprite goes
	# down it hides whatever is under the surface. (It matches the sand bed under it.)
	draw_rect(Rect2(0, 0, width, FILL), c["body"])
	if _sink > 1.0 and px > -100.0:
		# a darker hole where you're going under, and a faint swirl around it
		var hole := 6.0 + minf(_sink, 10.0)
		draw_rect(Rect2(roundf(px - hole), 0, roundf(hole * 2.0), 2), c["shade"])
		var sw := fmod(_t * 3.0, 1.0)
		for side in [-1.0, 1.0]:
			var sx: float = px + side * (hole + 6.0) * (1.0 - sw)
			draw_rect(Rect2(roundf(sx), -BAND + 1.0, 3, 1), Color(c["swirl"], sw))
	# the surface: a slow wave along the top, with a little sand pushed up around you as you sink
	var reach := 9.0 + minf(_sink, 12.0) * 0.5
	var x := 0.0
	while x < width:
		var h := BAND + roundf(sin(_t * 1.6 + x * 0.09) * 0.6 + 0.4)
		var d := absf(x - px)
		if d < reach and d > reach * 0.35:
			h += roundf(minf(_sink, 6.0) * 0.5)
		draw_rect(Rect2(x, -h, 2, h), c["body"])
		draw_rect(Rect2(x, -h, 2, 1), c["top"])
		draw_rect(Rect2(x, -1, 2, 1), c["shade"])
		x += 2.0
	# flow lines drifting in toward each whirl, as if the sand's being sucked down
	var drains := maxi(1, int(width / DRAIN_EVERY))
	for k in drains:
		var cx := (k + 0.5) * width / drains
		for j in 3:
			var f := fmod(_t * 0.5 + j / 3.0, 1.0)
			for side in [-1.0, 1.0]:
				var dx: float = side * (1.0 - f) * 40.0
				draw_rect(Rect2(roundf(cx + dx), -BAND + 1.0, 3, 1), Color(c["swirl"], f * 0.9))
		draw_rect(Rect2(cx - 1, -BAND + 2.0, 3, 1), c["shade"])
	for b in _bubbles:
		var age: float = _t - float(b[1])
		var bx: float = b[0]
		if age < 0.4:
			draw_rect(Rect2(bx, -BAND - roundf(age * 5.0), 1, 1), c["speck"])
		else:                                     # pop
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)]:
				draw_rect(Rect2(Vector2(bx, -BAND - 2.0) + d * 2.0, Vector2(1, 1)), c["swirl"])
	for b in _bits:
		var p: Vector2 = b[0]
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(c["top"] if randf() < 0.5 else c["body"], clampf(float(b[2]) * 5.0, 0.0, 1.0)))
