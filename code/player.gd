extends CharacterBody2D
# ---------- เพิ่มบรรทัดนี้ในกลุ่ม @onready ----------
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D   # เปลี่ยนชื่อ node ให้ตรงกับที่คุณใช้จริง

# DEBUG: double-tapping a direction goes straight to the gallop (full speed) instead of the run.
# Untick it in the Inspector (on the Player) for normal play.
@export var debug_tap_gallop := true

# ---------- ชื่อคลิปตามชีทจริง (16 คลิป) ----------
const ANIM_NAMES := {
	State.IDLE: "IDLE",
	State.WALK: "WALK",
	State.RUN: "RUN",
	State.SPRINT: "SPRINT",
	State.GALLOP: "GALLOP",
	State.BRAKE_LIGHT: "BRAKE",
	State.BRAKE_HARD: "BRAKE",
	State.JUMP_RISE: "JUMP_RISE",
	State.JUMP_FALL: "JUMP_FALL",
	State.DOUBLE_JUMP: "DOUBLE_JUMP",
	State.LAND: "LAND",
	State.ATTACK_LIGHT_1: "ATTACK_LIGHT_1",
	State.ATTACK_LIGHT_2: "ATTACK_LIGHT_2",
	State.ATTACK_HEAVY_WINDUP: "ATTACK_HEAVY_WINDUP",
	State.ATTACK_HEAVY_SMASH: "ATTACK_HEAVY_SMASH",
	State.DASH_ATTACK_LIGHT: "DASH_ATTACK_LIGHT",
	State.DASH_ATTACK_HEAVY_WINDUP: "DASH_ATTACK_HEAVY_WINDUP",
	State.DASH_ATTACK_HEAVY_SLAM: "JUMP_FALL",       # รียูส เล่นเร็วขึ้น
	State.DASH_ATTACK_HEAVY_IMPACT: "DASH_ATTACK_HEAVY_IMPACT",
	State.HEAVY_CHARGE: "ATTACK_HEAVY_WINDUP",        # held on its last frame while charging
	State.CHARGED_SMASH: "ATTACK_HEAVY_SMASH",
}

# สเตทที่รียูสคลิป แล้วอยากให้เล่นเร็ว/ช้ากว่าปกติ (ไม่กระทบ const เดิม)
const ANIM_SPEED_OVERRIDE := {
	State.BRAKE_HARD: 1.4,
	State.DASH_ATTACK_HEAVY_SLAM: 1.6,
	State.ATTACK_HEAVY_WINDUP: 5.0,          # short windup (no pause): play all 3 frames in 0.12 s
	State.DASH_ATTACK_HEAVY_WINDUP: 2.5,     # same for the running/air W
	State.CHARGED_SMASH: 1.5,
}
# ---------- STATES (ชื่อเดียวกับแอนิเมชั่นที่จะทำ) ----------
enum State {
	IDLE,
	WALK, RUN, SPRINT,
	BRAKE_LIGHT, BRAKE_HARD,
	JUMP_RISE, JUMP_FALL, DOUBLE_JUMP, LAND,
	ATTACK_LIGHT_1, ATTACK_LIGHT_2,
	ATTACK_HEAVY_WINDUP, ATTACK_HEAVY_SMASH,
	DASH_ATTACK_LIGHT,
	DASH_ATTACK_HEAVY_WINDUP, DASH_ATTACK_HEAVY_SLAM, DASH_ATTACK_HEAVY_IMPACT,
	GALLOP,                          # new states go at the end: enemies read states by position
	HEAVY_CHARGE, CHARGED_SMASH,     # hold W: the heavy swing holds and charges; let go: massive hit
}

# the ground-move state for each speed level
const MOVE_STATES := [State.IDLE, State.WALK, State.RUN, State.SPRINT, State.GALLOP]

# ---------- ค่าปรับแต่ง ----------
const SPEEDS := [0.0, 120.0, 260.0, 420.0, 600.0]   # index = speed level (0 หยุด, 1 เดิน, 2 วิ่ง, 3 วิ่งเร็ว, 4 gallop)
const TIME_TO_LEVEL_2 := 1.0     # เปลี่ยนจาก 0.35 เป็น 1.0 (จากเดินไปวิ่งใช้เวลา 1 วินาที)
const TIME_TO_LEVEL_3 := 1.9     # เปลี่ยนจาก 0.60 เป็น 3.0 (วิ่งเร็วในวินาทีที่ 3)
const TIME_TO_LEVEL_4 := 3.0     # gallop: keep holding 1.1 s after the sprint starts
const DOUBLE_TAP_LEVEL_3_TIME := 0.66
const DOUBLE_TAP_WINDOW := 0.7   
const ACCEL := 1600.0
const FAST_THRESHOLD := 0.7                  # ต้องมีความเร็วจริง >= 70% ของสปีด 2 ถึงจะแดชแอทแทคได้

