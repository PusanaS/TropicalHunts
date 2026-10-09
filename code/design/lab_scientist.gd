extends CharacterBody2D
# DR. SPLICE (Morgan's idea, 2026-10-09): level 2's first mini boss, waiting in the jelly factory's first
# room. He's your double in a white lab coat, with a giant syringe for a sword, and he has your moves. The
# duel's opening (the clashes, the blade lock and the talk) is run by lab_duel.gd, which holds him
# (`scripted`) until start_fight().
#
# Monster card
#   Moves:     yours. He runs up to you; the light combo (two lunging swings); the heavy smash; the running
#              slash; the leap and slam (a shockwave both ways); and hopping back out of reach.
#   Warning:   his goggles glint and he holds his wind-up before every attack (shorter the more he's hurt).
#              Before the leap, a ring on the floor shows where he'll come down.
#   Clash:     your swing meeting his (both mid-swing, facing each other) clangs: sparks fly, you're both
#              knocked apart, nobody's hurt.
#   Beaten by: 3 hits of anything: catch him in his wind-up, his recovery, or from behind. Q as he comes at
#              you in his running slash counters him (one hit). Galloping at him: he parries it and you're
#              knocked back (the flash never goes for him).
#   Hurt:      knocked back, dazed a moment, then quicker. The third hit blasts him off screen (Morgan's
#              call, 2026-10-09: that's his getaway): in slow motion his syringe shatters and he flies off the
#              way you hit him, spinning, through anything, and a star twinkles where he left the screen.
#   Animations BOOM and Violeta would need: all of the player's, in a lab coat with a syringe. For now his
#              sheets are BOOM's, recoloured (scene/design/art/scientist_*.png, made by
#              docs/tools/make_scientist_sheet.py).
# PLACEHOLDER art.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const SHEET: Texture2D = preload("res://scene/design/art/scientist_PsV3.png")
const SHEET_XP: Texture2D = preload("res://scene/design/art/scientist_PsVxp.png")
const CLASH_SOUNDS := [preload("res://sounds/sword/sword_clash_01.wav"), preload("res://sounds/sword/sword_clash_02.wav"),
	preload("res://sounds/sword/sword_clash_03.wav"), preload("res://sounds/sword/sword_clash_04.wav"),
	preload("res://sounds/sword/sword_clash_05.wav")]
const CLASH_HEAVY := preload("res://sounds/sword/sword_clash_heavy_01.wav")
const SWING_SOUNDS := [preload("res://sounds/sword/sword_swoosh_01.wav"), preload("res://sounds/sword/sword_swoosh_02.wav"),
	preload("res://sounds/sword/sword_swoosh_03.wav")]
const HIT_SOUNDS := [preload("res://sounds/sword/sword_hit_flesh_01.wav"), preload("res://sounds/sword/sword_hit_flesh_03.wav"),
	preload("res://sounds/sword/sword_hit_flesh_05.wav")]
const IMPACT_SOUND := preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")
const SHATTER_SOUND := preload("res://sounds/sword/sword_hit_metal_02.wav")
const GLINT_SOUND := preload("res://sounds/sword/sword_hit_metal_01.wav")   # (played high: a ting)

const GRAVITY := 980.0
const RUN_SPEED := 240.0
const DASH_SPEED := 430.0            # the run-up to his running slash
const SLASH_SPEED := 480.0
const LUNGE := 90.0                  # each light swing steps him forward
const LEAP_UP := 470.0
const BLAST := Vector2(820, 500)     # the last hit blasts him off: sideways, up
const SLAM_SPEED := 900.0
const NEAR := 62.0                   # close enough to swing
const FAR := 170.0
const CLASH_PUSH := 230.0
const PARRY_REACH := 22.0
const HURTBOX := Rect2(-13, -38, 26, 36)    # the player's own body box
const GLINT_AT := Vector2(5, -33)           # his goggles (facing right)
const TELL := [0.0, 0.2, 0.28, 0.36]        # how long he holds the wind-up, by hits left
const PAUSE := [0.0, 0.25, 0.38, 0.52]      # his pause between moves, by hits left
const SAFE_TIME := 1.1                      # after a hit, he can't be hit again for this long (real s)
const ATTACK_KEYS := {"LIGHT_1": "ATTACK_LIGHT_1", "LIGHT_2": "ATTACK_LIGHT_2", "HEAVY_SMASH": "ATTACK_HEAVY_SMASH",
	"DASH_SLASH": "DASH_ATTACK_LIGHT", "SLAM": "DASH_ATTACK_HEAVY_SLAM", "IMPACT": "DASH_ATTACK_HEAVY_IMPACT"}
