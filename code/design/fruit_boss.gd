extends CharacterBody2D
# FRUIT BOSS: Big Pineapple. PLACEHOLDER look (real design: Violeta, animation: BOOM).
#
# Boss card
#   Size:      about 2.5x the player (~100px tall). Walls stop it; the player double-jumps the gate.
#   Armor:     spiky skin. Light hits bounce off (sparks) unless it is dizzy.
#              Heavy smash, running slam and the flash always hurt.
#   Health:    no bar. The crown shows it: full crown -> broken crown -> bald.
#              It gets faster at each stage.
#   Attacks, each with a warning:
#     STOMP    crouches and shakes -> jumps -> lands and sends a shockwave along the floor both ways.
#              Jump over it.
#     ROLL     leans back and shakes -> rolls across the arena until it hits a wall. Double-jump it.
#              Hitting the wall leaves it DIZZY: the big punish window, light hits work too.
#     SUMMON   (broken crown and after) shakes its crown -> 2 Mango minions pop out.
#   Combos:    every hit that gets through knocks it up into the air, and the player is pulled up after
#              it into the AIR COMBO (boss_air_combo.gd): both hang there while the player keeps
#              attacking (Q quick, W big). Stop attacking and it drops (JUGGLED): it falls, lands and
#              needs a moment to get up (RECOVER: can be hurt, not launched). Empty its health during
#              the air combo and it goes straight into the anime finisher.
#   Finish:    when its health runs out it doesn't die: it's BROKEN (dizzy, sparkling over its head).
#              Jump up in front of it for the anime finisher (boss_finisher.gd): time stops, a hundred
#              slashes, the player lands behind it... and it falls apart in pieces.
#   Touch:     its body hurts, except while it is dizzy, broken or dead.
#   Drops:     3 pineapple juice drops. Its summoned minions pop when it dies.
#   Animations BOOM will need (one set per crown stage):
#     IDLE, WALK, STOMP_WINDUP, JUMP, LAND, ROLL_WINDUP, ROLL, DIZZY, SUMMON, DIE
#   (and for the player: a mid-air flurry and a landing pose for the finisher)

enum State { IDLE, WALK, STOMP_WINDUP, JUMP, LAND, ROLL_WINDUP, ROLL, DIZZY, SUMMON, JUGGLED, RECOVER, COMBO, BROKEN, FINISHED, DEAD }

@export_group("Look")
@export var fruit_name := "Pineapple"
@export var juice_color := Color(0.94, 0.77, 0.36)

@export_group("Stats")
@export var max_hp := 12                  # heavy smash, slam and flash do 3; light hits 1 (only when dizzy)
@export var armored := true               # light hits bounce off unless it is dizzy
@export var finisher := true              # out of health = waits for the anime finisher; false = just dies
@export var air_combo := true             # knocking it up pulls the player into the air combo; false = free juggling
@export var knockback_scale := 0.7        # how far hits knock it (it's heavy): 1 = as far as the table says
@export var recover_time := 0.7           # getting up after a combo
@export var engage_range := 520.0         # only fights when the player is this close
@export var idle_time := 0.9              # pause between attacks
@export var walk_speed := 45.0
@export var stomp_windup := 0.6
@export var stomp_jump := Vector2(60, -380)
@export var wave_speed := 220.0
@export var roll_windup := 0.8
@export var roll_speed := 300.0
@export var dizzy_time := 1.8
@export var summon_windup := 0.7
@export var max_minions := 3
@export var respawn_time := 6.0           # gym only: comes back after this long, 0 = stays dead
@export var leash_right := -1.0           # it never goes further right than this from its start (-1 = no limit);
                                          # keeps it out of a doorway next to it