const BRAKE_LIGHT_FRICTION := {1: 1400.0, 2: 700.0}
const BRAKE_HARD_FRICTION := 1300.0

const JUMP_VELOCITY := -450.0
const DOUBLE_JUMP_VELOCITY := -400.0
const MAX_AIR_JUMPS := 1
const JUMP_CUT := 0.45
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.10
const AIR_FRICTION := 300.0
const LAND_TIME := 0.10

const LIGHT_DURATIONS := {
	State.ATTACK_LIGHT_1: 0.30,
	State.ATTACK_LIGHT_2: 0.30,
}
const LIGHT_LUNGE := 80.0

const HEAVY_WINDUP_TIME := 0.12     # was 0.50: Morgan didn't like the pause before the smash
const HEAVY_SMASH_TIME := 0.40

# hold W: the heavy swing holds and charges; letting go hits everything around, harder the longer
# it charged. The effects (glow, shockwave, dust cloud) are in code/design/charge_fx.gd.
const CHARGE_TIME := 1.0                      # seconds to full charge
const CHARGE_MAX_HOLD := 3.0                  # it lets go by itself after this
const CHARGED_SMASH_TIME := 0.5
const CHARGE_RADIUS := Vector2(80, 180)       # reach at no charge / full charge
const CHARGE_DAMAGE := Vector2(3, 6)          # damage at no charge / full charge
const CHARGE_PUSH := Vector2(260, -380)       # knock at full charge (60% of it at no charge)
const CHARGE_HEIGHT := 90.0                   # enemies this far above or below the feet are hit too

# แดชแอทแทคเบา: กลิ้ง + ฟันไว แล้ววิ่งต่อ
const DASH_LIGHT_TIME := 0.30
const DASH_LIGHT_SPEED := 560.0

# แดชแอทแทคหนัก: ดีดตัว -> ลอยง้างดาบ -> ทุบลง -> หยุด
const DASH_HEAVY_LEAP_TIME := 0.12
const DASH_HEAVY_LEAP_X := 200.0
const DASH_HEAVY_LEAP_Y := -320.0
const DASH_HEAVY_WINDUP_TIME := 0.12         # รวมช่วงดีดตัว (was 0.55: leap straight into the slam, no hover pause)
const DASH_HEAVY_SLAM_SPEED := 1000.0
const DASH_HEAVY_IMPACT_TIME := 0.55

# กล้องสั่น
const SHAKE_SMALL_STRENGTH := 4.0
const SHAKE_SMALL_TIME := 0.15
const SHAKE_BIG_STRENGTH := 16.0
const SHAKE_BIG_TIME := 0.40

# Thunderclap flash: while galloping, an enemy ahead sets it off automatically. Instantly cut
# through every enemy in the lane, reappear past the last one and keep sprinting.
# Enemies: group "enemies" + take_hit().
const FLASH_TRIGGER_RANGE := 120.0   # enemy this close ahead starts it
const FLASH_LANE_HEIGHT := 48.0      # enemies this far above/below the feet still count
const FLASH_MIN_DIST := 160.0
const FLASH_MAX_DIST := 240.0
const FLASH_OVERSHOOT := 32.0        # land this far past the last enemy
const FLASH_DAMAGE := 3
const FLASH_PUSH := Vector2(80, -160)

# Counter: press Q while an enemy is lunging at you -> time stops, it's cut in half, then the player
# teleports to every other enemy that was on screen and cuts them too (code/counter_chain.gd).
# Enemies opt in with is_counterable() (true mid-lunge) and cut_in_half(dir).
const COUNTER_RANGE := 96.0
const CounterChain := preload("res://code/counter_chain.gd")
const COUNTER_BLOCKED := [          # committed moves that can't be interrupted by a counter
	State.ATTACK_HEAVY_WINDUP, State.ATTACK_HEAVY_SMASH,
	State.DASH_ATTACK_HEAVY_WINDUP, State.DASH_ATTACK_HEAVY_SLAM, State.DASH_ATTACK_HEAVY_IMPACT,
]

