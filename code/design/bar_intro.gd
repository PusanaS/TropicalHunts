extends Node2D
# THE TIKI BAR (level 1's opening scene, Morgan's idea, 2026-10-08): a room before the surf run. The tiki bar
# stands on the right, the customer (girl-Sheet.png) on the left, and you start behind the bar.
#   1. She says: "HEY! I'M REALLY FEELING LIKE A PINA COLADA RIGHT NOW."
#      and: "IT WOULD BE SO NICE IF YOU COULD DO THAT FOR ME ♥"
#   2. You say: "WELL... I'M OUT OF STOCK. BUT FOR YOU... I'LL SEE WHAT I CAN DO."
#   3. She says: "OH THANK YOU SWEETIE! I KNEW YOU'D BE A DARLING. BUT MAKE IT FAST, I'M SO THIRSTY!"
#   4. You say: "I NEED TO GO FIGHT... UHH, I MEAN... *FIND* THE RIGHT JUICES." and "I'LL BE RIGHT BACK"
#   5. You walk out from behind the bar to the right, through the gate (gate_path, a tutorial_gate.gd with
#      start_open), which slams shut behind you for good. The level starts there: the LEVEL 1 title comes in
#      (level.gd's intro_done), the timer starts on your first move, and falling sends you back past the gate.
# While it plays you're held still (your physics is paused) with the cinema bars on. Each line types out (a
# press of jump, Q or W finishes it early), then waits for a press, with a little bouncing arrow at the bottom
# of the bubble to say so (Morgan's call).
# THE ENDING (Morgan's idea, 2026-10-08): when the boss is beaten, level.gd calls play_ending() (this node is in
# the group "level_outro"). A blender (blender_finish.gd) drops in where it fell, its juice fills it, it blends
# and pours a pina colada. The cinema bars come back, the camera whips back across the level to the bar, the
# gate winches up and you walk back in and up behind the counter. The drink slides along the counter to her
# (hearts), a last little chat (OUTRO_LINES), then LEVEL CLEAR (level.gd's ending_done).
# THE FAIL ENDING (Morgan's idea, 2026-10-08): when the juice clock runs out, level.gd calls play_fail(). The bars,
# the same pan back, and you walk back in behind the bar empty-handed. You say you couldn't do it; she's
# disappointed, but these things happen in life: want to try again? YES or NO (← → to pick, jump/Q/W to say it).
# YES: "GO GET 'EM, TIGER!", and the level starts over (the scene reloads, `retrying` skips the chat: you walk
# straight out). NO: "I'LL COME BACK ANOTHER TIME", and a THANKS FOR PLAYING card (ENTER tries again).
# Place it at the bar's middle, on the floor. The bar is PLACEHOLDER art drawn in code; the girl is Violeta's.

@export var gate_path: NodePath
@export var girl_x := 300.0                       # (global) where the customer stands
@export var exit_x := 650.0                       # (global) you walk to here, then the level starts

