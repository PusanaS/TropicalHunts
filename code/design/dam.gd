extends StaticBody2D
# THE DAM (level 1, Morgan's idea): just past the surf wall, a big wooden dam holds back a crowd of
# Mangos, piled up against it and itching to get at you. One diagonal plank braces it. Break the plank
# (any attack or a charged W in reach; galloping and the Thunderclap flash pass straight through it) and
# the dam groans and bulges, then bursts: the logs fly and the whole crowd comes pouncing down on you in
# slow motion, with a big Q / COUNTER! over your head once they're in reach (Morgan's call). Counter one
# and the chain cuts through the lot (counter_chain.gd chains the "dam_flood" group at speed).
# Origin: the dam's bottom-left corner, on the floor. The crowd piles up to its right, the brace leans
# on its left. Until the dam bursts the Mangos are only drawn, so a hundred of them cost nothing while
# they wait; then each one becomes a real fruit minion (scene/design/fruit_minion.tscn) where it stood.
# PLACEHOLDER art drawn in code: the dam, the plank and the debris (the Mangos use their own sheet).

enum Mode { HOLDING, STRAINING, BURST }

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const MANGO := preload("res://scene/design/fruit_minion.tscn")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const PUFF: Texture2D = preload("res://scene/design/art/dust_puff.png")      # 6 frames, 16x16
const SNAP_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")   # the plank snapping
const SNAP_SOUND_DB := -6.0
const SNAP_SOUND_SKIP := 0.02        # the file starts with 20ms of silence
const STRAIN_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")   # the dam groaning
const STRAIN_SOUND_DB := -4.0
const BURST_SOUND := preload("res://sounds/GATE_CRASH_dragon-studio-boom-crash-487664.mp3")
const BURST_SOUND_DB := 0.0

const DAM_W := 64.0
const DAM_H := 176.0                 # taller than a double jump (its collision goes on up, out of sight)
const LOGS := 8
const BEAMS := [24.0, 88.0, 150.0]   # crossbeam heights
const BRACE_FOOT := 104.0            # the plank's foot is this far left of the dam...
const BRACE_TOP := 112.0             # ...and it props the dam up this high
const BRACE_W := 8.0
const PILE_H := DAM_H - 8.0          # the crowd is piled this high against the dam (the top ones poke over)
const PILE_CELL := 17.2              # how tightly they're packed (the pile tails off as far as `count` needs)
const FLUSH := 10.0                  # a Mango this far from the dam (feet) has its body right on the logs
const SQUISH := 0.84                 # the column against the dam is squashed flat on it (x scale)
const MANGO_LEFT := 11.0             # from a Mango's feet to its front edge, facing left (its sheet)
const STRAIN_TIME := 0.7             # from the plank snapping to the dam bursting
const STRAIN_LEAN := 16.0            # how far the top bows out before it goes
const RELEASE_TIME := 0.2            # the whole crowd bursts out over this long (game time), front first
# each one jumps to its own height over you and comes down at its own spot, so when you counter they're
# scattered all over the sky, not bunched up (Morgan's call). Heights and spots are spread evenly.
const APEX := Vector2(60, 200)           # how high over you they jump (spread between these)
const LAND_SPREAD := Vector2(-200, 150)  # where they come down, either side of where you stand
const HOLD_SCALE := 0.2              # slow motion while they come down on you (re-applied every frame)
const HOLD_MAX := 8.0                # real seconds: the slow motion never lasts longer than this
const PROMPT := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]   # the COUNTER! text: fill, shade, light
const PIECE_GRAVITY := 900.0
const PIECE_LIFE := 3.0
const WOOD := Color(0.55, 0.35, 0.18)
const WOOD_LIGHT := Color(0.69, 0.48, 0.26)
const WOOD_DARK := Color(0.38, 0.25, 0.13)
const ROPE := Color(0.82, 0.74, 0.55)
const GAP := Color(0.13, 0.09, 0.06)
const BUMP_KICK := 70.0               # galloping into it: how hard it's shoved in (it wobbles back)
const BUMP_SPRING := 300.0
const BUMP_DAMP := 9.0
const Z_FX := 4                      # splinters and dust in front of the player (the dam itself is behind)