@onready var state_label = $Label
@onready var camera = $Camera2D

var state: State = State.IDLE
var state_time := 0.0
var facing := 1
var speed_level := 0
var hold_time := 0.0
var charge := 0.0                  # 0..1 while W is held (charge_fx.gd reads it)
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_cut_done := false
var air_jumps_left := MAX_AIR_JUMPS
var combo_queued := false
var light_in_air := false        # the current light attack started in the air (landing cancels it)
var resume_level := 0
var last_tap_time := {-1: -10.0, 1: -10.0}
var _double_tap_dir := 0

var shake_strength := 0.0
var shake_duration := 0.0
var shake_time_left := 0.0

var _sparks: CPUParticles2D

const ComboHud := preload("res://code/combo_hud.gd")


func _ready():
	add_to_group("player")
	_ensure_action("attack_light", KEY_Q)
	_ensure_action("attack_heavy", KEY_W)
	_sparks = _make_sparks()
	add_child(ComboHud.new())
	_set_state(State.IDLE)


func _ensure_action(action: String, key: Key):
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------- กล้องสั่น ----------
func _shake(strength: float, duration: float):
	shake_strength = strength
	shake_duration = duration
	shake_time_left = duration


func _process(delta):
	if shake_time_left > 0.0:
		shake_time_left -= delta
		var fade := clampf(shake_time_left / shake_duration, 0.0, 1.0)
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength * fade
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


func _set_state(new_state: State):
	state = new_state
	state_time = 0.0
	_update_label()
	_play_anim(new_state)          # <-- เพิ่มบรรทัดนี้

	match new_state:
		State.HEAVY_CHARGE:
			# hold the swing: freeze on the windup's last frame while charging
			sprite.frame = sprite.sprite_frames.get_frame_count(sprite.animation) - 1
			sprite.pause()
		State.ATTACK_HEAVY_SMASH:
			_shake(SHAKE_SMALL_STRENGTH, SHAKE_SMALL_TIME)
		State.DASH_ATTACK_HEAVY_IMPACT:
			_shake(SHAKE_BIG_STRENGTH, SHAKE_BIG_TIME)


func _play_anim(s: State):
	var anim_name: String = ANIM_NAMES.get(s, "IDLE")
	sprite.speed_scale = ANIM_SPEED_OVERRIDE.get(s, 1.0)
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	elif not sprite.is_playing():
		sprite.play(anim_name)


func _set_state_if_changed(s: State):
	if s != state:
		_set_state(s)
	else:
		_update_label()


func _update_label():
	state_label.text = "%s  (lv %d)" % [State.keys()[state], speed_level]


func _physics_process(delta):
	state_time += delta

	# แรงโน้มถ่วง (ปิดตอนลอยค้างง้างดาบ)
	if not is_on_floor() and state != State.DASH_ATTACK_HEAVY_WINDUP:
		velocity += get_gravity() * delta

	if is_on_floor():
		coyote_timer = COYOTE_TIME
		air_jumps_left = MAX_AIR_JUMPS
	else:
		coyote_timer -= delta

	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer -= delta

	var dir := Input.get_axis("ui_left", "ui_right")
	_track_double_tap()

	# the counter beats everything else Q would do this frame
	if Input.is_action_just_pressed("attack_light") and _try_counter():
		move_and_slide()
		sprite.flip_h = facing < 0
		return

	match state:
		State.IDLE, State.WALK, State.RUN, State.SPRINT, State.GALLOP:
			_state_ground_move(delta, dir)
		State.BRAKE_LIGHT, State.BRAKE_HARD:
			_state_brake(delta, dir)
		State.JUMP_RISE, State.JUMP_FALL, State.DOUBLE_JUMP:
			_state_air(delta, dir)
		State.LAND:
			_state_land(delta, dir)
		State.ATTACK_LIGHT_1, State.ATTACK_LIGHT_2:
			_state_attack_light(delta)
		State.ATTACK_HEAVY_WINDUP, State.ATTACK_HEAVY_SMASH:
			_state_attack_heavy(delta)
		State.HEAVY_CHARGE:
			_state_heavy_charge(delta)
		State.CHARGED_SMASH:
			_state_charged_smash(delta)
		State.DASH_ATTACK_LIGHT:
			_state_dash_attack_light(delta, dir)
		State.DASH_ATTACK_HEAVY_WINDUP:
			_state_dash_heavy_windup(delta)
		State.DASH_ATTACK_HEAVY_SLAM:
			_state_dash_heavy_slam(delta)
		State.DASH_ATTACK_HEAVY_IMPACT:
			_state_dash_heavy_impact(delta)

	move_and_slide()
	sprite.flip_h = facing < 0


