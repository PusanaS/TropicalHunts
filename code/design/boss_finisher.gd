extends Node2D
# The anime finisher. The boss spawns this when it is BROKEN and the player jumps up in front of it:
#   1. lock-on:  the world goes dark, the player hangs in the air in front of it, charging
#   2. flurry:   a hundred slashes (cut lines across the boss, afterimages, hit flashes), faster and faster.
#                It only goes while the player mashes Q / W: each press releases the next slashes. If they
#                stop, the player slowly falls; falling for FAIL_TIME cancels it and the boss is back at full health.
#   3. final cut: the player dashes through and lands behind it, back turned
#   4. silence:  a beat where nothing happens
#   5. split:    the boss falls apart along the cut lines, then bursts into juice
# It steers the player from outside for a few seconds (player.gd is untouched).
# PLACEHOLDER effects: the real flurry and landing pose are BOOM's to animate.
# Placed at the boss's feet, so local positions here are relative to the boss.

const EnemyKit := preload("res://code/design/enemy_kit.gd")

const HOVER := Vector2(64, -56)           # where the player hangs, from the boss's feet
const BODY_CENTER := Vector2(0, -40)
const LOCK_ON_TIME := 0.35
const SLASHES := 26
const HITS_PER_SLASH := 4                 # added to the combo counter per slash (26 x 4 = "a hundred slashes")
const SLASH_GAP := Vector2(0.09, 0.03)    # time between slashes: first, last (the fastest mashing can go)
const SLASHES_PER_PRESS := 2              # each Q or W press releases this many slashes
const MAX_QUEUED := 4                     # presses can bank this many slashes, so stopping stops it quickly
const SLOW_FALL := 60.0                   # not mashing: the player sinks, speeding up by this much per second
const FALL_POSE_AFTER := 0.15             # stopped this long: switch to the falling pose
const FAIL_TIME := 1.5                    # falling this long cancels the finisher: the boss is back at full health
const DASH_TIME := 0.1
const BREAK_HEIGHT := 80.0                # highest it can be (feet above the floor) and still be on screen
const BOSS_DROP_TIME := 0.2               # how long the last cut takes to knock it down to that height
const SILENCE := 0.7
const CUTS := 5                           # how many of the slashes actually split it into pieces
const LAND_DIST := 80.0
const OVERLAY_COLOR := Color(0.04, 0.02, 0.08, 0.0)
const OVERLAY_ALPHA := 0.75
const SLASH_COLOR := Color(1.0, 0.97, 0.88)
const Z := 50                             # the finisher draws over everything else
const PIECE_GRAVITY := 700.0
const FINAL_SOUND := preload("res://sounds/sword/sword_crash_01.wav")   # the boss falling apart at the end
const FINAL_SOUND_DB := 0.0
const FINAL_SOUND_SKIP := 0.03            # the crash swells in over 35ms; start partway in
const SLASH_SOUND := preload("res://sounds/sword/sword_hit_flesh_06.wav")   # every slash in the flurry
const SLASH_SOUND_DB := -6.0              # quieter, since they pile up on top of each other
const SLASH_SOUND_SKIP := 0.015           # the file starts quiet; start right as it hits

var boss: CharacterBody2D
var player: CharacterBody2D

var _psprite: AnimatedSprite2D
var _overlay: Polygon2D
var _lines: Array = []       # [point, direction] of each cut, relative to the boss
var _pieces: Array = []      # [Polygon2D, velocity, spin]
var _piece_time := -1.0
var _z_before := {}
var _mashing := false        # Q / W presses count (lock-on and flurry)
var _queued := 0             # slashes the presses have released but not swung yet
var _slash_sound := AudioStreamPlayer.new()


func _ready():
	_slash_sound.stream = SLASH_SOUND
	_slash_sound.volume_db = SLASH_SOUND_DB
	_slash_sound.max_polyphony = 4
	add_child(_slash_sound)
	_run()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# the player stopped mashing for too long: the finisher fails, the player drops, the boss shrugs it off
