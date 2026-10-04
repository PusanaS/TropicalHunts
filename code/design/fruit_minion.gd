extends CharacterBody2D
# FRUIT MINION: the basic fruit enemy, and the template ("fruit format") for the others.
# A new fruit = this scene with its own sprite sheet (sprite_frames) and numbers in the Inspector.
# The sheet needs the animations listed on the card below.
#
# Monster card (default: Mango)
#   Moves:     walks back and forth around where it was placed, turns at walls and ledges.
#   Notices:   the player in front (sight_range) or right behind it -> hop + "!"
#   Attack:    runs at the player, stops and SHAKES (the warning), then lunges.
#   After:     dizzy for a moment after every lunge = the punish window.
#   Beaten by: any one hit (minions are one-shot). Hitting it while it shakes stops the lunge.
#   Touch:     touching it hurts, except while it is dizzy, hurt or dead.
#   Drops:     one juice drop of its fruit.
#   Animations BOOM will need: IDLE, WALK, NOTICE, RUN, WINDUP, LUNGE, DIZZY, HURT, DIE

enum State { IDLE, PATROL, NOTICE, CHASE, WINDUP, LUNGE, DIZZY, HURT, DEAD }

@export_group("Fruit look")
@export var fruit_name := "Mango"
@export var sprite_frames: SpriteFrames   # empty = the Mango sheet already in the scene
@export var juice_color := Color(0.91, 0.54, 0.13)
@export var body_radius := 12.0          # half its width, used to look for ledges

@export_group("Stats")
@export var max_hp := 1              # minions die in one hit
@export var walk_speed := 30.0
@export var chase_speed := 80.0
@export var patrol_range := 96.0     # how far it wanders from where it was placed
@export var sight_range := 160.0
@export var lunge_range := 140.0     # starts the windup when the player is this close (was 72: Morgan wanted
                                     # it to pounce from further away, for a bigger counter window)
@export var windup_time := 0.45      # the warning shake before the lunge
@export var lunge_velocity := Vector2(190, -320)   # a slower, higher pounce (was 230, -170): ~0.65 s in the air
@export var dizzy_time := 0.7        # punish window after a lunge
@export var respawn_time := 3.0      # gym only: comes back after this long, 0 = stays dead

# ---------- player attacks (stand-in hitboxes) ----------
# The player has no hitboxes yet, so the minion reads which attack the player is in.
# rect is relative to the player's feet when facing right. active = seconds into that state.
# push = how the hit knocks the enemy (x away from the player, negative y = up). Minions just burst;
# the numbers are tuned for knocking the boss around in combos (fruit_boss.gd scales them).
const PLAYER_HITS := {
	"ATTACK_LIGHT_1": {"active": Vector2(0.05, 0.20), "rect": Rect2(0, -40, 44, 40), "damage": 1, "push": Vector2(60, -280)},
	"ATTACK_LIGHT_2": {"active": Vector2(0.05, 0.20), "rect": Rect2(0, -40, 44, 40), "damage": 1, "push": Vector2(60, -280)},
	"ATTACK_HEAVY_SMASH": {"active": Vector2(0.0, 0.15), "rect": Rect2(-8, -48, 64, 48), "damage": 3, "push": Vector2(150, -420)},
	"DASH_ATTACK_LIGHT": {"active": Vector2(0.0, 0.30), "rect": Rect2(-8, -32, 48, 32), "damage": 1, "push": Vector2(200, -260)},
	# falling onto an enemy during the slam spikes it straight down (light damage, so boss armor blocks it
	# unless the boss is already in the air)
	"DASH_ATTACK_HEAVY_SLAM": {"active": Vector2(0.0, 2.0), "rect": Rect2(-20, -10, 40, 40), "damage": 1, "push": Vector2(0, 520)},
	# the slam is a shockwave: hits both sides and pushes away from the player
	"DASH_ATTACK_HEAVY_IMPACT": {"active": Vector2(0.0, 0.12), "rect": Rect2(-80, -32, 160, 32), "damage": 3, "push": Vector2(240, -340), "all_around": true},
}