# ---------- ดับเบิลแท็ป ----------
func _track_double_tap():
	_double_tap_dir = 0
	var now_time := _now()
	for d in [-1, 1]:
		var action := "ui_left" if d == -1 else "ui_right"
		if Input.is_action_just_pressed(action):
			if now_time - last_tap_time[d] <= DOUBLE_TAP_WINDOW:
				_double_tap_dir = d
				# เคลียร์ค่าเพื่อป้องกันไม่ให้การกดครั้งที่ 3 นับซ้ำเป็นดับเบิลแท็ปอีกรอบ
				last_tap_time[d] = -10.0
			else:
				last_tap_time[d] = now_time


# ---------- กระโดด / โจมตี (ใช้ร่วมกัน) ----------
func _try_jump() -> bool:
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_cut_done = false
		_set_state(State.JUMP_RISE)
		return true
	return false


func _is_fast() -> bool:
	return speed_level >= 2 and abs(velocity.x) >= SPEEDS[2] * FAST_THRESHOLD


func _try_attack() -> bool:
	if not is_on_floor():
		return false

	if Input.is_action_just_pressed("attack_heavy"):
		var fast := _is_fast()
		velocity.x = 0.0
		speed_level = 0
		if fast:
			_set_state(State.DASH_ATTACK_HEAVY_WINDUP)
		else:
			_set_state(State.ATTACK_HEAVY_WINDUP)
		return true

	if Input.is_action_just_pressed("attack_light"):
		if _is_fast():
			resume_level = speed_level
			_set_state(State.DASH_ATTACK_LIGHT)
		else:
			velocity.x = facing * LIGHT_LUNGE
			combo_queued = false
			light_in_air = false
			_set_state(State.ATTACK_LIGHT_1)
		return true
	return false


# ---------- พื้น: idle / walk / run / sprint ----------
# double-tap a direction: run straight away (or, with debug_tap_gallop, gallop straight away)
func _double_tap_start():
	if debug_tap_gallop:
		speed_level = SPEEDS.size() - 1
		hold_time = TIME_TO_LEVEL_4
		velocity.x = facing * SPEEDS[speed_level]      # full speed at once
	else:
		speed_level = 2
		# ตั้ง hold_time ให้เริ่มนับจากจุดที่วิ่ง เพื่อให้อีก 0.5 วินาทีถัดไป (รวมเป็น 1.5s) กลายเป็น speed_level 3
		hold_time = TIME_TO_LEVEL_3 - 0.5


func _state_ground_move(delta, dir):
	if not is_on_floor():
		_set_state(State.JUMP_FALL)
		return
	if _try_jump() or _try_attack() or _try_flash(dir):
		return

	if dir != 0:
		var d := int(sign(dir))
		if speed_level >= 2 and d != facing:
			_enter_brake()
			return
		if speed_level == 0 or d != facing:
			facing = d
			if _double_tap_dir == d:
				_double_tap_start()
			else:
				speed_level = 1
				hold_time = 0.0
		hold_time += delta
		if speed_level == 1 and hold_time >= TIME_TO_LEVEL_2:
			speed_level = 2
		elif speed_level == 2 and hold_time >= TIME_TO_LEVEL_3:
			speed_level = 3
		elif speed_level == 3 and hold_time >= TIME_TO_LEVEL_4:
			speed_level = 4
		velocity.x = move_toward(velocity.x, facing * SPEEDS[speed_level], ACCEL * delta)
		_set_state_if_changed(MOVE_STATES[speed_level])
	else:
		if speed_level >= 1 and abs(velocity.x) > 5.0:
			_enter_brake()
		else:
			velocity.x = 0.0
			speed_level = 0
			hold_time = 0.0
			_set_state_if_changed(State.IDLE)


