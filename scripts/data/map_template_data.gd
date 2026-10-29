@tool
class_name MapTemplateData
extends Resource
## One map template per map level. Difficulty never duplicates a template: it only
## supplies cell ratios at generation time (see MapDifficultyData).

@export var id: String = ""
@export var display_name: String = ""
@export_range(1, 3, 1) var level: int = 1
## Applied to enemy health, damage, experience and material drops on this map.
@export_range(0.1, 10.0, 0.1, "or_greater") var level_multiplier: float = 1.0
## Weights for keeping 1, 2 or 3 downward routes from an unbounded cell.
@export var route_count_weights: PackedFloat32Array = [0.1, 0.3, 0.6]
@export_range(1, 10, 1) var elite_min_depth: int = 6
@export_range(0.0, 1.0, 0.01) var elite_chance: float = 0.5
@export var start_name: String = "梦境入口"
@export var boss_name: String = "梦境深处"
@export var normal_encounters: Array[EncounterData] = []
@export var elite_encounters: Array[EncounterData] = []
@export var boss_encounter: EncounterData
@export var reward_options: Array[RewardOptionData] = []
@export var events: Array[EventData] = []

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("地图模板缺少 ID。")
	if route_count_weights.size() != 3:
		errors.append("%s 的路线数权重必须对应 1、2、3 条路线。" % id)
	else:
		var total := 0.0
		for weight in route_count_weights:
			if weight < 0.0:
				errors.append("%s 的路线数权重不能为负。" % id)
			total += weight
		if total <= 0.0:
			errors.append("%s 的路线数权重总和必须大于 0。" % id)
	if normal_encounters.is_empty():
		errors.append("%s 缺少普通战斗。" % id)
	for encounter in normal_encounters:
		if encounter == null or encounter.kind != EncounterData.Kind.NORMAL:
			errors.append("%s 的普通战斗列表只能包含 Normal Encounter。" % id)
	if elite_encounters.is_empty():
		errors.append("%s 缺少精英战斗。" % id)
	for encounter in elite_encounters:
		if encounter == null or encounter.kind != EncounterData.Kind.ELITE:
			errors.append("%s 的精英战斗列表只能包含 Elite Encounter。" % id)
	if boss_encounter == null or boss_encounter.kind != EncounterData.Kind.BOSS:
		errors.append("%s 必须配置 Boss Encounter。" % id)
	if reward_options.is_empty():
		errors.append("%s 缺少奖励选项。" % id)
	if events.is_empty():
		errors.append("%s 缺少事件。" % id)
	return errors