const SERUM := Color("5fd15a")
const SERUM_LIGHT := Color("a6f08f")
const SPARK := Color("fff3b0")
const MARK := Color("ff6a3a")

enum S { SCRIPTED, IDLE, APPROACH, TELL, LIGHT_1, LIGHT_2, HEAVY_WINDUP, HEAVY_SMASH, DASH_RUN, DASH_SLASH, LEAP, SLAM,
	IMPACT, BACKSTEP, RECOVER, CLASHED, HURT, DAZED, DEFEATED }

signal hurt(hp_left: int)
signal beaten
signal fled                          # blasted off: he's off screen (and gone)

@export var max_hp := 3
@export var boss_name := "DR. SPLICE"
@export var arena := Vector2(-100000, 100000)   # the world x he keeps between (left, right)

var hp := 3
var state := S.SCRIPTED
var state_time := 0.0
var facing := -1
var sprite := AnimatedSprite2D.new()
var player: CharacterBody2D = null
var _names: Array = []
var _top := 4
var _frames_ready := false
var _next := S.LIGHT_1               # what the wind-up leads into
var _last_moves: Array = []
var _recover := 0.4
var _swing_state := -1               # the player's swing he last checked (the "new swing" rule)
var _swing_time := 0.0
var _swing_hit := false
var _landed := false                 # his current swing has already hurt you
var _safe_until := 0.0
var _flash := 0.0
var _glint := -1.0                   # time since his goggles glinted (-1: none)
var _land_x := INF                   # the leap's landing mark (world x)
var _ghost_t := 0.0
var _floor_y := 0.0                  # where the floor is under him (world y)
var _fx_root: Node = null
var _snd := {}
var _spin := 0.0                     # blasted off: how fast he spins


func _ready():
	add_to_group("enemies")
	collision_layer = 4              # (like the minions: the world stops him, you don't)
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 10.0
	cap.height = 36.0
	shape.shape = cap
	shape.position = Vector2(0, -20)
	add_child(shape)
	add_child(sprite)
	hp = max_hp
	_fx_root = get_parent()
	_floor_y = global_position.y
	for k in ["clash", "swing", "hit", "impact", "glint"]:
		var s := AudioStreamPlayer.new()
		s.max_polyphony = 5 if k == "clash" else 3
		add_child(s)
		_snd[k] = s


func _sound(key: String, stream: AudioStream, pitch := 1.0, db := -4.0):
	var s: AudioStreamPlayer = _snd[key]
	s.stream = stream
	s.pitch_scale = pitch
	s.volume_db = db
	s.play()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------- his look: the player's own frames, on his sheets ----------
func _build_frames():
	var ps := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if ps == null or ps.sprite_frames == null or not ps.sprite_frames.has_animation("KNOCKBACK"):
		return
	var src := ps.sprite_frames
	var out := SpriteFrames.new()
	for anim in src.get_animation_names():
		if not out.has_animation(anim):
			out.add_animation(anim)
		out.set_animation_speed(anim, src.get_animation_speed(anim))
		out.set_animation_loop(anim, src.get_animation_loop(anim))
		for i in src.get_frame_count(anim):
			var tex := src.get_frame_texture(anim, i)
			var at := tex as AtlasTexture
			if at and at.atlas:
				var copy := AtlasTexture.new()
				copy.region = at.region
				copy.margin = at.margin
				var path := at.atlas.resource_path
				copy.atlas = SHEET if path.ends_with("PsV3.png") else (SHEET_XP if path.ends_with("PsVxp.png") else at.atlas)
				tex = copy
			out.add_frame(anim, tex, src.get_frame_duration(anim, i))
	sprite.sprite_frames = out
	sprite.position = ps.position
	sprite.centered = ps.centered
	sprite.offset = ps.offset
	_frames_ready = true
	sprite.play("IDLE")
	sprite.flip_h = facing < 0


