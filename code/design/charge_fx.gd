extends Node2D
# Charged W effects.
#   While the player holds W (HEAVY_CHARGE): they flicker brighter and brighter, sparks gather in,
#   energy rings keep closing in at their feet, dust swirls up and the screen trembles more and more.
#   A white burst when it's fully charged.
#   On release (CHARGED_SMASH): a screen flash, a hit-freeze, a shockwave ring racing along the
#   ground, a dome of force, a dust cloud rolling out both ways and flying debris. All of it grows
#   with how long W was held.
# Drop this node into any level (like LiveReload). It only watches the player (player.gd's `charge`).
# PLACEHOLDER effects, in BOOM's palette.

const EnemyKit := preload("res://code/design/enemy_kit.gd")
const PUFF: Texture2D = preload("res://scene/design/art/dust_puff.png")     # 6 frames, 16x16
const SMALL: Texture2D = preload("res://scene/design/art/dust_small.png")   # 4 frames, 8x8

const BODY := Vector2(0, -20)                 # the player's middle, from their feet
const GLOW := Color(1.0, 0.92, 0.55)
const WHITE := Color(1.0, 0.98, 0.92)
const DEBRIS := [Color(0.49, 0.43, 0.43), Color(0.68, 0.64, 0.64), Color(0.93, 0.87, 0.86)]
const TREMBLE_EVERY := 0.1
const SPARK_EVERY := 0.035
const GATHER_EVERY := 0.26                    # an energy ring closing in
const SWIRL_EVERY := 0.12
const CLOUD_SCALE := 2                        # the release dust cloud uses the puff at 2x (whole pixels)

var player: CharacterBody2D = null
var _sprite: AnimatedSprite2D = null
var _names: Array = []
var _last := ""
var _t_tremble := 0.0
var _t_spark := 0.0
var _t_gather := 0.0
var _t_swirl := 0.0
var _was_full := false
var _rings: Array = []    # each: {"pos", "age", "delay", "time", "from", "to", "w0", "w1", "color", "top", "fade_in"}
var _flash: ColorRect


func _ready():
	z_index = 3
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)


func _process(delta: float):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if player == null:
			return
		_sprite = player.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_names = player.get_script().State.keys()
	var s: String = _names[player.state]
	var charge: float = player.charge
	if s == "HEAVY_CHARGE":
		_charging(delta, charge)
	elif _last == "HEAVY_CHARGE":
		_sprite.self_modulate = Color.WHITE      # stop the glow
	if s == "CHARGED_SMASH" and _last != "CHARGED_SMASH":
		_release(charge)
	_last = s
	_age_rings(delta)


# ---------- while charging ----------
func _charging(delta: float, charge: float):
	var feet := player.global_position
	var center := feet + BODY
	# flicker, brighter and brighter
	var bright := 1.0 + 0.9 * charge
	var on := int(Time.get_ticks_msec() / 50.0) % 2 == 0
	_sprite.self_modulate = Color(bright, bright * 0.95, 0.8) if on else Color.WHITE
	_t_spark -= delta
	if _t_spark <= 0.0:
		_t_spark = SPARK_EVERY * (1.5 - charge)
		_spark_in(center)
	_t_gather -= delta
	if _t_gather <= 0.0:
		_t_gather = GATHER_EVERY * (1.2 - 0.5 * charge)
		_add_ring(feet, Vector2(36, 8), Vector2(6, 2), 1.0, 2.0, GLOW, 0.25, false, true)
	_t_swirl -= delta
	if _t_swirl <= 0.0:
		_t_swirl = SWIRL_EVERY
		for side: float in [-1.0, 1.0]:
			_dust(SMALL, 4, 8.0, feet + Vector2(side * 6.0, 0), Vector2(side * 30.0, -30.0 * charge - 10.0), 0.3, 0.0, 1)
	_t_tremble -= delta
	if _t_tremble <= 0.0:
		_t_tremble = TREMBLE_EVERY
		_shake(1.0 + 2.5 * charge, 0.12)
	if charge >= 1.0 and not _was_full:
		# fully charged: a white burst so the player knows it's ready
		_was_full = true
		_add_ring(center, Vector2(4, 4), Vector2(26, 26), 3.0, 1.0, WHITE, 0.2, false, false)
		for i in 8:
			_spark_out(center)
	elif charge < 1.0:
		_was_full = false


# a spark appears around the player and flies in to them
func _spark_in(center: Vector2):
	var p := _square(2.0, GLOW)
	p.global_position = (center + Vector2.from_angle(randf() * TAU) * randf_range(28.0, 42.0)).round()
	var t := p.create_tween()
	t.tween_property(p, "global_position", center.round(), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(p.queue_free)


func _spark_out(center: Vector2):
	var p := _square(2.0, WHITE)
	p.global_position = center.round()
	var t := p.create_tween()
	t.tween_property(p, "global_position", (center + Vector2.from_angle(randf() * TAU) * 30.0).round(), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(p, "modulate:a", 0.0, 0.2)
	t.tween_callback(p.queue_free)


func _square(size: float, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size, 0), Vector2(size, size), Vector2(0, size)])
	p.color = color
	add_child(p)
	return p