const NOTICE_TIME := 0.4
const IDLE_TIME := 0.8
const HURT_TIME := 0.3
const NOTICE_HOP := -110.0
const GIVE_UP_RANGE := 260.0
const BEHIND_SIGHT := 48.0           # notices a player this close even behind it
const SIGHT_HEIGHT := 48.0
const FLOOR_FRICTION := 900.0

const HURTBOX := Rect2(-12, -24, 24, 24)       # where the player can hit it
const TOUCH_BOX := Rect2(-10, -20, 20, 18)     # where it hurts the player
const PLAYER_BOX := Rect2(-13, -38, 26, 36)    # the player's body, from their feet
const PLAYER_PUSH := Vector2(220, -160)
const PLAYER_SAFE_TIME := 0.8        # the player can't be hurt again for this long
const HITSTOP_LIGHT := 0.04
const HITSTOP_HEAVY := 0.08

const ANIM_NAMES := {
	State.IDLE: "IDLE",
	State.PATROL: "WALK",
	State.NOTICE: "NOTICE",
	State.CHASE: "RUN",
	State.WINDUP: "WINDUP",
	State.LUNGE: "LUNGE",
	State.DIZZY: "DIZZY",
	State.HURT: "HURT",       # first frame is the white hit flash
	State.DEAD: "DIE",
}
const JuiceDrop := preload("res://code/design/juice_drop.gd")
# killed by one of the player's Q or W swings (not the flash or the counter): a flesh hit
const KILL_SOUND := preload("res://sounds/sword/sword_hit_flesh_01.wav")
const KILL_SOUND_DB := -3.0
const KILL_SOUND_SKIP := 0.025        # the file swells in over 40ms; start partway in
# every hit that does damage: a wet squelch (Q, W, the flash, W waves...)
const DAMAGE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const DAMAGE_SOUND_DB := 0.0
const DAMAGE_SOUND_SKIP := 0.12      # the file starts with 0.12 s of silence
const KILLING_SWINGS := ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2", "DASH_ATTACK_LIGHT", "ATTACK_HEAVY_SMASH",
	"DASH_ATTACK_HEAVY_SLAM", "DASH_ATTACK_HEAVY_IMPACT", "CHARGED_SMASH"]

