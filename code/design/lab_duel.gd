extends Node2D
# THE DUEL (Morgan's idea, 2026-10-09): the jelly factory's first room. You step inside and your double is
# waiting: DR. SPLICE, in a white lab coat with a giant syringe (lab_scientist.gd). The opening, a cutscene
# (you're held, cinema bars on):
#   1. The door hisses shut behind you, the lights cut out with a clunk to two spotlights, one on each of you,
#      and the view slides over to frame you both. He draws his syringe: the sound, his goggles glint.
#   2. The exchange (Morgan's call, 2026-10-09: much faster, with you in it): a flurry of six clashes, too
#      quick to follow, the clangs rising, anime style: you both blink from spot to spot round the room, on the
#      ground and in the air, sometimes swapping sides (FLURRY_1). Then he springs back and lunges at you: time all but
#      stops (SLOW), the screen's edges darken, an eerie slow-motion sound, and a big Q key bounces over your
#      head with CLASH! (the dam's prompt style). Press Q and you meet him. Three more quick clashes
#      (FLURRY_2), then he leaps for an overhead slam: slow motion again, W and SMASH!, and your blade meets
#      his in a heavy clash that throws him back. Four more, quicker still (FLURRY_3), then one last lunge:
#      Q and W together (TOGETHER!, two keys; Morgan's call), and you lock blades. The prompts wait for you
#      (a wrong key wiggles them).
#   3. The blade lock: Sparks pour off the crossed blades, the blades
#      grind, you both tremble, pushing back and forth, and the view zooms in on it (ZOOM). Then the talk:
#      him, "HALT! THIS IS A RESTRICTED AREA."; you, "RELAX, DOC. I'M JUST HERE FOR THE FREE SAMPLES.";
#      him, "OH, I'LL TAKE A SAMPLE... OF YOU!". Words pop in like the tiki bar's; jump, Q or W goes on.
#   4. The break: one last huge clash with a white flash, and you both leap back apart. The view comes back
#      out, the lights slam back on, and his name slams in with his health bar (the level HUD's boss_intro).
#      You're let go and the fight's on.
# During the fight he shouts after each hit (BARKS, no press needed). Beaten, he's blasted off screen (that's
# his getaway, Morgan's call, 2026-10-09), his bar goes, and the bunker door (bunker_door.gd) unlocks: it
# winches open as you come at it, on to the next part of the lab.
# Put it where the duel starts (you walking past it), inside the lab. The player.gd is untouched: it pauses the
# player's physics and poses its sprite, like the boss finisher.

const CinemaBars := preload("res://code/design/cinema_bars.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")
const SCRAPE_SOUND := preload("res://sounds/sword/sword_scrape_01.wav")
const DRAW_SOUND := preload("res://sounds/sword/sword_draw_01.wav")
# the flurries, anime style (Morgan's call, 2026-10-09): you both blink across the room from clash to clash,
# on the ground, in mid-air, up near the ceiling, sometimes swapping sides. Each: [pose, frame, where the
# blades meet (up from your feet), how far apart you each are from there, the spot (x from the middle, height
# off the floor), swapped sides]. Each flurry ends on the ground, you on the left, for the prompt after it.
# (Keep spot x - gap at -170 or more: the entrance wall is just past that)
const FLURRY_1 := [["ATTACK_LIGHT_1", 1, -30.0, 30.0, Vector2(-140, 0), false],
	["ATTACK_LIGHT_2", 1, -16.0, 30.0, Vector2(150, -90), true],
	["ATTACK_LIGHT_1", 2, -38.0, 28.0, Vector2(-40, -130), false],
	["DASH_ATTACK_LIGHT", 1, -12.0, 34.0, Vector2(70, 0), true],
	["ATTACK_LIGHT_2", 2, -26.0, 30.0, Vector2(-130, -60), false],
	["ATTACK_HEAVY_SMASH", 0, -34.0, 28.0, Vector2(20, 0), false]]
const FLURRY_2 := [["ATTACK_LIGHT_2", 1, -18.0, 30.0, Vector2(170, -110), true],
	["ATTACK_LIGHT_1", 2, -36.0, 28.0, Vector2(40, -70), false],
	["DASH_ATTACK_LIGHT", 1, -12.0, 34.0, Vector2(-120, 0), false]]
const FLURRY_3 := [["ATTACK_LIGHT_1", 1, -30.0, 30.0, Vector2(-125, -100), true],
	["ATTACK_LIGHT_2", 2, -24.0, 30.0, Vector2(130, 0), false],
	["ATTACK_HEAVY_SMASH", 0, -36.0, 28.0, Vector2(-30, -140), true],
	["ATTACK_LIGHT_2", 1, -16.0, 30.0, Vector2(10, 0), false]]