@export var count := 50              # how many Mangos it holds back (was 100: Morgan wanted fewer)
@export var layout_seed := 7

var player: CharacterBody2D = null
var _names: Array = []
var _mode: Mode = Mode.HOLDING
var _mode_t := 0.0
var _t := 0.0
var _lean := 0.0                     # how far the dam's top bows out towards you
var _jitter := 0.0
var _bump := 0.0                     # galloping into it shoves it in this far (a damped wobble)...
var _bump_v := 0.0
var _squash := 0.0                   # ...and squashes the Mangos against its back for a moment
var _last_pstate := -1
var _frames: SpriteFrames
var _crowd: Array = []               # the waiting Mangos: [feet (local), phase, animation, released?, against the dam?]
var _order: Array = []               # the order they pour out in: nearest the dam (and highest) first
var _released := 0
var _pile_len := 220.0                # how far behind the dam the pile tails off
var _logs: Array = []                # [x, width, height, stump height]
var _pieces: Array = []              # flying wood: [pos, vel, angle, spin, size, age]
var _holding := false                # the slow motion while they come down on you
var _hold_start := 0.0
var _prompt: Node2D                  # the Q / COUNTER! prompt, on its own layer above everything
var _prompt_on := false
var _shape: CollisionShape2D
var _snap_sound := AudioStreamPlayer.new()
var _strain_sound := AudioStreamPlayer.new()
var _burst_sound := AudioStreamPlayer.new()


func _ready():
	collision_layer = 1
	collision_mask = 0
	z_index = -1                     # behind the player
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(DAM_W, 800.0)
	_shape.shape = rect
	_shape.position = Vector2(DAM_W / 2.0, -400.0)
	add_child(_shape)
	for s: Array in [[_snap_sound, SNAP_SOUND, SNAP_SOUND_DB], [_strain_sound, STRAIN_SOUND, STRAIN_SOUND_DB],
			[_burst_sound, BURST_SOUND, BURST_SOUND_DB]]:
		s[0].stream = s[1]
		s[0].volume_db = s[2]
		add_child(s[0])
	_frames = _mango_frames()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var w := DAM_W / LOGS
	for i in LOGS:
		_logs.append([i * w, w, DAM_H + rng.randi_range(-4, 8), rng.randi_range(10, 22)])
	_pile_len = clampf(count * PILE_CELL * PILE_CELL * 2.5 / PILE_H, 60.0, 900.0)   # the pile's area fits `count`
	_build_crowd(rng)
	var layer := CanvasLayer.new()
	layer.layer = 20                 # over the level and its HUD
	add_child(layer)
	_prompt = Node2D.new()
	_prompt.draw.connect(_draw_prompt)
	layer.add_child(_prompt)


# the pile: highest against the dam, tailing off behind it, spaced so `count` of them fill it
func _build_crowd(rng: RandomNumberGenerator):
	var cell := PILE_CELL
	var spots: Array = []
	var row := 0
	var y := 0.0
	while y < PILE_H:
		# every row starts with one pressed flat against the dam
		spots.append([Vector2(DAM_W + FLUSH, -y - rng.randf_range(0.0, 2.0)), true])
		var x := DAM_W + FLUSH + cell * (1.5 if row % 2 == 1 else 1.0)
		while x < DAM_W + _pile_len:
			if y <= _pile_top(x - DAM_W):
				spots.append([Vector2(x + rng.randf_range(-3.0, 3.0), -y - rng.randf_range(0.0, 3.0)), false])
			x += cell
		y += cell
		row += 1
	while spots.size() > count:                              # too many: thin out the pile, never the wall
		var loose: Array = range(spots.size()).filter(func(i: int): return not spots[i][1])
		if loose.is_empty():
			break
		spots.remove_at(loose[rng.randi() % loose.size()])
	while spots.size() < count:
		var x := rng.randf_range(cell, _pile_len * 0.6)
		spots.append([Vector2(DAM_W + FLUSH + x, -rng.randf_range(0.0, _pile_top(x))), false])
	spots.sort_custom(func(a: Array, b: Array): return a[0].y < b[0].y)   # top first, so lower ones overlap them
	for spot: Array in spots:
		var p: Vector2 = spot[0]
		var anim := "IDLE"
		if p.x < DAM_W + 40.0:
			anim = "WINDUP"                                    # shoving against the dam
		elif -p.y > _pile_top(p.x - DAM_W) - cell * 1.5:
			anim = "RUN"                                       # scrambling on top of the pile
		_crowd.append([p, rng.randf(), anim, false, spot[1]])
	_order = range(_crowd.size())
	_order.sort_custom(func(a: int, b: int): return _pour_key(a) < _pour_key(b))