const Pixel := preload("res://code/design/pixel_font.gd")
const CinemaBars := preload("res://code/design/cinema_bars.gd")
const BlenderFinish := preload("res://code/design/blender_finish.gd")
const GIRL_SHEET := preload("res://girl-Sheet.png")
const GIRL_FEET := 96                             # her feet's row in each 128x128 cell
const GIRL_FPS := 6.0
# you stand on a little step behind the bar (BoardBarStep in the level, its top STEP_H up), so you show over the
# counter; walking out you hop down off its end, still behind the counter (Morgan's call)
const STEP_H := 18.0
const STEP_END := 38.0                            # its right end (from this node)
const DROP_GRAVITY := 900.0
const LINES := [
	["girl", "HEY! I'M REALLY FEELING\nLIKE A {PINA COLADA}\nRIGHT NOW."],
	["girl", "IT WOULD BE SO NICE IF\nYOU COULD DO THAT\nFOR ME ♥"],
	["you", "WELL... I'M OUT OF STOCK.\nBUT FOR YOU... I'LL SEE\nWHAT I CAN DO."],
	["girl", "OH THANK YOU SWEETIE!\nI KNEW YOU'D BE A\nDARLING. BUT MAKE IT\nFAST, I'M SO THIRSTY!"],
	["you", "I NEED TO GO FIGHT...\nUHH, I MEAN... *FIND* THE\nRIGHT JUICES."],
	["you", "I'LL BE RIGHT BACK"],
]
# her line about the juice clock (Morgan's call, 2026-10-08), after "...I'M SO THIRSTY!" (LINES[WAIT_AFTER]). Only
# when the level's juice clock is on, with its clock_start filled in. [words] in square brackets are red and shake;
# once they're out, a copy flies up out of the bubble to the top middle and becomes the countdown (level_hud.gd's
# juice_arrive), so you know what that number up there is
const WAIT_LINE := "...SO I'M WILLING TO WAIT\nABOUT [%d] SECONDS."
const WAIT_AFTER := 3
const RED := [Color("e8402e"), Color("a8201a"), Color("ff8a70")]
const FAIL_LINES := [
	["you", "SORRY... I RAN OUT OF\nJUICE. I COULDN'T DO IT."],
	["girl", "AWW... AND I WAS SO\nTHIRSTY, TOO..."],
	["girl", "BUT HEY, THESE THINGS\nHAPPEN IN LIFE. WANT\nTO TRY AGAIN?"],
]
const RETRY_LINES := [["girl", "YAY! GO GET 'EM,\nTIGER! ♥"]]
const GIVE_UP_LINES := [["girl", "OH... OKAY. I'LL COME\nBACK ANOTHER TIME,\nSWEETIE."]]   # she's the customer: she'll be back (Morgan's call)
const OUTRO_LINES := [
	["you", "ONE {PINA COLADA},\nFRESHLY SQUEEZED!"],
	["girl", "MMM... IT'S GREAT!\nYOU'RE AWESOME,\nSWEETIE ♥"],
	["you", "OH, IT WAS NOTHING...\n*TOTALLY* NOTHING."],
]
# the ending
const BLENDER_OFF := 70.0                         # the blender lands this far to the side of where the boss fell
const PAN_TIME := 1.3                             # the whip pan back to the bar
const BAR_VIEW := Vector2(-20, -80)               # where the camera settles (from this node)
const WALK_IN_FROM := 40.0                        # you walk back in from this far past exit_x
const SERVE_TO := -58.0                           # the drink slides along the counter to here (her end)
const HEART_LIFE := 1.6
const HEART := [Color("e86a9a"), Color("b03a6a"), Color("f6b0c8")]   # the ♥ in her line: pink
const HIGHLIGHT := [Color("f2c22e"), Color("d8901c"), Color("fff3b0")]  # {words} in braces: pineapple yellow
const START_WAIT := 0.6                           # a beat before she speaks
const TYPE_SPEED := 32.0                          # letters a second
const WALK_SPEED := 120.0
const SHUT_AT := 614.0                            # past this, the gate slams shut behind you
const BUBBLE_GIRL := Vector2(0, -74)              # where her bubble points (from her feet)
const BUBBLE_YOU := Vector2(0, -48)               # where yours does
const TEXT := [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE]

# the bar's colours (BOOM's style: flat, one shade each)
const STRAW := Color("c9a46a")
const STRAW_DARK := Color("8e6a3c")
const STRAW_LIGHT := Color("e2c48a")
const BAMBOO := Color("b8a356")
const BAMBOO_DARK := Color("7d6c32")
const WOOD := Color("6b4424")
const WOOD_LIGHT := Color("8e5c30")
const BOTTLES := [Color("d36618"), Color("3894b1"), Color("8d0e0e"), Color("76964a"), Color("ccad4b")]
const GLASS := Color("ecdfdb")
const COLADA := Color("f3ead0")
const FLAME := [Color("fff3b0"), Color("ffcf4a"), Color("ff9a2e")]

enum Step { WAIT, TALK, WALK, DONE, WALK_IN, CHOICE, CARD }

signal _walked_in
signal _talked
signal _chose

# set before the scene reloads for another try: the opening chat's skipped and you walk straight out
static var retrying := false

