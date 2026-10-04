extends Node2D
# TUTORIAL (scene/design/tutorial.tscn): every mechanic explained, then tested, one at a time.
# The level is a row of stations (the children of "Stations", in STEPS order). Each one ends in a gate
# (tutorial_gate.gd) that opens once its test is passed; walking through it brings up the next card.
# The cards, keys and progress pips are drawn by code/design/tutorial_hud.gd; this script decides what
# counts, and draws the flags and arrows in the world. What a station can hold:
#   Goal*    Marker2D: a flag to stand at (metadata "reach" = how close, in pixels)
#   Target*  training dummies (tutorial_target.gd): every hit is reported through the "tutorial" group
#   Mango*   fruit minions (the counter and the final test)
#   Spot     Marker2D: a glowing pad where to stand
#   Gate     the way out
# Start anywhere: stations left of where the player starts count as done. So LiveReload keeps your place,
# and moving the Player in the scene lets you test one station.

const Hud := preload("res://code/design/tutorial_hud.gd")
const Pixel := preload("res://code/design/pixel_font.gd")
const CounterChain := preload("res://code/counter_chain.gd")
const FruitMinion := preload("res://code/design/fruit_minion.gd")

const LIGHT := ["ATTACK_LIGHT_1", "ATTACK_LIGHT_2"]
const SLAMS := ["DASH_ATTACK_HEAVY_SLAM", "DASH_ATTACK_HEAVY_IMPACT"]
const TIP_GAP := 2.5             # a wrong-move tip waits this long after the last one
const ARROW := ["#######", ".#####.", "..###..", "...#..."]
# the big arrow over a Spot, pointing down at it (its tip is the bottom pixel)
const BIG_ARROW := ["...###...", "...###...", "...###...", "...###...", "...###...", "#########",
	".#######.", "..#####..", "...###...", "....#...."]
const SPOT_REACH := 14.0         # standing this close to a Spot counts as on it


