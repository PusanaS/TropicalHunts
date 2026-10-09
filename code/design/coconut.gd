extends CharacterBody2D
# COCONUT: Level 2's armoured fruit. It's hard and SOLID (collision layer 1, like the level), so the player
# can't walk through it, and galloping into it knocks them back like a wall. The Thunderclap flash never
# fires on it either: you smack into it instead. PLACEHOLDER look, drawn in code in BOOM's palette.
#
# Monster card
#   Moves:     "sit": sits in the way. "roll": once it sees you on its level, it rolls at you and keeps
#              rolling, bouncing off walls (and off you) and dropping off ledges.
#   Notices:   roll mode only: the player within sight_range at about its height.
#   Attack:    rolling into you. The warning: it wobbles for a moment before it sets off.
#   After:     it never stops rolling until it's broken.
#   Beaten by: heavy hits. Q (and the rolling slash) clang off and knock you back. A W (smash, leap slam,
#              air slam, charged smash, a W wave) cracks it; any hit after that breaks it. Or jump over it.
#              With gallop_breaks (the ones the grove's palms drop, coconut_drop.gd; Morgan's call,
#              2026-10-09), galloping at it sets off the Thunderclap flash like a Mango (it splits along the
#              slash), and one the flash doesn't catch (falling on you, say) smashes as you gallop into it,
#              just before you touch it, so you keep your speed.
#   Touch:     solid. Sitting: harmless, it just blocks. Rolling: hurts.
#   Drops:     one juice drop (coconut water).
#   Animations BOOM and Violeta will need: IDLE (sitting), WOBBLE (about to roll), ROLL (spinning),
#              CLANG (a light hit bouncing off), CRACKED (idle and rolling, with a crack), BREAK (two halves
#              and a splash)

enum State { SIT, WOBBLE, ROLL, BROKEN }

@export var mode := "sit"                    # "sit" or "roll"
@export var sight_range := 260.0             # roll mode: starts rolling when the player is this close
@export var roll_speed := 230.0
@export var wobble_time := 0.35              # the warning before it rolls
@export var respawn_time := 0.0              # comes back after this long, 0 = stays broken (and is freed)
@export var juice_color := Color(0.86, 0.93, 0.95)    # coconut water
@export var gallop_breaks := false           # galloping into it smashes it (instead of knocking you back)