var player: CharacterBody2D = null
var _step := Step.WAIT
var _t := 0.0
var _line := 0
var _shown := 0.0                                 # letters of the current line shown so far
var _gate: Node = null
var _held := false
var _girl := AnimatedSprite2D.new()
var _back := Node2D.new()                         # roof, posts, shelf and bottles: behind you
var _front := Node2D.new()                        # the counter: in front of you (you're behind the bar)
var _talk := Node2D.new()                         # the speech bubbles, over everything
var _drop_v := 0.0                                # hopping down off the step
var _lines: Array = LINES                         # what's being said: the opening, then the ending
var _outro := false
var _cam: Camera2D = null                         # the ending's own camera (on the blender, then the pan)
var _serve_on := false
var _serve_x := 10.0                              # the drink on the counter (from this node)
var _hearts: Array = []                           # floating up off her when it reaches her: [pos, age]
var _retry := false                               # this is another try: no chat, straight out
var _choice := 0                                  # 0 YES, 1 NO
var _red_at := Vector2.INF                        # where a line's [red] words were last drawn (local)
var _red_sent := false                            # their copy has flown up to the countdown


func _ready():
	add_to_group("level_intro")                   # level.gd waits for intro_done() before the level starts
	add_to_group("level_outro")                   # ...and calls play_ending() when the boss is beaten
	_back.z_index = -1
	_back.draw.connect(_draw_back)
	add_child(_back)
	_front.z_as_relative = false
	_front.z_index = 3                            # (over the grass blades in front of your feet, z 2)
	_front.draw.connect(_draw_front)
	add_child(_front)
	_talk.z_as_relative = false
	_talk.z_index = 50
	_talk.draw.connect(_draw_talk)
	add_child(_talk)
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", GIRL_FPS)
	for i in 4:
		var tex := AtlasTexture.new()
		tex.atlas = GIRL_SHEET
		tex.region = Rect2(i * 128, 0, 128, 128)
		frames.add_frame("default", tex)
	_girl.sprite_frames = frames
	_girl.z_index = -1
	_girl.position = Vector2(girl_x - global_position.x, 64 - GIRL_FEET)
	_girl.flip_h = true                           # (her sheet faces left: she faces the bar)
	add_child(_girl)
	_girl.play("default")
	_gate = get_node_or_null(gate_path)
	_retry = retrying
	retrying = false


func _process(delta: float):
	_t += delta
	_back.queue_redraw()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
	match _step:
		Step.WAIT:
			if player.global_position.x > exit_x + 50.0:      # (testing: the Player was moved further on in the
				_step = Step.DONE                               # scene) no opening: the level starts where you are
				get_tree().call_group("level", "intro_done", player.global_position)
				return
			_hold_player()
			if _t >= START_WAIT and _held:
				if _retry:                                      # another try: no chat, straight out
					_start_walk()
				else:
					_step = Step.TALK
					_line = 0
					_shown = 0.0
					var level := get_tree().get_first_node_in_group("level")
					if level and level.get("juice_clock"):
						_lines = LINES.duplicate()
						_lines.insert(WAIT_AFTER + 1, ["girl", WAIT_LINE % int(level.clock_start)])
		Step.TALK:
			_talking(delta)
		Step.WALK:
			_walking(delta)
		Step.WALK_IN:
			_walking_in(delta)
		Step.CHOICE:
			if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
				_choice = 1 - _choice
			elif _pressed():
				_step = Step.DONE
				_chose.emit()
		Step.CARD:
			if Input.is_action_just_pressed("ui_accept"):
				_try_again()
	for h: Array in _hearts:
		h[1] += delta
	_hearts = _hearts.filter(func(h): return h[1] < HEART_LIFE)
	if _serve_on:
		_front.queue_redraw()
	_talk.queue_redraw()


# held still behind the bar, facing her, with the cinema bars on
func _hold_player():
	if _held or not player.is_on_floor():
		return
	_held = true
	player.velocity = Vector2.ZERO
	var states: Dictionary = player.get_script().State
	player._set_state(states["IDLE"])
	player.set_physics_process(false)
	player.facing = -1
	(player.get_node("AnimatedSprite2D") as AnimatedSprite2D).flip_h = true
	CinemaBars.set_on(get_tree(), true)