const STAGE_SPEED := [1.0, 1.2, 1.4]      # full crown, broken crown, bald
const WALK_TIME := 1.2
const LAND_TIME := 0.5
const ROLL_MAX_TIME := 5.0
const BONK_PUSH := Vector2(140, -200)
const FLOOR_FRICTION := 900.0
const HURTBOX := Rect2(-30, -80, 60, 80)
const TOUCH_BOX := Rect2(-24, -70, 48, 68)
const FLASH_TIME := 0.08
const SHAKE_LAND := Vector2(10, 0.35)     # strength, seconds
const SHAKE_BONK := Vector2(14, 0.4)
const SHAKE_STAGE := Vector2(6, 0.2)
const HITSTOP := 0.08
const HITSTOP_LIGHT := 0.05               # air combo: quick Q hits...
const HITSTOP_HEAVY := 0.13               # ...and W hits land harder
const FINISHER_REACH := 100.0             # the player must be this close sideways...
const FINISHER_HEIGHT := Vector2(16, 150) # ...and in the air, this far above its feet
const GLINT_Y := -112.0
const GLINT_COLOR := Color(0.94, 0.77, 0.36)
const JUGGLE_GRAVITY := 0.55              # falls slower while juggled, so combos can continue
const JUGGLE_DECAY := 0.1                 # each extra hit in a combo knocks it up 10% less...
const JUGGLE_MIN := 0.35                  # ...down to this much
const JUGGLE_AIR_DRAG := 120.0
const COMBO_COLOR := Color(0.55, 0.2, 0.15)
const COMBO_PULL_RANGE := 220.0           # the player must be this close to be pulled into the air combo

