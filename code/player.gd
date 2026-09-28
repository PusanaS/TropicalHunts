extends CharacterBody2D

# ---------- STATES (ชื่อเดียวกับแอนิเมชั่นที่จะทำ) ----------
enum State {
	IDLE,
	WALK, RUN, SPRINT,
	BRAKE_LIGHT, BRAKE_HARD,
	JUMP_RISE, JUMP_FALL, DOUBLE_JUMP, LAND,
	ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3,
	ATTACK_HEAVY_WINDUP, ATTACK_HEAVY_SMASH,
	DASH_ATTACK_LIGHT,
	DASH_ATTACK_HEAVY_WINDUP, DASH_ATTACK_HEAVY_SLAM, DASH_ATTACK_HEAVY_IMPACT,
}

# ---------- ค่าปรับแต่ง ----------
const SPEEDS := [0.0, 120.0, 260.0, 420.0]   # index = speed level (0 หยุด, 1 เดิน, 2 วิ่ง, 3 วิ่งเร็ว)
const TIME_TO_LEVEL_2 := 1.0     # เปลี่ยนจาก 0.35 เป็น 1.0 (จากเดินไปวิ่งใช้เวลา 1 วินาที)
const TIME_TO_LEVEL_3 := 1.9     # เปลี่ยนจาก 0.60 เป็น 3.0 (วิ่งเร็วในวินาทีที่ 3)
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
	State.ATTACK_LIGHT_3: 0.45,
}
const LIGHT_LUNGE := 80.0

const HEAVY_WINDUP_TIME := 0.50
const HEAVY_SMASH_TIME := 0.40

# แดชแอทแทคเบา: กลิ้ง + ฟันไว แล้ววิ่งต่อ
const DASH_LIGHT_TIME := 0.30
const DASH_LIGHT_SPEED := 560.0

# แดชแอทแทคหนัก: ดีดตัว -> ลอยง้างดาบ -> ทุบลง -> หยุด
const DASH_HEAVY_LEAP_TIME := 0.12
const DASH_HEAVY_LEAP_X := 200.0
const DASH_HEAVY_LEAP_Y := -320.0
const DASH_HEAVY_WINDUP_TIME := 0.55         # รวมช่วงดีดตัว
const DASH_HEAVY_SLAM_SPEED := 1000.0
const DASH_HEAVY_IMPACT_TIME := 0.55

# กล้องสั่น
const SHAKE_SMALL_STRENGTH := 4.0
const SHAKE_SMALL_TIME := 0.15
const SHAKE_BIG_STRENGTH := 16.0
const SHAKE_BIG_TIME := 0.40

@onready var state_label = $Label
@onready var camera = $Camera2D

var state: State = State.IDLE
var state_time := 0.0
var facing := 1
var speed_level := 0
var hold_time := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_cut_done := false
var air_jumps_left := MAX_AIR_JUMPS
var combo_queued := false
var resume_level := 0
var last_tap_time := {-1: -10.0, 1: -10.0}
var _double_tap_dir := 0

var shake_strength := 0.0
var shake_duration := 0.0
var shake_time_left := 0.0


func _ready():
	_ensure_action("attack_light", KEY_Q)
	_ensure_action("attack_heavy", KEY_W)
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


# ---------- เปลี่ยนสเตท + อัปเดตเลเบล ----------
func _set_state(new_state: State):
	state = new_state
	state_time = 0.0
	_update_label()
	# TODO: ตอนมีสไปร์ท เรียก $AnimationPlayer.play(State.keys()[state].to_lower()) ตรงนี้

	match new_state:
		State.ATTACK_HEAVY_SMASH:
			_shake(SHAKE_SMALL_STRENGTH, SHAKE_SMALL_TIME)
		State.DASH_ATTACK_HEAVY_IMPACT:
			_shake(SHAKE_BIG_STRENGTH, SHAKE_BIG_TIME)


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

	match state:
		State.IDLE, State.WALK, State.RUN, State.SPRINT:
			_state_ground_move(delta, dir)
		State.BRAKE_LIGHT, State.BRAKE_HARD:
			_state_brake(delta, dir)
		State.JUMP_RISE, State.JUMP_FALL, State.DOUBLE_JUMP:
			_state_air(delta, dir)
		State.LAND:
			_state_land(delta, dir)
		State.ATTACK_LIGHT_1, State.ATTACK_LIGHT_2, State.ATTACK_LIGHT_3:
			_state_attack_light(delta)
		State.ATTACK_HEAVY_WINDUP, State.ATTACK_HEAVY_SMASH:
			_state_attack_heavy(delta)
		State.DASH_ATTACK_LIGHT:
			_state_dash_attack_light(delta, dir)
		State.DASH_ATTACK_HEAVY_WINDUP:
			_state_dash_heavy_windup(delta)
		State.DASH_ATTACK_HEAVY_SLAM:
			_state_dash_heavy_slam(delta)
		State.DASH_ATTACK_HEAVY_IMPACT:
			_state_dash_heavy_impact(delta)

	move_and_slide()


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
			_set_state(State.ATTACK_LIGHT_1)
		return true
	return false


