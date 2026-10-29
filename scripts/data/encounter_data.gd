class_name EncounterData
extends Resource

enum Kind { NORMAL, ELITE, BOSS }
@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.NORMAL
@export var preparation_time: float = 2.5
@export_range(1.0, 600.0, 0.1, "or_greater") var duration: float = 30.0
@export_range(0.01, 120.0, 0.01, "or_greater") var group_interval: float = 5.0
@export var schedules: Array[GroupSpawnSchedule] = []
@export var boss: EnemyData
@export var boss_after_group_count: int = 1
@export var boss_location: SpawnLocationData = SpawnLocationData.new()

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var has_normal: bool = false
	var has_elite: bool = false
	if schedules.is_empty() or not is_finite(preparation_time) or preparation_time < 0.0 or not is_finite(duration) or duration <= 0.0 or not is_finite(group_interval) or group_interval <= 0.0:
		errors.append("战斗需要敌人组列表、正的时长和组间隔，准备时间不能为负。")
	for schedule in schedules:
		if schedule == null:
			errors.append("生成计划不能为空。")
			continue
		errors.append_array(schedule.validation_errors())
		if schedule.group != null:
			if schedule.group.group_kind() == EnemyGroupData.Kind.ELITE:
				has_elite = true
			else:
				has_normal = true
	if kind == Kind.NORMAL and has_elite:
		errors.append("普通战斗只允许 Normal Group。")
	if kind != Kind.NORMAL and (not has_normal or not has_elite):
		errors.append("精英与 BOSS 战斗需要同时包含 Normal Group 和 Elite Group。")
	if kind == Kind.BOSS:
		if boss == null or boss.category != EnemyData.Category.BOSS:
			errors.append("BOSS 战斗需要独立配置 Boss 类别敌人。")
		else:
			errors.append_array(boss.validation_errors())
		if boss_after_group_count < 0 or boss_after_group_count > ceili(duration / group_interval):
			errors.append("BOSS 触发组数必须非负，且时长内有足够的生成次数。")
		if boss_location == null:
			errors.append("BOSS 缺少生成位置。")
		else:
			errors.append_array(boss_location.validation_errors(boss.required_spawn_margin() if boss != null else 24.0))
	elif boss != null:
		errors.append("非 BOSS 战斗不能配置 BOSS。")
	return errors
