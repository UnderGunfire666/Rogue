extends Node
## Persistent data for a single Run; actors own their battle simulation.
signal stats_changed
signal experience_changed

var character_id: String = "wanderer"
var character: CharacterData
var player_moving := false
var loadout := ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1)
var primary := PlayerPrimaryStats.new()
var rng := RandomNumberGenerator.new()
var weapons: Array[String]:
	get:
		return loadout.equipment_ids()
var relics: Array[String]:
	get:
		return loadout.relic_ids()
var max_health: float = 100.0
var health: float = 100.0
var base_movement_speed: float = ContentCatalog.PLAYER_BASE_SPEED
var gold: int = 0
var experience: int = 0
var level: int = 1
var pending_upgrades: int = 0
var damage_bonus: float = 0.0
var movement_bonus: float = 0.0
const COMBAT_CELL_STAT_GROWTH: float = 0.05
const COMBAT_CELL_REWARD_GROWTH: float = 0.05

var completed_waves: int = 0
var combats_completed_in_map: int = 0
var triggered_battle_cells_in_map: Array[String] = []
var locked_weapon_prices: Dictionary = {}
var locked_relic_prices: Dictionary = {}
var upgrade_offers: Array[Dictionary] = []
var completed_cells: Array[String] = []
var current_cell_id: String = ""
var available: Array[String]:
	get:
		if not completed_cells.has(current_cell_id):
			return []
		return current_map().neighbors(current_cell_id)
var won_run: bool = false
var active_encounter: EncounterData
var encounter_from_event: bool = false
var active_event_action_id: String = ""
var completed_event_actions: Array[String] = []
## Dream expedition in progress; null keeps the authored ContentCatalog map.
var expedition: ExpeditionState
## Per-combat XP and fragment accumulators for Dream Expedition rules.
var combat_pending_xp: int = 0
var combat_base_fragments: int = 0
## Event stat modifiers with duration (COMBAT / MAP / EXPEDITION).
var event_stat_modifiers: Array[Dictionary] = []
## Post-battle equipment/relic loot drops (Elite: 1+1, BOSS: 2+2) and abandoned shared pool.
var pending_combat_loot: Array[Resource] = []
var shared_loot_pool: Array[Resource] = []
## Persistent 5-slot shop state for locking items across shops.
var locked_shop_slots: Array[Dictionary] = []
## Multiplayer brainwave symbol arbitration (0: Alpha, 1: Beta, 2: Gamma; 0 beats 1, 1 beats 2, 2 beats 0)
## and shop gold gifting record per shop phase.
var gifted_teammates_this_shop: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	_register_inputs()

func new_run() -> void:
	_event_counts.clear()
	_move_distance = 0.0
	_event_depth = 0
	loadout = ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1)
	select_character("wanderer")
	gold = 0
	experience = 0
	level = 1
	pending_upgrades = 0
	damage_bonus = 0.0
	movement_bonus = 0.0
	completed_waves = 0
	combats_completed_in_map = 0
	triggered_battle_cells_in_map.clear()
	locked_weapon_prices.clear()
	locked_relic_prices.clear()
	upgrade_offers.clear()
	completed_cells.clear()
	completed_event_actions.clear()
	expedition = null
	combat_pending_xp = 0
	combat_base_fragments = 0
	event_stat_modifiers.clear()
	pending_combat_loot.clear()
	shared_loot_pool.clear()
	locked_shop_slots.clear()
	gifted_teammates_this_shop.clear()
	current_cell_id = ContentCatalog.map().starting_cell_id
	completed_cells.append(current_cell_id)
	active_encounter = null
	encounter_from_event = false
	active_event_action_id = ""
	won_run = false
	stats_changed.emit()

func select_character(id: String) -> void:
	var data := ContentCatalog.character(id)
	character = data
	character_id = id
	player_moving = false
	max_health = data.max_health
	health = data.max_health
	base_movement_speed = data.movement_units * ContentCatalog.PIXELS_PER_UNIT
	primary.reset(data.primary_stats)
	health = effective_max_health()