# ---------- พื้น: idle / walk / run / sprint ----------
func _state_ground_move(delta, dir):
	if not is_on_floor():
		_set_state(State.JUMP_FALL)
		return
	if _try_jump() or _try_attack():
		return

	if dir != 0:
		var d := int(sign(dir))
		if speed_level >= 2 and d != facing:
			_enter_brake()
			return
		if speed_level == 0 or d != facing:
			facing = d
			if _double_tap_dir == d:
				speed_level = 2
				# ตั้ง hold_time ให้เริ่มนับจากจุดที่วิ่ง เพื่อให้อีก 0.5 วินาทีถัดไป (รวมเป็น 1.5s) กลายเป็น speed_level 3
				hold_time = TIME_TO_LEVEL_3 - 0.5
			else:
				speed_level = 1
				hold_time = 0.0
		hold_time += delta
		if speed_level == 1 and hold_time >= TIME_TO_LEVEL_2:
			speed_level = 2
		elif speed_level == 2 and hold_time >= TIME_TO_LEVEL_3:
			speed_level = 3
		velocity.x = move_toward(velocity.x, facing * SPEEDS[speed_level], ACCEL * delta)
		_set_state_if_changed([State.IDLE, State.WALK, State.RUN, State.SPRINT][speed_level])
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
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if _try_jump():
		return
	if state_time >= LAND_TIME:
		if dir != 0:
			hold_time = 0.0
			speed_level = 1
			_set_state(State.WALK)
		else:
			speed_level = 0
			_set_state(State.IDLE)


# ---------- โจมตีเบา คอมโบ 3 ท่า ----------
func _state_attack_light(delta):
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if Input.is_action_just_pressed("attack_light"):
		combo_queued = true

	var duration: float = LIGHT_DURATIONS[state]
	if state_time >= duration:
		if combo_queued and state != State.ATTACK_LIGHT_3:
			combo_queued = false
			velocity.x = facing * LIGHT_LUNGE
			if state == State.ATTACK_LIGHT_1:
				_set_state(State.ATTACK_LIGHT_2)
			else:
				_set_state(State.ATTACK_LIGHT_3)
		else:
			speed_level = 0
			_set_state(State.IDLE)


# ---------- โจมตีหนัก ง้าง -> ทุบ (หยุดเคลื่อนไหว, กล้องสั่นเล็ก) ----------
func _state_attack_heavy(_delta):
	velocity.x = 0.0
	if state == State.ATTACK_HEAVY_WINDUP and state_time >= HEAVY_WINDUP_TIME:
		_set_state(State.ATTACK_HEAVY_SMASH)
	elif state == State.ATTACK_HEAVY_SMASH and state_time >= HEAVY_SMASH_TIME:
		_set_state(State.IDLE)


# ---------- แดชแอทแทคเบา: กลิ้ง ตีเร็ว วิ่งต่อ ----------
func _state_dash_attack_light(_delta, dir):
	velocity.x = facing * DASH_LIGHT_SPEED
	if state_time >= DASH_LIGHT_TIME:
		if dir != 0 and int(sign(dir)) == facing:
			speed_level = resume_level
			hold_time = TIME_TO_LEVEL_2 if resume_level == 2 else TIME_TO_LEVEL_3
			_set_state(State.RUN if resume_level == 2 else State.SPRINT)
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