# ---------- the stations ----------
# keys: what the card's key caps act out. press = when each key goes down in the loop (seconds), so
# keys can play one after the other. A "meter" shows the real build-up while you hold the key.
func _make_steps() -> Array:
	var all_keys := [_key("LEFT", _tap(0.0)), _key("RIGHT", _tap(0.3)), _key("SPACE", _tap(0.7)),
		_key("Q", _tap(1.1)), _key("W", _tap(1.5))]
	return [
		_step("Move", "move", "MOVE", [_key("LEFT", _tap(0.0)), _key("RIGHT", _tap(0.6))], 1.2,
			"USE THE {ARROW KEYS} TO WALK.\nWALK OVER TO THE FLAG.", 1, "NICE!"),
		_step("Jump", "jump", "JUMP", [_key("SPACE", _hold(0.0, 0.35))], 1.2,
			"PRESS {SPACE} TO JUMP. HOLD IT TO JUMP HIGHER.\nJUMP UP TO THE FLAG.", 1, "CLEAR!"),
		_step("DoubleJump", "double_jump", "DOUBLE JUMP", [_key("SPACE", _tap(0.0)), _sep("THEN"), _key("SPACE", _tap(0.4))], 1.4,
			"JUMP, THEN PRESS {SPACE} AGAIN IN THE AIR.\nGET UP ONTO THE TALL LEDGE.", 1, "GREAT!"),
		# double tap = gallop straight away (player.gd's debug_tap_gallop, Morgan's call). Its way out is the
		# gym's breakable gate (gallop_only): galloping through it, in slow motion, clears the station.
		_step("DoubleTap", "tap", "DOUBLE TAP", [_key("RIGHT", _tap_hold(0.0, 0.9))], 1.6,
			"TAP A DIRECTION TWICE TO GALLOP STRAIGHT AWAY.\nGALLOP INTO THE GATE TO SMASH RIGHT THROUGH IT!", 1, "SMASHED!"),
		_step("Slash", "light", "SLASH", [_key("Q", _tap(0.0)), _sep("OR HOLD"), _key("Q", _hold(0.0, 0.8))], 1.2,
			"PRESS {Q} TO SLASH. HOLD {Q} TO KEEP SLASHING.\nHIT THE DUMMY 6 TIMES.", 6, "JUICY!",
			{"wrong": "STAND STILL AND PRESS {Q}", "break": "cut"}),
		_step("Smash", "heavy", "SMASH", [_key("W", _tap(0.0))], 1.2,
			"PRESS {W} FOR A HEAVY SMASH.\nSMASH THE DUMMY 3 TIMES.", 3, "CLEAR!",
			{"wrong": "STAND STILL AND PRESS {W}", "break": "smash"}),
		_step("Charge", "charge", "CHARGED SMASH", [_key("W", _hold(0.1, 0.6), {"meter": "charge"})], 1.4,
			"HOLD {W}: IT CHARGES UP, THEN BLASTS ALL AROUND.\nSTAND ON THE SPOT AND HIT ALL 3 DUMMIES AT ONCE.", 3, "BOOM!",
			{"wrong": "HOLD {W} DOWN UNTIL IT BLASTS"}),
		_step("RollingSlash", "dash_q", "ROLLING SLASH", [_key("RIGHT", _double(0.0)), _sep("THEN"), _key("Q", _tap(0.55))], 1.4,
			"WHILE GALLOPING, PRESS {Q} TO ROLL AND SLASH.\nROLL THROUGH BOTH DUMMIES IN ONE GO.", 2, "SMOOTH!",
			{"wrong": "DOUBLE TAP FIRST, THEN PRESS {Q}"}),
		_step("LeapSlam", "dash_w", "LEAP SLAM", [_key("RIGHT", _double(0.0)), _sep("THEN"), _key("W", _tap(0.55))], 1.4,
			"WHILE GALLOPING, PRESS {W} TO LEAP AND SLAM DOWN.\nCATCH BOTH DUMMIES.", 2, "CRUSHED!",
			{"wrong": "DOUBLE TAP FIRST, THEN PRESS {W}"}),
		_step("AirSlash", "air_q", "AIR SLASH", [_key("SPACE", _tap(0.0)), _sep("THEN"), _key("Q", _tap(0.35))], 1.2,
			"JUMP, THEN PRESS {Q} TO SLASH IN THE AIR.\nHIT THE HANGING DUMMY TWICE.", 2, "SNAP!", {"break": "snap"}),
		_step("AirSlam", "air_w", "AIR SLAM", [_key("SPACE", _tap(0.0)), _sep("THEN"), _key("W", _tap(0.35))], 1.2,
			"JUMP, THEN PRESS {W} TO SLAM STRAIGHT DOWN.\nHIT BOTH DUMMIES.", 2, "GREAT!",
			{"wrong": "JUMP FIRST, THEN PRESS {W}"}),
		_step("Counter", "counter", "COUNTER", [_key("Q", _tap(0.0))], 1.2,
			"WHEN THE MANGO LUNGES AT YOU, PRESS {Q}.\nDON'T HIT IT FIRST: WAIT FOR THE LUNGE.", 1, "PERFECT!"),
		# after the flash you come out still galloping: the final arena is next, so that's fine
		# the only dummies that can be flashed (flashable): the others play dead to the flash
		_step("Flash", "flash", "THUNDERCLAP FLASH", [_key("RIGHT", _tap_hold(0.0, 1.0))], 1.6,
			"GALLOP INTO ENEMIES TO FLASH STRAIGHT THROUGH THEM.\nDOUBLE TAP {→} AND RUN AT THE DUMMIES.", 3, "LIGHTNING!",
			{"wrong": "DON'T ATTACK: GALLOP INTO THEM"}),
		_step("Final", "finale", "FINAL TEST", all_keys, 2.0,
			"USE EVERYTHING YOU LEARNED.\nPOP ALL 3 MANGOS.", 3, ""),
	]


