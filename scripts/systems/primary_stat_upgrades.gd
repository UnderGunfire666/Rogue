@tool
class_name PrimaryStatUpgrades
extends RefCounted
## Five brain organs governing the 15 player primary attributes (3 attributes per organ).

const ORGAN_ORDER := [
	"hippocampus",
	"amygdala",
	"prefrontal_cortex",
	"brainstem",
	"cerebellum"
]

const ORGANS := {
	"hippocampus": {
		"id": "hippocampus",
		"name": "海马体",
		"stats": ["weapon_range", "luck", "harvesting"]
	},
	"amygdala": {
		"id": "amygdala",
		"name": "杏仁核",
		"stats": ["damage", "elemental_damage", "life_steal"]
	},
	"prefrontal_cortex": {
		"id": "prefrontal_cortex",
		"name": "前额叶",
		"stats": ["ranged_damage", "attack_speed", "crit_chance"]
	},
	"brainstem": {
		"id": "brainstem",
		"name": "脑干",
		"stats": ["max_hp", "hp_regeneration", "armor"]
	},
	"cerebellum": {
		"id": "cerebellum",
		"name": "小脑",
		"stats": ["melee_damage", "speed", "dodge"]
	}
}

## Fixed bonus values for tiers 1..5 per primary attribute.
const TIER_VALUES := {
	"weapon_range": [12.0, 18.0, 25.0, 35.0, 50.0],
	"luck": [4.0, 6.0, 9.0, 13.0, 18.0],
	"harvesting": [4.0, 6.0, 9.0, 13.0, 18.0],
	"damage": [4.0, 6.0, 9.0, 13.0, 18.0],
	"elemental_damage": [1.0, 2.0, 3.0, 5.0, 8.0],
	"life_steal": [1.0, 2.0, 3.0, 4.0, 6.0],
	"ranged_damage": [1.0, 2.0, 3.0, 5.0, 8.0],
	"attack_speed": [4.0, 6.0, 9.0, 13.0, 18.0],
	"crit_chance": [2.0, 4.0, 6.0, 9.0, 12.0],
	"max_hp": [3.0, 5.0, 8.0, 12.0, 18.0],
	"hp_regeneration": [1.0, 2.0, 3.0, 5.0, 8.0],
	"armor": [1.0, 2.0, 3.0, 4.0, 6.0],
	"melee_damage": [2.0, 3.0, 5.0, 8.0, 12.0],
	"speed": [2.0, 4.0, 6.0, 9.0, 12.0],
	"dodge": [2.0, 4.0, 6.0, 9.0, 12.0]
}

## Legacy single-stat base values (Tier 1) kept for backward compatibility.
const VALUES := {
	"max_hp": 3.0, "hp_regeneration": 1.0, "life_steal": 1.0, "damage": 4.0,
	"melee_damage": 2.0, "ranged_damage": 1.0, "elemental_damage": 1.0,
	"attack_speed": 4.0, "crit_chance": 2.0, "weapon_range": 12.0,
	"armor": 1.0, "dodge": 2.0, "speed": 2.0, "luck": 4.0, "harvesting": 4.0
}

## 1-5 rarity probability brackets by player level interval:
## Bracket 0 (Lv 1-3), Bracket 1 (Lv 4-6), Bracket 2 (Lv 7-9), Bracket 3 (Lv 10-13), Bracket 4 (Lv 14+).
const LEVEL_RARITY_BRACKETS := [
	{"min_level": 1, "max_level": 3, "weights": [0.75, 0.20, 0.05, 0.00, 0.00]},
	{"min_level": 4, "max_level": 6, "weights": [0.50, 0.32, 0.15, 0.03, 0.00]},
	{"min_level": 7, "max_level": 9, "weights": [0.30, 0.35, 0.23, 0.10, 0.02]},
	{"min_level": 10, "max_level": 13, "weights": [0.15, 0.28, 0.32, 0.18, 0.07]},
	{"min_level": 14, "max_level": 9999, "weights": [0.08, 0.20, 0.32, 0.25, 0.15]}
]