# ---------- เบรค ----------
func _enter_brake():
	if speed_level >= 3:
		_set_state(State.BRAKE_HARD)
	else:
		_set_state(State.BRAKE_LIGHT)


func _state_brake(delta, dir):
	if not is_on_floor():
		_set_state(State.JUMP_FALL)
		return
	if _try_jump() or _try_attack():
		return

	var friction: float
	if state == State.BRAKE_HARD:
		friction = BRAKE_HARD_FRICTION
	else:
		friction = BRAKE_LIGHT_FRICTION.get(speed_level, 1000.0)
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	if dir != 0:
		var d := int(sign(dir))
		if d == facing:
			if _double_tap_dir == d:
				_double_tap_start()
				_set_state(MOVE_STATES[speed_level])
				return
			hold_time = 0.0
			speed_level = max(speed_level, 1)
			_set_state(State.WALK)
			return
		elif abs(velocity.x) < SPEEDS[1]:
			facing = d
			speed_level = 1
			hold_time = 0.0
			_set_state(State.WALK)
			return

	if abs(velocity.x) < 5.0:
		velocity.x = 0.0
		speed_level = 0
		_set_state(State.IDLE)


# ---------- อากาศ (กระโดด / ดับเบิ้ลจัมพ์ / ตก) ----------
func _state_air(delta, dir):
	if jump_buffer_timer > 0.0:
		# 1) กระโดดตอนตกขอบ (coyote time) ไม่กินสิทธิ์ดับเบิ้ลจัมพ์
		if _try_jump():
			return
		# 2) ดับเบิ้ลจัมพ์
		if air_jumps_left > 0:
			air_jumps_left -= 1
			velocity.y = DOUBLE_JUMP_VELOCITY
			jump_buffer_timer = 0.0
			jump_cut_done = false
			_set_state(State.DOUBLE_JUMP)
			return

	if _try_air_attack():
		return

	# กระโดดสั้น/ยาวตามระยะเวลากดปุ่ม (ใช้กับดับเบิ้ลจัมพ์ด้วย)
	if not jump_cut_done and velocity.y < 0.0 and not Input.is_action_pressed("ui_accept"):
		velocity.y *= JUMP_CUT
		jump_cut_done = true

	if dir != 0:
		var d := int(sign(dir))
		facing = d
		var target: float = SPEEDS[max(speed_level, 1)]
		velocity.x = move_toward(velocity.x, d * target, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, AIR_FRICTION * delta)

	if velocity.y > 0.0:
		_set_state_if_changed(State.JUMP_FALL)

	if is_on_floor() and state_time > 0.02:
		_set_state(State.LAND)


func _state_land(delta, dir):
	if dir == 0:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if _try_jump():
		return
	if state_time >= LAND_TIME:
		if dir != 0:
			if speed_level == 0:
				speed_level = 1
				hold_time = 0.0
			_set_state(MOVE_STATES[speed_level])
		else:
			speed_level = 0
			_set_state(State.IDLE)


func _state_attack_light(delta):
	# landing in the middle of an air light attack cancels it: show the landing instead
	if light_in_air and is_on_floor():
		light_in_air = false
		combo_queued = false
		_set_state(State.LAND)
		return
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)   # in the air you keep drifting
	if Input.is_action_just_pressed("attack_light"):
		combo_queued = true

	var duration: float = LIGHT_DURATIONS[state]
	if state_time >= duration:
		if combo_queued:
			combo_queued = false
			if is_on_floor():
				velocity.x = facing * LIGHT_LUNGE
			# สลับท่า: 1 -> 2, 2 -> 1 วนไปเรื่อยๆ
			if state == State.ATTACK_LIGHT_1:
				_set_state(State.ATTACK_LIGHT_2)
			else:
				_set_state(State.ATTACK_LIGHT_1)
		elif not is_on_floor():
			_set_state(State.JUMP_FALL)   # keeps speed_level, so air control stays the same
		else:
			speed_level = 0
			_set_state(State.IDLE)     # ปล่อยปุ่มเมื่อไหร่ กลับ IDLE ได้จากทั้ง 1 และ 2


# ---------- Air attacks: Q = light combo (no lunge), W = slam straight down (no hover first) ----------
func _try_air_attack() -> bool:
	if Input.is_action_just_pressed("attack_heavy"):
		velocity.x = 0.0
		speed_level = 0
		_set_state(State.DASH_ATTACK_HEAVY_SLAM)
		return true
	if Input.is_action_just_pressed("attack_light"):
		combo_queued = false
		light_in_air = true
		_set_state(State.ATTACK_LIGHT_1)
		return true
	return false


