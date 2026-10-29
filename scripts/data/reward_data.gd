class_name RewardData
extends Resource

@export_range(0, 9999) var gold: int = 0
@export var equipment: Array[EquipmentData] = []
@export var relics: Array[RelicData] = []

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if gold < 0:
		errors.append("奖励金币不能为负。")
	for item in equipment:
		if item == null or item.recipient != ItemDefinition.Recipient.PLAYER or not item is WeaponData:
			errors.append("玩家奖励只能包含玩家装备。")
	for item in relics:
		if item == null or item.recipient != ItemDefinition.Recipient.PLAYER:
			errors.append("玩家奖励只能包含玩家遗物。")
	return errors