static func level_rarity_weights(player_level: int, luck: float = 0.0) -> Array[float]:
	var lvl := maxi(1, player_level)
	var base_weights: Array = LEVEL_RARITY_BRACKETS[0]["weights"]
	for bracket in LEVEL_RARITY_BRACKETS:
		if lvl >= int(bracket["min_level"]) and lvl <= int(bracket["max_level"]):
			base_weights = bracket["weights"]
			break
	var luck_factor := clampf(luck / 100.0, -0.8, 2.0)
	var adjusted: Array[float] = []
	var total := 0.0
	for i in base_weights.size():
		var w := float(base_weights[i])
		if i > 0 and w > 0.0:
			w = maxf(0.0, w * (1.0 + luck_factor * 0.25 * i))
		adjusted.append(w)
		total += w
	if total <= 0.0:
		return [1.0, 0.0, 0.0, 0.0, 0.0]
	for i in adjusted.size():
		adjusted[i] /= total
	return adjusted

static func roll_organ_rarity(state: Node) -> int:
	var weights := level_rarity_weights(state.level, state.stat_value("luck"))
	var roll: float = state.rng.randf()
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i + 1
	return 1

static func organ_bonuses_for_tier(organ_id: String, tier: int) -> Dictionary:
	var clamped_tier := clampi(tier, 1, 5)
	var result: Dictionary = {}
	if not ORGANS.has(organ_id):
		return result
	var stat_ids: Array = ORGANS[organ_id]["stats"]
	for stat_id in stat_ids:
		var tiers: Array = TIER_VALUES[stat_id]
		result[stat_id] = float(tiers[clamped_tier - 1])
	return result

static func organ_for_stat(stat_id: String) -> String:
	for organ_id in ORGAN_ORDER:
		var stats: Array = ORGANS[organ_id]["stats"]
		if stats.has(stat_id):
			return organ_id
	return ""

static func create_offers(state: Node) -> Array[Dictionary]:
	var pool := ORGAN_ORDER.duplicate()
	var offers: Array[Dictionary] = []
	# Draw 4 distinct brain organs out of the 5; each rolls its 1-5 rarity independently by player level interval.
	for i in mini(4, pool.size()):
		var index: int = state.rng.randi_range(0, pool.size() - 1)
		var organ_id: String = pool.pop_at(index)
		var organ: Dictionary = ORGANS[organ_id]
		var tier := roll_organ_rarity(state)
		var bonuses := organ_bonuses_for_tier(organ_id, tier)
		var stats: Array = organ["stats"]
		offers.append({
			"id": organ_id,
			"organ_id": organ_id,
			"name": str(organ["name"]),
			"tier": tier,
			"stats": stats.duplicate(),
			"bonuses": bonuses,
			"amount": float(bonuses[stats[0]])
		})
	return offers

static func format_offer(option: Dictionary) -> String:
	var tier := int(option.get("tier", 1))
	if option.has("bonuses") and option["bonuses"] is Dictionary:
		var organ_name := str(option.get("name", option.get("id", "")))
		var lines := PackedStringArray(["稀有度 T%d · 【%s】" % [tier, organ_name]])
		var bonuses: Dictionary = option["bonuses"]
		for stat_id in bonuses.keys():
			lines.append("%s  %s" % [PlayerPrimaryStats.label(str(stat_id)), PlayerPrimaryStats.format_value(str(stat_id), float(bonuses[stat_id]))])
		return "\n".join(lines)
	var stat_id := str(option.get("id", ""))
	var amount := float(option.get("amount", 0.0))
	return "稀有度 T%d  ·  %s\n%s" % [tier, PlayerPrimaryStats.label(stat_id), PlayerPrimaryStats.format_value(stat_id, amount)]