func _play(anim: String):
	if _frames_ready and (sprite.animation != anim or not sprite.is_playing()):
		sprite.play(anim)


# a held pose (the duel's opening): one frame of an animation
func pose(anim: String, frame: int):
	if not _frames_ready:
		return
	sprite.animation = anim
	sprite.frame = mini(frame, sprite.sprite_frames.get_frame_count(anim) - 1)
	sprite.pause()


func face(dir: int):
	facing = dir
	sprite.flip_h = facing < 0


# the duel lets him loose
func start_fight():
	state = S.IDLE
	state_time = PAUSE[hp] * 0.5
	_play("IDLE")


# ---------- every frame ----------
func _physics_process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_names = player.get_script().State.keys()
		_top = player.get_script().SPEEDS.size() - 1
	if not _frames_ready:
		_build_frames()
	state_time += delta
	if is_on_floor():
		_floor_y = global_position.y
	_flash -= delta
	if _glint >= 0.0:
		_glint += delta
	sprite.self_modulate = Color(3, 3, 3) if _flash > 0.0 else Color.WHITE
	if state == S.SCRIPTED:
		queue_redraw()
		return
	if state != S.SLAM and not is_on_floor():
		velocity.y += GRAVITY * delta
	_think(delta)
	move_and_slide()
	if state != S.DEFEATED:
		global_position.x = clampf(global_position.x, arena.x + 14.0, arena.y - 14.0)
	if state not in [S.HURT, S.DAZED, S.DEFEATED]:
		_check_your_swing()
		_check_gallop()
		_check_my_swing()
	if state in [S.DASH_RUN, S.LEAP, S.SLAM, S.DASH_SLASH]:
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.04
			_ghost()
	sprite.flip_h = facing < 0
	queue_redraw()


func _go(s: S):            # (not _set: that's a Godot built-in)
	state = s
	state_time = 0.0
	_landed = false


func _dx() -> float:
	return player.global_position.x - global_position.x


# you're knocked down and dazed (or held by something): he waits for you to get up, fair's fair (you're
# dazed for longer than a hit keeps you safe)
func _you_down() -> bool:
	return _names[player.state] == "KNOCKBACK" or not player.is_physics_processing()


func _face_player():
	var d := _dx()
	if d != 0.0:
		facing = int(signf(d))


func _friction(delta: float, k := 900.0):
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, k * delta)