const RADIUS := 11.0
const SIGHT_HEIGHT := 40.0
const FLOOR_FRICTION := 700.0
const HURTBOX := Rect2(-12, -24, 24, 25)      # where the player can hit it (a little over the shell)
const TOUCH_BOX := Rect2(-13, -24, 26, 26)    # rolling: touching this hurts
const ARMOR_PUSHBACK := 220.0                 # a light hit bouncing off knocks the player back (like the boss)
const GALLOP_REACH := 24.0                    # gallop_breaks: this close ahead of you it smashes (as the barricades)
const PLAYER_HALF_WIDTH := 13.0
const PLAYER_HEIGHT := 40.0
const HITSTOP_CRACK := 0.06
const HITSTOP_BREAK := 0.09
const HITSTOP_GALLOP := 0.025
# hits that crack it (the rest clang off). Anything else hitting it through take_hit counts as heavy when it
# does 2 damage or more (the charged smash, W waves).
const HEAVY_MOVES := ["ATTACK_HEAVY_SMASH", "DASH_ATTACK_HEAVY_IMPACT", "DASH_ATTACK_HEAVY_SLAM", "CHARGED_SMASH"]
const JuiceDrop := preload("res://code/design/juice_drop.gd")
const EnemyKit := preload("res://code/design/enemy_kit.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const ARMOR_SOUND := preload("res://sounds/sword/sword_clash_06.wav")    # the boss's armour clang
const ARMOR_SOUND_DB := -6.0
const ARMOR_SOUND_SKIP := 0.012               # the clang gets loud 13ms in
const CRACK_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const CRACK_SOUND_DB := -9.0
const CRACK_SOUND_SKIP := 0.02                # the file starts with 20ms of silence
const SPLASH_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const SPLASH_SOUND_DB := -4.0
const SPLASH_SOUND_SKIP := 0.12               # 0.12 s of silence first

# placeholder palette: brown hairy shell, dark eyes, white flesh in the crack
const SHELL := Color("624021")
const SHELL_DARK := Color("4d321a")
const HAIR := Color("8a6338")
const FLESH := Pixel.OFF_WHITE
const OUTLINE := Color("c8a070")    # a 1px light brown outline round the shell, so it reads (Morgan's call:
                                    # it was white, which stuck out too much)

var state: State = State.SIT
var state_time := 0.0
var hp := 2                       # 2 = whole, 1 = cracked, 0 = broken (the combo HUD counts each drop)
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _names: Array = []
var _top_level := 4
var _top_speed := 600.0
var _dir := -1.0                  # which way it rolls
var _start_dir := 0.0             # coconut_drop.gd: set before it's added, so it rolls the moment it lands
var _marked_until := -1.0         # the flash's slash is on it: it holds still till its cut lands (real time)
var _walls_hit := 0               # a dropped coconut cracks open on its second wall (or it would roll forever)
var _spin := 0.0                  # how far round it has rolled (radians)
var _roll_v := 230.0              # how fast it's rolling now (roll_speed on the flat)
var _through := false             # you're galloping: it isn't solid to you (_see_through)
var _flash := 0.0
var _last_state := -1
var _last_time := 0.0
var _hit_this_swing := false
var _shape: CollisionShape2D
var _armor_sound := AudioStreamPlayer.new()
var _crack_sound := AudioStreamPlayer.new()
var _splash_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")
	for other in get_tree().get_nodes_in_group("coconut"):     # coconuts roll through each other (a grove
		add_collision_exception_with(other)                     # full of them bounced and cracked off each
		other.add_collision_exception_with(self)                # other)
	add_to_group("coconut")
	collision_layer = 1           # solid like the level: the player can't pass, galloping into it knocks them back
	collision_mask = 1
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	_shape.shape = circle
	_shape.position = Vector2(0, -RADIUS)
	add_child(_shape)
	home = global_position
	_roll_v = roll_speed
	for p in [[_armor_sound, ARMOR_SOUND, ARMOR_SOUND_DB], [_crack_sound, CRACK_SOUND, CRACK_SOUND_DB],
			[_splash_sound, SPLASH_SOUND, SPLASH_SOUND_DB]]:
		var s: AudioStreamPlayer = p[0]
		s.stream = p[1]
		s.volume_db = p[2]
		s.max_polyphony = 3
		add_child(s)
	if _start_dir != 0.0:
		_dir = signf(_start_dir)
		mode = "roll"
		_set_state(State.ROLL)


# coconut_drop.gd: drop it already rolling this way (call before adding it)
func start_rolling(dir: float, spin := 0.0):
	_start_dir = dir
	_spin = spin                  # (the palm drops it hanging upright, its eyes at the top)


# the flash only goes for enemies that are alive: while the player gallops a solid one isn't, so they
# smack into it instead (a solid body on layer 1 knocks a gallop back). A gallop_breaks one (the grove's)
# is, so galloping at it sets off the Thunderclap flash like a Mango (Morgan's call, 2026-10-09): you dash
# through it with time stopped, and it splits along your slash (cut_in_half)
func is_alive() -> bool:
	if state == State.BROKEN:
		return false
	if player and player.speed_level >= _top_level and not gallop_breaks:
		return false
	return true


func _set_state(s: State):
	state = s
	state_time = 0.0


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_names = player.get_script().State.keys()
		var speeds: Array = player.get_script().SPEEDS
		_top_level = speeds.size() - 1
		_top_speed = speeds[_top_level]


func _physics_process(delta: float):
	state_time += delta
	_flash -= delta
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	if state == State.BROKEN:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		elif respawn_time <= 0.0 and state_time >= 1.0:
			queue_free()          # (waits a moment, so the combo counter sees its last hit)
		return

	if _marked_until > 0.0:
		if Time.get_ticks_msec() / 1000.0 < _marked_until:
			velocity = Vector2.ZERO          # held under the flash's slash
			return
		_marked_until = -1.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	if player:
		if gallop_breaks:
			_see_through(_galloping())
		_check_player_attack()
		if state == State.BROKEN:
			return
		if gallop_breaks and _galloped_into(delta):
			hp = 0                          # (the combo counts it)
			_break(true, true)
			return

	match state:
		State.SIT:
			velocity.x = move_toward(velocity.x, 0.0, FLOOR_FRICTION * delta)
			if mode == "roll" and _sees_player():
				_dir = signf(player.global_position.x - global_position.x)
				if _dir == 0.0:
					_dir = -1.0
				_set_state(State.WOBBLE)
		State.WOBBLE:
			velocity.x = 0.0
			if state_time >= wobble_time:
				_set_state(State.ROLL)
		State.ROLL:
			if is_on_floor():                      # faster rolling downhill, slower uphill (the grove's dunes)
				var slope := get_floor_normal().x * _dir
				_roll_v = move_toward(_roll_v, roll_speed * clampf(1.0 + 2.4 * slope, 0.45, 2.0), 900.0 * delta)
				velocity.x = _dir * _roll_v

	move_and_slide()

	if state == State.ROLL:
		_spin += velocity.x / RADIUS * delta
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			if absf(c.get_normal().x) > 0.7 and c.get_normal().x * _dir < 0.0:
				if c.get_collider() == player:
					_hurt_player()           # it bounces off you either way
				else:
					_walls_hit += 1
					if _start_dir != 0.0 and _walls_hit >= 2:
						_break(false)
						break
				_dir = -_dir
				velocity.x = _dir * roll_speed
				break
		if state == State.ROLL:
			_hurt_player()
	queue_redraw()


# galloping into it (gallop_breaks): a gallop, heading its way, and it's just ahead at your height (or
# coming down on you). It closes in from both sides, so the reach grows with both speeds
# (Only the gallop counts, not how fast you're going sideways: up a steep dune it dips, and a coconut it
# missed hit you. One touching you counts whichever way you face. Morgan's catch, 2026-10-09)
func _galloped_into(delta: float) -> bool:
	if not _galloping() or Engine.time_scale == 0.0:
		return false                       # (not while the flash has time stopped: it cuts it itself)
	var dir := signf(player.velocity.x) if absf(player.velocity.x) > 60.0 else float(player.facing)
	var d := global_position - player.global_position
	if d.y > 2.0 * RADIUS + 10.0 or d.y < -PLAYER_HEIGHT - 8.0:
		return false                       # above or below you
	if absf(d.x) < RADIUS + PLAYER_HALF_WIDTH:
		return true                        # touching you
	var gap := d.x * dir - RADIUS - PLAYER_HALF_WIDTH
	if gap < 0.0:
		return false                       # behind you
	return gap < GALLOP_REACH + (absf(player.velocity.x) + absf(velocity.x)) * delta


func _galloping() -> bool:
	return player != null and player.speed_level >= _top_level


# a gallop_breaks coconut is never solid to you while you gallop (it either smashes or you go through): its
# body only went at the end of the frame it smashed in, and your gallop that frame hit it like a wall
# (knocked back, dazed). Both ways round: you skip it and it skips you
func _see_through(on: bool):
	if on == _through:
		return
	_through = on
	if on:
		add_collision_exception_with(player)
		player.add_collision_exception_with(self)
	else:
		remove_collision_exception_with(player)
		player.remove_collision_exception_with(self)


func _sees_player() -> bool:
	if player == null:
		return false
	var d := player.global_position - global_position
	return absf(d.y) <= SIGHT_HEIGHT and absf(d.x) <= sight_range


func _hurt_player():
	if player == null or (gallop_breaks and _galloping()):
		return                               # (galloping, they never hurt you: they smash)
	var box := Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size)
	EnemyKit.hurt_player(player, box.grow(2.0), global_position.x)