func _step(node: String, id: String, title: String, keys: Array, period: float, hint: String, goal: int,
		word: String, extra := {}) -> Dictionary:
	var d := {"node": node, "id": id, "title": title, "keys": keys, "period": period, "hint": hint,
		"goal": goal, "word": word}
	d.merge(extra)
	return d


func _key(key_name: String, press: Array, extra := {}) -> Dictionary:
	var d := {"key": key_name, "press": press}
	d.merge(extra)
	return d


func _sep(text: String) -> Dictionary:
	return {"sep": text}


func _tap(at: float) -> Array:
	return [[at, at + 0.12]]


func _double(at: float) -> Array:
	return [[at, at + 0.09], [at + 0.18, at + 0.27]]


func _hold(at: float, length: float) -> Array:
	return [[at, at + length]]


# a double tap, then keep holding
func _tap_hold(at: float, length: float) -> Array:
	return [[at, at + 0.09], [at + 0.18, at + 0.18 + length]]


# ---------- state ----------
var player: CharacterBody2D = null
var hud: CanvasLayer
var _steps: Array = []
var _stations: Array = []
var _names: Array = []
var _mango_states: Array = FruitMinion.State.keys()
var _time_to_gallop := 3.0
var _top_level := 4              # the gallop's speed level
var _sprint_speed := 420.0
var _index := 0                  # the station being taught (the ones before it are done)
var _entered := false            # the player has walked into it and its card is up
var _started := false
var _count := 0
var _reached := {}               # goals / dummies / mangos already counted in this station
var _prev_state := ""
var _slam_from_air := false
var _blast := []                 # dummies the last charged smash hit
var _roll := []                  # dummies the current rolling slash has hit
var _blast_frame := 0
var _countering := false         # a counter is running (time is stopped)
var _counter_at := Vector2.ZERO  # where it started
var _dead := {}                  # mango -> dead last frame
var _counterable := {}           # mango -> could be countered last frame
var _tip_ready := 0.0
var _last_target: Node2D = null  # the dummy that took the last hit that counted
var _back := Node2D.new()        # flags and the stand-here pad, behind the player
var _front := Node2D.new()       # arrows and the counter cue, in front of everything