# ---------- what he does ----------
func _think(delta: float):
	match state:
		S.IDLE:
			_play("IDLE")
			_face_player()
			_friction(delta)
			if state_time >= PAUSE[hp] and not _you_down():
				_decide()
		S.APPROACH:
			if _you_down():
				_go(S.IDLE)
				return
			_face_player()
			_play("RUN")
			velocity.x = facing * RUN_SPEED
			if absf(_dx()) <= NEAR:
				velocity.x = 0.0
				_wind_up(S.LIGHT_1 if randf() < 0.6 else S.HEAVY_WINDUP)
			elif state_time > 1.2:
				_decide()
		S.TELL:
			_friction(delta, 1400.0)
			if state_time >= TELL[hp]:
				_glint = -1.0
				_begin(_next)
		S.LIGHT_1, S.LIGHT_2:
			_friction(delta, 600.0)
			if state_time >= 0.3:
				if state == S.LIGHT_1 and absf(_dx()) < 84.0 and randf() < 0.75:
					_begin(S.LIGHT_2)
				else:
					_recovering(0.42)
		S.HEAVY_WINDUP:
			if state_time >= 0.12:
				_begin(S.HEAVY_SMASH)
		S.HEAVY_SMASH:
			_friction(delta, 700.0)
			if state_time >= 0.4:
				_recovering(0.55)
		S.DASH_RUN:
			_play("SPRINT")
			velocity.x = facing * DASH_SPEED
			if (absf(_dx()) < 70.0 and signf(_dx()) == facing) or state_time > 0.9:
				_begin(S.DASH_SLASH)
		S.DASH_SLASH:
			velocity.x = move_toward(velocity.x, 0.0, 1300.0 * delta)
			if state_time >= 0.3:
				_recovering(0.5)
		S.LEAP:
			_play("JUMP_RISE")
			if velocity.y >= -40.0 or state_time > 0.6:
				_begin(S.SLAM)
		S.SLAM:
			velocity = Vector2(0, SLAM_SPEED)
			if is_on_floor():
				_begin(S.IMPACT)
		S.IMPACT:
			_friction(delta)
			if state_time >= 0.55:
				_land_x = INF
				_recovering(0.5)
		S.BACKSTEP:
			_play("JUMP_RISE" if velocity.y < 0.0 else "JUMP_FALL")
			if is_on_floor() and state_time > 0.1:
				_go(S.IDLE)
				state_time = PAUSE[hp] * 0.4
		S.RECOVER:
			_play("IDLE")
			_friction(delta)
			if state_time >= _recover:
				_go(S.IDLE)
		S.CLASHED:
			_friction(delta, 700.0)
			if state_time >= 0.3:
				if absf(_dx()) <= NEAR + 10.0 and randf() < 0.5:
					_face_player()
					_wind_up(S.LIGHT_1)             # straight back at you
				else:
					_go(S.IDLE)
					state_time = PAUSE[hp] * 0.6
		S.HURT:
			_play("KNOCKBACK")
			if is_on_floor() and state_time > 0.12:
				velocity.x = 0.0
				_go(S.DAZED)
		S.DAZED:
			_play("STUN")
			_friction(delta)
			if state_time >= (0.75 if hp >= 2 else 0.55):
				_go(S.IDLE)
				state_time = PAUSE[hp] * 0.5
		S.DEFEATED:                                   # blasted off, spinning, till he's off screen
			sprite.rotation += _spin * delta
			if _off_screen():
				_vanish()


# what next, by how far you are (and not the same move three times running)
func _decide():
	_face_player()
	var d := absf(_dx())
	var pick: S
	var r := randf()
	if d > FAR:
		pick = S.DASH_RUN if r < 0.45 else (S.LEAP if r < 0.7 else S.APPROACH)
	elif d > NEAR:
		pick = S.APPROACH if r < 0.35 else (S.DASH_RUN if r < 0.7 else (S.LEAP if r < 0.9 else S.BACKSTEP))
	else:
		pick = S.LIGHT_1 if r < 0.45 else (S.HEAVY_WINDUP if r < 0.8 else S.BACKSTEP)
	if _last_moves.size() >= 2 and _last_moves[-1] == pick and _last_moves[-2] == pick:
		pick = S.APPROACH if pick != S.APPROACH else S.DASH_RUN
	if pick == S.BACKSTEP and not _room_behind():
		pick = S.LIGHT_1 if d <= NEAR else S.DASH_RUN
	_last_moves.append(pick)
	if _last_moves.size() > 3:
		_last_moves.pop_front()
	match pick:
		S.APPROACH:
			_go(S.APPROACH)
		S.BACKSTEP:
			_go(S.BACKSTEP)
			velocity = Vector2(-facing * 240.0, -260.0)
		_:
			_wind_up(pick)


func _room_behind() -> bool:
	var behind := global_position.x - facing * 90.0
	return behind > arena.x + 20.0 and behind < arena.y - 20.0


