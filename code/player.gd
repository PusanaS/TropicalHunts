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
	State.KNOCKBACK: "KNOCKBACK",                    # BOOM's PsVxp.png (built in _add_extra_anims); then STUN
	State.EDGE_GRAB: "EDGE_GRAB",                    # BOOM's PsVxp.png
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
	KNOCKBACK,                       # galloped into a wall: knocked back, then dazed for a moment
	EDGE_GRAB,                       # hanging from a ledge's edge: jump/up climbs on, down/away lets go
}

# the ground-move state for each speed level
const MOVE_STATES := [State.IDLE, State.WALK, State.RUN, State.SPRINT, State.GALLOP]

# ---------- ค่าปรับแต่ง ----------
const SPEEDS := [0.0, 120.0, 260.0, 420.0, 600.0]   # index = speed level (0 หยุด, 1 เดิน, 2 วิ่ง, 3 วิ่งเร็ว, 4 gallop)
const TIME_TO_LEVEL_2 := 0.5     # เปลี่ยนจาก 0.35 เป็น 1.0 (จากเดินไปวิ่งใช้เวลา 1 วินาที)
                                 # then 0.5: Morgan wanted half as long walking. Run and sprint keep their lengths:
const TIME_TO_LEVEL_3 := 1.4     # เปลี่ยนจาก 0.60 เป็น 3.0 (วิ่งเร็วในวินาทีที่ 3)   (was 1.9: run 0.9 s)
const TIME_TO_LEVEL_4 := 2.5     # gallop: keep holding 1.1 s after the sprint starts   (was 3.0)
const DOUBLE_TAP_LEVEL_3_TIME := 0.66
const DOUBLE_TAP_WINDOW := 0.7   
const ACCEL := 1600.0
const FAST_THRESHOLD := 0.7                  # ต้องมีความเร็วจริง >= 70% ของสปีด 2 ถึงจะแดชแอทแทคได้

const BRAKE_LIGHT_FRICTION := {1: 1400.0, 2: 700.0}
const BRAKE_HARD_FRICTION := 1300.0

const JUMP_VELOCITY := -450.0
const DOUBLE_JUMP_VELOCITY := -400.0
const MAX_AIR_JUMPS := 1
const JUMP_CUT := 0.82                # a quick tap still clears a 64px step (~70-83px); holding gets the full ~103 (Morgan's call, 2026-10-08: was 0.45, a tap was only ~25-50px)
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
# it charged. Keep holding and it goes off by itself just after full charge. The effects (glow, shockwave, dust cloud) are in code/design/charge_fx.gd.
const CHARGE_TIME := 0.35                     # seconds to full charge (was 1.0, then 0.5: Morgan wanted a shorter hold)
const CHARGE_FULL_HOLD := 0.15                # at full charge it holds just this long, then lets go by itself
const CHARGE_MAX_HOLD := CHARGE_TIME + CHARGE_FULL_HOLD   # (was 2 s at full charge: Morgan wanted holding W to go off sooner)
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

# attack sounds, played the moment a swing hits (in _set_state). Both files start quiet, so they play
# from a little way in.
const Q_SOUND := preload("res://sounds/Q_HIT_54427377-sword-slash-476148.mp3")
const Q_SOUND_SKIP := 0.60          # the file has 0.6 s of silence first; starts right as the slash gets loud
const W_SOUND := preload("res://sounds/W_HIT_daviddumaisaudio-sword-slash-and-swing-185432.mp3")
const W_SOUND_SKIP := 0.19          # skip the swing's build-up, so it's already loud when the smash lands

# a Q or W swing that reaches a wall clangs off it (the same clang as the boss's armor)
const WALL_SOUND := preload("res://sounds/sword/sword_clash_06.wav")
const WALL_SOUND_DB := -6.0         # the clang is much louder than the Q slash
const WALL_SOUND_SKIP := 0.012      # the clang gets loud 13ms in; start right there
const WALL_REACH := {               # how far ahead of the player's middle each swing reaches
	State.ATTACK_LIGHT_1: 44.0,
	State.ATTACK_LIGHT_2: 44.0,
	State.DASH_ATTACK_LIGHT: 40.0,
	State.ATTACK_HEAVY_SMASH: 56.0,
	State.CHARGED_SMASH: 56.0,
	State.DASH_ATTACK_HEAVY_IMPACT: 56.0,
}