const ZIP := 0.06                    # a blink from one clash to the next (real seconds)
const STREAK_YOU := Color(0.6, 0.95, 1.0)
const STREAK_HIM := Color(0.75, 1.0, 0.65)
const SLOW := 0.12                   # time while a prompt waits for you
const PROMPT := [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]   # the CLASH! / SMASH! text (the dam's colours)
const SLOW_SOUND := preload("res://sounds/HEARTBEAT_WHEN IT STARTS_freesound_community-eerie-slow-motion-effect-31536.mp3")
const LUNGE_SOUND := preload("res://sounds/sword/sword_swoosh_03.wav")
const LINES := [
	["doc", "HALT! THIS IS A\n{RESTRICTED} AREA."],
	["you", "RELAX, DOC. I'M JUST\nHERE FOR THE FREE\nSAMPLES."],
	["doc", "OH, I'LL TAKE A\nSAMPLE... OF {YOU}!"],
]
const BARKS := {2: "MY LAB COAT!!", 1: "THAT'S IT. NO MORE\nMR. NICE DOC!", 0: "...I SHOULD HAVE\nSTAYED IN ACCOUNTING."}
const BARK_TIME := 1.8
const TRAIL_EASE := 2.0              # his last line trails after him as he's blasted off: how quickly it catches up...
const TRAIL_MAX := 140.0             # ...but never faster than this (px a real second), so you can read it as it goes
const ZOOM := 1.5                    # the view zooms in this far on the blade lock (1.5: whole screen pixels)
const LOCK_GAP := 24.0               # you're each this far from the crossed blades
const LEAP_BACK := 130.0             # the break: you each land this far from the middle
const TEXT := [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE]
const GREEN := [Color("5fd15a"), Color("3f9e45"), Color("a6f08f")]    # his {words}
const YELLOW := [Color("f2c22e"), Color("d8901c"), Color("fff3b0")]   # yours
const BUBBLE := Color(0.1, 0.08, 0.12, 0.94)
const WORD_GAP := 0.05
const WORD_PER_LETTER := 0.009
const PAUSE_STOP := 0.1
const PAUSE_COMMA := 0.05
const POP_UP := 0.07
const POP_SETTLE := 0.13
const POP_FROM := 0.3
const POP_BIG := 1.45

@export var scientist_path: NodePath
@export var lab_path: NodePath
@export var door_path: NodePath     # the bunker door he flees through

var _started := false
var _player: CharacterBody2D = null
var _psprite: AnimatedSprite2D = null
var _sci: Node2D = null
var _lab: Node = null
var _door: Node2D = null
var _cam: Camera2D = null
var _cam_pos0 := Vector2.ZERO
var _cam_target := Vector2.ZERO      # the view's middle (world) while it's locked on the duel...
var _cam_k := 0.0                    # ...how far it's moved there from following you
var _zoom := 1.0
var _floor_y := 0.0
var _t := 0.0                        # real time
var _last := -1.0
var _spotlit := false
# the blade lock
var _locking := false
var _lock_mid := 0.0
var _lock_t := 0.0
var _spark_t := 0.0
var _scrape_t := 0.0
var _push := 0.0                     # the push and shove: who's winning (+: him)
var _push_to := 0.0
# the talk
var _lines: Array = []
var _line := -1
var _shown := 0
var _words: Array = []
var _word_i := 0
var _word_wait := 0.0
var _popped := {}
var _bark_text := ""
var _bark_until := 0.0
var _bark_from := 0.0
var _bark_at := Vector2.INF          # where his bubble points, pinned on screen (it followed him and shook)
var _bark_trail := false             # his last line: it drifts after him off screen instead
var _trail_at := Vector2.INF         # (where it is, in the world)
var _trail_goal := Vector2.ZERO      # (his head; once he's gone, where he'd be by now)
var _trail_v := Vector2.ZERO         # (his speed as he went, a real second)
var _talk_layer := CanvasLayer.new()
var _talk := Node2D.new()
var _glow := Node2D.new()            # the light where the blades cross
var _snd_scrape := AudioStreamPlayer.new()
var _snd_slow := AudioStreamPlayer.new()
var _snd_lunge := AudioStreamPlayer.new()
var _prompt_key := ""                # the prompt over your head: its key...
var _prompt_label := ""              # ...and its word
var _prompt_out := -10.0             # when it was answered (it pops away)
var _wiggle_t := -10.0               # a wrong key: it wiggles
var _vignette := 0.0                 # the slow motion's dark screen edges
var _vig_to := 0.0
var _last_key := ""
var _last_label := ""
var _snd_draw := AudioStreamPlayer.new()

signal _talked


func _ready():
	_talk_layer.layer = 10           # over the cinema bars
	_talk_layer.add_child(_talk)
	add_child(_talk_layer)
	_talk.draw.connect(_draw_talk)
	_glow.z_as_relative = false
	_glow.z_index = 22
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_snd_scrape.stream = SCRAPE_SOUND
	_snd_scrape.volume_db = -8.0
	_snd_scrape.max_polyphony = 2
	add_child(_snd_scrape)
	_snd_slow.stream = SLOW_SOUND
	_snd_slow.volume_db = -6.0
	add_child(_snd_slow)
	_snd_lunge.stream = LUNGE_SOUND
	_snd_lunge.volume_db = -4.0
	add_child(_snd_lunge)
	_snd_draw.stream = DRAW_SOUND
	_snd_draw.volume_db = -4.0
	add_child(_snd_draw)
	_sci = get_node_or_null(scientist_path)
	_lab = get_node_or_null(lab_path)
	_door = get_node_or_null(door_path)
	if _sci:
		_sci.hurt.connect(_on_hurt)
		_sci.beaten.connect(_on_beaten)
		_floor_y = _sci.global_position.y


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_delta: float):
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if _player == null:
			return
		_psprite = _player.get_node_or_null("AnimatedSprite2D")
		_cam = _player.get_node_or_null("Camera2D")
		if _cam:
			_cam_pos0 = _cam.position
	var px := _player.global_position.x - global_position.x
	if not _started and _sci and px >= 0.0 and px < 300.0 and _player.is_on_floor():
		_run()