func _cancel():
	_mashing = false
	create_tween().tween_property(_overlay, "color:a", 0.0, 0.2)
	_lower()
	_psprite.speed_scale = 1.0
	_psprite.self_modulate = Color.WHITE
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	if player.has_method("_set_state"):
		player._set_state(player.get_script().State.JUMP_FALL)
	EnemyKit.protect_player(0.6)
	boss.finisher_failed()
	await _wait(0.3)
	queue_free()


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, true, false, true).timeout


func _run():
	_psprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var side := signf(player.global_position.x - boss.global_position.x)
	if side == 0.0:
		side = 1.0
	EnemyKit.protect_player(LOCK_ON_TIME + SLASHES * SLASH_GAP.x + SILENCE + 1.5)

	# 1. lock-on: time stops, the world goes dark
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.global_position = boss.global_position + Vector2(side * HOVER.x, HOVER.y)
	player.facing = int(-side)
	_psprite.flip_h = -side < 0.0
	_raise(player)
	_raise(boss)
	_overlay = Polygon2D.new()
	_overlay.polygon = PackedVector2Array([Vector2(-3000, -2000), Vector2(3000, -2000), Vector2(3000, 2000), Vector2(-3000, 2000)])
	_overlay.color = OVERLAY_COLOR
	_overlay.z_index = Z
	add_child(_overlay)
	create_tween().tween_property(_overlay, "color:a", OVERLAY_ALPHA, 0.15)
	_psprite.play("ATTACK_HEAVY_WINDUP")
	_psprite.self_modulate = Color(1.8, 1.7, 0.6)
	_shake(4.0, 0.2)
	_mashing = true              # presses during the lock-on count too
	await _wait(LOCK_ON_TIME)
	_psprite.self_modulate = Color.WHITE

	# 2. the flurry: only while the player mashes Q / W. Stop, and the player slowly falls;
	# falling for longer than FAIL_TIME cancels the finisher and the boss is back at full health.
	var hover := player.global_position
	var i := 0
	var fall_start := -1.0
	var fall_speed := 0.0
	var last := 0.0
	while i < SLASHES:
		if _queued <= 0:
			var now := _now()
			if fall_start < 0.0:
				fall_start = now
				last = now
				fall_speed = 0.0
				_psprite.pause()                # hold the slash pose for a moment...
			if now - fall_start >= FAIL_TIME:
				_cancel()
				return
			if now - fall_start >= FALL_POSE_AFTER:
				_psprite.speed_scale = 1.0
				_psprite.play("JUMP_FALL")      # ...then it's clear they've stopped: falling pose
			var dt := now - last
			last = now
			fall_speed += SLOW_FALL * dt
			player.global_position.y = minf(player.global_position.y + fall_speed * dt, _ground_below(player.global_position.x))
			EnemyKit.protect_player(0.3)
			await get_tree().process_frame
			continue
		if fall_start >= 0.0:                   # mashing again: back up to the slashing spot
			fall_start = -1.0
			create_tween().tween_property(player, "global_position", hover, 0.08)
		_queued -= 1
		_slash(i)
		i += 1
		await _wait(lerpf(SLASH_GAP.x, SLASH_GAP.y, float(i) / SLASHES))
	_mashing = false
	EnemyKit.protect_player(DASH_TIME + SILENCE + 1.5)

	# 3. final cut: dash through and land behind it, back turned
	get_tree().call_group("combo_hud", "finish")   # the combo counter stops here with the full total
	var dir := -side
	var land := _landing_distance(dir)
	if land < 48.0:
		dir = side                  # a wall right behind it: land back on the near side
		land = _landing_distance(dir)
	var from := player.global_position
	var land_x := boss.global_position.x + dir * land
	var to := Vector2(land_x, _ground_below(land_x))   # the boss may be up in the air: land on the floor
	_psprite.play("DASH_ATTACK_LIGHT")
	_psprite.speed_scale = 2.0
	_streak(to_local(from) + Vector2(0, -20), to_local(to) + Vector2(0, -20), 6.0, 0.3)
	create_tween().tween_property(player, "global_position", to, DASH_TIME)
	_flash_boss()
	# the last cut knocks the boss down, just low enough to be on screen when it falls apart
	var break_y := _ground_below(boss.global_position.x) - BREAK_HEIGHT
	if boss.global_position.y < break_y:
		var fall := create_tween()
		fall.tween_property(boss, "global_position:y", break_y, BOSS_DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fall.tween_callback(_shake.bind(8.0, 0.2))
	await _wait(DASH_TIME)
	player.facing = int(dir)
	_psprite.flip_h = dir < 0.0
	_psprite.speed_scale = 1.0
	_psprite.play("IDLE")

	# 4. silence
	await _wait(SILENCE)

	# 5. it falls apart
	_split()
	var crash := AudioStreamPlayer.new()
	crash.stream = FINAL_SOUND
	crash.volume_db = FINAL_SOUND_DB
	add_child(crash)
	crash.play(FINAL_SOUND_SKIP)
	boss.finisher_death()
	_shake(16.0, 0.45)
	create_tween().tween_property(_overlay, "color:a", 0.0, 0.3)
	_lower()
	player.set_physics_process(true)
	if player.has_method("_set_state"):
		player._set_state(player.get_script().State.IDLE)
	await _wait(2.0)
	queue_free()


# ---------- the flurry ----------
func _slash(i: int):
	# the player swings over and over: the two light attacks, fast, from a random frame
	_psprite.play("ATTACK_LIGHT_1" if i % 2 == 0 else "ATTACK_LIGHT_2")
	_psprite.speed_scale = 3.0
	_psprite.frame = randi() % _psprite.sprite_frames.get_frame_count(_psprite.animation)
	_ghost(Vector2(randf_range(-8, 8), randf_range(-6, 6)))
	# a cut line across the boss
	var p := BODY_CENTER + Vector2(randf_range(-16, 16), randf_range(-26, 22))
	var d := Vector2.from_angle(randf() * PI)
	_lines.append([p, d])
	_streak(p - d * 70.0, p + d * 70.0, randf_range(2.0, 4.0), 0.14)
	_sparks(p)
	if i % 2 == 0:
		_flash_boss()
	_shake(3.0, 0.06)
	_slash_sound.play(SLASH_SOUND_SKIP)
	boss.spray_juice(player.global_position.x, 0.6, true)     # every cut bursts out somewhere, any direction
	get_tree().call_group("combo_hud", "add_hits", HITS_PER_SLASH)


# a see-through copy of the player's current frame that fades: reads as "moving too fast to see"
func _ghost(offset: Vector2):
	var g := Sprite2D.new()
	g.texture = _psprite.sprite_frames.get_frame_texture(_psprite.animation, _psprite.frame)
	g.flip_h = _psprite.flip_h
	g.modulate = Color(0.8, 0.9, 1.0, 0.5)
	g.z_index = Z + 1
	add_child(g)
	g.global_position = _psprite.global_position + offset
	var t := g.create_tween()
	t.tween_property(g, "modulate:a", 0.0, 0.2)
	t.tween_callback(g.queue_free)


func _streak(a: Vector2, b: Vector2, width: float, fade: float):
	var line := Line2D.new()
	line.points = PackedVector2Array([a, b])
	line.width = width
	line.default_color = SLASH_COLOR
	line.z_index = Z + 2
	add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "width", 0.0, fade)
	t.tween_callback(line.queue_free)