func _pressed() -> bool:
	return Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack_light") \
		or Input.is_action_just_pressed("attack_heavy")


# a line types out (a press finishes it early), then waits for a press to go on to the next
func _talking(delta: float):
	_send_red()
	var text: String = _lines[_line][1]
	var full := text.replace("\n", "").length()
	if _shown < full:
		_shown = minf(_shown + TYPE_SPEED * delta, full)
		if _pressed():
			_shown = full
		return
	if _pressed():
		_line += 1
		_shown = 0.0
		if _line >= _lines.size():
			if _outro:
				_step = Step.DONE
				_talked.emit()
			else:
				_start_walk()


# level.gd asks at the start: will the chat, with her line bringing in the countdown, play? (not on a retry)
func shows_clock_line() -> bool:
	return not _retry


# once a line's [red] words are all out (and drawn), a copy of them flies up to the countdown, once
func _send_red():
	if _red_sent or _red_at == Vector2.INF:
		return
	var flat := String(_lines[_line][1]).replace("\n", "")
	var start := flat.find("[")
	var end := flat.find("]")
	if start < 0 or end < 0 or _shown <= end:
		return
	_red_sent = true
	var from := get_viewport().get_canvas_transform() * _talk.to_global(_red_at)
	get_tree().call_group("level_hud", "juice_arrive", from, flat.substr(start + 1, end - start - 1))


# off you go: out from behind the bar, to the right, through the gate
func _start_walk():
	_step = Step.WALK
	player.facing = 1
	(player.get_node("AnimatedSprite2D") as AnimatedSprite2D).flip_h = false
	var states: Dictionary = player.get_script().State
	player._set_state(states["WALK"])


func _walking(delta: float):
	player.global_position.x += WALK_SPEED * delta
	if player.global_position.x - global_position.x > STEP_END and player.global_position.y < global_position.y:
		_drop_v += DROP_GRAVITY * delta                       # off the end of the step: down to the floor
		player.global_position.y = minf(player.global_position.y + _drop_v * delta, global_position.y)
	if player.global_position.x >= SHUT_AT and _gate and _gate.has_method("close") and not _gate.get_meta("shut", false):
		_gate.set_meta("shut", true)
		_gate.close()                             # it slams shut behind you, for good
	if player.global_position.x >= exit_x:
		player.global_position.x = exit_x
		_finish()


# the level starts: you're free, the bars go, LEVEL 1 comes in, and you respawn out here from now on
func _finish():
	_step = Step.DONE
	_let_go()
	var states: Dictionary = player.get_script().State
	player._set_state(states["IDLE"])
	get_tree().call_group("level", "intro_done", Vector2(exit_x, 0))


# ---------- the ending ----------
func play_ending(at: Vector2):
	if _outro:
		return
	_outro = true
	_run_ending(at)


func _run_ending(at: Vector2):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
	_hold_anywhere()
	# the blender, where the boss fell, on whichever side has room for the glass; our own camera on it
	var side := 1.0 if _room(at, 1.0) else -1.0
	var blender: Node2D = BlenderFinish.new()
	blender.side = side
	get_tree().current_scene.add_child(blender)
	blender.global_position = Vector2(at.x + side * BLENDER_OFF, at.y)
	_cam = Camera2D.new()
	get_tree().current_scene.add_child(_cam)
	_cam.global_position = Vector2(at.x + side * BLENDER_OFF * 0.7, at.y - 60.0)
	_cam.make_current()
	await blender.done
	await _back_to_bar()
	# the drink: on the counter in front of you, sliding along to her
	_serve_on = true
	_serve_x = 10.0
	await get_tree().create_timer(0.3).timeout
	var slide := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slide.tween_property(self, "_serve_x", SERVE_TO, 0.6)
	await slide.finished
	for i in 5:
		_hearts.append([Vector2(girl_x - global_position.x + randf_range(-14, 14), -70.0 - randf_range(0, 10)), -i * 0.12])
	await get_tree().create_timer(0.5).timeout
	_say(OUTRO_LINES)
	await _talked
	CinemaBars.set_on(get_tree(), false)
	get_tree().call_group("level", "ending_done")


