extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	var fixture := CharacterData.new()
	fixture.primary_stats = PrimaryStatsData.new()
	fixture.primary_stats.ranged_damage = 2
	fixture.growth_modifiers = PrimaryStatsData.new()
	fixture.growth_modifiers.ranged_damage = 50
	state.character = fixture
	state.primary.reset(fixture.primary_stats)
	state.add_primary_stat("ranged_damage", 4)
	check(is_equal_approx(state.stat_value("ranged_damage"), 8), "Growth multiplier applies to later gains but not starting stats")
	var conversion := StatConversionData.new()
	conversion.source = "ranged_damage"
	conversion.target = "melee_damage"
	conversion.factor = 2
	fixture.stat_conversions.append(conversion)
	check(is_equal_approx(state.stat_value("melee_damage"), 16), "Stat conversion uses current source attribute")
	state.add_primary_stat("ranged_damage", 2)
	check(is_equal_approx(state.stat_value("melee_damage"), 22), "Converted stat updates as the source changes")
	var conditional := ConditionalStatBonus.new()
	conditional.stat = "damage"
	conditional.condition = ConditionalStatBonus.Condition.MOVING
	conditional.amount = 40
	fixture.conditional_bonuses.append(conditional)
	check(state.stat_value("damage") == 0, "Moving bonus is inactive while standing")
	state.set_player_moving(true)
	check(state.stat_value("damage") == 40, "Moving activates the conditional bonus")
	var rules := CharacterEquipmentRules.new()
	rules.slots = 1
	rules.allow_melee = false
	rules.allow_duplicates = false
	var loadout := ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, rules)
	check(loadout.equipment.size() == 1 and not loadout.equip(ContentCatalog.weapon("needle"), 0), "Slot count and disallowed weapon type are enforced")
	check(loadout.equip(ContentCatalog.weapon("pistol"), 0), "Allowed weapon may be equipped")
	rules.slots = 2
	loadout = ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, rules)
	check(loadout.equip(ContentCatalog.weapon("pistol"), 0) and not loadout.equip(ContentCatalog.weapon("pistol"), 1), "Duplicate restriction applies across slots")
	fixture.combat_rules = CharacterCombatRules.new()
	fixture.combat_rules.dodge_cap = 0.9
	state.add_primary_stat("dodge", 80)
	check(is_equal_approx(state.dodge_chance(), 0.8), "Character-specific dodge cap is applied")
	fixture.combat_rules.item_price_multiplier = 0.5
	check(state.shop_relic_price(ContentCatalog.relic("brotato_bat")) == 10, "Character item price rule affects shop price")
	fixture.combat_rules.xp_gain_multiplier = 2
	state.experience = 0
	state.level = 1
	state.gain_loot(4, 0)
	check(state.experience == 8, "Experience gain multiplier is applied")
	var effect := CharacterEventEffect.new()
	effect.trigger = CharacterEventEffect.Trigger.DODGED
	effect.stat = "armor"
	effect.amount = 3
	effect.temporary_until_combat_end = true
	fixture.event_effects.append(effect)
	state.trigger_character_event(CharacterEventEffect.Trigger.DODGED)
	check(state.stat_value("armor") == 3, "Event applies temporary attribute bonus")
	state.finish_combat_events()
	check(state.stat_value("armor") == 0, "Temporary bonus expires at combat end")
	state.new_run()
	state.select_character("one_armed")
	state.start_with("needle", "seed")
	check(state.loadout.equipment.size() == 1 and state.weapons == ["needle"] and state.stat_value("attack_speed") == 200, "One Armed uses its one weapon slot and initial attack speed")
	state.add_primary_stat("damage", 5)
	check(state.stat_value("damage") == 10, "One Armed doubles damage growth")
	var before_id: String = state.character_id
	var preview: Dictionary = state.preview_character("hunter")
	check(preview.weapon_range == 100 and preview.damage == 10 and state.character_id == before_id, "Character preview includes conversions and does not mutate run state")
	state.select_character("ranger")
	state.start_with("pistol", "seed")
	check(state.weapons == ["pistol", "pistol"] and not state.equip_weapon("needle", 0), "Ranger starts with fixed pistol and rejects melee weapons")
	state.add_primary_stat("ranged_damage", 4)
	check(state.stat_value("ranged_damage") == 6, "Ranger's ranged damage growth is increased")
	state.select_character("multitasker")
	state.start_with("needle", "seed")
	check(state.loadout.equipment.size() == 12 and state.stat_value("damage") == 15, "Multitasker has twelve slots and counts its starting weapon")
	state.equip_weapon("pistol", 0)
	check(state.stat_value("damage") == 10, "Per-weapon bonus updates after equipping another weapon")
	state.select_character("gladiator")
	state.start_with("needle", "seed")
	check(state.stat_value("attack_speed") == -20 and not state.equip_weapon("pistol", 0), "Gladiator counts distinct weapons and prohibits ranged weapons")
	state.equip_weapon("cleaver", 0)
	check(state.stat_value("attack_speed") == 0, "A second distinct weapon changes the calculated bonus")
	var tagged := CharacterWeaponBonus.new()
	tagged.tag = "Precise"
	tagged.attack_speed = 50
	state.character.weapon_bonuses.append(tagged)
	check(state.weapon_bonus(ContentCatalog.weapon("needle"), "attack_speed") == 50 and state.weapon_bonus(ContentCatalog.weapon("cleaver"), "attack_speed") == 0, "Weapon tag bonus applies only to matching weapons")
	var walking := CharacterEventEffect.new()
	walking.trigger = CharacterEventEffect.Trigger.MOVE_STEP
	walking.effect = CharacterEventEffect.Effect.GAIN_MATERIALS
	walking.every_n = 10
	walking.amount = 5
	state.character.event_effects.append(walking)
	state.gold = 0
	state.register_movement(240)
	check(state.gold == 5, "Moving ten units triggers the configured material reward")
	state.select_character("jack")
	check(is_equal_approx(state.combat_rules().enemy_health_multiplier, 2.75) and is_equal_approx(state.combat_rules().elite_boss_damage_multiplier, 2.25) and state.combat_rules().enemy_material_multiplier == 3, "Jack configures elite damage and enemy modifiers")
	state.new_run()
	state.select_character("baby")
	state.start_with("needle", "seed")
	state.gain_loot(state.experience_needed(), 0)
	check(state.loadout.equipment.size() == 2 and state.pending_upgrades == 0, "Baby gains a weapon slot rather than a stat selection on leveling")
	state.new_run()
	state.select_character("hiker")
	state.start_with("needle", "seed")
	state.register_movement(80 * ContentCatalog.PIXELS_PER_UNIT)
	check(state.gold == 40 and state.effective_max_health() == 101, "Hiker receives separate material and health rewards at the configured movement intervals")
	state.new_run()
	state.select_character("farmer")
	state.start_with("needle", "seed")
	state.trigger_character_event(CharacterEventEffect.Trigger.CONSUMABLE_PICKUP)
	check(state.stat_value("harvesting") == 21, "Farmer gains harvesting from a consumable at full health")
	state.health = 50
	state.trigger_character_event(CharacterEventEffect.Trigger.CONSUMABLE_PICKUP)
	check(state.stat_value("harvesting") == 21, "Farmer does not gain harvesting when below full health")
	state.finish_wave()
	check(state.stat_value("harvesting") == 23, "Farmer's extra harvesting growth is applied")
	state.new_run()
	state.select_character("wounded")
	state.start_with("needle", "seed")
	var offers: PackedStringArray = state.roll_shop_items(PackedStringArray(["brotato_broken_mouth", "brotato_bat", "brotato_coffee"]), false, 3)
	check(offers == PackedStringArray(["brotato_coffee"]), "Wounded excludes health and lifesteal relics from random offers")
	state.new_run()
	state.select_character("mutant")
	check(is_equal_approx(state.combat_rules().xp_requirement_multiplier, 0.34) and is_equal_approx(state.combat_rules().item_price_multiplier, 1.5), "Mutant configures experience and item price")
	state.new_run()
	state.select_character("knight")
	state.start_with("arcane_staff", "seed")
	check(state.stat_value("armor") == 3 and state.stat_value("melee_damage") == 6 and not state.loadout.can_equip_weapon(ContentCatalog.weapon("pistol"), 0), "Knight converts armor and forbids ranged equipment")
	state.new_run()
	state.select_character("golem")
	state.start_with("needle", "seed")
	check(state.effective_max_health() == 120 and not state.combat_rules().can_heal, "Golem starts with extra health and cannot heal")
	state.health = 59
	check(state.stat_value("attack_speed") == 40 and state.stat_value("speed") == 20, "Golem receives its low-health bonuses")
	print("CHARACTER RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

