class_name SkillController
extends Node2D

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
signal cast_performed(point: Vector2, radius: float)
@onready var cooldown: Timer = $Cooldown
var data: SkillData
var entries: Array[Dictionary] = []
var selected := -1
var targeting: bool = false
var character_skill: SkillData
var character_cooldown: Timer

func _ready() -> void:
	_ensure_character_timer()

func _ensure_character_timer() -> void:
	if character_cooldown == null:
		character_cooldown = Timer.new()
		character_cooldown.one_shot = true
		add_child(character_cooldown)

func sync_loadout(loadout: ActorLoadout) -> void:
	_ensure_character_timer()
	var next_char_skill: SkillData = RunState.character.skill if RunState.character != null else null
	if character_skill != next_char_skill:
		character_skill = next_char_skill
		character_cooldown.stop()
	var selected_key: String = entries[selected].key if selected >= 0 and selected < entries.size() else ""
	var previous := {}
	for entry in entries: previous[entry.key] = entry
	var next: Array[Dictionary] = []
	for index in loadout.equipment.size():
		var item := loadout.equipment[index]
		if item != null and item.skill != null:
			_append_skill(next, previous, "weapon:%d:%s" % [index, item.id], item.skill)
	for index in loadout.relics.size():
		var item := loadout.relics[index]
		if item.skill != null:
			_append_skill(next, previous, "relic:%d:%s" % [index, item.id], item.skill)
	for key in previous:
		var old: Timer = previous[key].timer
		if old != $Cooldown: old.queue_free()
		else: old.stop()
	entries = next
	if entries.is_empty():
		selected = -1
		data = null
		cooldown = $Cooldown
		targeting = false
	else:
		var found := -1
		for index in entries.size():
			if entries[index].key == selected_key: found = index
		if found < 0: targeting = false
		selected = found if found >= 0 else 0
		data = entries[selected].data
		cooldown = entries[selected].timer

func _append_skill(next: Array[Dictionary], previous: Dictionary, key: String, skill_data: SkillData) -> void:
	if previous.has(key) and previous[key].data == skill_data:
		next.append(previous[key])
		previous.erase(key)
		return
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	next.append({"key": key, "data": skill_data, "timer": timer})

func toggle_targeting() -> void:
	if entries.is_empty(): return
	if targeting or (not cooldown.is_stopped() and entries.size() > 1):
		if entries.size() == 1:
			targeting = false
			return
		selected = (selected + 1) % entries.size()
		data = entries[selected].data
		cooldown = entries[selected].timer
	if cooldown.is_stopped(): targeting = true
	else: targeting = false

func cancel_targeting() -> void:
	targeting = false

func target_position() -> Vector2:
	if data == null: return global_position
	return global_position + (get_global_mouse_position() - global_position).limit_length(data.cast_range)

func character_target_position() -> Vector2:
	if character_skill == null: return global_position
	var delta := get_global_mouse_position() - global_position
	if delta.length_squared() < 4.0:
		delta = Vector2.RIGHT * minf(character_skill.cast_range, 120.0)
	return global_position + delta.limit_length(character_skill.cast_range)

func try_cast() -> bool:
	return try_cast_at(target_position())

func try_cast_at(requested_point: Vector2) -> bool:
	if data == null or not targeting or not cooldown.is_stopped():
		return false
	_execute_skill(data, requested_point)
	targeting = false
	cooldown.start(data.cooldown)
	return true

func trigger_character_skill() -> bool:
	return try_cast_character_skill_at(character_target_position())

func try_cast_character_skill_at(requested_point: Vector2) -> bool:
	_ensure_character_timer()
	if character_skill == null or not character_cooldown.is_stopped():
		return false
	_execute_skill(character_skill, requested_point)
	character_cooldown.start(character_skill.cooldown)
	return true

