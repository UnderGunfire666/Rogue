@tool
class_name MapDifficultyData
extends Resource
## Difficulty / theme pairing. Gameplay effect is limited to the cell ratios below;
## theme fields are presentation only.

@export var id: String = ""
@export var display_name: String = ""
@export var theme_name: String = ""
@export_multiline var description: String = ""
@export var order: int = 0
@export_range(0.0, 1.0, 0.01) var battle_ratio: float = 0.7
@export_range(0.0, 1.0, 0.01) var reward_ratio: float = 0.15
@export_range(0.0, 1.0, 0.01) var event_ratio: float = 0.15
## Placeholder until final artwork exists; art_count is the planned pool size.
@export var placeholder_art: Texture2D
@export_range(1, 20, 1) var art_count: int = 5
@export var accent_color: Color = Color("#d9e3d9")

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("地图难度缺少 ID。")
	if not is_equal_approx(battle_ratio + reward_ratio + event_ratio, 1.0):
		errors.append("%s 的战斗、奖励、事件比例之和必须为 100%%。" % id)
	return errors