# the bars, a whip pan all the way back to the bar, the gate winching up, and you walking back in and up behind
# the counter (the win and the fail both end here)
func _back_to_bar():
	CinemaBars.set_on(get_tree(), true)
	await get_tree().create_timer(0.4).timeout
	var pan := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	pan.tween_property(_cam, "global_position", global_position + BAR_VIEW, PAN_TIME)
	await pan.finished
	if _gate and _gate.has_method("open"):
		_gate.open()
	await get_tree().create_timer(0.3).timeout
	player.global_position = Vector2(exit_x + WALK_IN_FROM, global_position.y)
	player.facing = -1
	(player.get_node("AnimatedSprite2D") as AnimatedSprite2D).flip_h = true
	var states: Dictionary = player.get_script().State
	player._set_state(states["WALK"])
	_step = Step.WALK_IN
	await _walked_in


func _say(lines: Array):
	_lines = lines
	_line = 0
	_shown = 0.0
	_step = Step.TALK


# ---------- the fail ending ----------
func play_fail():
	if _outro:
		return
	_outro = true
	_run_fail()


func _run_fail():
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
	_hold_anywhere()
	_cam = Camera2D.new()                             # from wherever the view is now, back to the bar
	get_tree().current_scene.add_child(_cam)
	var now_cam := get_viewport().get_camera_2d()
	_cam.global_position = now_cam.get_screen_center_position() if now_cam else player.global_position + Vector2(0, -72)
	_cam.make_current()
	await _back_to_bar()
	await get_tree().create_timer(0.4).timeout
	_say(FAIL_LINES)
	await _talked
	_choice = 0                                       # YES or NO?
	_step = Step.CHOICE
	await _chose
	if _choice == 0:
		_say(RETRY_LINES)
		await _talked
		_try_again()
	else:
		_say(GIVE_UP_LINES)
		await _talked
		CinemaBars.set_on(get_tree(), false)
		get_tree().call_group("level", "fail_card")
		await get_tree().create_timer(1.2).timeout
		_step = Step.CARD


# the level starts over, straight out of the bar
func _try_again():
	_step = Step.DONE
	retrying = true
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# held still wherever you are (the boss fight's end): idle, physics paused
func _hold_anywhere():
	_held = true
	player.velocity = Vector2.ZERO
	var states: Dictionary = player.get_script().State
	player._set_state(states["IDLE"])
	player.set_physics_process(false)