# ---------- โจมตีหนัก ง้าง -> ทุบ (หยุดเคลื่อนไหว, กล้องสั่นเล็ก) ----------
func _state_attack_heavy(_delta):
	velocity.x = 0.0
	if state == State.ATTACK_HEAVY_WINDUP and state_time >= HEAVY_WINDUP_TIME:
		if Input.is_action_pressed("attack_heavy"):
			charge = 0.0
			_set_state(State.HEAVY_CHARGE)       # still holding W: hold the swing and charge it
		else:
			_set_state(State.ATTACK_HEAVY_SMASH)
	elif state == State.ATTACK_HEAVY_SMASH and state_time >= HEAVY_SMASH_TIME:
		_set_state(State.IDLE)


# ---------- hold W: charge the heavy smash, let go for a massive hit ----------
func _state_heavy_charge(_delta):
	velocity.x = 0.0
	if not is_on_floor():                        # knocked off the ground: the charge is lost
		charge = 0.0
		_set_state(State.JUMP_FALL)
		return
	charge = minf(state_time / CHARGE_TIME, 1.0)
	if not Input.is_action_pressed("attack_heavy") or state_time >= CHARGE_MAX_HOLD:
		_set_state(State.CHARGED_SMASH)
		_charged_hit()


func _state_charged_smash(_delta):
	velocity.x = 0.0
	if state_time >= CHARGED_SMASH_TIME:
		charge = 0.0
		_set_state(State.IDLE)


# hits every enemy around the player; reach, damage and knock grow with the charge
func _charged_hit():
	var reach := lerpf(CHARGE_RADIUS.x, CHARGE_RADIUS.y, charge)
	var damage := int(round(lerpf(CHARGE_DAMAGE.x, CHARGE_DAMAGE.y, charge)))
	var knock := 0.6 + 0.4 * charge
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not _is_alive(e) or not e.has_method("take_hit"):
			continue
		var d: Vector2 = e.global_position - global_position
		if absf(d.x) <= reach and absf(d.y) <= CHARGE_HEIGHT:
			var side := signf(d.x) if d.x != 0.0 else float(facing)
			e.take_hit(damage, Vector2(side * CHARGE_PUSH.x * knock, CHARGE_PUSH.y * knock))
	_shake(SHAKE_BIG_STRENGTH * (0.6 + 0.6 * charge), SHAKE_BIG_TIME + 0.2 * charge)


# ---------- แดชแอทแทคเบา: กลิ้ง ตีเร็ว วิ่งต่อ ----------
func _state_dash_attack_light(_delta, dir):
	velocity.x = facing * DASH_LIGHT_SPEED
	if state_time >= DASH_LIGHT_TIME:
		if dir != 0 and int(sign(dir)) == facing:
			speed_level = resume_level
			hold_time = [0.0, 0.0, TIME_TO_LEVEL_2, TIME_TO_LEVEL_3, TIME_TO_LEVEL_4][resume_level]
			_set_state(MOVE_STATES[resume_level])
		else:
			_enter_brake()


# ---------- แดชแอทแทคหนัก: ดีดตัว -> ลอยง้างดาบ -> ทุบ -> หยุด (กล้องสั่นใหญ่) ----------
func _state_dash_heavy_windup(_delta):
	if state_time < DASH_HEAVY_LEAP_TIME:
		velocity = Vector2(facing * DASH_HEAVY_LEAP_X, DASH_HEAVY_LEAP_Y)
	else:
		velocity = Vector2.ZERO          # ลอยค้างกลางอากาศ ง้างดาบใหญ่
	if state_time >= DASH_HEAVY_WINDUP_TIME:
		_set_state(State.DASH_ATTACK_HEAVY_SLAM)


func _state_dash_heavy_slam(_delta):
	velocity.x = 0.0
	velocity.y = max(velocity.y, DASH_HEAVY_SLAM_SPEED)
	if is_on_floor() and state_time > 0.03:
		_set_state(State.DASH_ATTACK_HEAVY_IMPACT)


func _state_dash_heavy_impact(_delta):
	velocity.x = 0.0
	if state_time >= DASH_HEAVY_IMPACT_TIME:
		speed_level = 0
		_set_state(State.IDLE)