# the warning: his goggles glint and he holds the wind-up pose
func _wind_up(next: S):
	_next = next
	_go(S.TELL)
	_glint = 0.0
	_sound("glint", GLINT_SOUND, 2.6, -14.0)
	match next:
		S.LIGHT_1:
			pose("ATTACK_LIGHT_1", 0)
		S.HEAVY_WINDUP:
			pose("ATTACK_HEAVY_WINDUP", 0)
		_:
			pose("LAND", 1)                           # crouched, ready to spring
	if next == S.LEAP:
		_land_x = clampf(player.global_position.x, arena.x + 20.0, arena.y - 20.0)


func _begin(s: S):
	_go(s)
	match s:
		S.LIGHT_1, S.LIGHT_2:
			_face_player()
			sprite.play("ATTACK_LIGHT_1" if s == S.LIGHT_1 else "ATTACK_LIGHT_2")
			sprite.frame = 0
			velocity.x = facing * LUNGE
			_sound("swing", SWING_SOUNDS.pick_random(), randf_range(0.95, 1.1))
		S.HEAVY_WINDUP:
			sprite.play("ATTACK_HEAVY_WINDUP")
		S.HEAVY_SMASH:
			sprite.play("ATTACK_HEAVY_SMASH")
			sprite.frame = 0
			velocity.x = facing * 60.0
			_sound("swing", SWING_SOUNDS.pick_random(), 0.8)
			_shake(4.0, 0.15)
		S.DASH_RUN:
			_face_player()
		S.DASH_SLASH:
			sprite.play("DASH_ATTACK_LIGHT")
			sprite.frame = 0
			velocity.x = facing * SLASH_SPEED
			_sound("swing", SWING_SOUNDS.pick_random(), 1.15)
		S.LEAP:
			var tx := _land_x if _land_x != INF else player.global_position.x
			velocity = Vector2(clampf((tx - global_position.x) / (LEAP_UP / GRAVITY), -520.0, 520.0), -LEAP_UP)
			if velocity.x != 0.0:
				facing = int(signf(velocity.x))
		S.SLAM:
			pose("DASH_ATTACK_HEAVY_WINDUP", 2)
		S.IMPACT:
			sprite.play("DASH_ATTACK_HEAVY_IMPACT")
			sprite.frame = 0
			_sound("impact", IMPACT_SOUND, 1.1, -6.0)
			_shake(7.0, 0.25)
			_dust(global_position, 18)
			get_tree().call_group("living_background", "burst", global_position, 4.0)


func _recovering(t: float):
	_go(S.RECOVER)
	_recover = t


# ---------- swords ----------
# his swing's hit box right now (world), from the player's own table: the same moves, the same reach
func _my_rect() -> Rect2:
	var key: String = ATTACK_KEYS.get(S.keys()[state], "")
	if key == "":
		return Rect2()
	var hit: Dictionary = FruitMinion.PLAYER_HITS[key]
	if state_time < hit["active"].x or state_time > hit["active"].y:
		return Rect2()
	var r: Rect2 = hit["rect"]
	if facing < 0:
		r.position.x = -r.position.x - r.size.x
	r.position += global_position
	return r


# the player's swing's hit box right now (world)
func _your_rect() -> Rect2:
	var hit = FruitMinion.PLAYER_HITS.get(_names[player.state])
	if hit == null or player.state_time < hit["active"].x or player.state_time > hit["active"].y:
		return Rect2()
	var r: Rect2 = hit["rect"]
	if player.facing < 0:
		r.position.x = -r.position.x - r.size.x
	r.position += player.global_position
	return r


