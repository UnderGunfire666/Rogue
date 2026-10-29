class_name PlayerActor
extends CharacterBody2D

signal died
signal combat_effect(position: Vector2, radius: float, kind: String, text: String)
@onready var health: HealthComponent = $Health
@onready var controls: LocalPlayerInput = $LocalInput
@onready var visual: ActorVisual = $Visual
@onready var inventory: WeaponInventory = $WeaponInventory
@onready var skill: SkillController = $Skill
@onready var regen_timer: Timer = $HPRegenTimer
@onready var life_steal_timer: Timer = $LifeStealTimer
var movement_bounds := Rect2(25, 77, 910, 410)
var invulnerability: float = 0.0

func _ready() -> void:
	add_to_group("players")
	skill.sync_loadout(RunState.loadout)
	health.initialize(RunState.effective_max_health(), RunState.health)
	regen_timer.timeout.connect(func(): health.heal(1.0))
	_update_regen_timer()
	health.changed.connect(_health_changed)
	health.damaged.connect(func(amount: float):
		visual.flash()
		combat_effect.emit(global_position, 0.0, "damage", str(int(ceil(amount))))
		RunState.trigger_character_event(CharacterEventEffect.Trigger.DAMAGED))
	health.healed.connect(func(_amount: float): RunState.trigger_character_event(CharacterEventEffect.Trigger.HEALED))
	var event_timer := Timer.new()
	event_timer.wait_time = 1.0
	event_timer.timeout.connect(func(): RunState.trigger_character_event(CharacterEventEffect.Trigger.COMBAT_SECOND))
	add_child(event_timer)
	event_timer.start()
	health.depleted.connect(func(): died.emit())
	controls.fire_requested.connect(_fire)
	controls.skill_requested.connect(skill.toggle_targeting)
	controls.character_skill_requested.connect(skill.trigger_character_skill)
	controls.cancel_skill_requested.connect(skill.cancel_targeting)
	controls.cancel_or_pause_requested.connect(func():
		if skill.targeting:
			skill.cancel_targeting()
		else:
			get_tree().call_group("arena_controller", "toggle_pause"))
	inventory.attack_performed.connect(func(point: Vector2, radius: float, kind: String):
		combat_effect.emit(point, radius, kind, ""))
	skill.cast_performed.connect(func(point: Vector2, radius: float):
		combat_effect.emit(point, radius, "blast", ""))
	RunState.stats_changed.connect(_sync_stats)

func _physics_process(delta: float) -> void:
	invulnerability = maxf(0.0, invulnerability - delta)
	if not health.is_alive():
		return
	var movement := controls.movement()
	RunState.set_player_moving(not movement.is_zero_approx())
	velocity = movement * RunState.movement_speed()
	var before := global_position
	move_and_slide()
	position = position.clamp(movement_bounds.position, movement_bounds.end)
	RunState.register_movement(before.distance_to(global_position))
	visual.update_motion(velocity)
	health.heal(RunState.regeneration() * delta)

func _fire() -> void:
	if not health.is_alive():
		return
	if skill.targeting:
		skill.try_cast()

func receive_damage(amount: float) -> void:
	if invulnerability > 0.0 or not health.is_alive():
		return
	if RunState.rng.randf() < RunState.dodge_chance():
		combat_effect.emit(global_position, 0.0, "dodge", "闪避")
		RunState.trigger_character_event(CharacterEventEffect.Trigger.DODGED)
		return
	invulnerability = 0.55
	health.take_damage(health.current if RunState.combat_rules().one_hit_death else maxf(1.0, roundf(roundf(amount) * RunState.armor_damage_multiplier())))

func get_damage_multiplier() -> float:
	return maxf(0.0, 1.0 + RunState.stat_value("damage") / 100.0)

func apply_weapon_hit(target: Node2D, weapon: WeaponData, explode: bool = true) -> void:
	if not is_instance_valid(target) or not target.health.is_alive(): return
	var damage := RunState.weapon_base_damage(weapon)
	damage = RunState.damage_against(target, damage)
	var crit := RunState.rng.randf() < clampf((weapon.base_crit_chance + RunState.stat_value("crit_chance") + RunState.weapon_bonus(weapon, "crit_chance")) / 100.0, 0.0, 1.0)
	if crit:
		damage = maxf(1.0, damage * weapon.crit_multiplier)
		combat_effect.emit(target.global_position, 0.0, "critical", "暴击")
		RunState.trigger_character_event(CharacterEventEffect.Trigger.CRITICAL_HIT)
	var impact: Vector2 = target.global_position
	target.receive_damage(damage)
	if weapon.burn_damage > 0 and weapon.burn_duration > 0 and target.has_method("apply_burn"):
		target.apply_burn(weapon.burn_damage, weapon.burn_duration)
	if weapon.charm_chance > 0 and target.has_method("apply_charm") and target.health.is_alive() and target.health.current <= target.health.maximum * weapon.charm_health_threshold and RunState.rng.randf() < weapon.charm_chance:
		target.apply_charm(weapon.charm_duration)
	if life_steal_timer.is_stopped() and RunState.rng.randf() < clampf((weapon.base_life_steal + RunState.stat_value("life_steal") + RunState.weapon_bonus(weapon, "life_steal")) / 100.0, 0.0, 1.0):
		health.heal(1.0)
		life_steal_timer.start(0.1)
	if explode and weapon.explosion_radius > 0:
		combat_effect.emit(impact, weapon.explosion_radius, "blast", "")
		for unit in CombatTargeting.attackable_targets(get_tree()):
			if unit != target and unit.global_position.distance_to(impact) <= weapon.explosion_radius:
				apply_weapon_hit(unit, weapon, false)

func get_combat_loadout() -> ActorLoadout:
	return RunState.loadout

func _health_changed(current: float, _maximum: float) -> void:
	RunState.health = current
	_sync_stats()

func _sync_stats() -> void:
	skill.sync_loadout(RunState.loadout)
	var maximum: float = RunState.effective_max_health()
	if health.maximum != maximum:
		health.maximum = maximum
		health.current = clampf(RunState.health, 0.0, maximum)
		health.changed.emit(health.current, health.maximum)
	_update_regen_timer()

func _update_regen_timer() -> void:
	var interval: float = RunState.regeneration_interval()
	if not is_finite(interval):
		regen_timer.stop()
	elif regen_timer.is_stopped() or not is_equal_approx(regen_timer.wait_time, interval):
		regen_timer.start(interval)
