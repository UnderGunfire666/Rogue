class_name MapCellData
extends Resource

## START is appended so saved integer kinds in existing maps keep their meaning.
enum Kind { NORMAL_BATTLE, ELITE_BATTLE, BOSS_BATTLE, REWARD, EVENT, START }
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.NORMAL_BATTLE
@export var grid_position: Vector2i = Vector2i.ZERO
@export var encounter: EncounterData
@export var reward_options: Array[RewardOptionData] = []
@export var event: EventData
## Route maps only: 1-based layer and directed links to the next layer.
@export var depth: int = 0
@export var next_cell_ids: PackedStringArray = []
## Route maps only: presentation position in cell units (layers are centred).
@export var view_position: Vector2 = Vector2.ZERO

func is_battle() -> bool:
	return kind <= Kind.BOSS_BATTLE

func type_name() -> String:
	return ["普通战斗", "精英战斗", "BOSS 战斗", "奖励", "事件", "起点"][kind]

func type_color() -> Color:
	return [Color("#a5cadd"), Color("#c8a0ee"), Color("#f18b86"), Color("#edcf87"), Color("#7fd1bc"), Color("#d9e3d9")][kind]

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if kind == Kind.START:
		return errors
	if is_battle():
		if encounter == null or encounter.kind != kind:
			errors.append("%s 的格子类型与战斗类型不匹配。" % display_name)
		else:
			errors.append_array(encounter.validation_errors())
	elif kind == Kind.REWARD:
		if reward_options.is_empty():
			errors.append("%s 缺少奖励选项。" % display_name)
		for option in reward_options:
			if option == null or option.reward == null:
				errors.append("%s 的奖励选项不能为空。" % display_name)
			else:
				errors.append_array(option.reward.validation_errors())
	elif event == null:
		errors.append("%s 缺少事件文本。" % display_name)
	elif event != null:
		errors.append_array(event.validation_errors())
	return errors