func _process(_delta: float):
	var now := _now()
	var dt := 0.0 if _last < 0.0 else minf(now - _last, 0.1)
	_last = now
	_t += dt
	_vignette = move_toward(_vignette, _vig_to, dt / 0.15)
	if _locking:
		_lock_frame(dt)                                  # (before the view: it moves you)
	if _cam and (_cam_k > 0.0 or _zoom != 1.0):        # the view: locked on the duel, zoomed. Worked out after
		_cam.position = _cam_pos0.lerp(_cam_target - _player.global_position, _cam_k)   # you've moved, or
		_cam.zoom = Vector2(_zoom, _zoom)                # it jittered with your trembling (and the bubbles too)
	if _spotlit and _lab and _player and _sci:
		_lab.set_spots([_player.global_position.x, _sci.global_position.x])
	if _bark_trail:
		_trail_bark(dt)
	elif _bark_text != "" and _bark_at == Vector2.INF and _t >= _bark_from and _sci:
		_bark_at = _screen_steady(_sci.global_position + Vector2(0, -46)).round()   # pinned where he is now
	_talk.queue_redraw()
	_glow.queue_redraw()


# ---------- the opening ----------
func _run():
	_started = true
	_hold_player()
	if _lab:
		_lab.shut_entrance()
		_lab.set_dim(true)
	_spotlit = true
	CinemaBars.set_on(get_tree(), true)
	var px := _player.global_position.x
	var sx: float = _sci.global_position.x
	var mid := (px + sx) / 2.0
	_floor_y = _player.global_position.y
	_cam_target = Vector2(mid, _floor_y + _cam_pos0.y)
	await _ease(0.5, func(k): _cam_k = k)
	# he draws his syringe: the sound, his goggles glint
	_sci.pose("ATTACK_HEAVY_WINDUP", 0)
	_snd_draw.play()
	_sci._glint = 0.0
	await _wait(0.6)
	# the flurry: blow after blow, too quick to follow, the clangs rising
	await _flurry(FLURRY_1, mid, 1.0)
	# he springs back and lunges: time all but stops, and it's your turn (Q)
	await _qte_lunge(mid, false)
	await _flurry(FLURRY_2, mid, 1.15)
	# he leaps for an overhead slam (W)
	await _qte_slam(mid)
	await _flurry(FLURRY_3, mid, 1.3)
	# one more lunge (Q), and the blades lock
	await _qte_lunge(mid, true)
	_lock_mid = mid
	_lock_t = 0.0
	_locking = true
	_cam_target = Vector2(mid, _floor_y - 52.0)
	_ease(0.8, func(k): _zoom = lerpf(1.0, ZOOM, k))
	await _wait(0.5)
	# the talk
	_say(LINES)
	await _talked
	# the break: one last huge clash, and you both leap back apart
	_push_to = 0.0
	await _wait(0.15)
	_locking = false
	_sci.clash_fx(Vector2(mid, _floor_y - 30.0), true)
	if _lab and _lab.has_method("flash"):
		_lab.flash(0.7)
	_ease(0.45, func(k): _zoom = lerpf(ZOOM, 1.0, k))
	await _leap_back(mid)
	await _ease(0.35, func(k): _cam_k = 1.0 - k)
	_cam.position = _cam_pos0
	# the lights slam back on, and his name slams in
	_spotlit = false
	if _lab:
		_lab.set_dim(false)
	var level := get_tree().get_first_node_in_group("level")
	if level and level.get("hud"):
		level.hud.boss_intro(_sci, _sci.boss_name)
	await _wait(0.5)
	CinemaBars.set_on(get_tree(), false)
	_let_go()
	_sci.start_fight()


func _wait(t: float) -> Signal:
	return get_tree().create_timer(t, true, false, true).timeout


# runs fn(k) every frame with k going 0 -> 1 over t real seconds, eased in and out
func _ease(t: float, fn: Callable):
	var t0 := _now()
	while true:
		var k := clampf((_now() - t0) / t, 0.0, 1.0)
		fn.call(k * k * (3.0 - 2.0 * k))
		if k >= 1.0:
			break
		await get_tree().process_frame


func _hold_player():
	_player.set_physics_process(false)
	_player.velocity = Vector2.ZERO
	_player.speed_level = 0
	_player.hold_time = 0.0
	_player.facing = 1
	FruitMinion._player_safe_until = _now() + 1000.0       # (nothing hurts you in the cutscene)
	if _psprite:
		_psprite.flip_h = false
		_psprite.play("IDLE")


func _let_go():
	FruitMinion._player_safe_until = _now() + 0.4
	_player._set_state(_player.get_script().State["IDLE"])
	_player.set_physics_process(true)


func _pose_player(anim: String, frame: int, flip := false):
	if _psprite == null:
		return
	_psprite.animation = anim
	_psprite.frame = mini(frame, _psprite.sprite_frames.get_frame_count(anim) - 1)
	_psprite.pause()
	_psprite.flip_h = flip


# both in a pose, facing each other (swapped: you on the right)
func _pose_both(anim: String, frame: int, swapped := false):
	_pose_player(anim, frame, swapped)
	_sci.pose(anim, frame)
	_sci.face(1 if swapped else -1)


# you rush each other: speeding up, leaving afterimages
func _rush(to_you: float, to_him: float, t: float):
	_pose_player("GALLOP", 1)
	_sci.pose("GALLOP", 1)
	_sci.face(-1)
	await _move_both(to_you, to_him, t)