static var _player_safe_until := 0.0  # shared, so two minions can't hit the player at once

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var ledge_check: RayCast2D = $LedgeCheck
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var state: State = State.PATROL
var state_time := 0.0
var facing := 1
var hp := 3
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _player_states: Array = []
var _last_player_state := -1
var _last_player_time := 0.0
var _hit_this_swing := false
var _lunge_landed := false           # this lunge already hit the player: too late to counter it
var _kill_sound := AudioStreamPlayer.new()
var _damage_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")   # other code finds enemies here and calls take_hit(damage, push)
	if sprite_frames:
		sprite.sprite_frames = sprite_frames
	sprite.animation_finished.connect(_on_anim_finished)
	home = global_position
	hp = max_hp
	_kill_sound.stream = KILL_SOUND
	_kill_sound.volume_db = KILL_SOUND_DB
	add_child(_kill_sound)
	var squelch := AudioStreamRandomizer.new()   # a different pitch each hit, so combos don't sound repetitive
	squelch.add_stream(-1, DAMAGE_SOUND)
	squelch.random_pitch = 1.3                    # anywhere from about 4 semitones lower to 4 higher
	squelch.random_volume_offset_db = 2.0
	_damage_sound.stream = squelch
	_damage_sound.volume_db = DAMAGE_SOUND_DB
	_damage_sound.max_polyphony = 3
	add_child(_damage_sound)
	_set_state(State.PATROL)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p == null and get_tree().current_scene:
		p = get_tree().current_scene.get_node_or_null("Player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_player_states = player.get_script().State.keys()
		add_collision_exception_with(player)
		ledge_check.add_exception(player)


func _set_state(s: State):
	state = s
	state_time = 0.0
	_play_anim(s)
	match s:
		State.NOTICE:
			_face_player()
			velocity.y = NOTICE_HOP
		State.LUNGE:
			velocity = Vector2(facing * lunge_velocity.x, lunge_velocity.y)
			_lunge_landed = false


func _play_anim(s: State):
	var anim_name: String = ANIM_NAMES[s]
	var frames := sprite.sprite_frames
	sprite.speed_scale = 1.0
	if s == State.WINDUP:
		# the shake always lasts exactly windup_time, whatever it is tuned to
		var length := frames.get_frame_count(anim_name) / frames.get_animation_speed(anim_name)
		sprite.speed_scale = length / windup_time
	sprite.visible = true
	sprite.stop()          # restart, so every hit shows the white flash again
	sprite.play(anim_name)


func _on_anim_finished():
	if state == State.DEAD:
		sprite.visible = false


func _physics_process(delta):
	state_time += delta
	if state == State.DEAD:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		return
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()

	if not is_on_floor():
		velocity += get_gravity() * delta

	_check_player_attack()
	if state == State.DEAD:
		return

	match state:
		State.IDLE:
			_state_idle(delta)
		State.PATROL:
			_state_patrol(delta)
		State.NOTICE:
			_state_notice(delta)
		State.CHASE:
			_state_chase(delta)
		State.WINDUP:
			_state_windup(delta)
		State.LUNGE:
			_state_lunge(delta)
		State.DIZZY:
			_state_dizzy(delta)
		State.HURT:
			_state_hurt(delta)

	move_and_slide()
	sprite.flip_h = facing < 0    # the art faces right
	_touch_player()


# ---------- senses ----------
func _to_player() -> Vector2:
	return player.global_position - global_position


func _face_player():
	if player and absf(_to_player().x) > 2.0:
		facing = int(signf(_to_player().x))


func _sees_player() -> bool:
	if player == null:
		return false
	var d := _to_player()
	if absf(d.y) > SIGHT_HEIGHT:
		return false
	if absf(d.x) <= BEHIND_SIGHT:
		return true
	return signf(d.x) == facing and absf(d.x) <= sight_range


# wall or ledge straight ahead
func _blocked() -> bool:
	if is_on_wall() and get_wall_normal().x * facing < 0.0:
		return true
	ledge_check.position.x = facing * (body_radius + 2.0)
	ledge_check.force_raycast_update()
	return is_on_floor() and not ledge_check.is_colliding()


func _brake(delta):
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FLOOR_FRICTION * delta)


# ---------- states ----------
func _state_idle(delta):
	_brake(delta)
	if _sees_player():
		_set_state(State.NOTICE)
	elif state_time >= IDLE_TIME:
		facing = -facing
		_set_state(State.PATROL)


func _state_patrol(_delta):
	if _sees_player():
		_set_state(State.NOTICE)
		return
	var from_home := (global_position.x - home.x) * facing
	if _blocked() or from_home >= patrol_range:
		velocity.x = 0.0
		_set_state(State.IDLE)
		return
	velocity.x = facing * walk_speed


func _state_notice(delta):
	_brake(delta)
	if state_time >= NOTICE_TIME and is_on_floor():
		_set_state(State.CHASE)


func _state_chase(_delta):
	if player == null:
		_set_state(State.IDLE)
		return
	var d := _to_player()
	if absf(d.x) > GIVE_UP_RANGE or absf(d.y) > SIGHT_HEIGHT * 2.0:
		_set_state(State.IDLE)
		return
	_face_player()
	if absf(d.x) <= lunge_range and is_on_floor():
		velocity.x = 0.0
		_set_state(State.WINDUP)
		return
	# waits at a ledge instead of running off it
	velocity.x = 0.0 if _blocked() else facing * chase_speed