func _sparks(at: Vector2):
	var s := CPUParticles2D.new()
	s.one_shot = true
	s.amount = 6
	s.lifetime = 0.25
	s.explosiveness = 1.0
	s.spread = 180.0
	s.initial_velocity_min = 60.0
	s.initial_velocity_max = 140.0
	s.gravity = Vector2.ZERO
	s.scale_amount_min = 2.0
	s.scale_amount_max = 2.0
	s.color = SLASH_COLOR
	s.position = at
	s.z_index = Z + 2
	s.finished.connect(s.queue_free)
	add_child(s)
	s.emitting = true


func _flash_boss():
	var spr: AnimatedSprite2D = boss.sprite
	spr.self_modulate = Color(4, 4, 4)
	create_tween().tween_property(spr, "self_modulate", Color.WHITE, 0.06)


func _shake(strength: float, seconds: float):
	if player.has_method("_shake"):
		player._shake(strength, seconds)


# how far behind the boss the player can land before a wall
func _landing_distance(dir: float) -> float:
	var from := boss.global_position + Vector2(0, -20)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(dir * (LAND_DIST + 20.0), 0), 1)
	var skip: Array[RID] = [player.get_rid(), boss.get_rid()]
	q.exclude = skip
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return LAND_DIST
	return absf(hit["position"].x - from.x) - 20.0