func _move_both(to_you: float, to_him: float, t: float):
	var from_you := _player.global_position.x
	var from_him: float = _sci.global_position.x
	var t0 := _now()
	var ghost_t := 0.0
	while true:
		var k := clampf((_now() - t0) / t, 0.0, 1.0)
		var e := k * k
		_player.global_position.x = lerpf(from_you, to_you, e)
		_sci.global_position.x = lerpf(from_him, to_him, e)
		ghost_t -= get_process_delta_time()
		if ghost_t <= 0.0:
			ghost_t = 0.03
			_afterimage(_psprite, Pixel.TEAL)
			_sci._ghost()
		if k >= 1.0:
			break
		await get_tree().process_frame


# knocked apart: skidding back, slowing
func _slide(to_you: float, to_him: float, t: float, dust := 5):
	var from_you := _player.global_position.x
	var from_him: float = _sci.global_position.x
	_pose_player("LAND", 0)
	_sci.pose("LAND", 0)
	_sci._dust(Vector2(from_you, _floor_y), dust)
	_sci._dust(Vector2(from_him, _floor_y), dust)
	await _ease(t, func(k):
		_player.global_position.x = lerpf(from_you, to_you, k)
		_sci.global_position.x = lerpf(from_him, to_him, k))


# a flurry, anime style: you both vanish and blink to the next spot (streaks of light where you went),
# appear mid-clash (sparks, a ring, a clang a little higher each time), recoil a touch, and blink on (speed:
# quicker). It ends with you both landed, you on the left
func _flurry(steps: Array, mid: float, speed: float):
	var pitch := 0.95
	for st: Array in steps:
		var spot: Vector2 = st[4]
		var swapped: bool = st[5]
		var gap: float = st[3]
		var c := Vector2(mid + spot.x, _floor_y + spot.y)
		var you := c + Vector2(gap if swapped else -gap, 0)
		var him := c + Vector2(-gap if swapped else gap, 0)
		await _zip(you, him, ZIP / speed)
		_pose_both(st[0], st[1], swapped)
		_sci.clash_fx(Vector2(c.x, c.y + st[2]), false, true, pitch)
		if spot.y < 0.0:
			_sci._ring(Vector2(c.x, c.y + st[2]), 18.0)        # (in mid-air, a bigger ring)
		else:
			_sci._dust(c, 3)
		pitch += 0.04
		await _wait(0.06 / speed)
		var push := Vector2(-6.0 if not swapped else 6.0, 0)
		var y0 := c.y
		await _ease(0.04 / speed, func(k):
			_player.global_position = you + push * k
			_sci.global_position = him - push * k)
		if y0 < _floor_y:
			await _wait(0.02 / speed)
	# down to the ground, you on the left, him on the right
	await _zip(Vector2(mid - 46.0, _floor_y), Vector2(mid + 46.0, _floor_y), ZIP / speed)
	_pose_both("LAND", 1)
	_sci._dust(Vector2(mid - 46.0, _floor_y), 4)
	_sci._dust(Vector2(mid + 46.0, _floor_y), 4)


# a blink: you both vanish, a streak of light runs to where you reappear
func _zip(you_to: Vector2, him_to: Vector2, t: float):
	var you_from := _player.global_position
	var him_from: Vector2 = _sci.global_position
	_streak(you_from + Vector2(0, -20), you_to + Vector2(0, -20), STREAK_YOU)
	_streak(him_from + Vector2(0, -20), him_to + Vector2(0, -20), STREAK_HIM)
	if _psprite:
		_psprite.visible = false
	_sci.sprite.visible = false
	await _ease(t, func(k):
		_player.global_position = you_from.lerp(you_to, k)
		_sci.global_position = him_from.lerp(him_to, k))
	if _psprite:
		_psprite.visible = true
	_sci.sprite.visible = true