func preview_character(id: String) -> Dictionary:
	var saved_character := character
	var saved_id := character_id
	var saved_primary := primary
	var saved_loadout := loadout
	var saved_max := max_health
	var saved_health := health
	var saved_speed := base_movement_speed
	var saved_moving := player_moving
	var saved_damage_bonus := damage_bonus
	var saved_movement_bonus := movement_bonus
	damage_bonus = 0.0
	movement_bonus = 0.0
	primary = PlayerPrimaryStats.new()
	loadout = ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1)
	select_character(id)
	loadout = ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, character.equipment_rules)
	var result := {}
	for stat in PlayerPrimaryStats.IDS: result[stat] = stat_value(stat)
	result["actual_speed"] = movement_speed()
	character = saved_character
	character_id = saved_id
	primary = saved_primary
	loadout = saved_loadout
	max_health = saved_max
	health = saved_health
	base_movement_speed = saved_speed
	player_moving = saved_moving
	damage_bonus = saved_damage_bonus
	movement_bonus = saved_movement_bonus
	return result

func start_with(weapon_id: String, relic_id: String) -> void:
	loadout = ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, character.equipment_rules if character != null else null)
	if character != null:
		for id in character.starting_weapons:
			for slot in loadout.equipment.size():
				if loadout.equipment[slot] == null and loadout.equip(ContentCatalog.weapon(id), slot): break
	if not weapon_id.is_empty() and not loadout.equipment.is_empty():
		for offset in loadout.equipment.size():
			var slot := loadout.equipment.size() - 1 - offset
			if loadout.equipment[slot] == null and loadout.equip(ContentCatalog.weapon(weapon_id), slot): break
	if character != null:
		for id in character.starting_relics: loadout.add_relic(ContentCatalog.relic(id))
	loadout.add_relic(ContentCatalog.relic(relic_id))
	health = effective_max_health()
	stats_changed.emit()

func equip_weapon(id: String, slot: int) -> bool:
	if not loadout.equip(ContentCatalog.weapon(id), slot):
		return false
	stats_changed.emit()
	return true

func add_relic(id: String) -> bool:
	if not loadout.add_relic(ContentCatalog.relic(id)):
		return false
	health = minf(health, effective_max_health())
	stats_changed.emit()
	return true

func regeneration() -> float:
	return loadout.regeneration()

func stat_value(id: String) -> float:
	return _stat_value(id, {})

func _stat_value(id: String, visiting: Dictionary) -> float:
	if visiting.has(id): return 0.0
	visiting[id] = true
	var value := primary.value(id, loadout, character.growth_modifiers if character != null else null)
	var multiplier := maxf(0.0, 1.0 + float(character.growth_modifiers.get(id)) / 100.0) if character != null and character.growth_modifiers != null else 1.0
	for mod in event_stat_modifiers:
		if str(mod.get("stat", "")) == id:
			value += float(mod.get("amount", 0.0)) * multiplier
	match id:
		"max_hp": value += max_health
		"damage": value += (damage_bonus + loadout.damage_bonus()) * 100.0 * multiplier
		"speed": value += (movement_bonus + loadout.movement_bonus()) * 100.0 * multiplier
	if id == "hp_regeneration" and character != null and character.combat_rules != null:
		value += get_tree().get_nodes_in_group("environment_trees").size() * character.combat_rules.tree_hp_regeneration
	if character != null:
		for bonus in character.equipment_stat_bonuses:
			if bonus == null or bonus.target != id: continue
			var used := 0
			var ids := {}
			for item in loadout.equipment:
				if item != null:
					used += 1
					ids[item.id] = true
			var count: int = used
			if bonus.source == EquipmentStatBonus.Source.DISTINCT_WEAPONS: count = ids.size()
			elif bonus.source == EquipmentStatBonus.Source.EMPTY_SLOTS: count = loadout.equipment.size() - used
			value += count * bonus.amount_per_unit
		for bonus in character.conditional_bonuses:
			if bonus == null or bonus.stat != id: continue
			var matches := (bonus.condition == ConditionalStatBonus.Condition.MOVING and player_moving) or (bonus.condition == ConditionalStatBonus.Condition.STANDING_STILL and not player_moving)
			if bonus.condition == ConditionalStatBonus.Condition.BELOW_HEALTH_FRACTION:
				var threshold_max := max_health + primary.value("max_hp", loadout, character.growth_modifiers)
				if id != "max_hp" and not visiting.has("max_hp"): threshold_max = _stat_value("max_hp", visiting)
				matches = health < maxf(1.0, threshold_max) * bonus.health_fraction
			if matches: value += bonus.amount
		for rule in character.stat_conversions:
			if rule != null and rule.target == id:
				var source := _stat_value(rule.source, visiting)
				value += (floorf(source / rule.source_step) if rule.source_step > 0 else source) * rule.factor
	visiting.erase(id)
	return value

func set_player_moving(value: bool) -> void:
	if player_moving == value: return
	player_moving = value
	stats_changed.emit()