const ANIM_NAMES := {
	State.IDLE: "IDLE",
	State.WALK: "WALK",
	State.STOMP_WINDUP: "STOMP_WINDUP",
	State.JUMP: "JUMP",
	State.LAND: "LAND",
	State.ROLL_WINDUP: "ROLL_WINDUP",
	State.ROLL: "ROLL",
	State.DIZZY: "DIZZY",
	State.SUMMON: "SUMMON",
	State.BROKEN: "DIZZY",
	State.FINISHED: "DIZZY",   # frozen on one frame while the finisher plays
	State.JUGGLED: "JUMP",     # tucked up in the air
	State.COMBO: "JUMP",
	State.RECOVER: "LAND",
	State.DEAD: "DIE",
}

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const BossFinisher := preload("res://code/design/boss_finisher.gd")
const BossAirCombo := preload("res://code/design/boss_air_combo.gd")
const BossWave := preload("res://code/design/boss_wave.gd")
const JuiceSpray := preload("res://code/design/juice_spray.gd")
const EXPLODE_SPRAYS := 14               # the finisher's end: this many juice bursts, all the way around...
const EXPLODE_POWER := 1.8               # ...each nearly twice a Q's spray, and faster
const JuiceDrop := preload("res://code/design/juice_drop.gd")
const MinionScene := preload("res://scene/design/fruit_minion.tscn")
const ARMOR_SOUND := preload("res://sounds/sword/sword_clash_06.wav")   # a hit bouncing off the armor
const ARMOR_SOUND_DB := -6.0          # the clang is much louder than the Q slash
const ARMOR_SOUND_SKIP := 0.012       # the clang gets loud 13ms in; start right there
# heavy impacts: the roll hitting a wall, landing from the stomp jump
const IMPACT_SOUNDS := [preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")]
const IMPACT_SKIP := 0.02             # the file starts with 20ms of silence
const IMPACT_SOUND_DB := -12.0
const IMPACT_PITCH := 0.8             # deeper and heavier (lower = deeper, and a little longer)
# every hit that does damage: a wet squelch (Q, W, the flash, W waves...)
const DAMAGE_SOUND := preload("res://sounds/FLESH_SOUNDS_universfield-wet-squelch-impact-352302.mp3")
const DAMAGE_SOUND_DB := 0.0
const DAMAGE_SOUND_SKIP := 0.12      # the file starts with 0.12 s of silence
const ARMOR_PUSHBACK := 220.0         # a melee hit bouncing off knocks the player back this fast (about 16 px)
# rumbles while it rolls. A 12 s copy of sounds/PINAPPLE_ROLL_...-6953.mp3 with grit added: the original is
# almost all deep bass, which laptop speakers can't play, so it sounded faint.
const ROLL_SOUND := preload("res://sounds/PINAPPLE_ROLL_freesound_community-earth-rumble-6953_boosted.wav")
const ROLL_SOUND_DB := -3.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var state: State = State.IDLE
var state_time := 0.0
var facing := 1
var hp := 12
var home := Vector2.ZERO
var player: CharacterBody2D = null
var _player_states: Array = []
var _last_player_state := -1
var _last_player_time := 0.0
var _hit_this_swing := false
var _stage := 0
var _attacks := 0
var _last_attack: State = State.IDLE
var _minions: Array = []
var _flash_left := 0.0
var _juggle_hits := 0
var _armor_sound := AudioStreamPlayer.new()
var _roll_sound := AudioStreamPlayer.new()
var _roll_fade: Tween
var _impact_sound := AudioStreamPlayer.new()
var _damage_sound := AudioStreamPlayer.new()


func _ready():
	add_to_group("enemies")   # other code finds enemies here and calls take_hit(damage, push)
	sprite.animation_finished.connect(_on_anim_finished)
	home = global_position
	hp = max_hp
	_armor_sound.stream = ARMOR_SOUND
	_armor_sound.volume_db = ARMOR_SOUND_DB
	_armor_sound.max_polyphony = 3      # quick hits layer their ring instead of cutting it off
	add_child(_armor_sound)
	_roll_sound.stream = ROLL_SOUND
	add_child(_roll_sound)
	var impacts := AudioStreamRandomizer.new()    # one of the three, a little higher or lower each time
	for s in IMPACT_SOUNDS:
		impacts.add_stream(-1, s)
	impacts.random_pitch = 1.08
	_impact_sound.stream = impacts
	_impact_sound.volume_db = IMPACT_SOUND_DB
	_impact_sound.pitch_scale = IMPACT_PITCH
	_impact_sound.max_polyphony = 2
	add_child(_impact_sound)
	var squelch := AudioStreamRandomizer.new()   # a different pitch each hit, so combos don't sound repetitive
	squelch.add_stream(-1, DAMAGE_SOUND)
	squelch.random_pitch = 1.3                    # anywhere from about 4 semitones lower to 4 higher
	squelch.random_volume_offset_db = 2.0
	_damage_sound.stream = squelch
	_damage_sound.volume_db = DAMAGE_SOUND_DB
	_damage_sound.max_polyphony = 3
	add_child(_damage_sound)
	_set_state(State.IDLE)


func _find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p == null and get_tree().current_scene:
		p = get_tree().current_scene.get_node_or_null("Player")
	if p is CharacterBody2D and "state" in p:
		player = p
		_player_states = player.get_script().State.keys()
		add_collision_exception_with(player)


func _k() -> float:
	return STAGE_SPEED[_stage]


func _stage_for(h: int) -> int:
	if h > max_hp * 2.0 / 3.0:
		return 0
	if h > max_hp / 3.0:
		return 1
	return 2


func _set_state(s: State):
	if state == State.ROLL and s != State.ROLL:
		_stop_roll_sound()
	state = s
	state_time = 0.0
	_play_anim()
	match s:
		State.RECOVER:
			_juggle_hits = 0        # the combo is over once it lands
		State.JUMP:
			velocity = Vector2(facing * stomp_jump.x, stomp_jump.y)
		State.LAND:
			_stomp_land()
		State.ROLL:
			_start_roll_sound()


# a different stretch of the rumble each roll, faded in and out so it doesn't click
func _start_roll_sound():
	if _roll_fade:
		_roll_fade.kill()
	_roll_sound.volume_db = -40.0
	_roll_sound.play(randf_range(0.0, 6.5))      # a roll lasts 5 s at most
	_roll_fade = create_tween().set_ignore_time_scale(true)
	_roll_fade.tween_property(_roll_sound, "volume_db", ROLL_SOUND_DB, 0.1)


func _stop_roll_sound():
	if _roll_fade:
		_roll_fade.kill()
	_roll_fade = create_tween().set_ignore_time_scale(true)
	_roll_fade.tween_property(_roll_sound, "volume_db", -40.0, 0.25)
	_roll_fade.tween_callback(_roll_sound.stop)


func _play_anim():
	var anim_name := "%s_%d" % [ANIM_NAMES[state], _stage]
	var frames := sprite.sprite_frames
	sprite.speed_scale = 1.0
	# windup animations always last exactly as long as the windup
	var windup := {State.STOMP_WINDUP: stomp_windup, State.ROLL_WINDUP: roll_windup, State.SUMMON: summon_windup}
	if windup.has(state):
		var length := frames.get_frame_count(anim_name) / frames.get_animation_speed(anim_name)
		sprite.speed_scale = length / (windup[state] / _k())
	elif state in [State.WALK, State.ROLL]:
		sprite.speed_scale = _k()
	sprite.visible = true
	sprite.stop()
	sprite.play(anim_name)


func _on_anim_finished():
	if state == State.DEAD:
		sprite.visible = false
	elif String(sprite.animation).begins_with("HURT"):
		_play_anim()            # back to whatever it was doing


# the hurt reaction (flash, jerks back wincing) on top of whatever state it's in
func _play_hurt():
	sprite.speed_scale = 1.0
	sprite.stop()
	sprite.play("HURT_%d" % _stage)


func _physics_process(delta):
	state_time += delta
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.self_modulate = Color.WHITE
	_clean_minions()
	queue_redraw()
	if state in [State.COMBO, State.FINISHED]:
		return                  # boss_air_combo.gd / boss_finisher.gd is in charge now
	if state == State.DEAD:
		if respawn_time > 0.0 and state_time >= respawn_time:
			_respawn()
		return
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()

	if not is_on_floor():
		velocity += get_gravity() * delta * (JUGGLE_GRAVITY if state == State.JUGGLED else 1.0)

	_check_player_attack()
	if state == State.DEAD:
		return

	match state:
		State.IDLE:
			_state_idle(delta)
		State.WALK:
			_state_walk(delta)
		State.STOMP_WINDUP:
			_state_windup(delta, stomp_windup, State.JUMP)
		State.JUMP:
			_state_jump(delta)
		State.LAND:
			_state_land(delta)
		State.ROLL_WINDUP:
			_state_windup(delta, roll_windup, State.ROLL)
		State.ROLL:
			_state_roll(delta)
		State.DIZZY:
			_state_dizzy(delta)
		State.SUMMON:
			_state_summon(delta)
		State.JUGGLED:
			_state_juggled(delta)
		State.RECOVER:
			_state_recover(delta)
		State.BROKEN:
			_state_broken(delta)

	move_and_slide()
	if state == State.ROLL and is_on_wall() and get_wall_normal().x * facing < 0.0:
		_bonk()
	if leash_right >= 0.0 and global_position.x > home.x + leash_right:
		global_position.x = home.x + leash_right   # the leash acts like a wall
		velocity.x = minf(velocity.x, 0.0)
		if state == State.ROLL and facing > 0:
			_bonk()
	sprite.flip_h = facing < 0    # the art faces right
	_touch_player()


# ---------- senses ----------
func _to_player() -> Vector2:
	return player.global_position - global_position


func _face_player():
	if player and absf(_to_player().x) > 2.0:
		facing = int(signf(_to_player().x))


func _player_in_arena() -> bool:
	if player == null or absf(_to_player().x) > engage_range or absf(_to_player().y) > 200.0:
		return false
	# only fights a player it can see: a closed gate or a wall in between hides them
	var from := global_position + Vector2(0, -40)
	var q := PhysicsRayQueryParameters2D.create(from, player.global_position + Vector2(0, -20), 1)
	var skip: Array[RID] = [get_rid(), player.get_rid()]
	q.exclude = skip
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _brake(delta):
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, FLOOR_FRICTION * delta)