# is there room beside `at` (world) for the blender and its glass on this side?
func _room(at: Vector2, side: float) -> bool:
	var reach := BLENDER_OFF + 70.0
	var q := PhysicsRayQueryParameters2D.create(at + Vector2(0, -20), at + Vector2(side * reach, -20), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# walking back in from the right, up onto the step, to your spot behind the bar
func _walking_in(delta: float):
	player.global_position.x -= WALK_SPEED * delta
	var lx := player.global_position.x - global_position.x
	if lx <= STEP_END + 4.0:                                  # up onto the step
		player.global_position.y = maxf(player.global_position.y - 160.0 * delta, global_position.y - STEP_H)
	if lx <= 10.0:
		player.global_position = Vector2(global_position.x + 10.0, global_position.y - STEP_H)
		var states: Dictionary = player.get_script().State
		player._set_state(states["IDLE"])
		_step = Step.DONE
		_walked_in.emit()


func _let_go():
	if _held and player and is_instance_valid(player):
		player.set_physics_process(true)
	if _held:
		CinemaBars.set_on(get_tree(), false)
	_held = false


func _exit_tree():
	_let_go()


# ---------- drawing ----------
# the speech bubble of whoever's talking: a dark plate with a tail down to them, the line typing out, and a
# little bouncing arrow at the bottom once it's all out (press to go on)
func _draw_talk():
	for h: Array in _hearts:                                  # hearts floating up off her
		var age: float = h[1]
		if age < 0.0:
			continue
		var k := age / HEART_LIFE
		var p: Vector2 = h[0] + Vector2(roundf(sin(age * 6.0 + h[0].x) * 3.0), -roundf(age * 22.0))
		Pixel.draw_cells(_talk, Pixel.cells("♥", p.round(), 1), HEART, 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0))
	if _step == Step.CHOICE and player:
		_draw_choice()
		return
	if _step != Step.TALK or player == null:
		return
	var who: String = _lines[_line][0]
	var lines: PackedStringArray = String(_lines[_line][1]).split("\n")
	var anchor: Vector2 = (Vector2(girl_x, 0) + BUBBLE_GIRL) if who == "girl" else (player.global_position + BUBBLE_YOU)
	anchor = (anchor - global_position).round()
	var w := 0.0
	for l in lines:
		w = maxf(w, Pixel.width(l.replace("[", "").replace("]", ""), 1))
	var size := Vector2(w + 12.0, lines.size() * 9.0 + 11.0)    # (room at the bottom for the arrow)
	var box := Rect2(Vector2(clampf(anchor.x - size.x / 2.0, anchor.x - size.x + 14.0, anchor.x - 14.0), anchor.y - 6.0 - size.y), size).abs()
	# always on screen: kept inside the view (and below the top cinema bar)
	var view := Rect2(to_local(get_viewport().get_canvas_transform().affine_inverse() * Vector2.ZERO),
		get_viewport().get_visible_rect().size)
	box.position.x = clampf(box.position.x, view.position.x + 4.0, view.end.x - 4.0 - box.size.x)
	box.position.y = maxf(box.position.y, view.position.y + CinemaBars.HEIGHT + 4.0)
	box.position = box.position.round()
	anchor.x = clampf(anchor.x, box.position.x + 6.0, box.end.x - 9.0)
	var accent: Color = Pixel.ORANGE if who == "girl" else Pixel.TEAL
	_talk.draw_rect(box.grow(1.0), Pixel.INK)
	_talk.draw_rect(box, Color(0.1, 0.08, 0.12, 0.94))
	_talk.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), accent)
	for i in 4:                                               # the tail
		_talk.draw_rect(Rect2(anchor.x - 3.0 + i, box.end.y + i, 7.0 - i * 2.0, 1), Pixel.INK if i == 3 else Color(0.1, 0.08, 0.12, 0.94))
	var left := int(_shown)
	var y := box.position.y + 5.0
	for l in lines:
		var part := l.substr(0, maxi(left, 0))
		left -= l.length()
		if part != "":
			_draw_words(part, Vector2(box.position.x + 6.0, y))
		y += 9.0
	var full := String(_lines[_line][1]).replace("\n", "").length()
	if _shown >= full:                                        # waiting for you: a little arrow, bouncing
		var bob := roundf(absf(sin(_t * 6.0)) * 2.0)
		var at := Vector2(box.end.x - 9.0, box.end.y - 6.0 + bob)
		for row in 3:
			_talk.draw_rect(Rect2(at.x - 3.0 + row, at.y + row - 1.0, 7.0 - row * 2.0 + 2.0, 2), Pixel.INK)
		for row in 3:
			_talk.draw_rect(Rect2(at.x - 2.0 + row, at.y + row - 1.0, 5.0 - row * 2.0, 1), accent if row < 2 else Pixel.WHITE)


# YES / NO in your bubble: the one picked is yellow with a little arrow by it (← → to pick, jump/Q/W to say it)
func _draw_choice():
	var anchor := (player.global_position + BUBBLE_YOU - global_position).round()
	var gap := 14.0
	var yes_w := Pixel.width("YES", 1)
	var no_w := Pixel.width("NO", 1)
	var size := Vector2(yes_w + no_w + gap + 22.0, 16.0)
	var box := Rect2((anchor - Vector2(size.x / 2.0, size.y + 6.0)).round(), size)
	_talk.draw_rect(box.grow(1.0), Pixel.INK)
	_talk.draw_rect(box, Color(0.1, 0.08, 0.12, 0.94))
	_talk.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), Pixel.TEAL)
	for i in 4:                                               # the tail
		_talk.draw_rect(Rect2(anchor.x - 3.0 + i, box.end.y + i, 7.0 - i * 2.0, 1), Pixel.INK if i == 3 else Color(0.1, 0.08, 0.12, 0.94))
	var y := box.position.y + 5.0
	var x_yes := box.position.x + 11.0
	var x_no := x_yes + yes_w + gap
	Pixel.draw_cells(_talk, Pixel.cells("YES", Vector2(x_yes, y), 1), HIGHLIGHT if _choice == 0 else TEXT)
	Pixel.draw_cells(_talk, Pixel.cells("NO", Vector2(x_no, y), 1), HIGHLIGHT if _choice == 1 else TEXT)
	var nudge := roundf(absf(sin(_t * 6.0)) * 1.0)
	var ax := (x_yes if _choice == 0 else x_no) - 7.0 + nudge
	Pixel.draw_cells(_talk, Pixel.cells("→", Vector2(ax, y), 1), HIGHLIGHT)


