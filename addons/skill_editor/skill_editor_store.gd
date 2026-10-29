@tool
extends RefCounted
## Skill library persistence and validation for res://resources/skills.

const ResourceIO = preload("res://addons/enemy_editor/enemy_editor_store.gd")
const SKILL_DIR := "res://resources/skills"
var io := ResourceIO.new()

func paths() -> Array[String]:
	var result: Array[String] = []
	for path in io.resource_paths(SKILL_DIR):
		if Engine.is_editor_hint() and not io.dependencies_ready(path, {}):
			continue
		if load(path) is SkillData:
			result.append(path)
	return result

func new_skill() -> SkillData:
	var skill := SkillData.new()
	skill.id = unique_id("new_skill")
	skill.display_name = "新技能"
	return skill

func unique_id(prefix: String) -> String:
	var used: Dictionary = {}
	for path in paths():
		var item := load(path) as SkillData
		if item != null:
			used[item.id] = true
	var candidate := prefix
	var suffix := 2
	while used.has(candidate) or FileAccess.file_exists(SKILL_DIR.path_join(candidate + ".tres")):
		candidate = "%s_%d" % [prefix, suffix]
		suffix += 1
	return candidate

func validate(skill: SkillData, path: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	if skill == null:
		return PackedStringArray(["请选择或新建技能。"])
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if pattern.search(skill.id) == null or not skill.id.is_valid_filename():
		errors.append("技能 ID 须以小写英文字母开头，只含小写字母、数字和下划线。")
	if skill.id.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
		errors.append("ID 不能使用系统保留文件名。")
	for other_path in paths():
		if other_path == path:
			continue
		var other := load(other_path) as SkillData
		if other != null and other.id == skill.id:
			errors.append("技能 ID 已存在：" + other_path)
	errors.append_array(skill.validation_errors())
	return errors

func save_skill(draft: SkillData, path: String, fingerprint: String = "") -> Dictionary:
	var errors := validate(draft, path)
	if not errors.is_empty():
		return {"ok": false, "message": "\n".join(errors)}
	var creating := path.is_empty()
	if creating:
		path = SKILL_DIR.path_join(draft.id + ".tres")
		if FileAccess.file_exists(path):
			return {"ok": false, "message": "目标文件已存在：" + path}
	elif not _allowed(path) or not FileAccess.file_exists(path):
		return {"ok": false, "message": "文件不存在或不在技能库中。"}
	elif not fingerprint.is_empty() and io.fingerprint(path) != fingerprint:
		return {"ok": false, "message": "文件已被其他位置修改，请重新载入后再编辑。"}
	var target: SkillData = io.copy_definition(draft) as SkillData if creating else load(path) as SkillData
	var backup := io.copy_definition(target)
	io._assign(draft, target)
	var error := ResourceSaver.save(target, path)
	if error != OK:
		io._assign(backup, target)
		return {"ok": false, "message": error_string(error)}
	if creating:
		target.take_over_path(path)
	target.emit_changed()
	return {"ok": true, "path": path}

func _allowed(path: String) -> bool:
	return path.begins_with(SKILL_DIR + "/") and path.simplify_path() == path and path.get_extension() in ["tres", "res"]

func delete_skill(path: String) -> Dictionary:
	if not _allowed(path) or not FileAccess.file_exists(path):
		return {"ok": false, "message": "无效文件路径。"}
	var users := io.references(path)
	if not users.is_empty():
		return {"ok": false, "message": "技能仍被以下资源引用，不能删除：\n" + "\n".join(users)}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": error == OK, "message": "技能已删除。" if error == OK else error_string(error)}