# your swing reaching him: a hit, or a clash if his own swing meets it
func _check_your_swing():
	var ps: int = player.state
	var pt: float = player.state_time
	if ps != _swing_state or pt < _swing_time:
		_swing_hit = false
	_swing_state = ps
	_swing_time = pt
	if _swing_hit:
		return
	var box := Rect2(global_position + HURTBOX.position, HURTBOX.size)
	var hit := EnemyKit.player_attack_hitting(player, _names, box)
	if hit.is_empty() and _names[ps] == "CHARGED_SMASH":
		var radius: Vector2 = player.get_script().CHARGE_RADIUS
		var reach := lerpf(radius.x, radius.y, float(player.charge))
		if absf(_dx()) <= reach and absf(player.global_position.y - global_position.y) <= 90.0:
			hit = {"damage": 3}
	var mine := _my_rect()
	var yours := _your_rect()
	var facing_you := signf(_dx()) == facing
	var clash := mine.has_area() and ((not hit.is_empty() and facing_you) or (yours.has_area() and mine.intersects(yours)))
	if hit.is_empty() and not clash:
		return
	_swing_hit = true
	if clash:
		var at := (mine.get_center() + (yours.get_center() if yours.has_area() else box.get_center())) / 2.0
		_clash(at)
		return
	if _now() < _safe_until:
		return
	_take_hit(signf(global_position.x - player.global_position.x))


# his swing reaching you
func _check_my_swing():
	if _landed or _you_down():
		return
	var r := _my_rect()
	if r.has_area() and EnemyKit.hurt_player(player, r, global_position.x):
		_landed = true
		_sound("hit", HIT_SOUNDS.pick_random(), 1.0, -6.0)


# blade on blade: sparks, a clang, both knocked apart, no one hurt
func _clash(at: Vector2, heavy := false):
	var dir := signf(global_position.x - player.global_position.x)
	if dir == 0.0:
		dir = -facing
	clash_fx(at, heavy)
	if player.has_method("bounce_back"):
		player.bounce_back(global_position.x, CLASH_PUSH)
	velocity = Vector2(dir * CLASH_PUSH, -60.0)
	_go(S.CLASHED)
	pose("LAND", 0)


# the clash itself, for the duel's opening too: sparks, a white ring, the clang, a freeze and a shake. quick:
# the opening's flurry (no freeze, a small shake, so it keeps its pace); pitch: its clangs rise
func clash_fx(at: Vector2, heavy := false, quick := false, pitch := 1.0):
	_sound("clash", CLASH_HEAVY if heavy else CLASH_SOUNDS.pick_random(), pitch * randf_range(0.97, 1.03), -2.0 if heavy else -4.0)
	if quick:
		_sparks(at, 12, 170.0)
		_ring(at, 10.0)
		_shake(2.5, 0.07)
		return
	_sparks(at, 34 if heavy else 18, 260.0 if heavy else 190.0)
	_ring(at, 26.0 if heavy else 14.0)
	EnemyKit.hitstop(get_tree(), 0.09 if heavy else 0.05)
	_shake(9.0 if heavy else 4.0, 0.25 if heavy else 0.12)


# galloping at him: he parries it with the syringe and you're knocked back
func _check_gallop():
	if player.speed_level < _top or state in [S.SCRIPTED, S.HURT, S.DAZED, S.DEFEATED]:
		return
	var d := -_dx()
	if signf(player.velocity.x) != signf(d) or absf(player.global_position.y - global_position.y) > 50.0:
		return
	if absf(d) - 26.0 < PARRY_REACH + absf(player.velocity.x) / 60.0:
		_face_player()
		clash_fx(global_position + Vector2(facing * 14.0, -28.0), false)
		pose("ATTACK_LIGHT_2", 1)
		EnemyKit.protect_player(0.8)
		if player.has_method("_start_knockback"):
			player._start_knockback()
		_go(S.CLASHED)


# ---------- getting hurt ----------
func _take_hit(away: float, counter := false):
	if hp <= 0:
		return
	hp -= 1
	_safe_until = _now() + SAFE_TIME
	_flash = 0.15
	_glint = -1.0
	_land_x = INF
	if away == 0.0:
		away = -facing
	facing = int(-away)
	_sound("hit", HIT_SOUNDS.pick_random(), 0.9, -2.0)
	_serum(global_position + Vector2(0, -24), away, 16)
	_sparks(global_position + Vector2(-away * 6.0, -24), 10, 180.0)
	velocity = Vector2(away * (260.0 if counter else 210.0), -260.0)
	_go(S.HURT)
	sprite.play("KNOCKBACK")
	hurt.emit(hp)
	if hp <= 0:
		_go_down(away)
	else:
		EnemyKit.hitstop(get_tree(), 0.12 if counter else 0.09)
		_shake(6.0, 0.2)