# ---------- states ----------
func _state_idle(delta):
	_brake(delta)
	if not _player_in_arena():
		return
	_face_player()
	if state_time >= idle_time / _k():
		_choose_attack()


func _choose_attack():
	_attacks += 1
	var dist := absf(_to_player().x)
	if _stage >= 1 and _attacks % 3 == 0 and _minions.size() < max_minions:
		_set_state(State.SUMMON)
	elif dist > 220.0 or _last_attack == State.STOMP_WINDUP:
		_set_state(State.ROLL_WINDUP)
	elif dist > 110.0 and _last_attack == State.ROLL_WINDUP:
		_set_state(State.WALK)
	else:
		_set_state(State.STOMP_WINDUP)
	_last_attack = state


func _state_walk(_delta):
	_face_player()
	velocity.x = facing * walk_speed * _k()
	if state_time >= WALK_TIME or absf(_to_player().x) < 90.0 or is_on_wall():
		velocity.x = 0.0
		_set_state(State.IDLE)


# shared by the stomp and roll windups: stand and shake, then go
func _state_windup(delta, windup: float, next: State):
	_brake(delta)
	if state_time >= windup / _k():
		_set_state(next)


func _state_jump(_delta):
	if is_on_floor() and state_time > 0.1:
		velocity.x = 0.0
		_set_state(State.LAND)