func _ground_below(x: float) -> float:
	var from := Vector2(x, boss.global_position.y - 20.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 600), 1)
	var skip: Array[RID] = [player.get_rid(), boss.get_rid()]
	q.exclude = skip
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return boss.global_position.y
	return float(hit["position"].y)


# ---------- draw order: the player and boss go above the dark overlay ----------
func _raise(node: CanvasItem):
	_z_before[node] = node.z_index
	node.z_index = Z + 1


func _lower():
	for node in _z_before:
		if is_instance_valid(node):
			node.z_index = _z_before[node]


# ---------- falling apart ----------
# Cuts the boss's current frame along some of the slash lines into Polygon2D pieces
# that show the same pixels, then lets them slide apart and fall.
func _split():
	global_position = boss.global_position    # the boss may have been knocked down: pieces start where it is
	var spr: AnimatedSprite2D = boss.sprite
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame) as AtlasTexture
	if tex == null:
		return
	var sheet: Texture2D = tex.atlas
	var region: Rect2 = tex.region
	var half := region.size / 2.0
	var origin: Vector2 = spr.position
	var polys: Array = [PackedVector2Array([Vector2(-40, -104), Vector2(40, -104), Vector2(40, 2), Vector2(-40, 2)])]
	var cuts := _lines.duplicate()
	cuts.shuffle()
	for k in mini(CUTS, cuts.size()):
		var next: Array = []
		for poly: PackedVector2Array in polys:
			for keep: float in [1.0, -1.0]:
				var part := _clip(poly, cuts[k][0], cuts[k][1], keep)
				if part.size() >= 3 and absf(_area(part)) > 12.0:
					next.append(part)
		polys = next
	for poly: PackedVector2Array in polys:
		var c := _centroid(poly)
		var local := PackedVector2Array()
		var uv := PackedVector2Array()
		for q in poly:
			local.append(q - c)
			# which pixel of the sheet is under this point (the sprite may be mirrored)
			var fx: float = q.x - origin.x
			if spr.flip_h:
				fx = -fx
			uv.append(region.position + Vector2(half.x + fx, half.y + q.y - origin.y))
		var piece := Polygon2D.new()
		piece.texture = sheet
		piece.polygon = local
		piece.uv = uv
		piece.position = c
		piece.z_index = Z + 1
		add_child(piece)
		var out := (c - BODY_CENTER).normalized()
		_pieces.append([piece, out * randf_range(60.0, 160.0) + Vector2(0, -randf_range(80.0, 220.0)), randf_range(-5.0, 5.0)])
	_piece_time = 0.0


func _process(delta):
	if _mashing and (Input.is_action_just_pressed("attack_light") or Input.is_action_just_pressed("attack_heavy")):
		_queued = mini(_queued + SLASHES_PER_PRESS, MAX_QUEUED)
	if _piece_time < 0.0:
		return
	_piece_time += delta
	# first they slip apart slowly along the cuts, then they fly
	var pace := 0.2 if _piece_time < 0.25 else 1.0
	for p in _pieces:
		var piece: Polygon2D = p[0]
		if _piece_time >= 0.25:
			p[1] += Vector2(0, PIECE_GRAVITY) * delta
		piece.position += p[1] * delta * pace
		piece.rotation += p[2] * delta * pace
		if _piece_time > 1.0:
			piece.modulate.a = maxf(0.0, 1.0 - (_piece_time - 1.0) / 0.8)


# keeps the part of a convex polygon on one side of the line through p along d
static func _clip(poly: PackedVector2Array, p: Vector2, d: Vector2, keep: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var da := keep * d.cross(a - p)
		var db := keep * d.cross(b - p)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s / 2.0


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	return c / poly.size()