# the third hit: slow motion, his syringe shatters, and he's blasted off the way you hit him, spinning,
# through anything (Morgan's call, 2026-10-09: that's how he gets away)
func _go_down(away: float):
	_go(S.DEFEATED)
	collision_mask = 0                           # (through walls and doors: off screen he goes)
	velocity = Vector2(away * BLAST.x, -BLAST.y)
	_spin = away * 16.0
	sprite.play("KNOCKBACK")
	_shake(12.0, 0.4)
	_sound("clash", CLASH_HEAVY, 0.8, 0.0)
	_sound("impact", SHATTER_SOUND, 0.7, -2.0)
	_serum(global_position + Vector2(0, -26), away, 40)
	_shards(global_position + Vector2(away * 10.0, -28))
	Engine.time_scale = 0.25
	get_tree().create_timer(0.9, true, false, true).timeout.connect(func():
		if Engine.time_scale == 0.25:
			Engine.time_scale = 1.0)
	remove_from_group("enemies")                 # (out of the fight: nothing goes for him now)
	beaten.emit()


func _off_screen() -> bool:
	var at := get_viewport().get_canvas_transform() * (global_position + Vector2(0, -20))
	var view := get_viewport().get_visible_rect().size
	return at.x < -30.0 or at.x > view.x + 30.0 or at.y > view.y + 60.0 or at.y < -60.0


