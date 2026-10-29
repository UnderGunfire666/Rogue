class_name EventActionData
extends Resource

enum Kind { TEXT, REWARD, ENCOUNTER, EFFECT }
enum Duration { COMBAT, MAP, EXPEDITION }
@export var id: String = ""
@export var label: String = ""
@export var kind: Kind = Kind.TEXT
@export_multiline var text: String = ""
@export var reward_options: Array[RewardOptionData] = []
@export var encounter: EncounterData
## Cost and effect fields for Dream Expedition event options.
@export var is_abandon: bool = false
@export var gold_cost: int = 0
@export var health_cost: float = 0.0
@export var requires_sacrifice_equipment: bool = false
@export var gold_gain: int = 0
@export var heal_amount: float = 0.0
@export var stat_id: String = ""
@export var stat_amount: float = 0.0
@export var duration_kind: Duration = Duration.EXPEDITION
@export var duration_combats: int = 1
@export var grant_random_equipment: bool = false
@export var grant_random_relic: bool = false

func has_cost() -> bool:
	return gold_cost > 0 or health_cost > 0.0 or requires_sacrifice_equipment

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if gold_cost < 0 or health_cost < 0.0:
		errors.append("事件代价不能为负。")
	if kind == Kind.ENCOUNTER:
		if encounter == null or encounter.kind == EncounterData.Kind.BOSS:
			errors.append("事件只能触发普通或精英战斗。")
		else:
			errors.append_array(encounter.validation_errors())
	if kind == Kind.REWARD:
		if reward_options.is_empty():
			errors.append("事件奖励需要至少一个选项。")
		for option in reward_options:
			if option == null or option.reward == null:
				errors.append("事件奖励选项不能为空。")
			else:
				errors.append_array(option.reward.validation_errors())
	if not stat_id.is_empty() and not PlayerPrimaryStats.IDS.has(stat_id):
		errors.append("事件属性 ID 无效：" + stat_id)
	return errors