func _state_land(delta):
	_brake(delta)
	if state_time >= LAND_TIME / _k():
		_set_state(State.IDLE)


func _state_roll(_delta):
	velocity.x = facing * roll_speed * _k()
	if state_time >= ROLL_MAX_TIME:
		velocity.x = 0.0
		_set_state(State.IDLE)


func _state_dizzy(delta):
	_brake(delta)
	if state_time >= dizzy_time:
		_set_state(State.IDLE)


func _state_summon(delta):
	_brake(delta)
	if state_time >= summon_windup / _k():
		_summon()
		_set_state(State.IDLE)


# knocked into the air: helpless until it lands
func _state_juggled(delta):
	velocity.x = move_toward(velocity.x, 0.0, JUGGLE_AIR_DRAG * delta)
	if is_on_floor() and state_time > 0.1:
		velocity.x = 0.0
		_set_state(State.RECOVER)


# landed after a combo: getting back up
func _state_recover(delta):
	_brake(delta)
	if state_time >= recover_time / _k():
		_set_state(State.IDLE)


# out of health: stays dizzy and sparkling until the player jumps up in front of it
func _state_broken(delta):
	_brake(delta)
	if player == null or player.is_on_floor():
		return
	var d := _to_player()
	if absf(d.x) <= FINISHER_REACH and d.y <= -FINISHER_HEIGHT.x and d.y >= -FINISHER_HEIGHT.y:
		start_finisher()


func start_finisher():
	_set_state(State.FINISHED)
	sprite.pause()
	velocity = Vector2.ZERO
	var fin: Node2D = BossFinisher.new()
	fin.boss = self
	fin.player = player
	fin.position = get_parent().to_local(global_position)
	get_parent().add_child.call_deferred(fin)


# ---------- attacks ----------
func _stomp_land():
	_shake(SHAKE_LAND)
	_impact_sound.play(IMPACT_SKIP)
	for dir in [-1, 1]:
		var w: Node2D = BossWave.new()
		w.direction = dir
		w.speed = wave_speed * _k()
		w.position = get_parent().to_local(global_position + Vector2(dir * 34, 0))
		get_parent().add_child.call_deferred(w)


func _bonk():
	velocity = Vector2(-facing * BONK_PUSH.x, BONK_PUSH.y)
	_shake(SHAKE_BONK)
	_impact_sound.play(IMPACT_SKIP)
	_set_state(State.DIZZY)


func _summon():
	for side in [-1, 1]:
		if _minions.size() >= max_minions:
			return
		var m: CharacterBody2D = MinionScene.instantiate()
		m.respawn_time = 0.0          # summoned minions don't come back
		m.facing = side
		m.velocity = Vector2(side * 120, -220)   # pop out of the crown
		m.position = get_parent().to_local(global_position + Vector2(side * 36, -60))
		get_parent().add_child.call_deferred(m)
		_minions.append(m)


# forget summoned minions once they're gone, and clear them away a moment after they die
func _clean_minions():
	var alive := []
	for m in _minions:
		if not is_instance_valid(m):
			continue
		if m.state == m.State.DEAD:
			if m.state_time > 1.0:
				m.queue_free()
			continue
		alive.append(m)
	_minions = alive


func _shake(s: Vector2):
	if player and player.has_method("_shake"):
		player._shake(s.x, s.y)


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
	var hit := EnemyKit.player_attack_hitting(player, _player_states, Rect2(global_position + HURTBOX.position, HURTBOX.size))
	if hit.is_empty():
		return
	_hit_this_swing = true
	if _armor_blocks(hit["damage"]) and player.has_method("bounce_back"):
		player.bounce_back(global_position.x, ARMOR_PUSHBACK)    # bounced off the spiky skin: knocked back a little
	take_hit(hit["damage"], hit["push"])


# armor is off while it's dizzy or up in the air (and in the states where hits don't count anyway)
func _armor_blocks(damage: int) -> bool:
	return armored and damage < 3 and state not in [State.DIZZY, State.JUGGLED, State.COMBO, State.BROKEN, State.FINISHED, State.DEAD]