func _pour_key(i: int) -> float:
	var feet: Vector2 = _crowd[i][0]
	return feet.x + feet.y * 0.5


# the Mango's sheet, read from its scene without making one
func _mango_frames() -> SpriteFrames:
	var state := MANGO.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != "Sprite":
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == "sprite_frames":
				return state.get_node_property_value(i, j)
	return null


func _pile_top(d: float) -> float:
	return PILE_H * pow(clampf(1.0 - d / _pile_len, 0.0, 1.0), 1.5)


func _physics_process(delta: float):
	_t += delta
	_mode_t += delta
	_update_pieces(delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
	_bump_v += (-_bump * BUMP_SPRING - _bump_v * BUMP_DAMP) * delta
	_bump += _bump_v * delta
	_squash = move_toward(_squash, 0.0, delta * 3.0)
	var ps: int = player.state
	if ps != _last_pstate:
		_last_pstate = ps
		if _names[ps] == "KNOCKBACK" and _mode != Mode.BURST:
			_gallop_bump()
	match _mode:
		Mode.HOLDING:
			_jitter = 1.0 if fmod(_t, 1.7) < 0.08 else 0.0      # a creak now and then
			_lean = 2.0
			_check_hits()
		Mode.STRAINING:
			var k := clampf(_mode_t / STRAIN_TIME, 0.0, 1.0)
			_lean = lerpf(4.0, STRAIN_LEAN, k * k)
			_jitter = float(randi_range(-1, 1)) * (1.0 + k)
			if _mode_t >= STRAIN_TIME:
				_burst()
		Mode.BURST:
			# the crowd pours out, front of the pile first
			var due := mini(_crowd.size(), int(ceilf(_mode_t / RELEASE_TIME * _crowd.size())))
			while _released < due:
				_release(_order[_released])
				_released += 1
	queue_redraw()


# ---------- breaking the brace ----------
# only a real swing or a charged W breaks it. Galloping and the Thunderclap flash go straight through
# (Morgan's call): the flash's dash happens with time stopped, so nothing counts while it is.
func _check_hits():
	if Engine.time_scale == 0.0:
		return
	var foot := global_position.x - BRACE_FOOT
	var box := Rect2(global_position + Vector2(-BRACE_FOOT, -BRACE_TOP), Vector2(BRACE_FOOT, BRACE_TOP))
	if not EnemyKit.player_attack_hitting(player, _names, box).is_empty():
		_snap()
		return
	var px := player.global_position.x
	if _names[player.state] == "CHARGED_SMASH":
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var charge: float = player.charge
		if absf(px - (foot + BRACE_FOOT / 2.0)) <= lerpf(radius.x, radius.y, charge):
			_snap()


func _snap():
	_mode = Mode.STRAINING
	_mode_t = 0.0
	_snap_sound.play(SNAP_SOUND_SKIP)
	_strain_sound.play()
	EnemyKit.hitstop(get_tree(), 0.08)
	_shake(6.0, 0.2)
	_shake_later(3.0, STRAIN_TIME, 0.2)
	# the plank breaks in the middle: the bottom half kicks away, the top half drops
	var foot := Vector2(-BRACE_FOOT, 0.0)
	var top := Vector2(_off(BRACE_TOP), -BRACE_TOP)
	var length := foot.distance_to(top)
	var angle := (top - foot).angle()
	var size := Vector2(length / 2.0, BRACE_W)
	_pieces.append([foot.lerp(top, 0.25), Vector2(-170, -150), angle, -7.0, size, 0.0])
	_pieces.append([foot.lerp(top, 0.75), Vector2(-50, -60), angle, 5.0, size, 0.0])
	_splinters(foot.lerp(top, 0.5), Vector2(-1, -0.6), 1.0)


# ---------- the dam bursting ----------
func _burst():
	_mode = Mode.BURST
	_mode_t = 0.0
	_shape.set_deferred("disabled", true)
	var t := _strain_sound.create_tween()
	t.tween_property(_strain_sound, "volume_db", -40.0, 0.4)
	t.tween_callback(_strain_sound.stop)
	_burst_sound.play()
	# every log above its stump breaks into chunks that fly out at you, higher ones further
	for lg: Array in _logs:
		var x: float = lg[0]
		var w: float = lg[1]
		var h := float(lg[3])
		while h < float(lg[2]):
			var chunk := minf(randf_range(26.0, 48.0), float(lg[2]) - h)
			var mid := h + chunk / 2.0
			_pieces.append([Vector2(x + w / 2.0 + _off(mid), -mid), Vector2(-randf_range(120.0, 420.0) - mid * 1.2, -randf_range(60.0, 380.0)),
				randf_range(-0.3, 0.3), randf_range(-12.0, 12.0), Vector2(w - 1.0, chunk), 0.0])
			h += chunk
	for b: float in BEAMS:
		_pieces.append([Vector2(DAM_W / 2.0 + _off(b), -b), Vector2(-randf_range(100.0, 300.0), -randf_range(150.0, 350.0)),
			0.0, randf_range(-6.0, 6.0), Vector2(DAM_W + 8.0, 6.0), 0.0])
	_splinters(Vector2(DAM_W / 2.0, -DAM_H / 2.0), Vector2(-1, -0.4), 1.8)
	for i in 8:
		_puff(Vector2(randf_range(0.0, DAM_W), 0.0), Vector2(-randf_range(60.0, 220.0), -randf_range(0.0, 30.0)), i * 0.03)
	get_tree().call_group("living_background", "burst", global_position, 7.0)
	_shake(14.0, 0.5)
	EnemyKit.protect_player(HOLD_MAX)    # they pass through you while they fall, so they stay counterable
	_holding = true
	_hold_start = _real()
	Engine.time_scale = HOLD_SCALE


# one waiting Mango becomes a real one, pouncing in an arc that comes down on the player
func _release(i: int):
	var c: Array = _crowd[i]
	c[3] = true
	var feet: Vector2 = c[0]
	var parent := (owner.get_node_or_null("Enemies") if owner else null) as Node2D
	if parent == null:
		parent = get_parent() as Node2D
	var m: FruitMinion = MANGO.instantiate()
	m.respawn_time = 0.0             # stays dead
	m.sight_range = 420.0            # keeps coming at you across the whole flood
	m.patrol_range = 160.0
	m.facing = -1
	m.position = parent.to_local(to_global(feet))
	parent.add_child(m)
	m.add_to_group("dam_flood")      # counter_chain.gd chains these at speed
	m._set_state(FruitMinion.State.LUNGE)      # mid-pounce: counterable until it lands (then dizzy, then it chases)
	# its own height and landing spot, stepped through evenly in both (an R2 sequence), so the sky fills up
	var k := float(_released)
	var from := m.global_position
	# the world's gravity (a Mango that was only just added has no physics yet: its own get_gravity() is zero,
	# and the arc below would divide by it)
	var g: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var top := player.global_position.y - lerpf(APEX.x, APEX.y, fmod(0.5 + k * 0.7548777, 1.0)) - randf_range(0.0, 12.0)
	top = minf(top, from.y - 20.0)                                   # always up out of the pile first
	var to := player.global_position + Vector2(lerpf(LAND_SPREAD.x, LAND_SPREAD.y, fmod(0.5 + k * 0.5698403, 1.0)) + randf_range(-10.0, 10.0), 0.0)
	var up := sqrt(2.0 * g * (from.y - top))
	var t := maxf(up / g + sqrt(2.0 * maxf(to.y - top, 0.0) / g), 0.1)
	m.velocity = Vector2((to.x - from.x) / t, -up)


# ---------- the slow motion and the Q prompt ----------
func _real() -> float:
	return Time.get_ticks_msec() / 1000.0


# runs every frame on real time: keeps the slow motion going (hit-freezes reset it) until the counter
# takes over, or they've all landed
func _process(_delta: float):
	if not _holding:
		return
	if Engine.time_scale == 0.0:         # the counter (or the flash) stopped time: it restarts it itself
		_end_hold(false)
		return
	var falling := false
	var ready := false
	var reach: float = player.get_script().COUNTER_RANGE if player else 0.0
	for m in get_tree().get_nodes_in_group("dam_flood"):
		if m.is_counterable():
			falling = true
			if player and m.global_position.distance_to(player.global_position) <= reach:
				ready = true
				break
	if (_released >= _crowd.size() and not falling) or _real() - _hold_start > HOLD_MAX:
		_end_hold(true)                  # they've landed and you didn't counter
		return
	Engine.time_scale = HOLD_SCALE
	_prompt_on = ready
	_prompt.queue_redraw()


func _end_hold(ease_out: bool):
	_holding = false
	_prompt_on = false
	_prompt.queue_redraw()
	if ease_out:                         # back up to speed over a moment (real-time timers, bound to Engine)
		Engine.time_scale = 0.45
		get_tree().create_timer(0.15, true, false, true).timeout.connect(Callable(Engine, "set").bind("time_scale", 1.0))


func _exit_tree():
	if _holding:                         # removed mid-flood (scene reload): never leave the game slowed
		Engine.time_scale = 1.0


# a big Q key over the player's head, acting out the press, with COUNTER! under it
func _draw_prompt():
	if not _prompt_on or player == null:
		return
	var t := _real()
	var feet := get_viewport().get_canvas_transform() * player.global_position
	var bounce := roundf(sin(t * 10.0) * 2.0)
	var text_w := Pixel.width("COUNTER!", 2)
	var text_y := feet.y - 58.0 + bounce
	_prompt.draw_set_transform(Vector2(roundf(feet.x - 13.0), text_y - 36.0), 0.0, Vector2(2, 2))
	Pixel.draw_key(_prompt, Vector2.ZERO, 13, "Q", fmod(t, 0.4) < 0.15, true)
	_prompt.draw_set_transform(Vector2.ZERO)
	Pixel.draw_cells(_prompt, Pixel.cells("COUNTER!", Vector2(roundf(feet.x - text_w / 2.0), text_y), 2), PROMPT)


# galloping into the dam (the player bounces off it into KNOCKBACK): it doesn't give, but it shudders in,
# the Mangos behind it get squashed, and splinters fly back off the logs where you hit (Morgan's call)
func _gallop_bump():
	var at := to_local(player.global_position)
	if at.x < -40.0 or at.x > DAM_W or at.y < -DAM_H - 10.0 or at.y > 10.0:
		return
	var hit := Vector2(_off(20.0) - 1.0, clampf(at.y - 22.0, -DAM_H + 6.0, -6.0))   # its face, at your chest
	_bump_v += BUMP_KICK
	_squash = 1.0
	_splinters(hit, Vector2(-1, -0.5), 1.2)
	for i in 7:                                                     # bigger chips that tumble and bounce
		_pieces.append([hit + Vector2(randf_range(-2.0, 2.0), randf_range(-8.0, 8.0)),
			Vector2(-randf_range(60.0, 200.0), -randf_range(80.0, 260.0)), randf() * TAU, randf_range(-14.0, 14.0),
			Vector2(randf_range(2.0, 4.0), randf_range(4.0, 8.0)), 0.0])
	for i in 3:
		_puff(Vector2(randf_range(-6.0, 4.0), 0.0), Vector2(-randf_range(40.0, 120.0), -randf_range(0.0, 20.0)), i * 0.04)


# ---------- effects ----------
func _shake(strength: float, seconds: float):
	if player and player.has_method("_shake"):
		player._shake(strength, seconds)


func _shake_later(strength: float, seconds: float, delay: float):
	get_tree().create_timer(delay).timeout.connect(_shake.bind(strength, seconds))


func _splinters(at: Vector2, dir: Vector2, power: float):
	for color: Color in [WOOD_LIGHT, WOOD, WOOD_DARK]:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = int(14 * power)
		p.lifetime = 0.9
		p.explosiveness = 1.0
		p.gravity = Vector2(0, 800)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.0
		p.color = color
		p.z_index = Z_FX
		p.position = at
		p.direction = dir
		p.spread = 50.0
		p.initial_velocity_min = 140.0 * power
		p.initial_velocity_max = 360.0 * power
		p.finished.connect(p.queue_free)
		add_child(p)
		p.emitting = true


# a dust puff at 2x (whole pixels), bottom on the floor; frames play while it drifts
func _puff(offset: Vector2, vel: Vector2, delay: float):
	var s := Sprite2D.new()
	s.texture = PUFF
	s.hframes = 6
	s.scale = Vector2(2, 2)
	s.offset = Vector2(0, -8)
	s.flip_h = vel.x < 0.0
	s.z_index = Z_FX
	add_child(s)
	s.position = offset
	var t := s.create_tween()
	if delay > 0.0:
		s.visible = false
		t.tween_interval(delay)
		t.tween_callback(s.show)
	t.tween_property(s, "frame", 5, 0.45).from(0)
	t.parallel().tween_property(s, "position", (offset + vel * 0.45).round(), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(s.queue_free)


# wood flies, spins, bounces and skids on the floor, then fades
func _update_pieces(delta: float):
	for p: Array in _pieces:
		p[5] += delta
		p[1].y += PIECE_GRAVITY * delta
		p[0] += p[1] * delta
		p[2] += p[3] * delta
		var s: Vector2 = p[4]
		var rest := minf(s.x, s.y) / 2.0
		if p[0].y > -rest and p[1].y > 0.0:
			p[0].y = -rest
			p[1].y *= -0.35
			p[1].x *= 0.6
			p[3] *= 0.6
	_pieces = _pieces.filter(func(p): return p[5] < PIECE_LIFE)


# ---------- drawing ----------
# how far the dam bows out at this height (its top leans towards you; a shudder moves all of it)
func _off(h: float) -> float:
	return -roundf(_lean * pow(clampf(h / DAM_H, 0.0, 1.0), 1.5)) + _jitter + roundf(_bump)


func _draw():
	_draw_crowd()
	if _mode == Mode.BURST:
		for lg: Array in _logs:                                   # jagged stumps
			_draw_log(lg[0], lg[1], float(lg[3]), false)
	else:
		_draw_dam()
		if _mode == Mode.HOLDING:
			_draw_brace()
	for p: Array in _pieces:
		var a := 1.0 - clampf((float(p[5]) - (PIECE_LIFE - 0.6)) / 0.6, 0.0, 1.0)
		var s: Vector2 = p[4]
		draw_set_transform(p[0], p[2])
		draw_rect(Rect2(-s / 2.0, s), Color(WOOD, a))
		draw_rect(Rect2(Vector2(-s.x / 2.0, s.y / 2.0 - 2.0), Vector2(s.x, 2.0)), Color(WOOD_DARK, a))
		draw_rect(Rect2(-s / 2.0, Vector2(s.x, 1.0)), Color(WOOD_LIGHT, a))
	draw_set_transform(Vector2.ZERO)


# they lean on the dam: the column against it is squashed flat on the logs and follows them as the dam
# bows, and the rest of the pile shoves along behind
func _draw_crowd():
	var hurry := 2.0 if _mode == Mode.STRAINING else 1.0
	for c: Array in _crowd:
		if c[3]:
			continue
		var anim: String = c[2]
		var phase: float = c[1]
		var n := _frames.get_frame_count(anim)
		var f := int(_t * _frames.get_animation_speed(anim) * hurry + phase * 10.0) % n
		var feet: Vector2 = c[0]
		var wall := _off(-feet.y + 14.0)                             # where the dam's back is at its middle
		var bob := roundf(sin(_t * 5.0 * hurry + phase * TAU) * 0.6)
		var flip := Vector2(-1, 1)                                   # facing left, at you (the art faces right)
		var x := feet.x
		if c[4]:
			var squish := SQUISH + 0.05 * sin(_t * 7.0 * hurry + phase * TAU) - 0.14 * _squash   # shoving in pulses
			flip = Vector2(-squish, 1.0 + (1.0 - squish) * 0.6)
			x = DAM_W - 1.0 + MANGO_LEFT * squish + wall              # its front right on the logs
		else:
			x += wall * clampf(1.0 - (feet.x - DAM_W) / _pile_len, 0.0, 1.0)
		draw_set_transform(Vector2(x, feet.y + bob).round(), 0.0, flip)
		draw_texture(_frames.get_frame_texture(anim, f), Vector2(-20, -36))
	draw_set_transform(Vector2.ZERO)


func _draw_dam():
	for lg: Array in _logs:
		_draw_log(lg[0], lg[1], float(lg[2]), true)
	for b: float in BEAMS:                                          # crossbeams, lashed to every log
		var x := _off(b)
		draw_rect(Rect2(x - 4.0, -b - 3.0, DAM_W + 8.0, 6.0), WOOD_LIGHT)
		draw_rect(Rect2(x - 4.0, -b + 2.0, DAM_W + 8.0, 1.0), WOOD_DARK)
		for lg: Array in _logs:
			draw_rect(Rect2(x + float(lg[0]) + 3.0, -b - 4.0, 2.0, 8.0), ROPE)


# one log, from the ground up to `height`, bowing with the dam; pointed on top (or jagged, as a stump)
func _draw_log(x: float, w: float, height: float, whole: bool):
	var band := 8.0
	var h := 0.0
	while h < height:
		var bh := minf(band, height - h)
		var lx := x + _off(h + bh / 2.0) if whole else x
		draw_rect(Rect2(lx, -h - bh, w - 1.0, bh), WOOD)
		draw_rect(Rect2(lx, -h - bh, 1.0, bh), WOOD_LIGHT)
		draw_rect(Rect2(lx + w - 3.0, -h - bh, 2.0, bh), WOOD_DARK)
		draw_rect(Rect2(lx + w - 1.0, -h - bh, 1.0, bh), GAP)
		if int(h + x * 3.0) % 40 < 8 and h > 0.0:                   # a bark ring now and then
			draw_rect(Rect2(lx, -h - 1.0, w - 1.0, 1.0), WOOD_DARK)
		h += bh
	var tx := x + _off(height) if whole else x
	if whole:                                                       # sharpened tip
		draw_rect(Rect2(tx + 1.0, -height - 2.0, w - 3.0, 2.0), WOOD)
		draw_rect(Rect2(tx + 2.0, -height - 4.0, w - 5.0, 2.0), WOOD_LIGHT)
	else:                                                           # broken: splintered teeth
		draw_rect(Rect2(tx, -height - 3.0, 2.0, 3.0), WOOD_LIGHT)
		draw_rect(Rect2(tx + w - 4.0, -height - 2.0, 2.0, 2.0), WOOD)


func _draw_brace():
	var foot := Vector2(-BRACE_FOOT, 0.0)
	var top := Vector2(_off(BRACE_TOP), -BRACE_TOP)
	var across := (top - foot).normalized().orthogonal() * BRACE_W / 2.0
	draw_colored_polygon(PackedVector2Array([foot - across, top - across, top + across, foot + across]), WOOD)
	draw_line(foot + across, top + across, WOOD_DARK, 1.0)
	draw_line(foot - across, top - across, WOOD_LIGHT, 1.0)
	draw_rect(Rect2(top + Vector2(-5, -2), Vector2(1, 1)), GAP)     # nails
	draw_rect(Rect2(top + Vector2(-5, 2), Vector2(1, 1)), GAP)
	draw_rect(Rect2(foot + Vector2(-4, -5), Vector2(4, 6)), WOOD_DARK)   # the stake holding its foot
