@tool
class_name ActorLoadout
extends RefCounted
## Shared slot limits, content eligibility and passive effects for every actor.

var recipient: ItemDefinition.Recipient
var equipment: Array[EquipmentData] = []
var relics: Array[RelicData] = []
var relic_slot_limit: int
var equipment_rules: CharacterEquipmentRules

func _init(owner_type: ItemDefinition.Recipient = ItemDefinition.Recipient.PLAYER, equipment_slots: int = 2, relic_slots: int = -1, rules: CharacterEquipmentRules = null) -> void:
	recipient = owner_type
	equipment_rules = rules
	equipment.resize(rules.slots if rules != null and owner_type == ItemDefinition.Recipient.PLAYER else equipment_slots)
	relic_slot_limit = relic_slots

func equip(item: EquipmentData, slot: int) -> bool:
	if slot < 0 or slot >= equipment.size():
		return false
	if item != null and item.recipient != recipient:
		return false
	if item is WeaponData and equipment_rules != null:
		if not can_equip_weapon(item, slot): return false
	equipment[slot] = item
	return true

func can_equip_weapon(item: WeaponData, slot: int) -> bool:
	if item == null or item.recipient != recipient or slot < 0 or slot >= equipment.size(): return false
	if equipment_rules == null: return true
	if item.rarity < equipment_rules.minimum_rarity or item.rarity > equipment_rules.maximum_rarity: return false
	if item.kind == WeaponData.Kind.MELEE and not equipment_rules.allow_melee: return false
	if item.kind == WeaponData.Kind.RANGED and not equipment_rules.allow_ranged: return false
	if item.kind == WeaponData.Kind.SPELL and not equipment_rules.allow_spell: return false
	if not equipment_rules.allow_duplicates:
		for index in equipment.size():
			if index != slot and equipment[index] != null and equipment[index].id == item.id: return false
	return true

func can_add_relic(item: RelicData) -> bool:
	if item == null or item.recipient != recipient:
		return false
	if relic_slot_limit >= 0 and relics.size() >= relic_slot_limit:
		return false
	if item.copy_limit > 0:
		var copies := 0
		for relic in relics:
			if relic.id == item.id: copies += 1
		if copies >= item.copy_limit: return false
	return true

func add_relic(item: RelicData) -> bool:
	if not can_add_relic(item): return false
	relics.append(item)
	return true

func clear_relics() -> void:
	relics.clear()

func regeneration() -> float:
	var amount: float = 0.0
	for item in relics:
		amount += item.regeneration
	return amount

func movement_bonus() -> float:
	var amount: float = 0.0
	for item in relics:
		amount += item.movement_bonus
	return amount

func damage_bonus() -> float:
	var amount: float = 0.0
	for item in relics:
		amount += item.damage_bonus
	return amount

func melee_speed_multiplier() -> float:
	var amount: float = 1.0
	for item in relics:
		amount += item.melee_attack_speed_bonus
	return maxf(0.01, amount)

func equipment_ids() -> Array[String]:
	var result: Array[String] = []
	for item in equipment:
		result.append("" if item == null else item.id)
	return result

func relic_ids() -> Array[String]:
	var result: Array[String] = []
	for item in relics:
		result.append(item.id)
	return result