func _state_windup(delta):
	_brake(delta)
	if state_time >= windup_time:
		_set_state(State.LUNGE)


func _state_lunge(_delta):
	if is_on_floor() and state_time > 0.05:
		velocity.x = 0.0
		_set_state(State.DIZZY)


func _state_dizzy(delta):
	_brake(delta)
	if state_time >= dizzy_time:
		_set_state(State.CHASE)


func _state_hurt(delta):
	_brake(delta)
	if state_time >= HURT_TIME and is_on_floor():
		_set_state(State.CHASE)


# ---------- getting hit ----------
func _check_player_attack():
	if player == null:
		return
	var ps: int = player.state
	var pt: float = player.state_time
	# a new state, or the same state restarted, is a new swing
	if ps != _last_player_state or pt < _last_player_time:
		_hit_this_swing = false
	_last_player_state = ps
	_last_player_time = pt
	if _hit_this_swing:
		return

	var hit = PLAYER_HITS.get(_player_states[ps])
	if hit == null or pt < hit["active"].x or pt > hit["active"].y:
		return
	var pf: int = player.facing
	var r: Rect2 = hit["rect"]
	if pf < 0:
		r.position.x = -r.position.x - r.size.x
	r.position += player.global_position
	if not r.intersects(Rect2(global_position + HURTBOX.position, HURTBOX.size)):
		return

	_hit_this_swing = true
	var dir := float(pf)
	if hit.get("all_around", false):
		dir = signf(global_position.x - player.global_position.x)
		if dir == 0.0:
			dir = pf
	take_hit(hit["damage"], Vector2(dir * hit["push"].x, hit["push"].y))


func take_hit(damage: int, push: Vector2):
	if state == State.DEAD:
		return
	hp -= damage
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	_hitstop(HITSTOP_HEAVY if damage >= 3 else HITSTOP_LIGHT)
	if hp <= 0:
		if player and _player_states[player.state] in KILLING_SWINGS:
			_kill_sound.play(KILL_SOUND_SKIP)
		_die()
		return
	velocity = push
	facing = -int(signf(push.x)) if push.x != 0.0 else facing
	_set_state(State.HURT)


# the player's counter (Q) can only catch it mid-lunge, before it has hit them (Morgan's call)
func is_counterable() -> bool:
	return state == State.LUNGE and not _lunge_landed


# killed by the counter: the current frame splits in two along the counter's slash (from a to b, in the
# world), so the cut lines up with the slash you see. Without a line it splits straight across the middle.
# The top half slides off down the cut, the bottom half slumps.
func cut_in_half(dir: int, a := Vector2.INF, b := Vector2.INF):
	if state == State.DEAD:
		return
	hp = 0
	_hitstop(HITSTOP_HEAVY)
	_spawn_halves(dir, a, b)
	_die()
	sprite.visible = false