# ---------- getting hit ----------
# same "new swing" rule as the fruit minion: a new state, or the same one restarted
func _check_player_attack():
	var ps: int = player.state
	var pt: float = player.state_time
	if ps != _last_state or pt < _last_time:
		_hit_this_swing = false
	_last_state = ps
	_last_time = pt
	if _hit_this_swing:
		return
	var hit := EnemyKit.player_attack_hitting(player, _names, Rect2(global_position + HURTBOX.position, HURTBOX.size))
	if hit.is_empty():
		return
	_hit_this_swing = true
	var heavy: bool = _names[ps] in HEAVY_MOVES
	if not heavy and hp >= 2 and player.has_method("bounce_back"):
		player.bounce_back(global_position.x, ARMOR_PUSHBACK)    # a light hit bounces off the shell
	_hit(heavy)


# from outside (the charged smash, W waves, the flash): 2 damage or more counts as heavy
func take_hit(damage: int, _push: Vector2):
	_hit(damage >= 2)


func _hit(heavy: bool):
	if state == State.BROKEN:
		return
	if hp >= 2 and not heavy:              # whole shell, light hit: clang
		_armor_sound.play(ARMOR_SOUND_SKIP)
		_flash = 0.06
		_burst(Pixel.OFF_WHITE, Vector2(0, -RADIUS), 7, 1.0)
		return
	hp -= 1
	if hp <= 0:
		_break()
		return
	# cracked: still solid, still rolling, but the next hit of any kind breaks it
	_crack_sound.play(CRACK_SOUND_SKIP)
	_flash = 0.08
	_burst(FLESH, Vector2(0, -RADIUS), 8, 2.0)
	EnemyKit.hitstop(get_tree(), HITSTOP_CRACK)
	if player:
		player._shake(4.0, 0.15)


