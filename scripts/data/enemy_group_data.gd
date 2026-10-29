class_name EnemyGroupData
extends Resource

enum Kind { NORMAL, ELITE }
@export var display_name: String = ""
@export var entries: Array[EnemyGroupEntry] = []
@export_range(0.01, 10.0) var entry_interval: float = 0.38

func group_kind() -> Kind:
	for entry in entries:
		if entry != null and entry.enemy != null and entry.enemy.category == EnemyData.Category.ELITE:
			return Kind.ELITE
	return Kind.NORMAL

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if entries.is_empty():
		errors.append("Enemy Group 不能为空。")
	if entry_interval <= 0.0:
		errors.append("组内进场间隔必须大于 0。")
	for entry in entries:
		if entry == null or entry.enemy == null or entry.count <= 0:
			errors.append("Enemy Group 需要有效敌人且数量大于 0。")
			continue
		if entry.enemy.category == EnemyData.Category.BOSS:
			errors.append("Enemy Group 不允许包含 BOSS。")
		errors.append_array(entry.enemy.validation_errors())
	return errors