# ---------- Thunderclap flash: sprint into an enemy -> cut through, reappear, keep sprinting ----------
func _try_flash(dir) -> bool:
	if speed_level < 4 or int(sign(dir)) != facing or not is_on_floor():   # gallop only
		return false
	if _enemies_ahead(FLASH_TRIGGER_RANGE).is_empty():
		return false
	_flash_strike()
	return true


func _flash_strike():
	var start := global_position
	var targets := _enemies_ahead(FLASH_MAX_DIST)
	var dist := FLASH_MIN_DIST
	for e in targets:
		dist = maxf(dist, (e.global_position.x - start.x) * facing + FLASH_OVERSHOOT)
	dist = minf(dist, FLASH_MAX_DIST)
	dist = _flash_clear_distance(dist)      # stop at walls
	dist = _flash_ground_distance(dist)     # never land over a pit
	for e in targets:
		if (e.global_position.x - start.x) * facing <= dist and e.has_method("take_hit"):
			e.take_hit(FLASH_DAMAGE, Vector2(facing * FLASH_PUSH.x, FLASH_PUSH.y))
	global_position.x = start.x + facing * dist
	velocity.x = facing * SPEEDS[speed_level]      # come out of it at the same speed (sprint or gallop)
	_flash_streak(start + Vector2(0, -20), global_position + Vector2(0, -20))
	_sparks.restart()                               # burst where it lands
	_shake(SHAKE_BIG_STRENGTH, SHAKE_SMALL_TIME)
	_set_state(MOVE_STATES[speed_level])


func _try_counter() -> bool:
	if state in COUNTER_BLOCKED:
		return false
	var target: Node2D = null
	var best := COUNTER_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and e.has_method("is_counterable") and e.is_counterable():
			var d := global_position.distance_to(e.global_position)
			if d <= best:
				best = d
				target = e
	if target == null:
		return false
	velocity = Vector2.ZERO
	speed_level = 0
	hold_time = 0.0
	var chain := CounterChain.new()     # takes over from here: freezes time and runs the cuts
	chain.player = self
	chain.first = target
	get_parent().add_child(chain)
	return true


func _enemies_ahead(reach: float) -> Array:
	var found := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not _is_alive(e):
			continue
		var d: float = (e.global_position.x - global_position.x) * facing
		if d > 0.0 and d <= reach and absf(e.global_position.y - global_position.y) <= FLASH_LANE_HEIGHT:
			found.append(e)
	return found


func _is_alive(e: Node) -> bool:
	if e.has_method("is_alive"):
		return e.is_alive()
	var hp = e.get("hp")
	return hp == null or hp > 0


# how far the body can slide sideways before a wall stops it (enemies don't block it)
func _flash_clear_distance(dist: float) -> float:
	var body: CollisionShape2D = $CollisionShape2D
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = body.shape
	q.transform = body.global_transform.translated(Vector2(0, -4))   # just off the floor
	q.motion = Vector2(facing * dist, 0)
	q.collision_mask = collision_mask
	q.exclude = _flash_exclude()
	return dist * get_world_2d().direct_space_state.cast_motion(q)[0]


# step back from the landing spot until there is floor under it
func _flash_ground_distance(dist: float) -> float:
	var space := get_world_2d().direct_space_state
	var d := dist
	while d > 0.0:
		var x := global_position.x + facing * d
		var q := PhysicsRayQueryParameters2D.create(Vector2(x, global_position.y - 8), Vector2(x, global_position.y + 24), collision_mask, _flash_exclude())
		if not space.intersect_ray(q).is_empty():
			return d
		d -= 8.0
	return 0.0


func _flash_exclude() -> Array[RID]:
	var ex: Array[RID] = [get_rid()]
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is CollisionObject2D:
			ex.append(e.get_rid())
	return ex


func _flash_streak(from: Vector2, to: Vector2):
	var line := Line2D.new()
	line.top_level = true
	line.points = PackedVector2Array([from, to])
	line.width = 10.0
	line.default_color = Color(1.0, 0.95, 0.45)
	add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "width", 0.0, 0.25)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.25)
	t.tween_callback(line.queue_free)


func _make_sparks() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 24
	p.lifetime = 0.25
	p.position = Vector2(0, -20)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 16.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1.0, 0.95, 0.45)
	add_child(p)
	return p