func take_hit(damage: int, push: Vector2):
	if state in [State.COMBO, State.BROKEN, State.FINISHED, State.DEAD]:
		return
	if _armor_blocks(damage):
		_spawn_sparks()           # bounced off the spiky skin
		_armor_sound.play(ARMOR_SOUND_SKIP)
		return
	hp -= damage
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	spray_juice(_attacker_x(), 1.0 + (damage - 1) * 0.4)    # a Q sprays, a W (3 damage) sprays nearly twice as much
	sprite.self_modulate = Color(4, 4, 4)    # white flash
	_flash_left = FLASH_TIME
	EnemyKit.hitstop(get_tree(), HITSTOP)
	if hp <= 0:
		if finisher:
			hp = 0
			_stage = 2
			_shake(SHAKE_BONK)
			_set_state(State.BROKEN)
		else:
			_die()
		return
	var stage := _stage_for(hp)
	if stage != _stage:
		_stage = stage          # loses part of its crown and speeds up
		_play_anim()
		_shake(SHAKE_STAGE)
	if state != State.RECOVER:
		_knock(push)            # while getting up it can be hurt, but not launched again
	_play_hurt()


# knocked back and up into the air; each extra hit in the same juggle knocks it up a bit less.
# If the player is close, they're pulled up after it into the air combo instead.
func _knock(push: Vector2):
	_juggle_hits = _juggle_hits + 1 if state == State.JUGGLED else 1
	var decay := maxf(JUGGLE_MIN, 1.0 - JUGGLE_DECAY * (_juggle_hits - 1))
	velocity = Vector2(push.x * knockback_scale, push.y * knockback_scale * decay)
	if push.x != 0.0:
		facing = -int(signf(push.x))    # keeps facing the player
	if air_combo and player and _to_player().length() <= COMBO_PULL_RANGE:
		_start_air_combo()
	else:
		_set_state(State.JUGGLED)


func _start_air_combo():
	_set_state(State.COMBO)
	velocity = Vector2.ZERO
	var c: Node2D = BossAirCombo.new()
	c.boss = self
	c.player = player
	get_parent().add_child.call_deferred(c)


# a hit from the air combo: damage and flash, no knockback. True if that emptied its health.
func combo_hit(damage: int) -> bool:
	hp -= damage
	_damage_sound.play(DAMAGE_SOUND_SKIP)
	spray_juice(_attacker_x(), 1.0 + (damage - 1) * 0.4)
	_juggle_hits += 1
	sprite.self_modulate = Color(4, 4, 4)
	_flash_left = FLASH_TIME
	EnemyKit.hitstop(get_tree(), HITSTOP_HEAVY if damage >= 3 else HITSTOP_LIGHT)
	if hp <= 0:
		hp = 0
		_stage = 2
		_play_anim()
		return true
	var stage := _stage_for(hp)
	if stage != _stage:
		_stage = stage          # loses part of its crown mid-combo
		_shake(SHAKE_STAGE)
	_play_hurt()
	return false


# the air combo emptied its health: straight into the anime finisher (or it just dies if that's off)
func combo_finished():
	if finisher:
		start_finisher()
	else:
		_die()


# the player stopped attacking: it falls, lands and gets up
func drop_from_combo(fall_velocity: Vector2):
	velocity = fall_velocity
	_set_state(State.JUGGLED)


func _die():
	_set_state(State.DEAD)    # plays DIE (flash, burst, splat), then the sprite hides
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)
	_shake(SHAKE_BONK)
	_spawn_remains()


# juice bursting out the far side of a cut, away from from_x (whoever cut it), leaning up.
# anywhere = true (the finisher's cuts): it bursts out of a random point all around the body, any direction.
func spray_juice(from_x: float, power: float, anywhere := false):
	var aim: Vector2
	var exit: Vector2                # where it comes out, from the boss's feet
	if anywhere:
		aim = Vector2.from_angle(randf() * TAU)
		exit = Vector2(0, -40) + aim * Vector2(HURTBOX.size.x / 2.0, HURTBOX.size.y / 2.0)
	else:
		var side := signf(global_position.x - from_x)
		if side == 0.0:
			side = float(-facing)
		aim = Vector2(side, -0.35).normalized()
		exit = Vector2(side * HURTBOX.size.x / 2.0, -40.0 + randf_range(-14.0, 14.0))
	_spray(aim, exit, power)


