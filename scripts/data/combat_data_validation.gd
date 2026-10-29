@tool
class_name CombatDataValidation
extends RefCounted

static func attack_errors(profile: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	if profile == null:
		return PackedStringArray(["攻击配置不能为空。"])
	if profile.kind not in [0, 1, 2]: errors.append("攻击类型无效。")
	if not is_finite(profile.damage) or profile.damage < 0: errors.append("攻击力须为非负有限数值。")
	if not is_finite(profile.attack_range) or profile.attack_range <= 0: errors.append("攻击范围须大于 0。")
	if not is_finite(profile.attack_interval) or profile.attack_interval <= 0: errors.append("攻击间隔须大于 0。")
	if profile.kind == 1:
		if profile.projectile_count < 1: errors.append("投射物数须至少为 1。")
		if not is_finite(profile.projectile_speed) or profile.projectile_speed <= 0: errors.append("弹速须大于 0。")
		if not is_finite(profile.spread_degrees) or profile.spread_degrees < 0 or profile.spread_degrees > 360: errors.append("散射角度须在 0–360 度之间。")
	else:
		if profile.target_count < 1: errors.append("攻击对象数须至少为 1。")
		if not is_finite(profile.area_radius) or profile.area_radius < 0 or (profile.target_count > 1 and profile.area_radius <= 0): errors.append("群体攻击的效果半径须大于 0。")
	if profile is AttackProfileData:
		if profile.effect not in [0, 1]: errors.append("施法效果无效。")
		if profile.effect == AttackProfileData.Effect.HEAL:
			if profile.kind != AttackProfileData.Kind.SPELL: errors.append("治疗效果须使用施法类型。")
			if not is_finite(profile.healing_per_second) or profile.healing_per_second <= 0: errors.append("每秒治疗量须大于 0。")
	return errors

static func item_errors(item: ItemDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	if item == null: return PackedStringArray(["物品不能为空。"])
	if item.id.strip_edges().is_empty() or item.display_name.strip_edges().is_empty(): errors.append("物品 ID 和名称不能为空。")
	if item.recipient not in [0, 1]: errors.append("使用者无效。")
	if item.rarity < 1 or item.rarity > 5: errors.append("稀有度须为 1 至 5。")
	if (item is WeaponData or item is RelicData) and item.skill != null:
		var skill: SkillData = item.skill
		if skill.display_name.strip_edges().is_empty(): errors.append("技能名称不能为空。")
		if not is_finite(skill.damage) or skill.damage < 0 or not is_finite(skill.elemental_scaling) or skill.elemental_scaling < 0: errors.append("技能伤害及属性系数须为非负有限数值。")
		if not is_finite(skill.cast_range) or skill.cast_range <= 0 or not is_finite(skill.radius) or skill.radius <= 0 or not is_finite(skill.cooldown) or skill.cooldown <= 0: errors.append("技能施放距离、半径和冷却须为正的有限数值。")
	if item is WeaponData:
		if not is_finite(item.charm_chance) or item.charm_chance < 0 or item.charm_chance > 1 or not is_finite(item.charm_duration) or item.charm_duration < 0 or not is_finite(item.charm_health_threshold) or item.charm_health_threshold < 0 or item.charm_health_threshold > 1 or (item.charm_chance > 0 and item.charm_duration <= 0): errors.append("魅惑概率、持续时间或生命阈值无效。")
		if item.pierce_count < 0 or item.bounce_count < 0 or not is_finite(item.bounce_range) or item.bounce_range <= 0 or not is_finite(item.explosion_radius) or item.explosion_radius < 0 or not is_finite(item.burn_damage) or item.burn_damage < 0 or not is_finite(item.burn_duration) or item.burn_duration < 0 or (item.burn_damage > 0 and item.burn_duration <= 0): errors.append("穿透、弹跳、爆炸或燃烧参数无效。")
		if item.melee_motion not in [0, 1] or not is_finite(item.melee_hit_radius) or item.melee_hit_radius <= 0 or not is_finite(item.sweep_angle) or item.sweep_angle <= 0 or item.sweep_angle > 360: errors.append("近战轨迹类型、角度或判定半径无效。")
		if item.recipient != ItemDefinition.Recipient.PLAYER: errors.append("玩家装备只能供玩家使用。")
		if not is_finite(item.stat_scaling) or item.stat_scaling < 0: errors.append("属性伤害系数须非负。")
		if not is_finite(item.base_crit_chance) or not is_finite(item.base_life_steal): errors.append("基础暴击率和吸血率须为有限数值。")
		if not is_finite(item.crit_multiplier) or item.crit_multiplier < 1: errors.append("暴击伤害倍率须至少为 1。")
		errors.append_array(attack_errors(item))
	elif item is EnemyEquipmentData:
		if item.recipient != ItemDefinition.Recipient.ENEMY: errors.append("敌人装备只能供敌人使用。")
		if item.attacks.is_empty(): errors.append("敌人装备至少需要一个攻击配置。")
		for index in item.attacks.size():
			for error in attack_errors(item.attacks[index]): errors.append("配置 %d：%s" % [index + 1, error])
	elif item is RelicData:
		if item.base_price < 0 or item.copy_limit < 0: errors.append("基础价格和数量上限不能为负数。")
		if not is_finite(item.regeneration) or item.regeneration < 0: errors.append("每秒回复生命须非负。")
		for field in ["movement_bonus", "melee_attack_speed_bonus", "damage_bonus"]:
			var value: float = item.get(field)
			if not is_finite(value) or value <= -1: errors.append("属性加成须大于 -100%。")
		if item.primary_stats != null:
			for id in PlayerPrimaryStats.IDS:
				if not is_finite(float(item.primary_stats.get(id))): errors.append("主属性须为有限数值：" + str(id))
	return errors