# a line's text: {words} in braces are pineapple yellow, a ♥ is pink, [words] in square brackets are red and shake
func _draw_words(text: String, at: Vector2):
	var x := at.x
	var chunks := text.split("[")
	for ci in chunks.size():
		var chunk: String = chunks[ci]
		if ci > 0:                                            # red up to the "]" (or the end, while it types out)
			var end := chunk.find("]")
			var red := chunk if end < 0 else chunk.substr(0, end)
			if red != "":
				_red_at = Vector2(x, at.y)
				var cells := Pixel.cells(red, _red_at, 1)
				for c: Array in cells:                        # each letter jitters a pixel
					var r: Rect2 = c[0]
					var i: int = c[2]
					r.position += Vector2(roundf(sin(_t * 41.0 + i * 1.9)), roundf(cos(_t * 37.0 + i * 2.7)))
					c[0] = r
				Pixel.draw_cells(_talk, cells, RED)
				x += Pixel.width(red, 1) + 1.0
			chunk = "" if end < 0 else chunk.substr(end + 1)
		x = _draw_plain(chunk, Vector2(x, at.y))


# plain words (with {braces} and ♥s): returns where the next letter goes
func _draw_plain(text: String, at: Vector2) -> float:
	var parts := text.split("♥")
	var x := at.x
	for i in parts.size():
		if parts[i] != "":
			Pixel.draw_cells(_talk, Pixel.cells(parts[i], Vector2(x, at.y), 1), TEXT, 1.0, HIGHLIGHT)
		x += Pixel.width(parts[i] + "♥", 1) - Pixel.width("♥", 1)
		if i < parts.size() - 1:
			Pixel.draw_cells(_talk, Pixel.cells("♥", Vector2(x, at.y), 1), HEART)
			x += Pixel.width("♥ ", 1) - Pixel.width(" ", 1)
	return x


