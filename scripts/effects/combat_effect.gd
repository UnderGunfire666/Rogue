extends Node2D

var kind: String = "slash"
var radius: float = 24.0
var message: String = ""
var edge: int = 0
var span: float = 120.0
var age: float = 0.0
var lifetime: float = 0.35
var color := Color("#f4d49b")

func _ready() -> void:
	if kind == "edge_warning":
		color = Color("#ff2b2b")
		if is_equal_approx(lifetime, 0.35):
			lifetime = 1.0
	elif kind.begins_with("heal"):
		color = Color("#9cdb9b")
	elif kind == "spell":
		color = Color("#bca5f8")
	elif kind == "enemy_strike" or kind == "damage":
		color = Color("#efb0a1")
	if kind in ["damage", "critical", "dodge", "loot"] and not message.is_empty():
		var label := Label.new()
		label.text = message
		label.position = Vector2(-12, -22)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_shadow_color", Color("#111b29"))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.add_theme_font_size_override("font_size", 15)
		add_child(label)
		lifetime = 0.6

func _process(delta: float) -> void:
	age += delta
	if kind == "edge_warning":
		var pulse := 0.5 + 0.5 * cos(age * TAU * 5.0)
		var fade_out := clampf((lifetime - age) / 0.12, 0.0, 1.0)
		modulate.a = lerpf(0.55, 1.0, pulse) * fade_out
	else:
		modulate.a = 1.0 - age / lifetime
	if kind in ["damage", "critical", "dodge", "loot"]:
		position.y -= delta * 26.0
	queue_redraw()
	if age >= lifetime:
		queue_free()

func _draw() -> void:
	if kind in ["damage", "critical", "dodge", "loot"]:
		return
	if kind == "edge_warning":
		_draw_edge_warning()
		return
	var fraction := age / lifetime
	var size := maxf(4.0, radius) * (0.7 + fraction * 0.3)
	var fill := color
	fill.a = 0.13
	if kind == "blast":
		draw_circle(Vector2.ZERO, size, fill)
		draw_arc(Vector2.ZERO, size, 0, TAU, 40, color, 3.0)
		for i in 10:
			var direction := Vector2.RIGHT.rotated(float(i) * TAU / 10.0)
			draw_line(direction * size * 0.5, direction * size, color, 2)
	elif kind == "slash":
		draw_circle(Vector2.ZERO, size, fill)
		draw_arc(Vector2.ZERO, size, -2.5, 2.2, 24, color, 4.0)
	elif kind == "spell":
		draw_circle(Vector2.ZERO, size, fill)
		draw_arc(Vector2.ZERO, size, 0, TAU, 32, color, 2.0)
		draw_line(Vector2(-size * 0.5, 0), Vector2(size * 0.5, 0), color, 2)
	elif kind == "heal_range":
		draw_arc(Vector2.ZERO, size, 0, TAU, 40, Color(color, 0.25), 1.0)
	elif kind == "heal":
		draw_line(Vector2(-5, 0), Vector2(5, 0), color, 3)
		draw_line(Vector2(0, -5), Vector2(0, 5), color, 3)
	else:
		draw_line(Vector2(-size, -size), Vector2(size, size), color, 3)
		draw_line(Vector2(-size, size), Vector2(size, -size), color, 2)

func _draw_edge_warning() -> void:
	var half := maxf(48.0, span * 0.5)
	var thickness := 22.0
	var aura_depth := 38.0
	var is_vertical := edge in [SpawnLocationData.Edge.LEFT, SpawnLocationData.Edge.RIGHT]
	var inward := Vector2.RIGHT
	match edge:
		SpawnLocationData.Edge.LEFT: inward = Vector2.RIGHT
		SpawnLocationData.Edge.RIGHT: inward = Vector2.LEFT
		SpawnLocationData.Edge.TOP: inward = Vector2.DOWN
		_: inward = Vector2.UP
	var tangent := Vector2(-inward.y, inward.x)
	var aura_rect: Rect2
	var bar_rect: Rect2
	if is_vertical:
		var x_start := -thickness * 0.5 if inward.x > 0.0 else -aura_depth + thickness * 0.5
		aura_rect = Rect2(x_start, -half - 6.0, aura_depth, (half + 6.0) * 2.0)
		bar_rect = Rect2(-thickness * 0.5, -half, thickness, half * 2.0)
	else:
		var y_start := -thickness * 0.5 if inward.y > 0.0 else -aura_depth + thickness * 0.5
		aura_rect = Rect2(-half - 6.0, y_start, (half + 6.0) * 2.0, aura_depth)
		bar_rect = Rect2(-half, -thickness * 0.5, half * 2.0, thickness)
	var outer_glow := Color(1.0, 0.08, 0.08, 0.28)
	var inner_fill := Color(1.0, 0.15, 0.15, 0.62)
	var core := Color(1.0, 0.28, 0.28, 0.98)
	var highlight := Color(1.0, 0.82, 0.82, 0.95)
	draw_rect(aura_rect, outer_glow, true)
	draw_rect(bar_rect, inner_fill, true)
	draw_rect(bar_rect, core, false, 3.0)
	# Animated inward-pushing double chevrons along the batch warning zone
	var shift := fmod(age * 36.0, 12.0)
	for offset_factor in [-0.62, 0.0, 0.62]:
		var base := tangent * (half * float(offset_factor)) + inward * shift
		var tip := base + inward * 14.0
		var wing_a := base - inward * 3.0 + tangent * 9.0
		var wing_b := base - inward * 3.0 - tangent * 9.0
		draw_line(wing_a, tip, highlight, 3.0)
		draw_line(wing_b, tip, highlight, 3.0)
		var tip2 := tip + inward * 8.0
		draw_line(wing_a + inward * 8.0, tip2, core, 2.5)
		draw_line(wing_b + inward * 8.0, tip2, core, 2.5)
	# Central warning diamond beacon
	var diamond := PackedVector2Array([
		inward * 10.0,
		tangent * 10.0,
		-inward * 10.0,
		-tangent * 10.0,
		inward * 10.0
	])
	draw_colored_polygon(diamond.slice(0, 4), Color(1.0, 0.12, 0.12, 0.92))
	draw_polyline(diamond, highlight, 2.2)