func effective_max_health() -> float:
	return maxf(1.0, stat_value("max_hp"))

func regeneration_interval() -> float:
	var value := stat_value("hp_regeneration")
	return 11.25 / (1.25 + value) if value > 0.0 else INF

func armor_damage_multiplier() -> float:
	var armor := stat_value("armor")
	return 1.0 / (1.0 + armor / 15.0) if armor >= 0.0 else (15.0 - 2.0 * armor) / (15.0 - armor)

func dodge_chance() -> float:
	return clampf(stat_value("dodge") / 100.0, 0.0, combat_rules().dodge_cap)

func combat_rules() -> CharacterCombatRules:
	if character != null and character.combat_rules != null: return character.combat_rules
	return _default_combat_rules

var _default_combat_rules := CharacterCombatRules.new()
var _event_depth := 0
var _event_counts: Dictionary = {}
var _move_distance := 0.0

func trigger_character_event(trigger: CharacterEventEffect.Trigger) -> void:
	if character == null or _event_depth > 0: return
	_event_depth += 1
	for effect in character.event_effects:
		if effect == null or effect.trigger != trigger: continue
		if effect.only_at_full_health and health < effective_max_health(): continue
		var key := effect.get_instance_id()
		_event_counts[key] = int(_event_counts.get(key, 0)) + 1
		if _event_counts[key] % maxi(1, effect.every_n) != 0 or rng.randf() >= effect.probability: continue
		match effect.effect:
			CharacterEventEffect.Effect.ADD_STAT:
				if effect.temporary_until_combat_end:
					primary.temporary[effect.stat] = float(primary.temporary.get(effect.stat, 0.0)) + effect.amount
				else:
					primary.add(effect.stat, effect.amount)
				stats_changed.emit()
			CharacterEventEffect.Effect.HEAL, CharacterEventEffect.Effect.SELF_DAMAGE:
				var player := get_tree().get_first_node_in_group("players")
				if is_instance_valid(player):
					if effect.effect == CharacterEventEffect.Effect.HEAL: player.health.heal(effect.amount)
					else: player.health.take_damage(effect.amount)
			CharacterEventEffect.Effect.DAMAGE_RANDOM_ENEMY:
				var enemies := CombatTargeting.living_enemies(get_tree())
				if not enemies.is_empty():
					var target: Node2D = enemies[rng.randi_range(0, enemies.size() - 1)]
					target.receive_damage(damage_against(target, effect.amount))
			CharacterEventEffect.Effect.GAIN_MATERIALS:
				gain_loot(0, roundi(effect.amount))
	_event_depth -= 1

func finish_combat_events() -> void:
	trigger_character_event(CharacterEventEffect.Trigger.COMBAT_END)
	for id in PlayerPrimaryStats.IDS: primary.temporary[id] = 0.0
	for index in range(event_stat_modifiers.size() - 1, -1, -1):
		var mod: Dictionary = event_stat_modifiers[index]
		if int(mod.get("duration_kind", EventActionData.Duration.EXPEDITION)) == EventActionData.Duration.COMBAT:
			var left := int(mod.get("remaining", 1)) - 1
			if left <= 0:
				event_stat_modifiers.remove_at(index)
			else:
				mod["remaining"] = left
	_event_counts.clear()
	_move_distance = 0.0
	stats_changed.emit()

func register_movement(distance: float) -> void:
	_move_distance += maxf(0.0, distance)
	while _move_distance >= ContentCatalog.PIXELS_PER_UNIT:
		_move_distance -= ContentCatalog.PIXELS_PER_UNIT
		trigger_character_event(CharacterEventEffect.Trigger.MOVE_STEP)

func shop_weapon_price() -> int:
	return maxi(0, roundi(18 * combat_rules().weapon_price_multiplier))

func shop_relic_price(item: RelicData) -> int:
	return maxi(0, roundi(item.base_price * combat_rules().item_price_multiplier))

func damage_against(target: Node2D, amount: float) -> float:
	if target.is_in_group("enemies") and target.data.category in [EnemyData.Category.ELITE, EnemyData.Category.BOSS]:
		return amount * combat_rules().elite_boss_damage_multiplier
	return amount

func effective_weapon_range(data: WeaponData) -> float:
	return maxf(25.0, data.attack_range + (stat_value("weapon_range") + weapon_bonus(data, "weapon_range")) * (0.5 if data.kind == WeaponData.Kind.MELEE else 1.0))