# footsteps: a random grass step (made in code, sounds/footsteps/) each time a foot plants
const FOOTSTEP_SOUNDS := [
	preload("res://sounds/footsteps/footstep_grass_01.wav"),
	preload("res://sounds/footsteps/footstep_grass_02.wav"),
	preload("res://sounds/footsteps/footstep_grass_03.wav"),
	preload("res://sounds/footsteps/footstep_grass_04.wav"),
	preload("res://sounds/footsteps/footstep_grass_05.wav"),
	preload("res://sounds/footsteps/footstep_grass_06.wav"),
]
const FOOTSTEP_DB := -12.0          # quieter than the attacks
# in water (the living background's pits and shallows): a splash instead, cut from
# sounds/WATER_FOOTSTEP_freesound_community-splash-6213.mp3 (its main splash, 0.20-0.44 s)
const FOOTSTEP_WATER_SOUND := preload("res://sounds/footsteps/footstep_water.wav")
const FOOTSTEP_WATER_DB := -10.0

# hold W: a build-up made in code (sounds/charge_buildup.wav). The file rises for 1 s, "tings", then hums
# for 2 s. It starts partway in when CHARGE_TIME is shorter, so the ting lands right at full charge. It
# stops (a quick fade) the moment the charge ends.
const CHARGE_SOUND := preload("res://sounds/charge_buildup.wav")
const CHARGE_SOUND_DB := -8.0
const CHARGE_SOUND_FULL_AT := 1.0   # where the ting is in the file

# galloping into a wall: an impact, the same one as the boss's, played lighter
const WALL_IMPACT_SOUNDS := [preload("res://sounds/IMPACT_dragon-studio-hard-heavy-impact-515256.mp3")]
const WALL_IMPACT_SKIP := 0.02       # the file starts with 20ms of silence
const WALL_IMPACT_DB := -14.0
const WALL_IMPACT_PITCH := 0.95     # a bit higher than the boss's (0.8): the player is smaller

# galloping into a wall: squashed against it for a moment, knocked back in a little arc (leaning back),
# then dazed on the ground with stars over the head before you can move again.
# PLACEHOLDER animation, made in code from BOOM's existing frames until he draws a real KNOCKBACK.
const KNOCKBACK_PUSH := Vector2(180, -200)    # back and up
const KNOCKBACK_IMPACT_TIME := 0.08            # squashed flat against the wall, flashing white
const KNOCKBACK_TILT := 0.2                    # radians: how far it leans back while flying (BOOM's frame already leans)
const KNOCKBACK_DAZE := 0.5                    # dazed on the ground before control returns (one STUN loop; was 0.3)
# BOOM's extra frames (PsVxp.png, 128x128 cells like PsV3.png): 1 edge grab, 2 knockback, 3-6 stun (stars drawn in)
const EXTRA_SHEET := preload("res://PsVxp.png")
const STUN_FPS := 8.0
# grabbing a ledge's edge (Morgan's call, 2026-10-08): falling past a ledge while pushing toward it, with its top
# near your hands, you catch it and hang (EDGE_GRAB). Jump or up pulls you on; down or pushing away lets go.
const GRAB_HANG := 27.0                        # hanging: your feet are this far below the ledge's top (the paw's on it)
const GRAB_WINDOW := Vector2(16, 40)           # a ledge top this far above your feet (min, max) can be caught
const GRAB_FEEL := 21.0                        # how far in front of your middle it feels for the ledge
const GRAB_COOL := 0.3                         # after letting go or climbing on, before you can grab again
const CLIMB_HOP := Vector2(130, -340)          # pulling up onto the ledge: a little hop up and forward
const BODY_HALF := 15.0                        # (the capsule's radius)
const KNOCKBACK_SHAKE := Vector2(8, 0.25)      # strength, seconds

