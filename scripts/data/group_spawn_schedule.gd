class_name GroupSpawnSchedule
extends Resource

@export var group: EnemyGroupData
@export var location: SpawnLocationData = SpawnLocationData.new()

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if group == null:
		errors.append("生成计划缺少 Enemy Group。")
	else:
		errors.append_array(group.validation_errors())
	if location == null:
		errors.append("生成计划缺少位置配置。")
	else:
		var required_margin: float = 24.0
		if group != null:
			for entry in group.entries:
				if entry != null and entry.enemy != null:
					required_margin = maxf(required_margin, entry.enemy.required_spawn_margin())
		errors.append_array(location.validation_errors(required_margin))
	return errors