func weapon_bonus(data: WeaponData, stat: String) -> float:
	var result := 0.0
	if character == null: return result
	for bonus in character.weapon_bonuses:
		if bonus != null and data.weapon_tags.has(bonus.tag): result += float(bonus.get(stat))
	return result

func weapon_attack_interval(data: WeaponData) -> float:
	var bonus := (stat_value("attack_speed") + weapon_bonus(data, "attack_speed")) / 100.0
	if data.kind == WeaponData.Kind.MELEE:
		bonus += loadout.melee_speed_multiplier() - 1.0
	var speed_multiplier := 1.0 + bonus if bonus >= 0.0 else 1.0 / (1.0 - bonus)
	var travel_adjustment := (effective_weapon_range(data) - data.attack_range) * 0.001 if data.kind == WeaponData.Kind.MELEE else 0.0
	return maxf(1.0 / 12.0, (data.attack_interval + travel_adjustment) / speed_multiplier)

func weapon_base_damage(data: WeaponData) -> float:
	var stat_id: String = ["melee_damage", "ranged_damage", "elemental_damage"][data.kind]
	return maxf(1.0, (data.damage + stat_value(stat_id) * data.stat_scaling) * maxf(0.0, 1.0 + (stat_value("damage") + weapon_bonus(data, "damage")) / 100.0))

func add_primary_stat(id: String, amount: float) -> bool:
	if not primary.add(id, amount): return false
	health = minf(health, effective_max_health())
	stats_changed.emit()
	return true

func movement_speed() -> float:
	return base_movement_speed * ContentCatalog.PLAYER_STARTING_SPEED_MULTIPLIER * maxf(0.0, 1.0 + stat_value("speed") / 100.0)

func melee_speed_multiplier() -> float:
	return loadout.melee_speed_multiplier()

func experience_needed() -> int:
	return maxi(1, roundi((12 + (level - 1) * 7) * combat_rules().xp_requirement_multiplier))

func gain_loot(xp: int, coins: int) -> void:
	gold = maxi(0, gold + (roundi(coins * combat_rules().material_gain_multiplier) if coins > 0 else coins))
	experience = maxi(0, experience + (roundi(xp * combat_rules().xp_gain_multiplier) if xp > 0 else xp))
	while experience >= experience_needed():
		experience -= experience_needed()
		level += 1
		if combat_rules().gain_weapon_slot_on_level:
			if loadout.equipment.size() < combat_rules().maximum_weapon_slots:
				loadout.equipment.resize(loadout.equipment.size() + 1)
		else: pending_upgrades += 1
		trigger_character_event(CharacterEventEffect.Trigger.LEVEL_UP)
	experience_changed.emit()
	stats_changed.emit()

func finish_wave() -> void:
	completed_waves += 1
	var harvest := int(roundf(stat_value("harvesting")))
	if harvest != 0:
		if expedition == null:
			gain_loot(harvest, harvest)
		if harvest > 0:
			primary.add("harvesting", ceilf(harvest * maxf(0.0, 0.05 + combat_rules().harvesting_growth_bonus)))
	stats_changed.emit()

const EXPEDITION_RARITY_TABLE := {
	1: [0.80, 0.20, 0.00, 0.00, 0.00],
	2: [0.50, 0.35, 0.15, 0.00, 0.00],
	3: [0.25, 0.30, 0.25, 0.15, 0.05]
}
const EXPEDITION_BOSS_RARITY_TABLE := {
	1: [0.60, 0.30, 0.10, 0.00, 0.00],
	2: [0.35, 0.35, 0.22, 0.08, 0.00],
	3: [0.15, 0.25, 0.30, 0.20, 0.10]
}
const REWARD_CELL_GOLD_RANGES := {
	1: Vector2i(20, 25),
	2: Vector2i(30, 40),
	3: Vector2i(45, 60)
}

func effective_harvesting() -> float:
	return clampf(stat_value("harvesting"), -1000.0, 100.0)

func harvesting_item_appear_chance(base_chance: float = 0.5) -> float:
	var h := clampf(stat_value("harvesting"), 0.0, 50.0)
	return clampf(base_chance * (1.0 + h * 0.01), 0.0, 1.0)

func harvesting_rarity_upgrade_chance() -> float:
	var h := clampf(stat_value("harvesting"), 0.0, 100.0)
	return clampf((h - 50.0) * 0.01, 0.0, 0.50) if h > 50.0 else 0.0

