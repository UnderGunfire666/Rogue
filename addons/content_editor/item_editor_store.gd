@tool
extends RefCounted
## Equipment/relic library operations reuse the enemy editor's Resource IO helpers.

const ResourceIO = preload("res://addons/enemy_editor/enemy_editor_store.gd")
var io := ResourceIO.new()
var kind := "equipment"

func directories() -> Array[String]:
	return ["res://resources/weapons", "res://resources/enemy_equipment"] if kind == "equipment" else ["res://resources/relics", "res://resources/enemy_relics"]

func accepts(resource: Resource) -> bool:
	return (resource is WeaponData or resource is EnemyEquipmentData) if kind == "equipment" else resource is RelicData

func paths() -> Array[String]:
	var result: Array[String] = []
	for directory in directories():
		for path in io.resource_paths(directory):
			if Engine.is_editor_hint() and not io.dependencies_ready(path, {}): continue
			if accepts(load(path)): result.append(path)
	return result

func new_item(recipient: int) -> ItemDefinition:
	var item: ItemDefinition
	if kind == "relic":
		item = RelicData.new()
	elif recipient == ItemDefinition.Recipient.PLAYER:
		item = WeaponData.new()
	else:
		var equipment := EnemyEquipmentData.new()
		equipment.attacks.append(AttackProfileData.new())
		item = equipment
	item.recipient = recipient
	item.id = unique_id("new_" + kind, recipient)
	item.display_name = "新装备" if kind == "equipment" else "新遗物"
	return item

func unique_id(prefix: String, recipient: int) -> String:
	var used: Dictionary = {}
	for path in paths():
		var item := load(path) as ItemDefinition
		if item.recipient == recipient: used[item.id] = true
	var candidate := prefix
	var suffix := 2
	while used.has(candidate) or FileAccess.file_exists(_directory(recipient).path_join(candidate + ".tres")):
		candidate = prefix + "_" + str(suffix)
		suffix += 1
	return candidate

func _directory(recipient: int) -> String:
	return directories()[0 if recipient == ItemDefinition.Recipient.PLAYER else 1]

func validate(item: ItemDefinition, path: String = "") -> PackedStringArray:
	var errors := CombatDataValidation.item_errors(item)
	if item == null: return errors
	if not accepts(item): errors.append("资源类型与当前编辑器不匹配。")
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(item.id) == null or not item.id.is_valid_filename():
		errors.append("ID 须以小写英文字母开头，只含小写字母、数字和下划线。")
	if item.id.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		errors.append("ID 不能使用系统保留文件名。")
	for other_path in paths():
		if other_path == path: continue
		var other := load(other_path) as ItemDefinition
		if other.recipient == item.recipient and other.id == item.id:
			errors.append("相同使用者的 ID 已存在：" + other_path)
	if not path.is_empty() and FileAccess.file_exists(path):
		var original := load(path) as ItemDefinition
		if original == null or original.recipient != item.recipient or original.get_script() != item.get_script():
			errors.append("已有资源的使用者和资源类型不能更改，请复制为新资源。")
	if item is EnemyEquipmentData:
		for enemy_path in io.resource_paths(ResourceIO.ENEMY_DIR):
			var enemy := load(enemy_path) as EnemyData
			if enemy != null and enemy.equipment != null and enemy.equipment.resource_path == path and enemy.movement == EnemyData.Movement.CASTER and item.first_attack(AttackProfileData.Kind.SPELL) == null:
				errors.append("移除施法会使施法类敌人失效：" + enemy_path)
	return errors

func save_item(draft: ItemDefinition, path: String, fingerprint: String = "") -> Dictionary:
	var errors := validate(draft, path)
	if not errors.is_empty(): return {"ok": false, "message": "\n".join(errors)}
	var creating := path.is_empty()
	if creating:
		path = _directory(draft.recipient).path_join(draft.id + ".tres")
		if FileAccess.file_exists(path): return {"ok": false, "message": "目标文件已存在。"}
	elif not _allowed(path) or not FileAccess.file_exists(path):
		return {"ok": false, "message": "文件不存在或不在本物品库中。"}
	elif io.fingerprint(path) != fingerprint:
		return {"ok": false, "message": "文件已被其他位置修改，请重新载入后再编辑。"}
	var target: ItemDefinition = io.copy_definition(draft) as ItemDefinition if creating else load(path) as ItemDefinition
	var backup := io.copy_definition(target)
	io._assign(draft, target)
	var error := ResourceSaver.save(target, path)
	if error != OK:
		io._assign(backup, target)
		return {"ok": false, "message": error_string(error)}
	if creating: target.take_over_path(path)
	target.emit_changed()
	return {"ok": true, "path": path}

func _allowed(path: String) -> bool:
	if path.simplify_path() != path or path.get_extension() not in ["tres", "res"]: return false
	for directory in directories():
		if path.begins_with(directory + "/"): return true
	return false

func delete_item(path: String) -> Dictionary:
	if not _allowed(path) or not FileAccess.file_exists(path): return {"ok": false, "message": "无效文件路径。"}
	var users := io.references(path)
	if not users.is_empty(): return {"ok": false, "message": "资源仍被以下文件引用，不能删除：\n" + "\n".join(users)}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": error == OK, "message": "资源已删除。" if error == OK else error_string(error)}