# a streak of light where someone blinked: thin, fading fast
func _streak(a: Vector2, b: Vector2, col: Color):
	if a.distance_to(b) < 8.0:
		return
	var line := Line2D.new()
	line.add_point(a)
	line.add_point(b)
	line.width = 3.0
	line.default_color = Color(col, 0.85)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_as_relative = false
	line.z_index = 21
	get_parent().add_child(line)
	var tw := line.create_tween().set_parallel().set_ignore_time_scale(true)
	tw.tween_property(line, "width", 0.5, 0.2)
	tw.tween_property(line, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(line.queue_free)


# he springs back and lunges at you, and time all but stops: Q to meet him. into_lock: you meet him blade to
# blade and lock
func _qte_lunge(mid: float, into_lock: bool):
	var gap := LOCK_GAP if into_lock else 32.0
	var you := mid - gap
	await _slide(you, mid + 96.0, 0.1, 2)
	_pose_player("ATTACK_HEAVY_WINDUP", 0)
	_sci.pose("GALLOP", 1)
	_sci._glint = 0.0
	_snd_lunge.pitch_scale = 0.8
	_snd_lunge.play()
	var from: float = _sci.global_position.x
	var close := lerpf(from, mid + gap, 0.6)
	await _ease(0.09, func(k): _sci.global_position.x = lerpf(from, close, k))
	await _wait_key("both" if into_lock else "attack_light", "Q+W" if into_lock else "Q",
			"TOGETHER!" if into_lock else "CLASH!", func(dt):
		_sci.global_position.x = move_toward(_sci.global_position.x, mid + gap + 12.0, 10.0 * dt))
	_pose_player("ATTACK_LIGHT_1", 2 if into_lock else 1)
	_sci.pose("ATTACK_LIGHT_1" if into_lock else "DASH_ATTACK_LIGHT", 2 if into_lock else 1)
	await _move_both(you + 4.0, mid + gap, 0.04)
	if _lab and _lab.has_method("flash"):
		_lab.flash(0.3)
	if into_lock:
		_player.global_position.x = mid - LOCK_GAP
		_sci.global_position.x = mid + LOCK_GAP
		_sci.clash_fx(Vector2(mid, _floor_y - 30.0), true)
		return
	_sci.clash_fx(Vector2(mid, _floor_y - 22.0), false)
	await _wait(0.08)
	await _slide(mid - 46.0, mid + 46.0, 0.08, 3)


# he leaps for an overhead slam, and time all but stops: W to meet it. Your blades crash together and he's
# thrown back over to his side
func _qte_slam(mid: float):
	var you := _player.global_position.x
	await _slide(you, mid + 70.0, 0.08, 2)
	_sci.pose("JUMP_RISE", 0)
	_snd_lunge.pitch_scale = 0.65
	_snd_lunge.play()
	var from: Vector2 = _sci.global_position
	var top := Vector2(you + 22.0, _floor_y - 100.0)
	await _ease(0.2, func(k):
		_sci.global_position = Vector2(lerpf(from.x, top.x, k), lerpf(from.y, top.y, sin(k * PI / 2.0))))
	_sci.pose("DASH_ATTACK_HEAVY_WINDUP", 2)
	_sci.face(-1)
	_sci._glint = 0.0
	_pose_player("ATTACK_HEAVY_WINDUP", 0)
	await _wait_key("attack_heavy", "W", "SMASH!", func(dt):
		_sci.global_position.y = move_toward(_sci.global_position.y, _floor_y - 76.0, 8.0 * dt))
	_pose_player("ATTACK_HEAVY_WINDUP", 2)
	var y0: float = _sci.global_position.y
	await _ease(0.04, func(k): _sci.global_position.y = lerpf(y0, _floor_y - 44.0, k))
	_sci.clash_fx(Vector2(you + 10.0, _floor_y - 50.0), true)
	_sci._dust(Vector2(you, _floor_y), 14)
	get_tree().call_group("living_background", "burst", Vector2(you, _floor_y), 4.0)
	if _lab and _lab.has_method("flash"):
		_lab.flash(0.35)
	await _wait(0.1)
	_sci.pose("JUMP_RISE", 0)
	_pose_player("LAND", 0)
	var p0: Vector2 = _sci.global_position
	var land := Vector2(mid + 56.0, _floor_y)
	var t0 := _now()
	while true:                                        # thrown back up and over, to his side
		var k := clampf((_now() - t0) / 0.32, 0.0, 1.0)
		_sci.global_position = Vector2(lerpf(p0.x, land.x, k), lerpf(p0.y, land.y, k) - sin(k * PI) * 40.0)
		if k > 0.5:
			_sci.pose("JUMP_FALL", 0)
		if k >= 1.0:
			break
		await get_tree().process_frame
	_sci.pose("LAND", 1)
	_sci._dust(land, 6)


# the prompt: time all but stops (the edges darken, the eerie sound), and a big key bounces over your head
# until you press it (a wrong key wiggles it). creep(dt) runs every frame meanwhile (real seconds)
func _wait_key(action: String, key: String, label: String, creep: Callable):
	_prompt_key = key
	_prompt_label = label
	_vig_to = 1.0
	_snd_slow.play()
	var ghost_t := 0.0
	var last := _now()
	while true:
		Engine.time_scale = SLOW
		if action == "both":                         # Q and W together (pressed one then the other is fine)
			if Input.is_action_pressed("attack_light") and Input.is_action_pressed("attack_heavy"):
				break
			if Input.is_action_just_pressed("ui_accept"):
				_wiggle_t = _t
		else:
			if Input.is_action_just_pressed(action):
				break
			for other in ["ui_accept", "attack_light", "attack_heavy"]:
				if other != action and Input.is_action_just_pressed(other):
					_wiggle_t = _t
		var now := _now()
		creep.call(now - last)
		last = now
		ghost_t -= get_process_delta_time() / SLOW
		if ghost_t <= 0.0:
			ghost_t = 0.15
			_sci._ghost()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_snd_slow.stop()
	_vig_to = 0.0
	_prompt_key = ""
	_prompt_out = _t


# the break: you both leap back in an arc, and land
func _leap_back(mid: float):
	var from_you := _player.global_position.x
	var from_him: float = _sci.global_position.x
	_pose_player("JUMP_RISE", 0)
	_sci.pose("JUMP_RISE", 0)
	var t0 := _now()
	while true:
		var k := clampf((_now() - t0) / 0.5, 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var up := sin(k * PI) * 46.0
		_player.global_position = Vector2(lerpf(from_you, mid - LEAP_BACK, e), _floor_y - up)
		_sci.global_position = Vector2(lerpf(from_him, mid + LEAP_BACK, e), _floor_y - up)
		if k > 0.5:
			_pose_player("JUMP_FALL", 0)
			_sci.pose("JUMP_FALL", 0)
		if k >= 1.0:
			break
		await get_tree().process_frame
	_pose_player("LAND", 1)
	_sci.pose("LAND", 1)
	_sci._dust(_player.global_position, 8)
	_sci._dust(_sci.global_position, 8)
	if _player.has_method("_shake"):
		_player._shake(5.0, 0.2)
	await _wait(0.15)
	_psprite.play("IDLE")
	_sci.pose("IDLE", 0)
	_sci.sprite.play("IDLE")


# a fading copy of a sprite's frame (your rush)
func _afterimage(spr: AnimatedSprite2D, col: Color):
	if spr == null:
		return
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.texture = tex
	g.centered = spr.centered
	g.offset = spr.offset
	g.flip_h = spr.flip_h
	g.modulate = Color(col, 0.55)
	get_parent().add_child(g)
	g.global_position = spr.global_position
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.2)
	tw.tween_callback(g.queue_free)


# the blade lock, every frame: you both tremble and shove back and forth, sparks pour off the crossed blades
# and the blades grind
func _lock_frame(dt: float):
	_lock_t += dt
	_push = lerpf(_push, _push_to + sin(_lock_t * 1.7) * 3.0, minf(dt * 4.0, 1.0))
	var shove := roundf(_push)
	var jit := roundf(sin(_lock_t * 47.0)) if int(_lock_t * 30.0) % 2 == 0 else 0.0
	_player.global_position.x = _lock_mid - LOCK_GAP + shove + jit
	_sci.global_position.x = _lock_mid + LOCK_GAP + shove - jit
	_spark_t -= dt
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.04, 0.09)
		_sci._sparks(_lock_point(), randi_range(3, 6), 150.0)
	_scrape_t -= dt
	if _scrape_t <= 0.0:
		_scrape_t = randf_range(0.35, 0.55)
		_snd_scrape.pitch_scale = randf_range(0.85, 1.2)
		_snd_scrape.play()