# flash_finish.gd: the flash's slash was just drawn across it. It holds still (no rolling, falling or
# turning) until its cut lands as time restarts, so it splits right under the slash you saw (it used to roll
# on out from under it while the cuts before it landed; Morgan's catch, 2026-10-09). 3 real seconds at most,
# in case the cut never comes
func flash_marked():
	_marked_until = Time.get_ticks_msec() / 1000.0 + 3.0


# the Thunderclap flash's cut (flash_finish.gd calls it, as on a Mango): it splits along the slash you saw,
# at the slash's slope through its middle
func cut_in_half(_facing: int, a := Vector2.INF, b := Vector2.INF):
	if state == State.BROKEN:
		return
	hp = 0
	var along := Vector2(1, -0.5).normalized()
	if a != Vector2.INF and b != Vector2.INF and a != b:
		along = (b - a).normalized()
	_break(true, false, along)


# by_player false: it cracked on a wall by itself (no freeze or shake, wherever the player is). galloped: you
# smashed through it at a gallop: a lighter freeze and shake (a grove's worth in a row), and it all flies on
# ahead of you. cut: the flash's slash (its direction): the halves split along it instead, as a Mango's do
func _break(by_player := true, galloped := false, cut := Vector2.ZERO):
	_set_state(State.BROKEN)
	velocity = Vector2.ZERO
	_shape.set_deferred("disabled", true)
	if player and is_instance_valid(player):
		player.add_collision_exception_with(self)    # (gone for you this frame already, not at its end)
	visible = false
	if by_player or (player and global_position.distance_to(player.global_position) < 400.0):
		_crack_sound.play(CRACK_SOUND_SKIP)
		_splash_sound.play(SPLASH_SOUND_SKIP)
	if cut != Vector2.ZERO:
		EnemyKit.hitstop(get_tree(), HITSTOP_GALLOP)       # (the flash shakes the screen itself)
	elif galloped:
		EnemyKit.hitstop(get_tree(), HITSTOP_GALLOP)
		if player:
			player._shake(4.0, 0.12)
	elif by_player:
		EnemyKit.hitstop(get_tree(), HITSTOP_BREAK)
		if player:
			player._shake(7.0, 0.2)
	var away := signf(global_position.x - player.global_position.x) if player else _dir
	if galloped:
		away = signf(player.velocity.x)
	if away == 0.0:
		away = 1.0
	# the shell splits in two halves that fly off, spinning (well on ahead of a gallop), or slide apart along
	# the flash's cut
	if cut != Vector2.ZERO:
		_cut_halves(cut, away)
	else:
		var fling := 2.6 if galloped else 1.0
		for side in [-1.0, 1.0]:
			_fly_half(side, Vector2(away * randf_range(60, 140) * fling + side * 50.0, randf_range(-260, -180)), side * randf_range(8, 14))
	# and the coconut water bursts out
	_burst(juice_color, Vector2(0, -RADIUS), 22, 2.0)
	_burst(FLESH, Vector2(0, -RADIUS), 8, 2.0)
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = "Coconut"
	drop.color = juice_color
	drop.position = get_parent().to_local(global_position + Vector2(0, -12))
	get_parent().add_child.call_deferred(drop)


func _respawn():
	if player and is_instance_valid(player):
		player.remove_collision_exception_with(self)  # (solid to you again)
	_through = false
	global_position = home
	velocity = Vector2.ZERO
	hp = 2
	_spin = 0.0
	visible = true
	_shape.set_deferred("disabled", false)
	_set_state(State.SIT)


