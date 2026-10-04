extends Node2D
# A vent in the floor that blows on a rhythm. Origin on the floor's top, at the vent's middle.
#   kind "blowhole"  (Level 2) sea spray bursting up through the rocks: when it blows it throws you high
#                    into the air, a jump pad you have to time
#   kind "lava"      (Level 3) a column of lava: touching it knocks you back with a red flash. The
#                    Thunderclap flash's dash keeps you safe for a moment, so flashing through an enemy
#                    beside it gets you past
# Its rhythm: it rumbles (the warning) for WARN, blows for BLOW, then rests for the rest of `period`.
# `offset` shifts the rhythm, so a row of them can take turns.
# PLACEHOLDER look, drawn in code.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const SPLASH := preload("res://sounds/WAVE_SOUND_universfield-water-splash-199583.mp3")
const SPLASH_DB := -8.0
const SPLASH_SKIP := 0.17         # the file starts with near-silence
const HEAR_RANGE := 320.0         # only blows you can see make a sound

@export var kind := "lava"
@export var period := 2.8
@export var offset := 0.0
@export var height := 150.0
@export var launch_speed := 760.0 # blowhole: how hard it throws you up (760 is about 290px)
@export var always_on := false    # a curtain of fire that never stops (Level 3's fire wall, under a ceiling)

const WARN := 0.6
const BLOW := 0.9
const HALF_W := 9.0               # the column's half width
const LOOKS := {
	"blowhole": {"core": Color("ecf4f2"), "edge": Color("8fc5d4"), "deep": Color("3894b1"), "rock": Color("4a3a46"), "rock_top": Color("6e5866")},
	"lava": {"core": Color("ffe27a"), "edge": Color("ff8a2a"), "deep": Color("c0391b"), "rock": Color("2a2430"), "rock_top": Color("4a4250")},
}

var player: CharacterBody2D = null
var _t := 0.0
var _blowing := false
var _thrown := false              # (blowhole) already threw the player this time
var _drops := []                  # [pos (local), vel, life]
var _sound := AudioStreamPlayer.new()


func _ready():
	z_index = 1
	_sound.stream = SPLASH
	_sound.volume_db = SPLASH_DB
	_sound.pitch_scale = 1.0 if kind == "blowhole" else 0.55    # lava: a thick, low blorp
	add_child(_sound)


func _phase() -> float:
	return fmod(_t + offset + period * 10.0, period)


func _warning() -> bool:
	var p := _phase()
	return p >= period - WARN - BLOW and p < period - BLOW


# 0..1: how much of the column is up
func _column() -> float:
	if always_on:
		return 1.0
	var p := _phase() - (period - BLOW)
	if p < 0.0:
		return 0.0
	return clampf(p / 0.12, 0.0, 1.0) * clampf((BLOW - p) / 0.15, 0.0, 1.0)


func _physics_process(delta: float):
	_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var col := _column()
	var blowing := col > 0.0
	if blowing and not _blowing:
		_thrown = false
		if not always_on and player and player.global_position.distance_to(global_position) < HEAR_RANGE:
			_sound.play(SPLASH_SKIP)
	_blowing = blowing
	# while time is stopped (the counter, the flash) nothing burns or throws: the counter can carry you
	# right past a fire wall
	if blowing and player and Engine.time_scale > 0.0:
		var r := Rect2(global_position + Vector2(-HALF_W, -height * col), Vector2(HALF_W * 2.0, height * col))
		var body := Rect2(player.global_position + Vector2(-10, -36), Vector2(20, 36))
		if r.intersects(body):
			if kind == "blowhole":
				if not _thrown:
					_thrown = true
					player.launch(Vector2(player.velocity.x * 0.5, -launch_speed), 0.12)
			else:
				EnemyKit.hurt_player(player, r, global_position.x)
	# spray or lava droplets: a few while it rumbles, lots while it blows
	var rate := 40.0 if blowing else (10.0 if _warning() else 0.0)
	if randf() < rate * delta:
		var top := -height * col if blowing else -2.0
		_drops.append([Vector2(randf_range(-HALF_W, HALF_W), top), Vector2(randf_range(-70, 70), randf_range(-160, -60)), randf_range(0.4, 0.8)])
	for d in _drops:
		d[0] += d[1] * delta
		d[1].y += 600.0 * delta
		d[2] -= delta
	_drops = _drops.filter(func(d): return d[2] > 0.0 and d[0].y < 2.0)
	queue_redraw()


func _draw():
	var c: Dictionary = LOOKS.get(kind, LOOKS["lava"])
	var col := _column()
	# the column
	if col > 0.0:
		var h := roundf(height * col)
		if kind == "lava":            # a soft glow around it
			draw_rect(Rect2(-HALF_W - 4, -h - 4, HALF_W * 2 + 8, h + 4), Color(c["edge"], 0.25))
		var y := -h
		while y < 0.0:
			var wob := roundf(sin(_t * 18.0 + y * 0.15) * 1.5)
			var w := HALF_W + wob
			draw_rect(Rect2(-w, y, w * 2.0, 3), c["edge"])
			draw_rect(Rect2(-w + 3, y, w * 2.0 - 6, 3), c["core"])
			if kind == "lava" and int(y + _t * 60.0) % 17 == 0:
				draw_rect(Rect2(-w + 2, y, 2, 2), c["deep"])      # crust bits rising
			y += 3.0
		# a frothy crown on top
		for i in 6:
			var a := _t * 10.0 + i * 1.3
			draw_rect(Rect2(roundf(cos(a) * (HALF_W + 3)), -h - 3 + roundf(sin(a * 1.7) * 2.0), 3, 3), c["core"])
	elif _warning():                  # rumbling: the vent glows / bubbles up
		var k := fmod(_t * 8.0, 1.0)
		draw_rect(Rect2(-HALF_W + 2, -3 - roundf(k * 3.0), HALF_W * 2 - 4, 3), c["edge"])
		draw_rect(Rect2(-3, -5 - roundf(k * 4.0), 6, 2), c["core"])
	# the vent: a ring of rocks
	for i in 5:
		var x := -HALF_W - 7 + i * 6
		var h := 4 + (i * 2) % 3
		draw_rect(Rect2(x, -h, 6 if i % 2 == 0 else 5, h), c["rock"])
		draw_rect(Rect2(x, -h, 6 if i % 2 == 0 else 5, 1), c["rock_top"])
	draw_rect(Rect2(-HALF_W + 2, -2, HALF_W * 2 - 4, 2), c["deep"])
	for d in _drops:
		var p: Vector2 = d[0]
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(c["core"] if randf() < 0.5 else c["edge"], clampf(float(d[2]) * 4.0, 0.0, 1.0)))