# the finisher's end: it bursts apart, juice exploding out from its middle in every direction
func explode_juice():
	for i in EXPLODE_SPRAYS:
		var aim := Vector2.from_angle(TAU * i / EXPLODE_SPRAYS + randf_range(-0.2, 0.2))
		_spray(aim, Vector2(0, -40) + aim * Vector2(15, 20), EXPLODE_POWER)


func _spray(aim: Vector2, exit: Vector2, power: float):
	var s: Node2D = JuiceSpray.new()
	s.color = juice_color
	s.aim = aim
	s.power = power
	s.floor_y = _ground_y()
	s.position = get_parent().to_local(global_position + exit)
	get_parent().add_child(s)


func _attacker_x() -> float:
	return player.global_position.x if player else global_position.x - facing * 10.0


# called by boss_finisher.gd when the player stops mashing too long: it shrugs it off, full health again
func finisher_failed():
	hp = max_hp
	_stage = 0                  # full crown again
	_juggle_hits = 0
	_flash_left = 0.0
	sprite.self_modulate = Color.WHITE
	velocity = Vector2.ZERO
	_set_state(State.IDLE)      # if it was up in the air, it just drops


# called by boss_finisher.gd once it has fallen apart: no DIE animation, the pieces are the show
func finisher_death():
	state = State.DEAD
	state_time = 0.0
	velocity = Vector2.ZERO
	sprite.visible = false
	body_shape.set_deferred("disabled", true)
	explode_juice()
	_spawn_remains()


func _spawn_remains():
	_spawn_burst(juice_color, Vector2(0, -40), 40, 4.0)
	var ground := _ground_y()     # it may die in mid-air: the drops land on the floor below
	for i in 3:
		var drop: Area2D = JuiceDrop.new()
		drop.fruit_name = fruit_name
		drop.color = juice_color
		drop.position = get_parent().to_local(Vector2(global_position.x + (i - 1) * 24, ground - 10))
		get_parent().add_child.call_deferred(drop)
	# its minions pop with it
	for m in _minions:
		if is_instance_valid(m):
			m.take_hit(3, Vector2(0, -200))


func _ground_y() -> float:
	var from := global_position + Vector2(0, -4)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 600), 1)
	var skip: Array[RID] = [get_rid()]
	if player:
		skip.append(player.get_rid())
	q.exclude = skip
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return global_position.y
	return float(hit["position"].y)


func _spawn_sparks():
	var side := signf(_to_player().x) if player else float(facing)
	_spawn_burst(Color(0.93, 0.87, 0.86), Vector2(side * 28, -40), 8, 2.0)


func _spawn_burst(color: Color, offset: Vector2, amount: int, size: float):
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 90.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.color = color
	p.position = get_parent().to_local(global_position + offset)
	p.finished.connect(p.queue_free)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("emitting", true)


func _respawn():
	global_position = home
	velocity = Vector2.ZERO
	hp = max_hp
	_stage = 0
	_attacks = 0
	_last_attack = State.IDLE
	_flash_left = 0.0
	_juggle_hits = 0
	sprite.self_modulate = Color.WHITE
	body_shape.set_deferred("disabled", false)
	_set_state(State.IDLE)


# ---------- hurting the player ----------
func _touch_player():
	if player == null or state in [State.DIZZY, State.JUGGLED, State.RECOVER, State.COMBO, State.BROKEN, State.DEAD]:
		return
	EnemyKit.hurt_player(player, Rect2(global_position + TOUCH_BOX.position, TOUCH_BOX.size), global_position.x)


# ---------- finisher-ready sparkle over its head (blinks) ----------
func _draw():
	# combo counter while it's being juggled or in the air combo
	if state in [State.JUGGLED, State.COMBO] and _juggle_hits >= 2:
		draw_string(ThemeDB.fallback_font, Vector2(-40, -124), "%d HITS" % _juggle_hits, HORIZONTAL_ALIGNMENT_CENTER, 80, 10, COMBO_COLOR)
	if state != State.BROKEN or int(state_time * 6.0) % 2 == 1:
		return
	draw_rect(Rect2(-6, GLINT_Y, 13, 1), GLINT_COLOR)
	draw_rect(Rect2(0, GLINT_Y - 6, 1, 13), GLINT_COLOR)
	draw_rect(Rect2(-1, GLINT_Y - 1, 3, 3), Color.WHITE)