# gone: a star twinkles where he left the screen, with a ting
func _vanish():
	var xf := get_viewport().get_canvas_transform()
	var view := get_viewport().get_visible_rect().size
	var at := xf * (global_position + Vector2(0, -20))
	at = Vector2(clampf(at.x, 10.0, view.x - 10.0), clampf(at.y, 10.0, view.y - 10.0))
	var star := Node2D.new()
	star.z_as_relative = false
	star.z_index = 30
	_fx_root.add_child(star)
	star.global_position = xf.affine_inverse() * at
	for k in 2:                                   # a four-point star: a long cross and a short one
		var line := Line2D.new()
		line.width = 1.0 if k == 0 else 2.0
		line.default_color = Color.WHITE
		var r := 10.0 if k == 0 else 4.0
		line.points = PackedVector2Array([Vector2(-r, 0), Vector2(r, 0)])
		star.add_child(line)
		var line2 := line.duplicate() as Line2D
		line2.points = PackedVector2Array([Vector2(0, -r), Vector2(0, r)])
		star.add_child(line2)
	star.scale = Vector2.ZERO
	var t := star.create_tween().set_ignore_time_scale(true)
	t.tween_property(star, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(star, "rotation", PI / 4.0, 0.4)
	t.tween_property(star, "scale", Vector2.ZERO, 0.28).set_ease(Tween.EASE_IN)
	t.tween_callback(star.queue_free)
	_sound("glint", GLINT_SOUND, 2.8, -6.0)
	visible = false
	set_physics_process(false)
	fled.emit()


# the counter (counter_chain.gd): one hit, harder
func countered(dir: int):
	_take_hit(float(dir), true)


func is_counterable() -> bool:
	if state == S.DASH_SLASH:
		return not _landed
	return state == S.DASH_RUN and absf(_dx()) < 160.0 and signf(_dx()) == facing


# the flash only goes for enemies that are alive: he isn't while you gallop (he parries it instead), nor
# before the fight or once he's down
func is_alive() -> bool:
	if hp <= 0 or state in [S.SCRIPTED, S.DEFEATED]:
		return false
	return not (player and player.speed_level >= _top)


func take_hit(_damage: int, _push: Vector2):
	if state in [S.SCRIPTED, S.HURT, S.DAZED, S.DEFEATED] or _now() < _safe_until:
		return
	_take_hit(signf(global_position.x - player.global_position.x) if player else float(-facing))


# ---------- effects ----------
func _shake(strength: float, time: float):
	if player and player.has_method("_shake"):
		player._shake(strength, time)


func _particles(at: Vector2, amount: int, speed: float, col: Color, life := 0.45, size := 2.0, grav := 520.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, grav)
	p.scale_amount_min = 1.0
	p.scale_amount_max = size
	p.color = col
	p.z_as_relative = false
	p.z_index = 20
	_fx_root.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _sparks(at: Vector2, amount: int, speed: float):
	if _fx_root == null:
		_fx_root = get_parent()
	_particles(at, amount, speed, SPARK, 0.35, 2.0, 380.0)
	_particles(at, int(amount * 0.5), speed * 0.7, Color.WHITE, 0.25, 1.0, 200.0)


func _serum(at: Vector2, dir: float, amount: int):
	var p := _particles(at, amount, 200.0, SERUM, 0.6, 2.5, 600.0)
	p.direction = Vector2(dir, -0.6)
	p.spread = 50.0


func _dust(at: Vector2, amount: int):
	var p := _particles(at + Vector2(0, -2), amount, 140.0, Color(0.9, 0.93, 0.96), 0.5, 3.0, 60.0)
	p.direction = Vector2.UP
	p.spread = 85.0


# a white ring of light, growing and fading (a clash)
func _ring(at: Vector2, size: float):
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1, 1, 1, 0.9)
	ring.closed = true
	for k in 16:
		ring.add_point(Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)))
	ring.z_as_relative = false
	ring.z_index = 21
	_fx_root.add_child(ring)
	ring.global_position = at
	ring.scale = Vector2.ONE * 2.0
	var t := ring.create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(ring, "scale", Vector2.ONE * size, 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(ring.queue_free)


# the syringe shattering: glass and serum
func _shards(at: Vector2):
	_particles(at, 26, 260.0, Color(0.85, 0.97, 1.0), 0.8, 2.0, 700.0)
	_particles(at, 18, 220.0, SERUM_LIGHT, 0.7, 2.5, 700.0)


# a green afterimage of him, fading (dashing, leaping)
func _ghost():
	if not _frames_ready:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.texture = tex
	g.centered = sprite.centered
	g.offset = sprite.offset
	g.flip_h = sprite.flip_h
	g.modulate = Color(SERUM_LIGHT, 0.55)
	_fx_root.add_child(g)
	g.global_position = sprite.global_position
	var t := g.create_tween()
	t.tween_property(g, "modulate:a", 0.0, 0.22)
	t.tween_callback(g.queue_free)


# his goggles' glint, and the leap's landing mark
func _draw():
	if _glint >= 0.0 and _glint < 0.3:
		var k := _glint / 0.3
		var r := roundf(sin(k * PI) * 6.0)
		var at := Vector2(GLINT_AT.x * facing, GLINT_AT.y)
		draw_rect(Rect2(at.x - r, at.y, r * 2.0 + 1.0, 1), Color.WHITE)
		draw_rect(Rect2(at.x, at.y - r, 1, r * 2.0 + 1.0), Color.WHITE)
		draw_rect(Rect2(at.x - 1.0, at.y - 1.0, 3, 3), Color(1, 1, 1, 0.9))
	if _land_x != INF and state in [S.TELL, S.LEAP, S.SLAM]:
		var x := _land_x - global_position.x
		var y := _floor_y - global_position.y                     # (the floor, wherever he is)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)
		for k in 3:
			var w := 14.0 + k * 8.0
			draw_rect(Rect2(x - w, y - 1.0 + k, w * 2.0, 1), Color(MARK, (0.8 - k * 0.25) * pulse))
		draw_rect(Rect2(x - 1.0, y - 6.0, 2, 4), Color(MARK, pulse))