func roll_expedition_rarity(is_boss: bool = false, map_level_override: int = -1) -> int:
	var map_lvl := map_level_override if map_level_override > 0 else (expedition.level if expedition != null and expedition.level > 0 else 1)
	map_lvl = clampi(map_lvl, 1, 3)
	var dist: Array = EXPEDITION_BOSS_RARITY_TABLE[map_lvl] if is_boss else EXPEDITION_RARITY_TABLE[map_lvl]
	var roll := rng.randf()
	var cumulative := 0.0
	var tier := 1
	for i in dist.size():
		cumulative += float(dist[i])
		if roll < cumulative:
			tier = i + 1
			break
	var upgrade_chance := harvesting_rarity_upgrade_chance()
	if upgrade_chance > 0.0 and rng.randf() < upgrade_chance:
		tier = mini(5, tier + 1)
	return tier

func roll_rarity(wave: int, is_boss: bool = false) -> int:
	if expedition != null and expedition.level > 0:
		return roll_expedition_rarity(is_boss)
	var luck_factor := maxf(0.0, 1.0 + stat_value("luck") / 100.0)
	var tier2 := minf(0.60, maxf(0.0, wave - 1) * 0.06 * luck_factor)
	var tier3 := minf(0.25, maxf(0.0, wave - 3) * 0.02 * luck_factor)
	var tier4 := minf(0.08, maxf(0.0, wave - 7) * 0.0023 * luck_factor)
	var roll := rng.randf()
	if roll < tier4: return 4
	if roll < tier3: return 3
	if roll < tier2: return 2
	return 1

func roll_shop_items(ids: PackedStringArray, equipment: bool, count: int = 3, is_boss: bool = false) -> PackedStringArray:
	var remaining := ids.duplicate()
	if equipment:
		for id in ids:
			var permitted := false
			for slot in loadout.equipment.size():
				if loadout.can_equip_weapon(ContentCatalog.weapon(id), slot): permitted = true
			if not permitted: remaining.remove_at(remaining.find(id))
	else:
		for id in ids:
			var relic := ContentCatalog.relic(id)
			var forbidden := false
			if relic != null:
				for tag in relic.tags:
					if combat_rules().excluded_relic_tags.has(tag): forbidden = true
			if forbidden or not loadout.can_add_relic(relic): remaining.remove_at(remaining.find(id))
	var result := PackedStringArray()
	for i in mini(count, remaining.size()):
		var tier := roll_rarity(maxi(1, completed_waves), is_boss)
		var candidates := PackedStringArray()
		for priority in range(5):
			var wanted := tier - priority
			if wanted < 1: continue
			for id in remaining:
				var item: ItemDefinition = ContentCatalog.weapon(id) if equipment else ContentCatalog.relic(id)
				if item != null and item.rarity == wanted: candidates.append(id)
			if not candidates.is_empty(): break
		if candidates.is_empty(): candidates = remaining.duplicate()
		var chosen := candidates[rng.randi_range(0, candidates.size() - 1)]
		result.append(chosen)
		remaining.remove_at(remaining.find(chosen))
	return result

func apply_upgrade(id: String) -> void:
	if pending_upgrades <= 0:
		return
	var matched_offer: Dictionary = {}
	for offer in upgrade_offers:
		if str(offer.get("id", "")) == id:
			matched_offer = offer
			break
	if matched_offer.has("bonuses") and matched_offer["bonuses"] is Dictionary:
		var bonuses: Dictionary = matched_offer["bonuses"]
		for stat_id in bonuses.keys():
			var amt := float(bonuses[stat_id])
			primary.add(str(stat_id), amt)
			if str(stat_id) == "max_hp" and amt > 0.0:
				health = minf(health + amt, effective_max_health())
	elif PrimaryStatUpgrades.ORGANS.has(id):
		var bonuses := PrimaryStatUpgrades.organ_bonuses_for_tier(id, int(matched_offer.get("tier", 1)))
		for stat_id in bonuses.keys():
			var amt := float(bonuses[stat_id])
			primary.add(str(stat_id), amt)
			if str(stat_id) == "max_hp" and amt > 0.0:
				health = minf(health + amt, effective_max_health())
	elif id == "power":
		damage_bonus += 0.15
	elif id == "vitality":
		primary.add("max_hp", 15.0)
		health = minf(health + 15.0, effective_max_health())
	elif id == "speed" and matched_offer.is_empty():
		movement_bonus += 0.05
	elif PrimaryStatUpgrades.VALUES.has(id):
		var amount: float = float(matched_offer.get("amount", PrimaryStatUpgrades.VALUES[id]))
		primary.add(id, amount)
	else:
		return
	pending_upgrades -= 1
	health = minf(health, effective_max_health())
	stats_changed.emit()

