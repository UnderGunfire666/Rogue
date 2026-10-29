@tool
class_name PlayerPrimaryStats
extends RefCounted

const IDS := ["max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting"]
const NAMES := ["最大生命", "生命再生", "生命窃取", "伤害", "近战伤害", "远程伤害", "元素伤害", "攻击速度", "暴击率", "攻击范围", "护甲", "闪避", "移速", "幸运", "收获"]
const PERCENT_IDS := ["life_steal", "damage", "attack_speed", "crit_chance", "dodge", "speed"]
var base: Dictionary = {}
var gained: Dictionary = {}
var temporary: Dictionary = {}

func reset(starting: PrimaryStatsData = null) -> void:
	base.clear()
	gained.clear()
	temporary.clear()
	for id in IDS:
		base[id] = float(starting.get(id)) if starting != null else 0.0
		gained[id] = 0.0
		temporary[id] = 0.0

func add(id: String, amount: float) -> bool:
	if not IDS.has(id) or not is_finite(amount): return false
	gained[id] = float(gained.get(id, 0.0)) + amount
	return true

func value(id: String, loadout: ActorLoadout, growth: PrimaryStatsData = null) -> float:
	var modifier := float(gained.get(id, 0.0)) + float(temporary.get(id, 0.0))
	if loadout != null:
		for relic in loadout.relics:
			if relic.primary_stats != null:
				modifier += float(relic.primary_stats.get(id))
	var multiplier := maxf(0.0, 1.0 + float(growth.get(id)) / 100.0) if growth != null else 1.0
	return float(base.get(id, 0.0)) + modifier * multiplier

static func label(id: String) -> String:
	var index := IDS.find(id)
	return NAMES[index] if index >= 0 else id

static func format_value(id: String, value: float) -> String:
	return "%+.1f%s" % [value, "%" if PERCENT_IDS.has(id) else ""]