# jump and double jump: a crunchy step, sounds/JUMP_V2_freesound_community-snow-step-1-81064.mp3 trimmed and
# brought up to full volume (sounds/jump/jump_snow.wav). A splash step instead in water. The double jump is
# the same sound, a bit higher.
const JUMP_SOUNDS := [preload("res://sounds/jump/jump_snow.wav")]
const DOUBLE_JUMP_PITCH := 1.12     # about 2 semitones higher
const JUMP_SOUND_DB := -9.0         # a touch louder than the footsteps (-12)

const RECOIL_TIME := 0.15          # bounce_back: the knock lasts this long, slowing to a stop
const FOOTSTEP_ANIMS := ["WALK", "RUN", "SPRINT", "GALLOP"]
const FOOTSTEP_FRAMES := [0, 2]     # a foot plants on these frames in all four cycles (BOOM's sheet)

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
# Enemies opt in with is_counterable() (true mid-lunge) and cut_in_half(dir, a, b).
const COUNTER_RANGE := 160.0         # was 96: the Mango now pounces from 140 px, and the whole pounce counts
const CounterChain := preload("res://code/counter_chain.gd")
const FlashFinish := preload("res://code/flash_finish.gd")   # the flash's freeze-frame, then its kills
const COUNTER_BLOCKED := [          # committed moves that can't be interrupted by a counter
	State.ATTACK_HEAVY_WINDUP, State.ATTACK_HEAVY_SMASH,
	State.DASH_ATTACK_HEAVY_WINDUP, State.DASH_ATTACK_HEAVY_SLAM, State.DASH_ATTACK_HEAVY_IMPACT,
	State.KNOCKBACK,
]

@onready var state_label = $Label
@onready var camera = $Camera2D

var state: State = State.IDLE
var state_time := 0.0
var facing := 1
var speed_level := 0
var hold_time := 0.0
var charge := 0.0                  # 0..1 while W is held (charge_fx.gd reads it)
var flashing := false              # true while the flash's hits land (flash_finish.gd), so targets can tell
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
var _q_sound: AudioStreamPlayer
var _w_sound: AudioStreamPlayer
var _wall_sound: AudioStreamPlayer
var _wall_clanged := false         # this swing already clanged off a wall
var _step_sound: AudioStreamPlayer
var _water_step_sound: AudioStreamPlayer
var _charge_sound: AudioStreamPlayer
var _charge_fade: Tween
var _wall_impact_sound: AudioStreamPlayer
var _recoil_speed := 0.0
var _recoil_left := 0.0
var _launch_left := 0.0            # launch(): air steering waits this long, so the arc goes where it was aimed
var _knock_phase := 0               # 0 squashed against the wall, 1 flying back, 2 dazed on the ground
var _knock_time := 0.0
var _grab_cool := 0.0
var _grab_top := 0.0                           # the ledge you're hanging from: its top...
var _grab_wall := 0.0                          # ...and its face (global)
var _jump_sound: AudioStreamPlayer
var _double_jump_sound: AudioStreamPlayer

const ComboHud := preload("res://code/combo_hud.gd")


