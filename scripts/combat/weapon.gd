class_name WeaponInstance
extends Node2D

signal attack_performed(point: Vector2, radius: float, kind: String)
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
@export var data: WeaponData
var holder: Node2D
var loadout: ActorLoadout
var melee: MeleeTrajectory
@onready var cooldown: Timer = $Cooldown
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	if loadout == null:
		loadout = holder.get_combat_loadout()
	sprite.texture = data.icon
	melee = MeleeTrajectory.new()
	add_child(melee)
	melee.target_hit.connect(func(target: Node2D):
		holder.apply_weapon_hit(target, data)
		attack_performed.emit(target.global_position, 12.0, "slash"))
	melee.motion_updated.connect(func(offset: Vector2, angle: float):
		var origin := holder.global_position - global_position if is_instance_valid(holder) else Vector2.ZERO
		sprite.position = origin + offset
		sprite.rotation = angle)
	melee.motion_finished.connect(func():
		sprite.position = Vector2.ZERO
		sprite.rotation = 0.0)

func _physics_process(_delta: float) -> void:
	if RunState.player_moving and not RunState.combat_rules().can_attack_while_moving: return
	if cooldown.is_stopped() and not melee.active:
		if data.kind == WeaponData.Kind.RANGED:
			var target := CombatTargeting.nearest(holder.global_position, RunState.effective_weapon_range(data), CombatTargeting.attackable_targets(get_tree()))
			if target != null: try_fire(target.global_position)
		else: _try_direct_attack()

func _try_direct_attack() -> void:
	var units := CombatTargeting.attackable_targets(get_tree())
	if data.kind == WeaponData.Kind.MELEE:
		var center_pos := holder.global_position if is_instance_valid(holder) else global_position
		var target := CombatTargeting.nearest(center_pos, RunState.effective_weapon_range(data), units)
		if target == null or melee.active or not cooldown.is_stopped(): return
		var interval := RunState.weapon_attack_interval(data)
		melee.begin(data, target.global_position - center_pos, RunState.effective_weapon_range(data), interval, target)
		cooldown.start(interval)
		return
	var selected := CombatTargeting.direct_targets(holder.global_position, RunState.effective_weapon_range(data), data.target_count, data.area_radius, units)
	if selected.is_empty():
		return
	var center := Vector2.ZERO
	for target in selected:
		center += target.global_position
		holder.apply_weapon_hit(target, data)
		if data.kind == WeaponData.Kind.SPELL:
			attack_performed.emit(target.global_position, 18.0, "spell")
	center /= selected.size()
	cooldown.start(RunState.weapon_attack_interval(data))
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", (center - global_position).angle() + 0.8, 0.06)
	tween.tween_property(sprite, "rotation", 0.0, 0.18)

func _damage() -> float:
	return RunState.weapon_base_damage(data)

func try_fire(aim: Vector2) -> bool:
	if data.kind != WeaponData.Kind.RANGED or not cooldown.is_stopped():
		return false
	# Range gates activation; projectiles themselves have no distance or lifetime limit.
	if CombatTargeting.nearest(holder.global_position, RunState.effective_weapon_range(data), CombatTargeting.attackable_targets(get_tree())) == null:
		return false
	var direction := (aim - holder.global_position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	for shot_direction in CombatTargeting.projectile_directions(direction, data.projectile_count, data.spread_degrees):
		var bullet: CombatProjectile = PROJECTILE.instantiate()
		bullet.direction = shot_direction
		bullet.damage = _damage()
		bullet.speed = data.projectile_speed
		bullet.friendly = true
		bullet.weapon = data
		bullet.attacker = holder
		bullet.pierce_remaining = data.pierce_count
		bullet.bounce_remaining = data.bounce_count
		bullet.bounce_range = data.bounce_range
		bullet.position = holder.global_position + shot_direction * 24.0
		get_tree().get_first_node_in_group("projectile_root").add_child(bullet)
	cooldown.start(RunState.weapon_attack_interval(data))
	sprite.rotation = direction.angle()
	sprite.flip_v = direction.x < 0.0
	attack_performed.emit(holder.global_position + direction * 24.0, 6.0, "muzzle")
	return true