func _lock_point() -> Vector2:
	return Vector2(_lock_mid + roundf(_push), _floor_y - 30.0)


# the light where the blades cross: a pulsing star
func _draw_glow():
	if not _locking:
		return
	var at := _lock_point() - global_position
	var p := 0.75 + 0.25 * sin(_t * 23.0)
	for k in 3:
		var r := (6.0 + k * 5.0) * p
		_glow.draw_circle(at, r, Color(1.0, 0.95, 0.6, 0.22 - k * 0.06))
	var arm := roundf(9.0 * p)
	_glow.draw_rect(Rect2(at.x - arm, at.y, arm * 2.0 + 1.0, 1), Color.WHITE)
	_glow.draw_rect(Rect2(at.x, at.y - arm, 1, arm * 2.0 + 1.0), Color.WHITE)
	_glow.draw_rect(Rect2(at.x - 1.0, at.y - 1.0, 3, 3), Color(1, 1, 0.8))


# ---------- the talk ----------
func _say(lines: Array):
	_lines = lines
	_line = 0
	_start_line()
	_talking_loop()


func _pressed() -> bool:
	return Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack_light") \
		or Input.is_action_just_pressed("attack_heavy")


func _talking_loop():
	while _line >= 0 and _line < _lines.size():
		await get_tree().process_frame
		var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.05)
		var full := _flat_len(String(_lines[_line][1]))
		if _shown < full:
			_word_wait -= dt
			var rush := _pressed()
			while _word_i < _words.size() and (_word_wait <= 0.0 or rush):
				var w: Array = _words[_word_i]
				_popped[w[0]] = _t
				_shown = w[1]
				_word_wait += w[2]
				_word_i += 1
			if _word_i >= _words.size():
				_shown = full
			continue
		if _pressed():
			_line += 1
			if _line < _lines.size():
				_start_line()
	_line = -1
	_talked.emit()


# a line's length as the words count it: braces left out, each line break a space
func _flat_len(text: String) -> int:
	return text.replace("{", "").replace("}", "").length()


# a new line: the speaker shoves (sparks fly), and its words line up to pop in
func _start_line():
	_shown = 0
	_words.clear()
	_word_i = 0
	_word_wait = 0.0
	_popped.clear()
	var who: String = _lines[_line][0]
	_push_to = 5.0 if who == "you" else -5.0                   # the one talking gets the upper hand
	_sci._sparks(_lock_point(), 10, 200.0)
	var flat := String(_lines[_line][1]).replace("\n", " ").replace("{", "").replace("}", "")
	var i := 0
	while i < flat.length():
		if flat[i] == " ":
			i += 1
			continue
		var start := i
		while i < flat.length() and flat[i] != " ":
			i += 1
		var word := flat.substr(start, i - start)
		var end := i
		while end < flat.length() and flat[end] == " ":
			end += 1
		var wait := WORD_GAP + WORD_PER_LETTER * word.length()
		if word.ends_with(".") or word.ends_with("!") or word.ends_with("?"):
			wait += PAUSE_STOP
		elif word.ends_with(","):
			wait += PAUSE_COMMA
		_words.append([start, end, wait])


# during the fight: a quick line from him, no press needed. It waits for him to land (`delay`), then pins
# itself on screen there, steady, while he gets up
func _bark(text: String, delay: float, time := BARK_TIME, trail := false):
	_bark_text = text
	_bark_from = _t + delay
	_bark_until = _bark_from + time
	_bark_at = Vector2.INF
	_bark_trail = trail
	_trail_at = Vector2.INF


func _on_hurt(hp_left: int):
	if BARKS.has(hp_left):
		if hp_left == 0:
			_bark(BARKS[0], 0.08, 6.0, true)             # (as he's blasted off: it trails after him, till it's off screen)
		else:
			_bark(BARKS[hp_left], 0.45)