func _ready():
	add_to_group("player")
	_ensure_action("attack_light", KEY_Q)
	_ensure_action("attack_heavy", KEY_W)
	_sparks = _make_sparks()
	_q_sound = _make_sound(Q_SOUND)
	_w_sound = _make_sound(W_SOUND)
	_wall_sound = _make_sound(WALL_SOUND)
	_wall_sound.volume_db = WALL_SOUND_DB
	var steps := AudioStreamRandomizer.new()     # a different step each time, never the same twice in a row
	for s in FOOTSTEP_SOUNDS:
		steps.add_stream(-1, s)
	steps.random_pitch = 1.1                     # each step a little higher or lower
	steps.random_volume_offset_db = 2.0
	_step_sound = _make_sound(steps)
	_step_sound.volume_db = FOOTSTEP_DB
	var splash := AudioStreamRandomizer.new()    # one splash, varied in pitch so steps don't sound identical
	splash.add_stream(-1, FOOTSTEP_WATER_SOUND)
	splash.random_pitch = 1.15
	splash.random_volume_offset_db = 2.0
	_water_step_sound = _make_sound(splash)
	_water_step_sound.volume_db = FOOTSTEP_WATER_DB
	sprite.frame_changed.connect(_on_sprite_frame)
	_charge_sound = _make_sound(CHARGE_SOUND)
	_charge_sound.max_polyphony = 1
	_add_extra_anims()
	_jump_sound = _make_jump_sound(JUMP_SOUNDS)
	_double_jump_sound = _make_jump_sound(JUMP_SOUNDS)
	_double_jump_sound.pitch_scale = DOUBLE_JUMP_PITCH
	var impacts := AudioStreamRandomizer.new()
	for s in WALL_IMPACT_SOUNDS:
		impacts.add_stream(-1, s)
	impacts.random_pitch = 1.08
	_wall_impact_sound = _make_sound(impacts)
	_wall_impact_sound.volume_db = WALL_IMPACT_DB
	_wall_impact_sound.pitch_scale = WALL_IMPACT_PITCH
	add_child(ComboHud.new())
	_set_state(State.IDLE)


# a random one of the variations each jump, at a slightly different pitch, so it doesn't get samey
func _make_jump_sound(streams: Array) -> AudioStreamPlayer:
	var r := AudioStreamRandomizer.new()
	for s in streams:
		r.add_stream(-1, s)
	r.random_pitch = 1.05
	var p := _make_sound(r)
	p.volume_db = JUMP_SOUND_DB
	return p