# behind you: the thatched roof with its sign, the bamboo posts, the shelf of bottles and a blender, and a tiki
# torch out front by her
func _draw_back():
	# the torch, by the customer
	var tx := girl_x - global_position.x - 70.0
	_back.draw_rect(Rect2(tx - 1.0, -46, 3, 46), BAMBOO_DARK)
	_back.draw_rect(Rect2(tx - 3.0, -52, 7, 6), STRAW_DARK)
	for i in 3:
		var h := 6.0 + roundf(absf(sin(_t * 9.0 + i * 1.7)) * 4.0) - i * 2.0
		_back.draw_rect(Rect2(tx - 2.0 + i, -52.0 - h, 5.0 - i * 2.0, h), FLAME[i])
	# posts
	for px in [-88.0, 84.0]:
		_back.draw_rect(Rect2(px, -92, 6, 92), BAMBOO)
		_back.draw_rect(Rect2(px + 4.0, -92, 2, 92), BAMBOO_DARK)
		var ry := -84.0
		while ry < 0.0:
			_back.draw_rect(Rect2(px, ry, 6, 1), BAMBOO_DARK)
			ry += 14.0
	# the shelf behind the bar, with bottles and a blender
	_back.draw_rect(Rect2(-64, -60, 128, 3), WOOD)
	_back.draw_rect(Rect2(-64, -60, 128, 1), WOOD_LIGHT)
	for i in 7:
		var bx := -58.0 + i * 15.0
		var col: Color = BOTTLES[i % BOTTLES.size()]
		var bh := 10.0 + float((i * 7) % 4)
		_back.draw_rect(Rect2(bx, -60.0 - bh, 5, bh), col)
		_back.draw_rect(Rect2(bx + 1.0, -64.0 - bh, 3, 4), col.darkened(0.3))
		_back.draw_rect(Rect2(bx + 1.0, -58.0 - bh, 1, bh - 4.0), Color(1, 1, 1, 0.35))
	_back.draw_rect(Rect2(46, -76, 10, 16), Color(0.75, 0.85, 0.9, 0.8))   # the blender
	_back.draw_rect(Rect2(44, -62, 14, 2), Pixel.INK)
	# the step you stand on (mostly hidden by the counter): a little crate
	_back.draw_rect(Rect2(-18, -STEP_H, STEP_END + 18.0, STEP_H), WOOD)
	_back.draw_rect(Rect2(-18, -STEP_H, STEP_END + 18.0, 1), WOOD_LIGHT)
	_back.draw_rect(Rect2(-18, -STEP_H / 2.0, STEP_END + 18.0, 1), WOOD.darkened(0.3))
	# the thatched roof, ragged along its bottom, with its sign
	_back.draw_colored_polygon(PackedVector2Array([Vector2(-100, -90), Vector2(100, -90), Vector2(80, -118), Vector2(-80, -118)]), STRAW)
	var sx := -100.0
	while sx < 100.0:
		var drop := 3.0 + float(posmod(int(sx) * 7, 5))
		_back.draw_rect(Rect2(sx, -90, 4, drop), STRAW_DARK if int(sx) % 8 == 0 else STRAW)
		sx += 4.0
	for i in 5:
		_back.draw_line(Vector2(-80 + i * 40, -118), Vector2(-100 + i * 50, -90), STRAW_DARK, 1.0)
	_back.draw_line(Vector2(-80, -118), Vector2(80, -118), STRAW_LIGHT, 1.0)
	var title := "TIKI BAR"
	var sw := Pixel.width(title, 1)
	_back.draw_rect(Rect2(-sw / 2.0 - 4.0, -111, sw + 8.0, 11), WOOD)
	Pixel.draw_cells(_back, Pixel.cells(title, Vector2(-roundf(sw / 2.0), -109), 1), [Pixel.MUSTARD, Pixel.ORANGE, Pixel.OFF_WHITE])


# in front of you: the bamboo counter (you're behind it), with a pina colada on top at her end
func _draw_front():
	_front.draw_rect(Rect2(-74, -34, 148, 4), WOOD)
	_front.draw_rect(Rect2(-74, -34, 148, 1), WOOD_LIGHT)
	var x := -72.0
	var i := 0
	while x < 72.0:
		_front.draw_rect(Rect2(x, -30, 6, 30), BAMBOO if i % 2 == 0 else BAMBOO.darkened(0.12))
		_front.draw_rect(Rect2(x + 5.0, -30, 1, 30), BAMBOO_DARK)
		_front.draw_rect(Rect2(x, -18.0 + float(i % 3) * 4.0, 6, 1), BAMBOO_DARK)
		x += 6.0
		i += 1
	# the pina colada (only once you're back with it): a curvy glass, the drink, a pineapple wedge and an umbrella
	if not _serve_on:
		return
	var g := Vector2(roundf(_serve_x), -34)
	_front.draw_rect(Rect2(g.x - 1.0, g.y - 2.0, 4, 2), GLASS)
	_front.draw_rect(Rect2(g.x, g.y - 6.0, 2, 4), GLASS)
	_front.draw_rect(Rect2(g.x - 3.0, g.y - 14.0, 8, 8), COLADA)
	_front.draw_rect(Rect2(g.x - 3.0, g.y - 14.0, 1, 8), GLASS)
	_front.draw_rect(Rect2(g.x + 4.0, g.y - 17.0, 3, 3), Pixel.MUSTARD)
	_front.draw_line(Vector2(g.x - 2.0, g.y - 14.0), Vector2(g.x - 6.0, g.y - 22.0), Pixel.PALE, 1.0)
	_front.draw_rect(Rect2(g.x - 10.0, g.y - 24.0, 8, 2), Pixel.RED)
