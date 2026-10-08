extends Node2D
# "NO DAMAGE" (Morgan's call, 2026-10-08): pops up right above an enemy when a hit bounces off it (Q on the snake
# fruit, the watermelon shark or the Pineapple's armour), because players kept spamming Q without realising it
# did nothing. It punches in, rises a little and fades out in LIFE (real seconds, so hit-freezes and slow motion
# don't hold it up). Spamming the same enemy restarts its pop instead of stacking a pile of them.
# In BOOM's pixel style (pixel_font.gd), grey so it doesn't read as a reward like the juicy "+1"s.
# Use: NoDamagePop.show_on(enemy, world point just above where it was hit). An optional third argument swaps the
# words (the watermelon shark says IMMUNE IN WATER while it swims).

const Pixel := preload("res://code/design/pixel_font.gd")
const TEXT := "NO DAMAGE"
const LIFE := 0.6
const RISE := 10.0                    # it floats up this far
const PUNCH := 0.06                   # drawn double size this long first
const COLORS := [Pixel.PALE, Color(0.52, 0.47, 0.47), Pixel.OFF_WHITE]   # middle rows, bottom rows, top row

var _at := Vector2.ZERO
var _text := TEXT
var _born := 0.0


static func show_on(enemy: Node, at: Vector2, text := TEXT):
	if enemy == null or not enemy.is_inside_tree():
		return
	var pop: Node2D = null
	if enemy.has_meta("no_damage_pop"):
		var old = enemy.get_meta("no_damage_pop")
		if is_instance_valid(old):
			pop = old
	if pop == null:
		var scene := enemy.get_tree().current_scene
		if scene == null:
			return
		pop = load("res://code/design/no_damage_pop.gd").new()
		scene.add_child(pop)
		enemy.set_meta("no_damage_pop", pop)
	pop.restart(at, text)


func _ready():
	z_as_relative = false
	z_index = 60                      # over everything in the world


func restart(at: Vector2, text := TEXT):
	_at = at
	_text = text
	_born = _now()
	global_position = at
	queue_redraw()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta):
	var age := _now() - _born
	if age >= LIFE:
		queue_free()
		return
	var k := age / LIFE
	global_position = (_at + Vector2(0, -RISE * (1.0 - (1.0 - k) * (1.0 - k)))).round()
	queue_redraw()


func _draw():
	var age := _now() - _born
	var s := 2 if age < PUNCH else 1
	var a := 1.0 - clampf((age / LIFE - 0.6) / 0.4, 0.0, 1.0)
	var w := Pixel.width(_text, s)
	Pixel.draw_cells(self, Pixel.cells(_text, Vector2(-roundf(w / 2.0), -7.0 * s), s), COLORS, a)