func _make_sound(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.max_polyphony = 3            # quick swings layer instead of cutting the last one off
	add_child(p)
	return p


func _start_charge_sound():
	if _charge_fade:
		_charge_fade.kill()
	_charge_sound.volume_db = CHARGE_SOUND_DB
	_charge_sound.play(maxf(CHARGE_SOUND_FULL_AT - CHARGE_TIME, 0.0))


# a very quick fade instead of a hard stop, so it doesn't click (real time: hit-freezes don't slow it)
func _stop_charge_sound():
	if not _charge_sound.playing:
		return
	_charge_fade = create_tween().set_ignore_time_scale(true)
	_charge_fade.tween_property(_charge_sound, "volume_db", -60.0, 0.06)
	_charge_fade.tween_callback(_charge_sound.stop)


# ---------- galloping into a wall: knockback ----------
# PLACEHOLDER animation: three of BOOM's existing poses (brake = squashed against the wall, double jump =
# flying back, land = dazed), copied from his animations so they follow his updates. His sheet is untouched.
# BOOM's extra animations, cut from PsVxp.png at runtime (scene/player.tscn's SpriteFrames are untouched):
# EDGE_GRAB (frame 1), KNOCKBACK (frame 2) and STUN (frames 3-6, looping, with its own dizzy stars)
func _add_extra_anims():
	var frames := sprite.sprite_frames
	for a: Array in [["EDGE_GRAB", [0], 5.0, false], ["KNOCKBACK", [1], 5.0, false], ["STUN", [2, 3, 4, 5], STUN_FPS, true]]:
		var anim: String = a[0]
		if frames.has_animation(anim):
			frames.remove_animation(anim)
		frames.add_animation(anim)
		frames.set_animation_loop(anim, a[3])
		frames.set_animation_speed(anim, a[2])
		for cell: int in a[1]:
			var tex := AtlasTexture.new()
			tex.atlas = EXTRA_SHEET
			tex.region = Rect2(cell * 128, 0, 128, 128)
			frames.add_frame(anim, tex)


func _start_knockback():
	speed_level = 0
	hold_time = 0.0
	_set_state(State.KNOCKBACK)
	_knock_phase = 0
	_knock_time = 0.0
	velocity = Vector2.ZERO
	sprite.self_modulate = Color(2.5, 2.5, 2.5)     # white flash
	sprite.scale = Vector2(0.75, 1.2)                # squashed against the wall
	_shake(KNOCKBACK_SHAKE.x, KNOCKBACK_SHAKE.y)


func _state_knockback(delta):
	_knock_time += delta
	match _knock_phase:
		0:   # squashed flat against the wall, flashing white
			velocity = Vector2.ZERO
			if _knock_time >= KNOCKBACK_IMPACT_TIME:
				_knock_phase = 1
				_knock_time = 0.0
				velocity = Vector2(-facing * KNOCKBACK_PUSH.x, KNOCKBACK_PUSH.y)
				sprite.scale = Vector2.ONE
				sprite.self_modulate = Color.WHITE
		1:   # flying back in an arc, leaning further back (head away from the wall)
			sprite.rotation = -facing * KNOCKBACK_TILT * minf(_knock_time / 0.3, 1.0)
			if is_on_floor() and _knock_time > 0.05:
				_knock_phase = 2
				_knock_time = 0.0
				sprite.play("STUN")             # BOOM's stun: dazed, stars round the head
				sprite.rotation = 0.0
			elif _knock_time > 2.0:            # never landed (fell off something): just fall
				_set_state(State.JUMP_FALL)
		2:   # dazed on the ground for a moment
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
			if _knock_time >= KNOCKBACK_DAZE:
				_set_state(State.IDLE)


func _end_knockback_look():
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	sprite.self_modulate = Color.WHITE


# ---------- grabbing a ledge's edge ----------
# falling past a ledge while pushing toward it, its top near your hands: catch it and hang (EDGE_GRAB)
func _try_grab(dir: float) -> bool:
	if _grab_cool > 0.0 or velocity.y < -60.0 or _launch_left > 0.0 or dir == 0.0 or int(signf(dir)) != facing:
		return false
	var f := float(facing)
	var p := global_position
	# feel down in front of you for the ledge's top, within reach of your hands
	var x := p.x + f * GRAB_FEEL
	var top_hit := _grab_ray(Vector2(x, p.y - GRAB_WINDOW.y - 2.0), Vector2(x, p.y - GRAB_WINDOW.x))
	if top_hit.is_empty() or top_hit["normal"].y > -0.7:
		return false
	var top: float = top_hit["position"].y
	# its face, just under the top, and open space above it to climb into
	var face := _grab_ray(Vector2(p.x, top + 3.0), Vector2(p.x + f * (GRAB_FEEL + 10.0), top + 3.0))
	if face.is_empty() or face["normal"].x * f > -0.7:          # (a real wall, not a slope like a ramp)
		return false
	if not _grab_ray(Vector2(p.x, top - 8.0), Vector2(p.x + f * (GRAB_FEEL + 10.0), top - 8.0)).is_empty():
		return false
	_grab_top = top
	_grab_wall = face["position"].x
	global_position = Vector2(_grab_wall - f * BODY_HALF, top + GRAB_HANG)
	velocity = Vector2.ZERO
	speed_level = 0
	hold_time = 0.0
	air_jumps_left = MAX_AIR_JUMPS
	_set_state(State.EDGE_GRAB)
	_step_sound.play()
	return true


# hanging: jump or up pulls you on with a little hop; down or pushing away lets go
func _state_edge_grab(_delta, dir):
	velocity = Vector2.ZERO
	var f := float(facing)
	if _grab_ray(Vector2(_grab_wall + f * 4.0, _grab_top - 4.0), Vector2(_grab_wall + f * 4.0, _grab_top + 4.0)).is_empty():
		_let_go_of_ledge()                       # the ledge has gone (crumbled, broken)
		return
	if jump_buffer_timer > 0.0 or Input.is_action_just_pressed("ui_up"):
		jump_buffer_timer = 0.0
		jump_cut_done = true
		_grab_cool = GRAB_COOL
		velocity = Vector2(f * CLIMB_HOP.x, CLIMB_HOP.y)
		_jump_sound.play()
		_set_state(State.JUMP_RISE)
	elif Input.is_action_just_pressed("ui_down") or (dir != 0.0 and int(signf(dir)) != facing):
		_let_go_of_ledge()


func _let_go_of_ledge():
	_grab_cool = GRAB_COOL
	_set_state(State.JUMP_FALL)


# a ray against the level's solid ground (not enemies or anything that moves on its own)
func _grab_ray(from: Vector2, to: Vector2) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(from, to, collision_mask, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var c = hit["collider"]
	if not (c is StaticBody2D or c is AnimatableBody2D) or c.is_in_group("enemies"):
		return {}
	return hit


# feet in the living background's water (pits and shallows)
func _in_water() -> bool:
	var bg := get_tree().get_first_node_in_group("living_background")
	return bg != null and bg.in_water(global_position)


# something throws the player through the air (a starfruit bounce, a blowhole, a geyser): velocity v,
# the double jump back, and for `hold` seconds steering can't bend the arc, so it goes where it was aimed.
# They face the way they're thrown, and can attack straight away.
func launch(v: Vector2, hold := 0.3):
	velocity = v
	if v.x != 0.0:
		facing = int(signf(v.x))
	air_jumps_left = MAX_AIR_JUMPS
	jump_cut_done = true
	jump_buffer_timer = 0.0
	combo_queued = false
	light_in_air = false
	_launch_left = hold
	_set_state(State.JUMP_RISE if v.y < 0.0 else State.JUMP_FALL)


# a swing bounced off something armored (the boss's spiky skin): knocked back a little, away from from_x
func bounce_back(from_x: float, speed: float):
	var dir := signf(global_position.x - from_x)
	if dir == 0.0:
		dir = -float(facing)
	if state == State.DASH_ATTACK_LIGHT:   # the running Q stops instead of carrying on through it
		speed_level = 0
		_set_state(State.IDLE)
	_recoil_speed = dir * speed
	_recoil_left = RECOIL_TIME


# a foot plants in the walk / run / sprint / gallop cycle: footstep (a splash in water)
func _on_sprite_frame():
	if not (String(sprite.animation) in FOOTSTEP_ANIMS and sprite.frame in FOOTSTEP_FRAMES and is_on_floor()):
		return
	if _in_water():
		_water_step_sound.play()
	else:
		_step_sound.play()


# the Q or W sound. Code that swings the player's sword from outside (the boss air combo) calls this too.
func play_swing_sound(heavy: bool):
	if heavy:
		_w_sound.play(W_SOUND_SKIP)
	else:
		_q_sound.play(Q_SOUND_SKIP)


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
	if state == State.HEAVY_CHARGE and new_state != State.HEAVY_CHARGE:
		_stop_charge_sound()
	if state == State.KNOCKBACK and new_state != State.KNOCKBACK:
		_end_knockback_look()
	state = new_state
	state_time = 0.0
	_wall_clanged = false
	_update_label()
	_play_anim(new_state)          # <-- เพิ่มบรรทัดนี้

	match new_state:
		State.HEAVY_CHARGE:
			# hold the swing: freeze on the windup's last frame while charging
			sprite.frame = sprite.sprite_frames.get_frame_count(sprite.animation) - 1
			sprite.pause()
			_start_charge_sound()
		State.ATTACK_LIGHT_1, State.ATTACK_LIGHT_2, State.DASH_ATTACK_LIGHT:
			play_swing_sound(false)
		State.ATTACK_HEAVY_SMASH:
			_shake(SHAKE_SMALL_STRENGTH, SHAKE_SMALL_TIME)
			play_swing_sound(true)
		State.DASH_ATTACK_HEAVY_IMPACT:
			_shake(SHAKE_BIG_STRENGTH, SHAKE_BIG_TIME)
			play_swing_sound(true)
		State.CHARGED_SMASH:
			play_swing_sound(true)
		State.KNOCKBACK:
			sprite.pause()                  # its three poses are picked by hand in _state_knockback
			sprite.frame = 0


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
	_launch_left -= delta
	_grab_cool -= delta

	# แรงโน้มถ่วง (ปิดตอนลอยค้างง้างดาบ)
	if not is_on_floor() and state != State.DASH_ATTACK_HEAVY_WINDUP and state != State.EDGE_GRAB:
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
		State.KNOCKBACK:
			_state_knockback(delta)
		State.EDGE_GRAB:
			_state_edge_grab(delta, dir)

	if _recoil_left > 0.0:             # bounced off armor: this wins over whatever the state wants
		_recoil_left -= delta
		velocity.x = _recoil_speed * maxf(_recoil_left, 0.0) / RECOIL_TIME
	var speed_into := velocity.x * facing
	move_and_slide()
	# galloping into a wall: impact and knockback (once: the wall stops you, so the next frame isn't fast)
	if state in [State.GALLOP, State.JUMP_RISE, State.JUMP_FALL, State.DOUBLE_JUMP] \
			and speed_level == SPEEDS.size() - 1 and speed_into >= SPEEDS[SPEEDS.size() - 1] * 0.8 \
			and is_on_wall() and get_wall_normal().x * facing < 0.0:
		_wall_impact_sound.play(WALL_IMPACT_SKIP)
		_start_knockback()
	sprite.flip_h = facing < 0
	_check_wall_clang()


# ---------- swings clang off walls ----------
func _check_wall_clang():
	if _wall_clanged or not WALL_REACH.has(state):
		return
	var reach: float = WALL_REACH[state]
	var box := RectangleShape2D.new()
	box.size = Vector2(reach, 30.0)                 # body height, clear of the floor and low ceilings
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = box
	q.transform = Transform2D(0.0, global_position + Vector2(facing * reach / 2.0, -21.0))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var body = hit["collider"]
		if body is StaticBody2D and body.get_script() == null:   # plain level blocks, not the breakable gate
			_wall_clanged = true
			_wall_sound.play(WALL_SOUND_SKIP)
			return


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
		if _in_water():
			_water_step_sound.play()
		else:
			_jump_sound.play()
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
			_double_jump_sound.play()
			jump_buffer_timer = 0.0
			jump_cut_done = false
			_set_state(State.DOUBLE_JUMP)
			return

	if _try_air_attack():
		return

	if _try_grab(dir):                       # a ledge's edge in reach: catch it
		return

	# กระโดดสั้น/ยาวตามระยะเวลากดปุ่ม (ใช้กับดับเบิ้ลจัมพ์ด้วย)
	if not jump_cut_done and velocity.y < 0.0 and not Input.is_action_pressed("ui_accept"):
		velocity.y *= JUMP_CUT
		jump_cut_done = true

	if _launch_left > 0.0:
		pass                                # launched: the arc is aimed, steering waits
	elif dir != 0:
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
	if Input.is_action_pressed("attack_light"):     # holding Q keeps the combo going
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
	var cut := []
	for e in targets:
		if (e.global_position.x - start.x) * facing <= dist and e.has_method("take_hit"):
			cut.append(e)
	cut.sort_custom(func(a, b): return absf(a.global_position.x - start.x) < absf(b.global_position.x - start.x))
	var end := Vector2(start.x + facing * dist, start.y)
	velocity.x = facing * SPEEDS[speed_level]      # come out of it at the same speed (sprint or gallop)
	_set_state(MOVE_STATES[speed_level])
	if cut.is_empty():         # (nothing to cut after all: just reappear there)
		global_position = end
		_flash_streak(start + Vector2(0, -20), end + Vector2(0, -20))
		_sparks.restart()
		_shake(SHAKE_BIG_STRENGTH, SHAKE_SMALL_TIME)
		return
	# you're not moved yet: with time stopped you dash there, cutting each enemy as you pass, hold the
	# pose for a beat, then they drop one after another (code/flash_finish.gd, the professor's idea:
	# show the kills). It moves you, and does the streak, sparks and shake.
	var finish := FlashFinish.new()
	finish.player = self
	finish.targets = cut
	finish.from = start
	finish.to = end
	finish.damage = FLASH_DAMAGE
	finish.push = Vector2(facing * FLASH_PUSH.x, FLASH_PUSH.y)
	get_parent().add_child(finish)


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
	_stop_charge_sound()                # the counter can cut a W charge short
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