# his last line drifts slowly after him as he flies off, eased in and capped at TRAIL_MAX so you can read it;
# once he's vanished it keeps on the way he went, and it's done when it's off the screen (Morgan's call,
# 2026-10-09; it used to be pinned)
func _trail_bark(dt: float):
	if _bark_text == "" or _t < _bark_from or _sci == null:
		return
	var head := _sci.global_position + Vector2(0, -46)
	if _trail_at == Vector2.INF:
		_trail_at = head
		_trail_goal = head
	if _sci.visible:
		_trail_goal = head
		_trail_v = _sci.velocity * Engine.time_scale
	else:
		_trail_goal += _trail_v * dt
	var step := (_trail_goal - _trail_at) * (1.0 - exp(-TRAIL_EASE * dt))
	_trail_at += step.limit_length(TRAIL_MAX * dt)
	_bark_at = _screen_steady(_trail_at).round()
	var view := get_viewport().get_visible_rect().size
	if _bark_at.x < -90.0 or _bark_at.x > view.x + 90.0 or _bark_at.y < 0.0 or _bark_at.y > view.y + 40.0:
		_bark_text = ""                              # (gone, with him)
		_bark_trail = false


# beaten: he's blasted off screen; his bar goes, and once he's gone the bunker door unlocks (it opens as you
# come at it)
func _on_beaten():
	await _wait(0.9)
	var level := get_tree().get_first_node_in_group("level")
	if level and level.get("hud"):
		level.hud.hide_boss()
	if _sci.visible:
		await _sci.fled
	await _wait(0.4)
	if _door and _door.has_method("unlock"):
		_door.unlock()


# ---------- drawing the bubbles (the tiki bar's style), on screen ----------
func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


# on screen, steady: from the camera itself, leaving out its shake (the shake moves its offset)
func _screen_steady(world: Vector2) -> Vector2:
	if _cam == null:
		return _screen(world)
	return (world - _cam.global_position) * _cam.zoom + get_viewport().get_visible_rect().size / 2.0


# where a speaker's bubble points: in the blade lock, their steady place there (not their trembling and
# shoving body: the bubble shook too and was hard to read, Morgan's catch, 2026-10-09)
func _speaker_head(who: String) -> Vector2:
	if _locking or _line >= 0:
		return Vector2(_lock_mid + (LOCK_GAP if who == "doc" else -LOCK_GAP), _floor_y - 46.0)
	return (_sci.global_position if who == "doc" else _player.global_position) + Vector2(0, -46)


func _draw_talk():
	_draw_vignette()
	_draw_prompt()
	if _line >= 0 and _line < _lines.size():
		var who: String = _lines[_line][0]
		_bubble(String(_lines[_line][1]), _screen_steady(_speaker_head(who)), GREEN if who == "doc" else YELLOW,
			Pixel.TEAL if who == "you" else GREEN[0], _shown, true)
	if _bark_text != "" and _bark_at != Vector2.INF and _t < _bark_until:
		_bubble(_bark_text, _bark_at, GREEN, GREEN[0], _flat_len(_bark_text), false, not _bark_trail)


# slow motion: the screen's edges darken
func _draw_vignette():
	if _vignette <= 0.0:
		return
	var size := get_viewport().get_visible_rect().size
	for i in 8:
		var a := 0.07 * _vignette
		var d := i * 5.0
		_talk.draw_rect(Rect2(0, d, size.x, 5), Color(0, 0, 0, a * (8 - i) / 4.0))
		_talk.draw_rect(Rect2(0, size.y - d - 5.0, size.x, 5), Color(0, 0, 0, a * (8 - i) / 4.0))
		_talk.draw_rect(Rect2(d, 0, 5, size.y), Color(0, 0, 0, a * (8 - i) / 4.0))
		_talk.draw_rect(Rect2(size.x - d - 5.0, 0, 5, size.y), Color(0, 0, 0, a * (8 - i) / 4.0))


# the big key over your head (the dam's style): bouncing, acting out the press, its word under it, a ring
# pulsing round it; answered, it pops away
func _draw_prompt():
	var out := _t - _prompt_out
	var key := _prompt_key
	var label := _prompt_label
	if key == "":
		if out > 0.18:
			return
		key = _last_key
		label = _last_label
	else:
		_last_key = key
		_last_label = label
	var head := _screen_steady(_player.global_position + Vector2(0, -44)).round()
	var bounce := roundf(sin(_t * 10.0) * 2.0)
	var wig := roundf(sin((_t - _wiggle_t) * 60.0) * 3.0) if _t - _wiggle_t < 0.25 else 0.0
	var k := 2.0
	var a := 1.0
	if _prompt_key == "":                                   # popping away
		k = lerpf(2.0, 3.0, out / 0.18)
		a = 1.0 - out / 0.18
	var center := Vector2(head.x + wig, head.y - 30.0 + bounce)
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var tap := _prompt_key == "" or fmod(_t, 0.4) < 0.15
	if key == "Q+W":                                        # two keys, Q + W, each lit while you hold it
		_talk.draw_arc(center, 24.0 + pulse * 3.0, 0.0, TAU, 32, Color(Pixel.MUSTARD, 0.7 * a), 1.0)
		var held := [Input.is_action_pressed("attack_light"), Input.is_action_pressed("attack_heavy")]
		for i in 2:
			var at := center + Vector2((-1.0 if i == 0 else 1.0) * 17.0, 0) - Vector2(13.0, 7.0) * k / 2.0
			_talk.draw_set_transform(at, 0.0, Vector2(k, k))
			Pixel.draw_key(_talk, Vector2.ZERO, 13, "Q" if i == 0 else "W", tap or held[i], held[i] or _prompt_key != "", a)
			_talk.draw_set_transform(Vector2.ZERO)
		var plus_w := Pixel.width("+", 2)
		Pixel.draw_cells(_talk, Pixel.cells("+", Vector2(roundf(center.x - plus_w / 2.0), center.y - 6.0), 2), PROMPT, a)
	else:
		_talk.draw_arc(center, 15.0 + pulse * 3.0, 0.0, TAU, 24, Color(Pixel.MUSTARD, 0.7 * a), 1.0)
		_talk.draw_set_transform(center - Vector2(13.0, 7.0) * k / 2.0, 0.0, Vector2(k, k))
		Pixel.draw_key(_talk, Vector2.ZERO, 13, key, tap, true, a)
		_talk.draw_set_transform(Vector2.ZERO)
	var w := Pixel.width(label, 2)
	Pixel.draw_cells(_talk, Pixel.cells(label, Vector2(roundf(center.x - w / 2.0), center.y + 14.0), 2), PROMPT, a)


