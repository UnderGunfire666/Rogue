extends Node2D

const EFFECT := preload("res://scenes/effects/combat_effect.tscn")

func present(point: Vector2, radius: float, kind: String, text: String = "") -> void:
	# Presentation listens to combat events; it never changes damage or AI.
	var effect := EFFECT.instantiate()
	effect.position = point
	effect.radius = radius
	effect.kind = kind
	effect.message = text
	add_child(effect)

func present_edge_warning(edge: int, point: Vector2, span: float, duration: float = 1.0, group_index: int = 0) -> Node2D:
	var effect := EFFECT.instantiate()
	effect.position = point
	effect.radius = maxf(24.0, span * 0.5)
	effect.kind = "edge_warning"
	effect.edge = edge
	effect.span = maxf(48.0, span)
	effect.lifetime = maxf(0.1, duration)
	effect.set_meta("group_index", group_index)
	add_child(effect)
	return effect