func _ready():
	global_position = Vector2.ZERO
	add_to_group("tutorial")
	process_physics_priority = 10        # after the player has moved this frame
	_steps = _make_steps()
	for s in _steps:
		_stations.append(get_parent().get_node("Stations/" + String(s["node"])))
	hud = Hud.new()
	hud.meter_source = _meter
	add_child(hud)
	_back.z_index = -1
	_back.draw.connect(_draw_back)
	add_child(_back)
	_front.z_index = 20
	_front.draw.connect(_draw_front)
	add_child(_front)
	get_parent().child_entered_tree.connect(_on_node_added)
	for i in _stations.size():               # a breakable gate (DOUBLE TAP): smashing it clears its station
		var gate = _stations[i].get_node_or_null("Gate")
		if gate and gate.has_signal("shattered"):
			gate.shattered.connect(_on_gate_smashed.bind(i))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(_delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		var s: GDScript = player.get_script()
		_names = s.State.keys()
		_time_to_gallop = s.TIME_TO_LEVEL_4
		var speeds: Array = s.SPEEDS
		_top_level = speeds.size() - 1
		_sprint_speed = speeds[_top_level - 1]
	_apply_locks()
	if not _started:
		_begin()
		return
	_track_player()
	if _index >= _steps.size():
		return
	# the game never waits for the HUD: a station counts from the moment you're in it, even while its
	# card is still waiting to come in (the HUD catches up)
	if not _entered:
		if player.global_position.x > _start_x(_index):
			_enter()
		return
	_check_step()


# moves aren't there until their station: no double jump before DOUBLE JUMP, no gallop before DOUBLE TAP. It holds down two of player.gd's own variables after the
# player moves each frame, so player.gd itself is untouched.
func _apply_locks():
	if not _taught("double_jump"):
		player.air_jumps_left = 0                   # refilled on the ground, emptied again as soon as you're up
	if not _taught("tap"):
		# the hold timer stops short of the gallop, so holding a direction tops out at the sprint
		player.hold_time = minf(player.hold_time, _time_to_gallop - 0.2)
		if player.speed_level >= _top_level:      # a double tap jumps straight to it: make that a sprint
			player.speed_level = _top_level - 1
			player.velocity.x = clampf(player.velocity.x, -_sprint_speed, _sprint_speed)


# the station with this id has started (or is done)
func _taught(id: String) -> bool:
	for i in _steps.size():
		if _steps[i]["id"] == id:
			return _index > i or (_index == i and _entered)
	return true


# the first frame: stations left of the player are done (their gates open at once)
func _begin():
	_started = true
	for i in _steps.size():
		var gate = _stations[i].get_node_or_null("Gate")
		if gate and player.global_position.x > gate.global_position.x:
			if gate.has_method("open"):
				gate.open(true)
			_index = i + 1
	hud.station_total = _steps.size()
	hud.station_index = _index
	if _index == 0:
		hud.banner(["TUTORIAL"], "LEARN EVERY MOVE, ONE AT A TIME", 1.6)


# a station starts once the player is through the gate before it
func _start_x(i: int) -> float:
	if i == 0:
		return -INF
	var gate = _stations[i - 1].get_node_or_null("Gate")
	return gate.global_position.x + 30.0 if gate else -INF


func _enter():
	_entered = true
	_count = 0
	_reached.clear()
	_blast.clear()
	_roll.clear()
	_dead.clear()
	_counterable.clear()
	hud.station_index = _index
	hud.show_card(_steps[_index], _index + 1, _steps.size())


func _progress(at: Vector2):
	if not _entered:
		return
	_count += 1
	hud.add_progress(at)
	var goal: int = _steps[_index]["goal"]
	if _count >= goal:
		_complete()


func _complete():
	var gate = _stations[_index].get_node_or_null("Gate")
	if gate and gate.has_method("open"):       # (a breakable gate is already in pieces)
		gate.open()
	# "break": the hit that finished the station breaks that dummy off its post ("cut" or "smash")
	if _steps[_index].has("break") and is_instance_valid(_last_target):
		_last_target.break_off(_steps[_index]["break"])
	if _index == _steps.size() - 1:
		hud.finale()
	else:
		hud.clear(_steps[_index]["word"])
	_index += 1
	_entered = false
	hud.station_index = _index


func _tip(text: String):
	if _now() < _tip_ready:
		return
	_tip_ready = _now() + TIP_GAP
	hud.toast(text)


# ---------- what counts ----------
func _track_player():
	var st: String = _names[player.state]
	if st != _prev_state:
		if st == "DASH_ATTACK_HEAVY_SLAM":     # the running W leaps first; the air W slams straight away
			_slam_from_air = _prev_state != "DASH_ATTACK_HEAVY_WINDUP"
		if st == "KNOCKBACK":                  # galloped into a wall
			_tip("OUCH! LET GO TO STOP BEFORE YOU HIT A WALL")
		# ROLLING SLASH: both dummies in one roll (Morgan's call). A roll that only got one: try again.
		if _prev_state == "DASH_ATTACK_LIGHT" and _entered and _steps[_index]["id"] == "dash_q" and _count > 0:
			_count = 0
			hud.fail("ALMOST! ROLL THROUGH BOTH DUMMIES IN ONE GO")
		if st == "DASH_ATTACK_LIGHT":
			_roll.clear()
		_prev_state = st


func _check_step():
	var station: Node = _stations[_index]
	match _steps[_index]["id"]:
		"move", "jump", "double_jump":
			for g in station.get_children():
				if g is Marker2D and g.name.begins_with("Goal") and not _reached.has(g) and _standing_at(g):
					_reached[g] = true
					_progress(g.global_position + Vector2(0, -20))
		"charge":
			if not _blast.is_empty() and Engine.get_physics_frames() > _blast_frame:
				_resolve_blast()
		"counter":
			for m in _mangos(station):
				var dead: bool = m.hp <= 0
				if dead and not _dead.get(m, false) and not _countering:
					_tip("TOO EARLY! WAIT FOR THE LUNGE, THEN PRESS {Q}")
				_dead[m] = dead
				# still mid-pounce but no longer counterable: it got you first
				var can: bool = m.is_counterable()
				if _counterable.get(m, false) and not can and _mango_states[m.state] == "LUNGE":
					_tip("TOO LATE! PRESS {Q} WHILE IT'S IN THE AIR")
				_counterable[m] = can
		"finale":
			for m in _mangos(station):
				if m.hp <= 0 and not _reached.has(m):
					_reached[m] = true
					_progress(m.global_position + Vector2(0, -16))


# at a goal flag. metadata "pass": getting to it or past it counts, at any speed and height (Morgan's call:
# MOVE clears even if you run straight past it, JUMP even if you jump right over it)
func _standing_at(g: Node2D) -> bool:
	var reach: float = g.get_meta("reach", 20.0)
	var d := player.global_position - g.global_position
	if g.get_meta("pass", false):
		return d.x >= -reach
	return player.is_on_floor() and absf(d.x) <= reach and absf(d.y) <= 6.0


func _mangos(station: Node) -> Array:
	return station.get_children().filter(func(n): return n.has_method("is_counterable"))


# every dummy hit lands here (tutorial_target.gd calls it through the "tutorial" group)
func target_hit(target: Node2D, move: String):
	if not _entered or not _stations[_index].is_ancestor_of(target):
		return
	var step: Dictionary = _steps[_index]
	var ok := false
	match step["id"]:
		"light":
			ok = move in LIGHT and not player.light_in_air
		"heavy":              # a held W (the charged smash) counts too
			ok = move in ["ATTACK_HEAVY_SMASH", "CHARGED_SMASH"]
		"charge":
			if move == "CHARGED_SMASH":      # one blast hits them all in the same frame
				if not target in _blast:
					_blast.append(target)
				_blast_frame = Engine.get_physics_frames()
				return
		"dash_q":
			ok = move == "DASH_ATTACK_LIGHT"
			if ok and target in _roll:
				return
			if ok:
				_roll.append(target)
		"dash_w", "air_w":                    # each dummy once: the slam can hit one twice on the way down
			ok = move in SLAMS and _slam_from_air == (step["id"] == "air_w")
			if ok and _reached.has(target):
				return
			if ok:
				_reached[target] = true
		"air_q":
			ok = move in LIGHT and player.light_in_air
		"flash":
			ok = move == "FLASH"              # its hits land just after the freeze (flash_finish.gd)
			if ok and _reached.has(target):
				return
			if ok:
				_reached[target] = true
	if ok:
		_last_target = target
		_progress(target.global_position + Vector2(0, -24))
	elif step.has("wrong"):
		_tip(step["wrong"])


# the charged smash: all the dummies in one blast, or the pips drain and you try again
func _resolve_blast():
	var where := []
	for d in _blast:
		where.append(d.global_position + Vector2(0, -24))
	_blast.clear()
	var goal: int = _steps[_index]["goal"]
	if where.size() >= goal:
		for p in where:
			_progress(p)
	else:
		for p in where:
			hud.add_progress(p)
		hud.fail("ALMOST! STAND ON THE SPOT AND HOLD {W} LONGER")


func _on_gate_smashed(i: int):
	if _entered and _index == i:
		var gate: Node2D = _stations[i].get_node("Gate")
		_progress(gate.global_position + Vector2(0, -56))


# the counter: player.gd adds a counter_chain.gd node next to the player; it frees itself when it's over
func _on_node_added(node: Node):
	if node.get_script() != CounterChain:
		return
	var first = node.first
	_counter_at = first.global_position if first else player.global_position
	_countering = true
	node.tree_exited.connect(_on_counter_done)


func _on_counter_done():
	if not is_inside_tree():
		return
	_countering = false
	if _entered and _steps[_index]["id"] == "counter":
		for m in _mangos(_stations[_index]):
			_dead[m] = m.hp <= 0
		_progress(_counter_at + Vector2(0, -20))


# the HUD's meter beside a held key: the real build-up while the player is doing it, else -1
func _meter(kind: String) -> float:
	if player == null:
		return -1.0
	match kind:
		"charge":
			if _names[player.state] in ["HEAVY_CHARGE", "CHARGED_SMASH"]:
				return player.charge
	return -1.0


# ---------- in the world ----------
func _process(_delta):
	_back.queue_redraw()
	_front.queue_redraw()


func _draw_back():
	var t := _now()
	for i in _stations.size():
		for g in _stations[i].get_children():
			if g is Marker2D and g.name.begins_with("Goal"):
				_draw_flag(g.global_position, i < _index or (i == _index and _reached.has(g)), t)
	if _entered:
		var spot = _stations[_index].get_node_or_null("Spot")
		if spot:
			_draw_spot(spot.global_position, t)
 

# arrows bob over whatever is still to do; the counter's mango gets a warning, then a Q to press
func _draw_front():
	if not _entered or _index >= _steps.size():
		return
	var t := _now()
	var teach_counter: bool = _steps[_index]["id"] == "counter"
	var spot = _stations[_index].get_node_or_null("Spot")
	if spot:              # where to stand is what matters here: point at that instead of the dummies
		_draw_stand_here(spot.global_position, t)
	for n in _stations[_index].get_children():
		if n is Marker2D and n.name.begins_with("Goal"):
			if not _reached.has(n):
				_draw_arrow(n.global_position + Vector2(6, -46), t)
		elif n.has_method("is_counterable"):
			if n.hp > 0:
				_draw_mango_cue(n, t, teach_counter)
		elif n.has_method("take_hit") and not n.hanging and not _reached.has(n) and not spot:
			_draw_arrow(n.global_position + Vector2(0, -56), t)


# a pole with a pennant flapping in the wind; it turns green once you've stood there
func _draw_flag(at: Vector2, done: bool, t: float):
	var base := at.round() + Vector2(6, 0)
	var top := base.y - 30.0
	_back.draw_rect(Rect2(base.x - 1, top, 3, 30), Pixel.INK)
	_back.draw_rect(Rect2(base.x, top, 1, 30), Pixel.OFF_WHITE)
	_back.draw_rect(Rect2(base.x - 2, top - 3, 5, 4), Pixel.INK)
	_back.draw_rect(Rect2(base.x - 1, top - 2, 3, 2), Pixel.MUSTARD)
	var cols := [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE] if done else [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD]
	for c in 10:
		var h := 7 - int(c * 0.65)
		var y := top + 1.0 + roundf(sin(t * 6.0 - c * 0.7) * c / 9.0 * 1.5) + floorf((7 - h) / 2.0)
		var x := base.x + 2.0 + c
		_back.draw_rect(Rect2(x, y - 1, 1 if c < 9 else 2, h + 2), Pixel.INK)
		_back.draw_rect(Rect2(x, y, 1, h), cols[0])
		_back.draw_rect(Rect2(x, y, 1, 1), cols[2])
		_back.draw_rect(Rect2(x, y + h - 1, 1, 1), cols[1])


func _on_spot(at: Vector2) -> bool:
	return player != null and player.is_on_floor() and absf(player.global_position.x - at.x) <= SPOT_REACH


# a glowing pad on the floor (green while you stand on it)
func _draw_spot(at: Vector2, t: float):
	var on := _on_spot(at)
	var pulse := 1.0 if on else 0.5 + 0.5 * sin(t * 5.0)
	var w := 30.0 + roundf(pulse * 4.0)
	var x := roundf(at.x - w / 2.0)
	var fill := Pixel.GREEN if on else Pixel.MUSTARD
	_back.draw_rect(Rect2(x - 1, at.y - 3, w + 2, 3), Color(Pixel.INK, 0.6))
	_back.draw_rect(Rect2(x, at.y - 2, w, 2), Color(fill, 0.6 + 0.4 * pulse))
	_back.draw_rect(Rect2(x + 4, at.y - 4, w - 8, 2), Color(Pixel.INK, 0.6))
	_back.draw_rect(Rect2(x + 5, at.y - 3, w - 10, 1), Color(Pixel.OFF_WHITE, 0.5 + 0.5 * pulse))


# a big arrow bobbing down at the spot, just over head height, with STAND HERE over it. Once you're on
# it, both go green and it tells you what to do next.
func _draw_stand_here(at: Vector2, t: float):
	var on := _on_spot(at)
	var bob := 0.0 if on else roundf(sin(t * 5.0) * 3.0)
	var tl := (at + Vector2(-4.0, -50.0 - BIG_ARROW.size() + bob)).round()
	var fill := Pixel.GREEN if on else Pixel.MUSTARD
	for outline in [true, false]:
		for row in BIG_ARROW.size():
			var line: String = BIG_ARROW[row]
			var first := line.find("#")
			for col in line.length():
				if line[col] != "#":
					continue
				var r := Rect2(tl + Vector2(col, row), Vector2(1, 1))
				if outline:
					_front.draw_rect(r.grow(1.0), Pixel.INK)
				else:
					_front.draw_rect(r, Pixel.OFF_WHITE if col == first else fill)
	var text := "NOW HOLD {W}" if on else "STAND HERE"
	var pos := (tl + Vector2(4.5 - Pixel.width(text, 1) / 2.0, -12.0)).round()
	var colors := [Pixel.GREEN, Pixel.GREEN_DARK, Pixel.OFF_WHITE] if on else [Pixel.OFF_WHITE, Pixel.PALE, Pixel.WHITE]
	Pixel.draw_cells(_front, Pixel.cells(text, pos, 1), colors)


func _draw_arrow(at: Vector2, t: float):
	var p := (at + Vector2(-3.0, sin(t * 5.0) * 2.0)).round()
	for outline in [true, false]:
		for row in ARROW.size():
			var line: String = ARROW[row]
			for col in line.length():
				if line[col] != "#":
					continue
				var r := Rect2(p + Vector2(col, row), Vector2(1, 1))
				if outline:
					_front.draw_rect(r.grow(1.0), Pixel.INK)
				else:
					_front.draw_rect(r, Pixel.OFF_WHITE if row == 0 else Pixel.MUSTARD)


func _draw_mango_cue(m: Node2D, t: float, teach: bool):
	var head := m.global_position + Vector2(0, -34)
	if teach and m.is_counterable():
		# it's lunging: NOW! over a Q key that pumps
		Pixel.draw_key(_front, (head + Vector2(-7, -10)).round(), 15, "Q", int(t * 12.0) % 2 == 0, true)
		var cs := Pixel.cells("NOW!", (head + Vector2(-Pixel.width("NOW!", 1) / 2.0, -22)).round(), 1)
		Pixel.draw_cells(_front, cs, [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD])
	elif teach and _mango_states[m.state] == "WINDUP":
		# the warning shake: a big ! shaking with it
		var cs := Pixel.cells("!", (head + Vector2(sin(t * 50.0) * 1.5 - 1.0, -14)).round(), 2)
		Pixel.draw_cells(_front, cs, [Pixel.ORANGE, Pixel.RUST, Pixel.MUSTARD])
	else:
		_draw_arrow(head + Vector2(0, -10), t)
