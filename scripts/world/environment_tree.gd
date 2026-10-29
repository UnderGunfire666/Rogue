class_name EnvironmentTree
extends StaticBody2D

signal defeated(tree: EnvironmentTree)
var health: HealthComponent

func _ready() -> void:
	add_to_group("destructibles")
	add_to_group("environment_trees")
	collision_layer = 2
	collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12
	collision.shape = shape
	add_child(collision)
	health = HealthComponent.new()
	add_child(health)
	health.initialize(30)
	health.depleted.connect(_die)

func receive_damage(amount: float) -> void:
	health.take_damage(amount)

func _die() -> void:
	remove_from_group("destructibles")
	remove_from_group("environment_trees")
	defeated.emit(self)
	RunState.stats_changed.emit()
	queue_free()

func _draw() -> void:
	draw_rect(Rect2(-4, -10, 8, 18), Color("#806343"))
	draw_circle(Vector2(0, -14), 13, Color("#5b8d65"))
	draw_circle(Vector2(-5, -18), 5, Color("#84b879"))
