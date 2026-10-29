@tool
extends RefCounted
## Editor-only persistence. Enemy drafts retain references to saved items.

const ENEMY_DIR := "res://resources/enemies"
const EQUIPMENT_DIR := "res://resources/enemy_equipment"
const RELIC_DIR := "res://resources/enemy_relics"
const SKILL_DIR := "res://resources/skills"
const EnemyDefinition = preload("res://scripts/data/enemy_data.gd")

func resource_paths(directory: String, extensions: Array[String] = ["tres", "res"]) -> Array[String]:
	var paths: Array[String] = []
	_scan(directory, extensions, paths)
	paths.sort()
	return paths

func _scan(directory: String, extensions: Array[String], paths: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for folder in dir.get_directories():
		if not folder.begins_with("."):
			_scan(directory.path_join(folder), extensions, paths)
	for file in dir.get_files():
		if file.get_extension().to_lower() in extensions:
			paths.append(directory.path_join(file))

func dependencies_ready(path: String, visited: Dictionary) -> bool:
	if visited.has(path): return true
	visited[path] = true
	for entry in ResourceLoader.get_dependencies(path):
		var dependency := entry.get_slice("::", 2) if entry.contains("::") else entry
		if dependency.get_extension().to_lower() in ["svg", "png", "jpg", "jpeg", "webp"]:
			if not FileAccess.file_exists(dependency + ".import"): return false
		elif dependency.get_extension() in ["tres", "res"] and not dependencies_ready(dependency, visited):
			return false
	return true

func copy_definition(source: Resource) -> Resource:
	if source == null:
		return null
	var result: Resource = source.get_script().new()
	for property in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = source.get(property.name)
			if value is Resource and not value is Texture2D:
				if value is SkillData and not (source is SkillData) and is_saved_item(value, SKILL_DIR):
					pass
				else:
					value = copy_definition(value)
			elif value is Array:
				var copied: Array = value.duplicate()
				for index in copied.size():
					if copied[index] is Resource:
						copied[index] = copy_definition(copied[index])
				value = copied
			result.set(property.name, value)
	return result

func copy_enemy(source: EnemyData) -> EnemyData:
	if source == null: return null
	var result := copy_definition(source) as EnemyData
	result.equipment = source.equipment
	result.relic = source.relic
	result.skill = source.skill
	return result

func new_enemy() -> EnemyData:
	var enemy: EnemyData = EnemyDefinition.new()
	enemy.id = unique_id("new_enemy")
	enemy.display_name = "新敌人"
	return enemy

func unique_id(prefix: String) -> String:
	var ids: Dictionary = {}
	for path in resource_paths(ENEMY_DIR):
		var enemy := load(path) as EnemyData
		if enemy != null:
			ids[enemy.id] = true
	var candidate := prefix
	var suffix := 2
	while ids.has(candidate) or FileAccess.file_exists(ENEMY_DIR.path_join(candidate + ".tres")):
		candidate = prefix + "_" + str(suffix)
		suffix += 1
	return candidate

func validate(enemy: EnemyData, path: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	if enemy == null:
		return PackedStringArray(["请选择或新建敌人。"])
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if pattern.search(enemy.id) == null or not enemy.id.is_valid_filename():
		errors.append("敌人 ID 必须以小写英文字母开头，只含小写字母、数字和下划线。")
	if enemy.id.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		errors.append("ID 不能使用系统保留文件名。")
	for other_path in resource_paths(ENEMY_DIR):
		if other_path == path:
			continue
		var other := load(other_path) as EnemyData
		if other != null and other.id == enemy.id:
			errors.append("ID 已被使用：" + other_path)
	if enemy.display_name.strip_edges().is_empty():
		errors.append("显示名称不能为空。")
	if enemy.category not in [0, 1, 2] or enemy.movement not in [0, 1, 2]:
		errors.append("类别或移动行为无效。")
	if not is_finite(enemy.max_health) or enemy.max_health <= 0 or not is_finite(enemy.movement_speed) or enemy.movement_speed <= 0:
		errors.append("生命和固定移动速度必须是大于 0 的有限数值。")
	if not is_finite(enemy.safety_distance) or enemy.safety_distance < 0 or enemy.experience_reward < 0 or enemy.gold_reward < 0:
		errors.append("安全距离与掉落奖励不能为负数。")
	if not is_finite(enemy.consumable_drop_chance) or not is_finite(enemy.relic_drop_chance) or enemy.consumable_drop_chance < 0 or enemy.consumable_drop_chance > 1 or enemy.relic_drop_chance < 0 or enemy.relic_drop_chance > 1:
		errors.append("消耗品和遗物箱的基础掉落率须为 0%–100%。")
	_validate_item(enemy.equipment, "装备", errors)
	if enemy.equipment != null and not is_saved_item(enemy.equipment, EQUIPMENT_DIR):
		errors.append("装备必须选择已保存的敌人装备资源。")
	if enemy.equipment == null or enemy.equipment.attacks.is_empty():
		errors.append("必须装备一件至少包含一个攻击配置的敌人装备。")
	else:
		errors.append_array(CombatDataValidation.item_errors(enemy.equipment))
		if enemy.movement == EnemyData.Movement.CASTER and enemy.equipment.first_attack(AttackProfileData.Kind.SPELL) == null:
			errors.append("施法类行为需要至少一个施法配置（伤害或治疗）。")
	if enemy.relic != null:
		_validate_item(enemy.relic, "遗物", errors)
		if not is_saved_item(enemy.relic, RELIC_DIR):
			errors.append("遗物必须选择已保存的敌人遗物资源。")
		if not is_finite(enemy.relic.regeneration) or enemy.relic.regeneration < 0:
			errors.append("遗物每秒回血须非负。")
		for field in ["movement_bonus", "melee_attack_speed_bonus", "damage_bonus"]:
			var amount: float = enemy.relic.get(field)
			if not is_finite(amount) or amount <= -1.0:
				errors.append("遗物属性加成须大于 -100%。")
	if enemy.skill != null:
		if not is_saved_item(enemy.skill, SKILL_DIR):
			errors.append("技能必须选择已保存的技能资源。")
		errors.append_array(enemy.skill.validation_errors())
	if not path.is_empty():
		var original := load(path) as EnemyData
		if original != null and original.category != enemy.category:
			errors.append_array(_category_constraints(path, enemy.category))
	return errors

func is_saved_item(item: Resource, directory: String) -> bool:
	if item == null: return false
	var path := item.resource_path
	return path.begins_with(directory + "/") and path.simplify_path() == path and not path.contains("::") and path.get_extension() in ["tres", "res"] and FileAccess.file_exists(path)

func _category_constraints(path: String, category: int) -> PackedStringArray:
	var errors := PackedStringArray()
	for resource_path in resource_paths("res://resources"):
		var resource := load(resource_path)
		if resource is EnemyGroupData:
			var group_state := _group_state(resource, path, category)
			if group_state.affected and group_state.boss:
				errors.append("改为 BOSS 会破坏常规敌人组：" + resource_path)
		elif resource is EncounterData:
			var affected := false
			var has_normal := false
			var has_elite := false
			var has_boss := false
			for schedule in resource.schedules:
				if schedule == null or schedule.group == null: continue
				var state := _group_state(schedule.group, path, category)
				affected = affected or state.affected
				has_elite = has_elite or state.elite
				has_normal = has_normal or not state.elite
				has_boss = has_boss or state.boss
			if affected and (has_boss or (resource.kind == EncounterData.Kind.NORMAL and has_elite) or (resource.kind != EncounterData.Kind.NORMAL and (not has_normal or not has_elite))):
				errors.append("类别变更会使战斗的 Normal / Elite 组组成失效：" + resource_path)
			if resource.boss != null and resource.boss.resource_path == path and category != EnemyData.Category.BOSS:
				errors.append("此敌人仍作为独立 BOSS 使用，不能改为普通或精英：" + resource_path)
	return errors

func _group_state(group: EnemyGroupData, path: String, category: int) -> Dictionary:
	var state := {"affected": false, "elite": false, "boss": false}
	for entry in group.entries:
		if entry == null or entry.enemy == null: continue
		var replaced := entry.enemy.resource_path == path
		state.affected = state.affected or replaced
		var value: int = category if replaced else entry.enemy.category
		state.elite = state.elite or value == EnemyData.Category.ELITE
		state.boss = state.boss or value == EnemyData.Category.BOSS
	return state

func _validate_item(item: ItemDefinition, label: String, errors: PackedStringArray) -> void:
	if item == null:
		return
	if item.recipient != ItemDefinition.Recipient.ENEMY:
		errors.append(label + "必须为敌人专用。")
	if item.id.strip_edges().is_empty() or item.display_name.strip_edges().is_empty():
		errors.append(label + "的 ID 和显示名称不能为空。")

func fingerprint(path: String) -> String:
	return FileAccess.get_sha256(path) if not path.is_empty() and FileAccess.file_exists(path) else ""

func save_enemy(draft: EnemyData, path: String, expected_fingerprint: String = "") -> Dictionary:
	var errors := validate(draft, path)
	if not errors.is_empty():
		return {"ok": false, "message": "\n".join(errors)}
	var creating := path.is_empty()
	if creating:
		path = ENEMY_DIR.path_join(draft.id + ".tres")
		if FileAccess.file_exists(path):
			return {"ok": false, "message": "目标文件已存在：" + path}
	elif not _is_enemy_path(path) or not FileAccess.file_exists(path):
		return {"ok": false, "message": "原敌人文件不存在或已移动，请重新载入。"}
	elif fingerprint(path) != expected_fingerprint:
		return {"ok": false, "message": "文件已在其他位置修改。请放弃草稿并重新载入，避免覆盖。"}
	var target: EnemyData = copy_enemy(draft) if creating else load(path) as EnemyData
	if target == null:
		return {"ok": false, "message": "无法载入原敌人文件。"}
	var backup := copy_enemy(target)
	_assign(draft, target)
	var error := ResourceSaver.save(target, path)
	if error != OK:
		_assign(backup, target)
		return {"ok": false, "message": error_string(error)}
	if creating:
		target.take_over_path(path)
	target.emit_changed()
	return {"ok": true, "path": path}

func _assign(source: Resource, target: Resource) -> void:
	var isolated: Resource = copy_enemy(source) if source is EnemyData else copy_definition(source)
	for property in isolated.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			target.set(property.name, isolated.get(property.name))

func references(target: String) -> PackedStringArray:
	var found := PackedStringArray()
	for path in resource_paths("res://", ["tres", "res", "tscn", "scn"]):
		if path != target and _depends_on(path, target, {}):
			found.append(path)
	return found

func _depends_on(path: String, target: String, visited: Dictionary) -> bool:
	if visited.has(path):
		return false
	visited[path] = true
	for entry in ResourceLoader.get_dependencies(path):
		var dependency := entry.get_slice("::", 2) if entry.contains("::") else entry
		if dependency.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(dependency)
			dependency = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
		if dependency == target:
			return true
		if dependency.get_extension() in ["tres", "res", "tscn", "scn"] and _depends_on(dependency, target, visited):
			return true
	return false

func _is_enemy_path(path: String) -> bool:
	return path.begins_with(ENEMY_DIR + "/") and path.simplify_path() == path and path.get_extension() in ["tres", "res"]

func delete_enemy(path: String) -> Dictionary:
	if not _is_enemy_path(path) or not FileAccess.file_exists(path):
		return {"ok": false, "message": "敌人文件不存在或路径无效。"}
	var users := references(path)
	if not users.is_empty():
		return {"ok": false, "message": "敌人仍被引用，不能删除：\n" + "\n".join(users)}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": error == OK, "message": "敌人已删除。" if error == OK else error_string(error)}