func _spawn_halves(dir: int, a: Vector2, b: Vector2):
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var sheet: Texture2D = tex
	var region := Rect2(Vector2.ZERO, tex.get_size())
	var atlas_tex := tex as AtlasTexture
	if atlas_tex:
		sheet = atlas_tex.atlas
		region = atlas_tex.region
	# the frame as a rectangle in the sprite's own space, and the cut line in that space too
	var center := sprite.offset + (Vector2.ZERO if sprite.centered else region.size / 2.0)
	var rect := Rect2(center - region.size / 2.0, region.size)
	var la := center - Vector2(20, 0)
	var lb := center + Vector2(20, 0)
	if a != Vector2.INF and b != Vector2.INF and a != b:
		la = sprite.to_local(a)
		lb = sprite.to_local(b)
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var halves := _split(corners, la, lb)
	# the top half slides off down the slope of the cut
	var along := (lb - la).normalized()
	if along.y < 0.0 or (along.y == 0.0 and along.x * dir < 0.0):
		along = -along
	var top_index := 0 if _centroid(halves[0]).y < _centroid(halves[1]).y else 1
	for i in 2:
		var pts: Array[Vector2] = halves[i]
		if pts.size() < 3:
			continue
		var c := _centroid(pts)
		var poly := PackedVector2Array()
		var uv := PackedVector2Array()
		for p in pts:
			poly.append(p - c)
			var u := rect.end.x - p.x if sprite.flip_h else p.x - rect.position.x
			uv.append(region.position + Vector2(u, p.y - rect.position.y))
		var piece := Polygon2D.new()
		piece.texture = sheet
		piece.polygon = poly
		piece.uv = uv
		get_parent().add_child(piece)
		piece.global_position = sprite.to_global(c)
		piece.global_scale = sprite.global_scale
		var top := i == top_index
		var slide := along * (18.0 if top else -3.0) + Vector2(0, -2 if top else 3)
		var t := piece.create_tween().set_parallel()
		t.tween_property(piece, "position", piece.position + slide, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(piece, "rotation", signf(along.x) * (0.6 if top else -0.15), 0.35)
		t.tween_property(piece, "modulate:a", 0.0, 0.25).set_delay(0.35)
		t.chain().tween_callback(piece.queue_free)


# a convex polygon cut by the line through a and b: [the points on one side, the points on the other]
func _split(poly: Array[Vector2], a: Vector2, b: Vector2) -> Array:
	var one: Array[Vector2] = []
	var other: Array[Vector2] = []
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var sp := (b - a).cross(p - a)
		var sq := (b - a).cross(q - a)
		if sp >= 0.0:
			one.append(p)
		if sp <= 0.0:
			other.append(p)
		if (sp > 0.0 and sq < 0.0) or (sp < 0.0 and sq > 0.0):
			var x := p.lerp(q, sp / (sp - sq))
			one.append(x)
			other.append(x)
	return [one, other]


func _centroid(pts: Array[Vector2]) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1.0)


# tiny freeze on impact. The reset is bound to Engine, so it still runs if this minion is freed.
func _hitstop(time: float):
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(time, true, false, true)
	t.timeout.connect(Callable(Engine, "set").bind("time_scale", 1.0))


func _die():
	_set_state(State.DEAD)    # plays DIE (flash + splat), then the sprite hides
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)
	_spawn_splash()
	var drop: Area2D = JuiceDrop.new()
	drop.fruit_name = fruit_name
	drop.color = juice_color
	drop.position = get_parent().to_local(global_position + Vector2(0, -10))
	get_parent().add_child.call_deferred(drop)


func _spawn_splash():
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 2.0    # 2px squares, like the pixel art
	p.color = juice_color
	p.position = get_parent().to_local(global_position + Vector2(0, -12))
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


func _respawn():
	global_position = home
	velocity = Vector2.ZERO
	hp = max_hp
	body_shape.set_deferred("disabled", false)
	_set_state(State.PATROL)


# ---------- hurting the player ----------
func _touch_player():
	if player == null or state in [State.DIZZY, State.HURT, State.DEAD]:
		return
	if _now() < _player_safe_until:
		return
	var mine := Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size)
	var theirs := Rect2(player.global_position + PLAYER_BOX.position, PLAYER_BOX.size)
	if not mine.intersects(theirs):
		return
	_player_safe_until = _now() + PLAYER_SAFE_TIME
	_lunge_landed = state == State.LUNGE
	var dir := signf(_to_player().x)
	if dir == 0.0:
		dir = facing
	player.velocity = Vector2(dir * PLAYER_PUSH.x, PLAYER_PUSH.y)
	# no player health yet: flash red instead
	player.modulate = Color(1, 0.35, 0.35)
	player.create_tween().tween_property(player, "modulate", Color.WHITE, PLAYER_SAFE_TIME)