func move_to_cell(id: String) -> bool:
	if not available.has(id):
		return false
	current_cell_id = id
	if expedition != null:
		expedition.exploration.reveal_around(current_map(), id)
	stats_changed.emit()
	return true

# --- Map / dream expedition ---------------------------------------------------

func current_map() -> MapData:
	if expedition != null and expedition.map != null:
		return expedition.map
	return ContentCatalog.map()

func begin_expedition() -> void:
	expedition = ExpeditionState.new()
	completed_cells.clear()
	completed_event_actions.clear()
	combats_completed_in_map = 0
	triggered_battle_cells_in_map.clear()
	current_cell_id = ""
	won_run = false

## Generates the next map with the chosen difficulty, resets exploration and
## position, and restores full health as required when entering a new map.
func enter_expedition_map(difficulty_id: String) -> bool:
	if expedition == null or not expedition.enter_map(difficulty_id, rng):
		return false
	for index in range(event_stat_modifiers.size() - 1, -1, -1):
		var mod: Dictionary = event_stat_modifiers[index]
		if int(mod.get("duration_kind", EventActionData.Duration.EXPEDITION)) == EventActionData.Duration.MAP:
			event_stat_modifiers.remove_at(index)
	completed_cells.clear()
	completed_event_actions.clear()
	combats_completed_in_map = 0
	triggered_battle_cells_in_map.clear()
	current_cell_id = expedition.map.starting_cell_id
	completed_cells.append(current_cell_id)
	expedition.exploration.reveal_around(expedition.map, current_cell_id)
	health = effective_max_health()
	stats_changed.emit()
	return true

func is_cell_revealed(id: String) -> bool:
	return expedition == null or expedition.exploration.is_revealed(id)

## Map level multiplier for enemy health, damage, experience and materials.
func map_level_multiplier() -> float:
	return expedition.level_multiplier() if expedition != null else 1.0

## Linear growth multiplier (+5% per prior combat cell in the current map) for enemy HP and attack.
func combat_cell_stat_multiplier() -> float:
	return 1.0 + float(maxi(0, combats_completed_in_map)) * COMBAT_CELL_STAT_GROWTH

## Linear growth multiplier (+5% per prior combat cell in the current map) for enemy XP and gold/fragment drops.
func combat_cell_reward_multiplier() -> float:
	return 1.0 + float(maxi(0, combats_completed_in_map)) * COMBAT_CELL_REWARD_GROWTH

## Total enemy HP & damage multiplier combining map base level multiplier and per-combat-cell linear growth.
func enemy_stat_multiplier() -> float:
	return map_level_multiplier() * combat_cell_stat_multiplier()

## Total enemy XP & gold/fragment reward multiplier combining map base level multiplier and per-combat-cell linear growth.
func enemy_reward_multiplier() -> float:
	return map_level_multiplier() * combat_cell_reward_multiplier()

## Scene to open after a battle/shop: next-map selection once a BOSS map is cleared.
func route_scene() -> String:
	if expedition != null and expedition.needs_map_selection():
		return "res://scenes/map/map_select.tscn"
	var cell := current_map().find_cell(current_cell_id)
	if cell != null and cell.kind == MapCellData.Kind.EVENT and not completed_cells.has(current_cell_id):
		return "res://scenes/map/cell_resolution.tscn"
	return "res://scenes/map/map_screen.tscn"

## Hook for future abilities that move the party. Reveals around the new cell;
## resolving the destination's content remains the caller's responsibility.
func relocate_party(id: String, mark_completed: bool = false) -> bool:
	if current_map().find_cell(id) == null:
		return false
	current_cell_id = id
	if mark_completed and not completed_cells.has(id):
		completed_cells.append(id)
	if expedition != null:
		expedition.exploration.reveal_around(current_map(), id)
	stats_changed.emit()
	return true

## Hook for future abilities that widen the revealed range (in route steps).
func add_reveal_radius(amount: int) -> void:
	if expedition == null:
		return
	expedition.exploration.reveal_radius_bonus += amount
	expedition.exploration.reveal_around(current_map(), current_cell_id)

func begin_cell_encounter() -> bool:
	var cell := current_map().find_cell(current_cell_id)
	if cell == null or not cell.is_battle() or not cell.validation_errors().is_empty():
		return false
	if not triggered_battle_cells_in_map.has(cell.id):
		combats_completed_in_map = maxi(combats_completed_in_map, triggered_battle_cells_in_map.size())
		triggered_battle_cells_in_map.append(cell.id)
	else:
		combats_completed_in_map = maxi(combats_completed_in_map, triggered_battle_cells_in_map.find(cell.id))
	active_encounter = cell.encounter
	encounter_from_event = false
	active_event_action_id = ""
	return true