# ---------- the release ----------
func _release(charge: float):
	var feet := player.global_position
	var radius: Vector2 = player.get_script().CHARGE_RADIUS
	var reach := lerpf(radius.x, radius.y, charge)
	_sprite.self_modulate = Color.WHITE
	# screen flash and a hit-freeze
	_flash.color = Color(1, 1, 1, 0.35 + 0.35 * charge)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.18)
	EnemyKit.hitstop(get_tree(), 0.06 + 0.08 * charge)
	# shockwave: two rings racing along the ground and a dome of force rising from the player
	_add_ring(feet, Vector2(8, 2), Vector2(reach * 1.15, reach * 0.16), 5.0, 1.0, WHITE, 0.45, false, false)
	_add_ring(feet, Vector2(8, 2), Vector2(reach * 0.9, reach * 0.12), 3.0, 1.0, GLOW, 0.4, false, false, 0.08)
	_add_ring(feet, Vector2(6, 6), Vector2(reach * 0.7, reach * 0.55), 4.0, 1.0, WHITE, 0.35, true, false)
	# a dust cloud rolling out both ways, and some rising up (in water: a wave instead, living_background.gd)
	if not _in_water(feet):
		var rolls := int(4 + 6 * charge)
		for side: float in [-1.0, 1.0]:
			for i in rolls:
				var vel := Vector2(side * (80.0 + i * 26.0) * (0.5 + 0.5 * charge), -randf_range(0.0, 20.0))
				_dust(PUFF, 6, 16.0, feet + Vector2(side * (6.0 + i * 6.0), 0), vel, 0.45, i * 0.025, CLOUD_SCALE, side < 0.0)
		for i in int(2 + 4 * charge):
			_dust(PUFF, 6, 16.0, feet + Vector2(randf_range(-20.0, 20.0), -4.0),
				Vector2(randf_range(-30.0, 30.0), -60.0 - 40.0 * charge), 0.5, 0.05, CLOUD_SCALE, randf() < 0.5)
	_debris(feet, int(12 + 20 * charge))


func _in_water(feet: Vector2) -> bool:
	var bg := get_tree().get_first_node_in_group("living_background")
	return bg != null and bg.in_water(feet)


func _debris(at: Vector2, amount: int):
	for color: Color in DEBRIS:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.amount = maxi(int(float(amount) / DEBRIS.size()), 1)
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.direction = Vector2.UP
		p.spread = 75.0
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 320.0
		p.gravity = Vector2(0, 700)
		p.scale_amount_min = 2.0
		p.scale_amount_max = 3.0
		p.color = color
		add_child(p)
		p.global_position = at + Vector2(0, -4)
		p.finished.connect(p.queue_free)
		p.emitting = true


# one dust sprite: its frames play through while it drifts, then it's gone (bottom sits at `pos`)
func _dust(tex: Texture2D, frames: int, height: float, pos: Vector2, vel: Vector2, time: float, delay: float, scale_by: int, flip := false):
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = frames
	s.flip_h = flip
	s.scale = Vector2(scale_by, scale_by)
	s.offset = Vector2(0, -height / 2.0)
	add_child(s)
	s.global_position = pos.round()
	var t := s.create_tween()
	if delay > 0.0:
		s.visible = false
		t.tween_interval(delay)
		t.tween_callback(s.show)
	t.tween_property(s, "frame", frames - 1, time).from(0)
	t.parallel().tween_property(s, "global_position", (pos + vel * time).round(), time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(s.queue_free)


# ---------- rings (energy gathering, the full-charge burst, the shockwave) ----------
func _add_ring(pos: Vector2, from: Vector2, to: Vector2, w0: float, w1: float, color: Color, time: float, top: bool, fade_in: bool, delay := 0.0):
	_rings.append({"pos": pos, "age": 0.0, "delay": delay, "time": time, "from": from, "to": to,
		"w0": w0, "w1": w1, "color": color, "top": top, "fade_in": fade_in})


func _age_rings(delta: float):
	var alive: Array = []
	for r: Dictionary in _rings:
		r["age"] = float(r["age"]) + delta
		if float(r["age"]) < float(r["delay"]) + float(r["time"]):
			alive.append(r)
	_rings = alive
	queue_redraw()


func _draw():
	for r: Dictionary in _rings:
		var age: float = r["age"]
		var delay: float = r["delay"]
		if age < delay:
			continue
		var t := clampf((age - delay) / float(r["time"]), 0.0, 1.0)
		var grow := 1.0 - (1.0 - t) * (1.0 - t)          # fast, then slowing
		var from: Vector2 = r["from"]
		var to: Vector2 = r["to"]
		var size := from.lerp(to, grow)
		var c := to_local(r["pos"])
		var top: bool = r["top"]
		var pts := PackedVector2Array()
		var n := 32
		for i in n + 1:
			var a := lerpf(PI, TAU, i / float(n)) if top else TAU * i / float(n)
			pts.append((c + Vector2(cos(a) * size.x, sin(a) * size.y)).round())
		var alpha := t if bool(r["fade_in"]) else 1.0 - t
		var color: Color = r["color"]
		draw_polyline(pts, Color(color, alpha), lerpf(float(r["w0"]), float(r["w1"]), t))


func _shake(strength: float, seconds: float):
	if player.has_method("_shake"):
		player._shake(strength, seconds)