func _bubble(text: String, anchor: Vector2, hi: Array, accent: Color, shown: int, wait_arrow: bool, on_screen := true):
	anchor = anchor.round()
	var lines := text.split("\n")
	var w := 0.0
	for l in lines:
		w = maxf(w, Pixel.width(l.replace("{", "").replace("}", ""), 1))
	var size := Vector2(w + 12.0, lines.size() * 9.0 + (11.0 if wait_arrow else 7.0))
	var box := Rect2(Vector2(clampf(anchor.x - size.x / 2.0, anchor.x - size.x + 14.0, anchor.x - 14.0), anchor.y - 6.0 - size.y), size).abs()
	var view := get_viewport().get_visible_rect()
	if on_screen:                                             # (kept in view; his last line can go off it, after him)
		box.position.x = clampf(box.position.x, 4.0, view.size.x - 4.0 - box.size.x)
		box.position.y = maxf(box.position.y, CinemaBars.HEIGHT + 4.0)
	box.position = box.position.round()
	anchor.x = clampf(anchor.x, box.position.x + 6.0, box.end.x - 9.0)
	_talk.draw_rect(box.grow(1.0), Pixel.INK)
	_talk.draw_rect(box, BUBBLE)
	_talk.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), accent)
	for i in 4:                                               # the tail
		_talk.draw_rect(Rect2(anchor.x - 3.0 + i, box.end.y + i, 7.0 - i * 2.0, 1), Pixel.INK if i == 3 else BUBBLE)
	var y := box.position.y + 5.0
	var count := 0                                            # letters so far (no breaks, no braces)
	var hl := false
	for l in lines:
		var x := box.position.x + 6.0
		var i := 0
		while i < l.length():
			if l[i] == " ":
				x += Pixel.width(" ", 1) + 1.0
				i += 1
				count += 1
				continue
			var start := i
			while i < l.length() and l[i] != " ":
				i += 1
			var word := l.substr(start, i - start)
			var marked := ("{" if hl and not word.begins_with("{") else "") + word
			for ch in word:
				if ch == "{": hl = true
				elif ch == "}": hl = false
			var plain := word.replace("{", "").replace("}", "")
			var word_w := Pixel.width(plain, 1)
			if count < shown:
				_draw_popping(marked, Vector2(x, y), word_w, _t - float(_popped.get(count, -10.0)), hi)
			x += word_w + 1.0
			count += plain.length()
		count += 1                                            # (the break counts as a space)
		y += 9.0
	if wait_arrow and shown >= _flat_len(text):                          # waiting for you: a little arrow, bouncing
		var bob := roundf(absf(sin(_t * 6.0)) * 2.0)
		var at := Vector2(box.end.x - 9.0, box.end.y - 6.0 + bob)
		for row in 3:
			_talk.draw_rect(Rect2(at.x - 3.0 + row, at.y + row - 1.0, 7.0 - row * 2.0 + 2.0, 2), Pixel.INK)
		for row in 3:
			_talk.draw_rect(Rect2(at.x - 2.0 + row, at.y + row - 1.0, 5.0 - row * 2.0, 1), accent if row < 2 else Pixel.WHITE)


func _draw_popping(word: String, at: Vector2, w: float, age: float, hi: Array):
	var k := 1.0
	if age < POP_UP:
		var e := age / POP_UP
		k = lerpf(POP_FROM, POP_BIG, 1.0 - (1.0 - e) * (1.0 - e))
	elif age < POP_UP + POP_SETTLE:
		var e := (age - POP_UP) / POP_SETTLE
		k = lerpf(POP_BIG, 1.0, e * e * (3.0 - 2.0 * e))
	if k == 1.0:
		Pixel.draw_cells(_talk, Pixel.cells(word, at, 1), TEXT, 1.0, hi)
		return
	var center := at + Vector2(w / 2.0, 3.5)
	_talk.draw_set_transform(center, 0.0, Vector2(k, k))
	Pixel.draw_cells(_talk, Pixel.cells(word, Vector2(-w / 2.0, -3.5), 1), TEXT, 1.0, hi)
	_talk.draw_set_transform(Vector2.ZERO)