func begin_event_encounter(action: EventActionData) -> bool:
	var cell := current_map().find_cell(current_cell_id)
	if cell == null or cell.kind != MapCellData.Kind.EVENT:
		return false
	if action == null or action.kind != EventActionData.Kind.ENCOUNTER or not action.validation_errors().is_empty():
		return false
	if event_action_completed(action.id):
		return false
	active_encounter = action.encounter
	encounter_from_event = true
	active_event_action_id = action.id
	return true

func finish_encounter() -> void:
	if encounter_from_event:
		mark_event_action_completed(active_event_action_id)
	else:
		complete_current_cell()
	active_encounter = null
	encounter_from_event = false
	active_event_action_id = ""

func complete_current_cell() -> void:
	var cell := current_map().find_cell(current_cell_id)
	if cell == null:
		return
	if not completed_cells.has(cell.id):
		completed_cells.append(cell.id)
	if cell.is_battle():
		if not triggered_battle_cells_in_map.has(cell.id):
			triggered_battle_cells_in_map.append(cell.id)
		combats_completed_in_map = maxi(combats_completed_in_map, triggered_battle_cells_in_map.size())
	if cell.kind == MapCellData.Kind.BOSS_BATTLE:
		if expedition != null and not expedition.is_final_map():
			expedition.map_cleared = true
		else:
			won_run = true
	stats_changed.emit()

func event_action_completed(id: String) -> bool:
	return completed_event_actions.has(current_cell_id + ":" + id)

func mark_event_action_completed(id: String) -> void:
	var key := current_cell_id + ":" + id
	if not completed_event_actions.has(key):
		completed_event_actions.append(key)

# --- Dream Expedition Combat Economy, Loot, Events & Co-op Arbitration --------

func reset_combat_accumulators() -> void:
	combat_pending_xp = 0
	combat_base_fragments = 0
	pending_combat_loot.clear()

func record_combat_enemy_xp(amount: int) -> void:
	if amount > 0:
		combat_pending_xp += amount

func collect_combat_fragments(base_fragments: int) -> void:
	if base_fragments > 0:
		combat_base_fragments += base_fragments

func calculate_fragments_with_harvesting(base_fragments: int = -1) -> int:
	var raw := combat_base_fragments if base_fragments < 0 else base_fragments
	if raw <= 0:
		return 0
	var harvest_pct := maxf(-1.0, effective_harvesting() * 0.01)
	return maxi(0, floori(float(raw) * (1.0 + harvest_pct)))

func settle_combat_economy(encounter_kind: int = 0) -> Dictionary:
	var total_fragments := calculate_fragments_with_harvesting(combat_base_fragments)
	var converted_gold := total_fragments / 10
	var xp_earned := combat_pending_xp
	combat_base_fragments = 0
	combat_pending_xp = 0
	gain_loot(xp_earned, converted_gold)
	generate_post_battle_loot(encounter_kind)
	return {"xp": xp_earned, "fragments": total_fragments, "gold": converted_gold}

func generate_post_battle_loot(encounter_kind: int) -> Array[Resource]:
	pending_combat_loot.clear()
	var is_boss := encounter_kind == EncounterData.Kind.BOSS
	var equip_count := 2 if is_boss else (1 if encounter_kind == EncounterData.Kind.ELITE else 0)
	var relic_count := 2 if is_boss else (1 if encounter_kind == EncounterData.Kind.ELITE else 0)
	if equip_count > 0:
		for id in roll_shop_items(ContentCatalog.weapon_ids(), true, equip_count, is_boss):
			var w := ContentCatalog.weapon(id)
			if w != null: pending_combat_loot.append(w)
	if relic_count > 0:
		for id in roll_shop_items(ContentCatalog.relic_ids(), false, relic_count, is_boss):
			var r := ContentCatalog.relic(id)
			if r != null: pending_combat_loot.append(r)
	return pending_combat_loot

func abandon_loot_to_shared_pool(item: Resource) -> void:
	if item != null:
		shared_loot_pool.append(item)
	pending_combat_loot.erase(item)

func roll_reward_cell_gold(map_level_override: int = -1) -> int:
	var lvl := map_level_override if map_level_override > 0 else (expedition.level if expedition != null and expedition.level > 0 else 1)
	lvl = clampi(lvl, 1, 3)
	var bounds: Vector2i = REWARD_CELL_GOLD_RANGES[lvl]
	return rng.randi_range(bounds.x, bounds.y)

