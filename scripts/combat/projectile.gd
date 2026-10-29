class_name CombatProjectile
extends Area2D

@export var speed: float = 380.0
var direction := Vector2.RIGHT
var damage: float = 10.0
var friendly: bool = true
var consumed: bool = false
var attacker: Node2D
var weapon: WeaponData
var pierce_remaining := 0
var bounce_remaining := 0
var bounce_range := 250.0
var explosion_radius := 0.0
var hit_ids: Dictionary = {}

func _ready() -> void:
	collision_layer = 4 if friendly else 8
	collision_mask = 2 if friendly else 1
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	queue_redraw()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if consumed or not body.has_method("receive_damage"):
		return
	if friendly and body.is_in_group("enemies") and bool(body.get("charmed")): return
	if hit_ids.has(body.get_instance_id()): return
	hit_ids[body.get_instance_id()] = true
	if friendly and is_instance_valid(attacker) and weapon != null and attacker.has_method("apply_weapon_hit"):
		attacker.apply_weapon_hit(body, weapon)
	else:
		body.receive_damage(damage)
	if explosion_radius > 0.0:
		if friendly:
			for unit in CombatTargeting.living_enemies(get_tree()):
				if unit != body and unit.global_position.distance_to(body.global_position) <= explosion_radius:
					unit.receive_damage(damage * 0.75)
		if is_instance_valid(attacker) and attacker.has_signal("combat_effect"):
			attacker.emit_signal("combat_effect", body.global_position, explosion_radius, "blast", "")
	if friendly and pierce_remaining > 0:
		pierce_remaining -= 1
		return
	if friendly and bounce_remaining > 0:
		var targets: Array[Node2D] = []
		for unit in CombatTargeting.living_enemies(get_tree()):
			if not hit_ids.has(unit.get_instance_id()): targets.append(unit)
		var target := CombatTargeting.nearest(global_position, bounce_range, targets)
		if target != null:
			direction = global_position.direction_to(target.global_position)
			rotation = direction.angle()
			bounce_remaining -= 1
			return
	consumed = true
	queue_free()

func _draw() -> void:
	var color := Color("#f8d898") if friendly else Color("#ee8491")
	draw_rect(Rect2(-7, -2, 12, 4), color)
	draw_rect(Rect2(1, -1, 5, 2), Color.WHITE)
