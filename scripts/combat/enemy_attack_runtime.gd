class_name EnemyAttackRuntime
extends Node

signal attack_performed(point: Vector2, radius: float, kind: String)
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
var data: AttackProfileData
var holder: Node2D
var loadout: ActorLoadout
var cooldown: Timer
var healing_visual_time: float = 0.0

func _ready() -> void:
	cooldown = Timer.new()
	cooldown.one_shot = true
	add_child(cooldown)

func tick(delta: float, allow_attack: bool = true) -> void:
	if data.kind == AttackProfileData.Kind.SPELL and data.effect == AttackProfileData.Effect.HEAL:
		_heal_allies(delta)
		return
	if not allow_attack:
		return
	var target: Node2D = holder.attack_target()
	if not is_instance_valid(target):
		return
	if holder.global_position.distance_to(target.global_position) > data.attack_range or not cooldown.is_stopped():
		return
	if data.kind != AttackProfileData.Kind.RANGED:
		var players: Array[Node2D] = []
		if holder.charmed:
			players = CombatTargeting.living_enemies(get_tree())
		else:
			for unit in get_tree().get_nodes_in_group("players"):
				if unit.health.is_alive(): players.append(unit)
		var selected := CombatTargeting.direct_targets(holder.global_position, data.attack_range, data.target_count, data.area_radius, players)
		if selected.is_empty(): return
		for unit in selected:
			unit.receive_damage(data.damage * holder.get_damage_multiplier())
			attack_performed.emit(unit.global_position, 13.0, "spell" if data.kind == AttackProfileData.Kind.SPELL else "enemy_strike")
		cooldown.start(data.attack_interval / loadout.melee_speed_multiplier() if data.kind == AttackProfileData.Kind.MELEE else data.attack_interval)
	else:
		var direction := holder.global_position.direction_to(target.global_position)
		for shot_direction in CombatTargeting.projectile_directions(direction, data.projectile_count, data.spread_degrees):
			var bullet: CombatProjectile = PROJECTILE.instantiate()
			bullet.friendly = holder.charmed
			bullet.direction = shot_direction
			bullet.damage = data.damage * holder.get_damage_multiplier()
			bullet.speed = data.projectile_speed
			bullet.position = holder.global_position + bullet.direction * 24.0
			get_tree().get_first_node_in_group("projectile_root").add_child(bullet)
		attack_performed.emit(holder.global_position, 8.0, "enemy_strike")
		cooldown.start(data.attack_interval)

func _heal_allies(delta: float) -> void:
	var allies: Array[Node2D] = []
	if holder.charmed:
		for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
			if ally != holder and (ally.is_in_group("players") or ally.charmed) and ally.health.is_alive() and ally.health.current < ally.health.maximum:
				allies.append(ally)
	else:
		allies = holder.wounded_allies()
	allies.sort_custom(func(a: Node2D, b: Node2D):
		return a.get_node("Health").current < b.get_node("Health").current)
	var affected: int = 0
	healing_visual_time -= delta
	for ally in allies:
		if holder.global_position.distance_to(ally.global_position) > data.attack_range:
			continue
		ally.get_node("Health").heal(data.healing_per_second * delta)
		if healing_visual_time <= 0.0:
			attack_performed.emit(ally.global_position, 14.0, "heal")
		affected += 1
		if affected >= data.target_count:
			break
	if affected > 0 and healing_visual_time <= 0.0:
		attack_performed.emit(holder.global_position, data.attack_range, "heal_range")
		healing_visual_time = 0.8