func generate_reward_cell_candidates() -> Array[Resource]:
	var result: Array[Resource] = []
	var chance := harvesting_item_appear_chance(0.5)
	var has_equip := rng.randf() < chance
	var has_relic := rng.randf() < chance
	if not has_equip and not has_relic:
		if rng.randf() < 0.5:
			has_equip = true
		else:
			has_relic = true
	if has_equip:
		var w_ids := roll_shop_items(ContentCatalog.weapon_ids(), true, 1, false)
		if not w_ids.is_empty():
			result.append(ContentCatalog.weapon(w_ids[0]))
	if has_relic:
		var r_ids := roll_shop_items(ContentCatalog.relic_ids(), false, 1, false)
		if not r_ids.is_empty():
			result.append(ContentCatalog.relic(r_ids[0]))
	return result

func apply_event_health_cost(cost: float) -> void:
	if cost <= 0.0:
		return
	health = maxf(1.0, health - cost)
	stats_changed.emit()

func add_event_stat_modifier(stat: String, amount: float, duration_kind: int = EventActionData.Duration.EXPEDITION, combats: int = 1) -> void:
	if not PlayerPrimaryStats.IDS.has(stat) or is_zero_approx(amount):
		return
	event_stat_modifiers.append({
		"stat": stat,
		"amount": amount,
		"duration_kind": duration_kind,
		"remaining": maxi(1, combats)
	})
	health = minf(health, effective_max_health())
	stats_changed.emit()

func can_pay_event_action(action: EventActionData) -> bool:
	if action == null:
		return false
	if action.gold_cost > 0 and gold < action.gold_cost:
		return false
	if action.requires_sacrifice_equipment:
		var has_weapon := false
		for item in loadout.equipment:
			if item != null:
				has_weapon = true
				break
		if not has_weapon:
			return false
	return true

## Brainwave symbol cyclic arbitration (0 beats 1, 1 beats 2, 2 beats 0).
## Supports up to 3 rounds on ties before randomizing among tied choices.
func resolve_brainwave_vote(choices: Dictionary, symbol_provider: Callable = Callable()) -> Variant:
	if choices.is_empty():
		return null
	var unique_targets := {}
	for player_id in choices:
		unique_targets[choices[player_id]] = true
	if unique_targets.size() == 1:
		return unique_targets.keys()[0]
	var contenders: Array = choices.keys()
	for _round in 3:
		var symbols := {}
		var present := {}
		for pid in contenders:
			var sym: int = int(symbol_provider.call(pid, _round)) % 3 if symbol_provider.is_valid() else rng.randi_range(0, 2)
			symbols[pid] = sym
			present[sym] = true
		if present.size() == 2:
			var s_keys := present.keys()
			var a: int = int(s_keys[0])
			var b: int = int(s_keys[1])
			var winning_sym: int = a if (a + 1) % 3 == b else b
			var next_contenders: Array = []
			for pid in contenders:
				if symbols[pid] == winning_sym:
					next_contenders.append(pid)
			contenders = next_contenders
			var remaining_targets := {}
			for pid in contenders:
				remaining_targets[choices[pid]] = true
			if remaining_targets.size() == 1:
				return remaining_targets.keys()[0]
	var pick_pid = contenders[rng.randi_range(0, contenders.size() - 1)]
	return choices[pick_pid]

## Shop gold gifting: 10% fee rounded up (min 1 gold), once per teammate per shop phase.
func gift_fee(amount: int) -> int:
	return maxi(1, ceili(float(amount) * 0.10)) if amount > 0 else 0

func can_gift_gold(teammate_id: String, amount: int) -> bool:
	if amount <= 0 or teammate_id.is_empty() or gifted_teammates_this_shop.has(teammate_id):
		return false
	return gold >= amount + gift_fee(amount)

func gift_gold_to_teammate(teammate_id: String, amount: int) -> Dictionary:
	if not can_gift_gold(teammate_id, amount):
		return {"ok": false, "fee": 0, "received": 0}
	var fee := gift_fee(amount)
	gold -= (amount + fee)
	gifted_teammates_this_shop[teammate_id] = amount
	stats_changed.emit()
	return {"ok": true, "fee": fee, "received": amount}

func go_to(path: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(path)

func _register_inputs() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"skill": [KEY_Q], "character_skill": [KEY_E, KEY_SPACE], "pause_game": [KEY_ESCAPE]
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