func _burst(color: Color, offset: Vector2, amount: int, size: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 190.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.color = color
	p.position = get_parent().to_local(global_position + offset)
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


# one half of the shell (side -1 = left, 1 = right): a textured polygon that flies off, spins, lands where
# the coconut was and fades
func _fly_half(side: float, vel: Vector2, spin: float):
	var tex := _texture(false)
	var r := OVAL + Vector2(1.5, 1.5)      # (the shell and its outline)
	var poly := PackedVector2Array()
	var uv := PackedVector2Array()
	for k in 9:                            # round the half from top to bottom (the cut closes it)
		var p := Vector2(side * sin(PI * k / 8.0) * r.x, -cos(PI * k / 8.0) * r.y)
		poly.append(p)
		uv.append(shell_size() / 2.0 + p)
	var piece := Polygon2D.new()
	piece.texture = tex
	piece.polygon = poly
	piece.uv = uv
	piece.z_index = 3
	get_parent().add_child(piece)
	var start := global_position + Vector2(side * 2.0, -RADIUS)
	piece.global_position = start
	var start_spin := _spin
	var floor_y := global_position.y - 4.0
	var t := piece.create_tween()
	t.tween_method(func(time: float):
		var pos := start + vel * time + Vector2(0, 450.0 * time * time)
		piece.global_position = Vector2(pos.x, minf(pos.y, floor_y))
		piece.rotation = start_spin + spin * minf(time, 0.6), 0.0, 1.2, 1.2)
	t.parallel().tween_property(piece, "modulate:a", 0.0, 0.4).set_delay(0.8)
	t.tween_callback(piece.queue_free)


# the two halves of a flash cut: the shell as drawn (its turn, its bob) split along the cut through its
# middle; the top half slides off down the slope of the cut and tips, the bottom one settles, and both fade
# (the Mango's halves move the same way: fruit_minion.gd's _spawn_halves)
func _cut_halves(cut: Vector2, dir: float):
	var tex := _texture(false)
	var r := OVAL + Vector2(1.5, 1.5)
	var mid := Vector2(0, -roundf(centre_height(_spin)))
	var ring: Array = []                       # [position here, uv], round the shell
	for k in 20:
		var local := Vector2(cos(TAU * k / 20.0) * r.x, sin(TAU * k / 20.0) * r.y)
		ring.append([mid + local.rotated(_spin), shell_size() / 2.0 + local])
	var halves := [[], []]                     # the side of the cut each point is on: 0 above, 1 below
	var n := Vector2(-cut.y, cut.x)
	if n.y > 0.0:
		n = -n                                 # (n points up)
	for k in ring.size():
		var p: Array = ring[k]
		var q: Array = ring[(k + 1) % ring.size()]
		var sp: float = (p[0] - mid).dot(n)
		var sq: float = (q[0] - mid).dot(n)
		halves[0 if sp >= 0.0 else 1].append(p)
		if (sp >= 0.0) != (sq >= 0.0):         # the cut crosses this edge: a point on it, in both halves
			var t := sp / (sp - sq)
			var on := [p[0].lerp(q[0], t), p[1].lerp(q[1], t)]
			halves[0].append(on)
			halves[1].append(on)
	var down := cut if cut.y > 0.0 or (cut.y == 0.0 and cut.x * dir > 0.0) else -cut
	for i in 2:
		var pts: Array = halves[i]
		if pts.size() < 3:
			continue
		var c := Vector2.ZERO
		for p: Array in pts:
			c += p[0]
		c /= pts.size()
		var poly := PackedVector2Array()
		var uv := PackedVector2Array()
		for p: Array in pts:
			poly.append(p[0] - c)
			uv.append(p[1])
		var piece := Polygon2D.new()
		piece.texture = tex
		piece.polygon = poly
		piece.uv = uv
		piece.z_index = 3
		get_parent().add_child(piece)
		piece.global_position = global_position + c
		var top := i == 0
		var slide := down * (18.0 if top else -3.0) + Vector2(0, -2 if top else 3)
		var t := piece.create_tween().set_parallel()
		t.tween_property(piece, "position", piece.position + slide, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(piece, "rotation", signf(down.x) * (0.6 if top else -0.15), 0.35)
		t.tween_property(piece, "modulate:a", 0.0, 0.25).set_delay(0.35)
		t.chain().tween_callback(piece.queue_free)


# ---------- drawing ----------
# THE OVAL (Morgan's try-out, 2026-10-09: "like a real coconut"; it was a round disk of RADIUS): the shell is
# an oval, OVAL its half-length (along its long axis, local x) and half-width. Lying down it's on its side;
# hanging in the palm it hangs upright, its eyes at the top. Its body is still a circle of RADIUS, so it
# rolls the same; only the drawing bobs, its lowest point kept on the floor as it turns (a lumpy roll).
# OVAL = (RADIUS, RADIUS) makes it round again.
const OVAL := Vector2(13, 10)
static var _textures := {}             # cracked? -> the shell drawn once into a texture


# the texture's size: the shell and its 1px outline
static func shell_size() -> Vector2:
	return OVAL * 2.0 + Vector2(3, 3)


# the shell centred on (0, 0) of `ci`'s current transform (coconut_drop.gd draws the hanging ones with it too)
static func draw_shell(ci: CanvasItem, cracked: bool, tint := Color.WHITE):
	var half := shell_size() / 2.0
	ci.draw_texture_rect(_texture(cracked), Rect2(Vector2(0.5, 0.5) - half, half * 2.0), false, tint)


# how high its centre sits over the floor at this turn: the oval's half-height turned that far
static func centre_height(angle: float) -> float:
	return sqrt(pow(OVAL.x * sin(angle), 2.0) + pow(OVAL.y * cos(angle), 2.0))


# the shell as a pixel oval: its three "eyes" at one end (a real coconut's), two ridges running along it,
# hairy fibres and shade (and a white crack once hit), with a 1px light brown outline round it (Morgan's
# call, 2026-10-09; a white one, then a half-pixel white one, were tried). The shell's centre is in the
# texture's middle pixel
static func _texture(cracked: bool) -> ImageTexture:
	var size := Vector2i(shell_size())
	if _textures.has(cracked) and Vector2i(_textures[cracked].get_size()) == size:
		return _textures[cracked]      # (LiveReload keeps static vars: a copy from the old art is made again)
	var a := int(OVAL.x)
	var b := int(OVAL.y)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half_w := func(y: int) -> int:                 # how far the shell reaches across row y (-1: none)
		if absi(y) > b:
			return -1
		return roundi(float(a) * sqrt(maxf(1.0 - pow(float(y) / (float(b) + 0.5), 2.0), 0.0)))   # (no 1px tips)
	for y in range(-b, b + 1):
		var w: int = half_w.call(y)
		for x in range(-w, w + 1):
			var edge: bool = absi(x) == w or absi(x) > half_w.call(y - 1) or absi(x) > half_w.call(y + 1)
			var col := SHELL_DARK if edge else SHELL
			if not edge and posmod(x * 7 + y * 13, 5) == 0:
				col = HAIR                              # hairy fibres
			var ridge := roundi(0.55 * float(b) * sqrt(maxf(1.0 - float(x * x) / float(a * a), 0.0)))
			if not edge and x < a - 7 and absi(y) == ridge:
				col = SHELL.lightened(0.12)             # the ridges, running along it to the eyes
			if y * 2 > b:                               # (the lower half)
				col = col.darkened(0.15)                # shade underneath
			for eye in [Vector2(a - 3, -3), Vector2(a - 3, 3), Vector2(a - 7, 0)]:
				if not edge and (Vector2(x, y) - eye).length() < 1.2:
					col = Pixel.INK                     # the three "eyes", at its end
			if cracked and not edge and absi(x - roundi(sin(y * 1.3) * 1.5)) < 1:
				col = FLESH                             # the crack, white flesh showing
			img.set_pixel(x + a + 1, y + b + 1, col)
	for y in size.y:                                    # the outline: every empty pixel touching the shell
		for x in size.x:
			if img.get_pixel(x, y).a > 0.0 and img.get_pixel(x, y) != OUTLINE:
				continue
			for q: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + q
				if n.x >= 0 and n.y >= 0 and n.x < size.x and n.y < size.y:
					var c := img.get_pixelv(n)
					if c.a > 0.0 and c != OUTLINE:
						img.set_pixel(x, y, OUTLINE)
						break
	var tex := ImageTexture.create_from_image(img)
	_textures[cracked] = tex
	return tex


func _draw():
	var angle := _spin
	if state == State.WOBBLE:
		angle = sin(state_time * 40.0) * 0.18
	draw_set_transform(Vector2(0, -roundf(centre_height(angle))), angle)    # (its lowest point on the floor)
	draw_shell(self, hp < 2, Color(3, 3, 3) if _flash > 0.0 else Color.WHITE)
	draw_set_transform(Vector2.ZERO)