func _execute_skill(skill_def: SkillData, requested_point: Vector2) -> void:
	var actor := get_parent()
	var offset := requested_point - global_position
	var point := global_position + offset.limit_length(skill_def.cast_range)
	var base_damage := (skill_def.damage + RunState.stat_value("elemental_damage") * skill_def.elemental_scaling) * actor.get_damage_multiplier()
	match skill_def.kind:
		SkillData.Kind.AOE_DAMAGE:
			for unit in CombatTargeting.living_enemies(get_tree()):
				if point.distance_to(unit.global_position) <= skill_def.radius:
					unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
			cast_performed.emit(point, skill_def.radius)
		SkillData.Kind.CHARGE_DASH:
			var start_pos: Vector2 = actor.global_position
			var dir := (point - start_pos).normalized() if point.distance_to(start_pos) > 2.0 else Vector2.RIGHT
			var end_pos: Vector2 = start_pos + dir * minf(skill_def.cast_range, maxf(60.0, start_pos.distance_to(point)))
			if actor.get("movement_bounds") is Rect2:
				var bounds: Rect2 = actor.movement_bounds
				end_pos = end_pos.clamp(bounds.position, bounds.end)
			for unit in CombatTargeting.living_enemies(get_tree()):
				var closest := Geometry2D.get_closest_point_to_segment(unit.global_position, start_pos, end_pos)
				if closest.distance_to(unit.global_position) <= skill_def.radius:
					unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
			actor.global_position = end_pos
			if actor.get("invulnerability") != null:
				actor.invulnerability = maxf(float(actor.invulnerability), maxf(0.35, skill_def.duration))
			cast_performed.emit(end_pos, skill_def.radius)
		SkillData.Kind.PROJECTILE_BURST:
			var dir := (point - global_position).normalized() if point.distance_to(global_position) > 1.0 else Vector2.RIGHT
			var count := maxi(1, skill_def.projectile_count)
			var spread_rad := deg_to_rad(skill_def.spread_angle)
			var root := get_tree().get_first_node_in_group("projectile_root")
			if root != null:
				for i in count:
					var t := 0.0 if count == 1 else (float(i) / float(count - 1) - 0.5)
					var shot_dir := dir.rotated(t * spread_rad)
					var bullet: CombatProjectile = PROJECTILE.instantiate()
					bullet.global_position = global_position + shot_dir * 16.0
					bullet.direction = shot_dir
					bullet.speed = 420.0
					bullet.friendly = true
					bullet.attacker = actor
					bullet.damage = maxf(1.0, base_damage)
					if count == 1 and skill_def.radius >= 40.0:
						bullet.explosion_radius = skill_def.radius
					root.add_child(bullet)
			else:
				for unit in CombatTargeting.living_enemies(get_tree()):
					if point.distance_to(unit.global_position) <= skill_def.radius:
						unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
			cast_performed.emit(global_position + dir * 28.0, maxf(28.0, skill_def.radius * 0.5))
		SkillData.Kind.BUFF_AURA:
			var move_add := skill_def.buff_move_speed_bonus * 100.0
			var atk_add := skill_def.buff_attack_speed_bonus * 100.0
			RunState.primary.temporary["speed"] = float(RunState.primary.temporary.get("speed", 0.0)) + move_add
			RunState.primary.temporary["attack_speed"] = float(RunState.primary.temporary.get("attack_speed", 0.0)) + atk_add
			RunState.stats_changed.emit()
			var dur := maxf(1.5, skill_def.duration)
			var buff_timer := Timer.new()
			buff_timer.one_shot = true
			buff_timer.wait_time = dur
			buff_timer.timeout.connect(func():
				RunState.primary.temporary["speed"] = float(RunState.primary.temporary.get("speed", 0.0)) - move_add
				RunState.primary.temporary["attack_speed"] = float(RunState.primary.temporary.get("attack_speed", 0.0)) - atk_add
				RunState.stats_changed.emit()
				buff_timer.queue_free())
			add_child(buff_timer)
			buff_timer.start()
			if skill_def.damage > 0.0:
				for unit in CombatTargeting.living_enemies(get_tree()):
					if global_position.distance_to(unit.global_position) <= skill_def.radius:
						unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
			cast_performed.emit(global_position, skill_def.radius)
		SkillData.Kind.SUMMON_MINION:
			var charmed_count := 0
			for unit in CombatTargeting.living_enemies(get_tree()):
				if point.distance_to(unit.global_position) <= skill_def.radius:
					unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
					if charmed_count < skill_def.projectile_count and unit.has_method("apply_charm"):
						unit.apply_charm(maxf(4.0, skill_def.duration if skill_def.duration > 0.0 else 5.0))
						charmed_count += 1
			cast_performed.emit(point, skill_def.radius)
		SkillData.Kind.CHAIN_LIGHTNING:
			var remaining := CombatTargeting.living_enemies(get_tree())
			var search_pos := point
			var max_hops := maxi(1, skill_def.projectile_count)
			var hit_any := false
			for hop in max_hops:
				var reach := maxf(skill_def.radius, 140.0) if hop == 0 else 180.0
				var target := CombatTargeting.nearest(search_pos, reach, remaining)
				if target == null:
					break
				hit_any = true
				remaining.erase(target)
				target.receive_damage(RunState.damage_against(target, maxf(1.0, base_damage * pow(0.88, hop))))
				search_pos = target.global_position
				cast_performed.emit(search_pos, 36.0)
			if not hit_any:
				cast_performed.emit(point, skill_def.radius)
		SkillData.Kind.DEFENSIVE_SURGE:
			var start_pos: Vector2 = actor.global_position
			var dir := (point - start_pos).normalized() if point.distance_to(start_pos) > 2.0 else Vector2.RIGHT
			var dist := point.distance_to(start_pos) if point.distance_to(start_pos) > 2.0 else minf(skill_def.cast_range, 120.0)
			var end_pos: Vector2 = start_pos + dir * minf(skill_def.cast_range, dist)
			if actor.get("movement_bounds") is Rect2:
				var bounds: Rect2 = actor.movement_bounds
				end_pos = end_pos.clamp(bounds.position, bounds.end)
			actor.global_position = end_pos
			if actor.get("invulnerability") != null:
				actor.invulnerability = maxf(float(actor.invulnerability), maxf(0.8, skill_def.duration))
			if skill_def.damage > 0.0:
				for unit in CombatTargeting.living_enemies(get_tree()):
					if end_pos.distance_to(unit.global_position) <= skill_def.radius:
						unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
			cast_performed.emit(end_pos, skill_def.radius)
		SkillData.Kind.FIRE_WHIRL:
			var burn_dur := maxf(2.0, skill_def.duration)
			for unit in CombatTargeting.living_enemies(get_tree()):
				if point.distance_to(unit.global_position) <= skill_def.radius:
					unit.receive_damage(RunState.damage_against(unit, maxf(1.0, base_damage)))
					if unit.has_method("apply_burn"):
						unit.apply_burn(maxf(4.0, base_damage * 0.35), burn_dur)
			cast_performed.emit(point, skill_def.radius)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not targeting or data == null:
		return
	var local_target := to_local(target_position())
	draw_arc(Vector2.ZERO, data.cast_range, 0.0, TAU, 80, Color(0.95, 0.69, 0.35, 0.25), 1.0)
	draw_circle(local_target, data.radius, Color(0.95, 0.56, 0.25, 0.15))
	draw_arc(local_target, data.radius, 0.0, TAU, 64, Color(1.0, 0.79, 0.46), 2.0)
	draw_line(local_target + Vector2(-8, 0), local_target + Vector2(8, 0), Color.WHITE, 1.0)
	draw_line(local_target + Vector2(0, -8), local_target + Vector2(0, 8), Color.WHITE, 1.0)
