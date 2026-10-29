extends SceneTree

var state: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _enemy(arena: Node, point: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = arena.player
	unit.position = point
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.entered_arena = true
	return unit

func _run() -> void:
	state = root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	state.loadout.clear_relics()
	check(PlayerPrimaryStats.IDS.size() == 15 and not PlayerPrimaryStats.IDS.has("engineering"), "All fifteen requested primary stats are present without engineering")
	check(state.effective_max_health() == 100 and state.movement_speed() == 180 and state.stat_value("luck") == 0, "Existing baseline player health and speed are preserved")
	var melee := ContentCatalog.weapon("needle")
	var ranged := ContentCatalog.weapon("pistol")
	var spell := ContentCatalog.weapon("arcane_staff")
	state.add_primary_stat("melee_damage", 3)
	state.add_primary_stat("ranged_damage", 5)
	state.add_primary_stat("elemental_damage", 7)
	state.add_primary_stat("damage", 50)
	check(is_equal_approx(state.weapon_base_damage(melee), 57.0), "Melee damage adds its stat before global damage percentage")
	check(is_equal_approx(state.weapon_base_damage(ranged), 28.5), "Ranged stat scales ranged weapon damage")
	check(is_equal_approx(state.weapon_base_damage(spell), 63.0), "Elemental stat scales spell weapon damage")
	var scaled := melee.duplicate() as WeaponData
	scaled.stat_scaling = 0.5
	check(is_equal_approx(state.weapon_base_damage(scaled), 54.75), "Weapon-configured scaling coefficient is applied")
	state.add_primary_stat("damage", -200)
	check(state.weapon_base_damage(melee) == 1, "Negative damage respects minimum one damage")
	state.primary.reset()
	state.add_primary_stat("weapon_range", 100)
	check(state.effective_weapon_range(melee) == 118 and state.effective_weapon_range(ranged) == 600 and state.effective_weapon_range(spell) == 320, "Range adds half to melee and full to ranged/spell")
	check(state.weapon_attack_interval(melee) > melee.attack_interval, "Increasing melee range slightly increases swing interval")
	state.add_primary_stat("weapon_range", -1100)
	check(state.effective_weapon_range(melee) == 25 and state.effective_weapon_range(ranged) == 25, "Negative range has a minimum weapon range")
	state.primary.reset()
	state.add_primary_stat("attack_speed", 100)
	check(is_equal_approx(state.weapon_attack_interval(melee), melee.attack_interval / 2.0), "Positive global attack speed affects melee")
	check(is_equal_approx(state.weapon_attack_interval(ranged), ranged.attack_interval / 2.0) and is_equal_approx(state.weapon_attack_interval(spell), spell.attack_interval / 2.0), "Global attack speed affects ranged and spell weapons")
	state.add_primary_stat("attack_speed", -150)
	check(is_equal_approx(state.weapon_attack_interval(spell), spell.attack_interval * 1.5), "Negative attack speed increases cooldown without division by zero")
	state.primary.reset()
	state.add_primary_stat("armor", 15)
	check(is_equal_approx(state.armor_damage_multiplier(), 0.5), "Positive armor uses reference damage reduction curve")
	state.add_primary_stat("armor", -30)
	check(is_equal_approx(state.armor_damage_multiplier(), 1.5), "Negative armor increases damage with reference curve")
	state.add_primary_stat("dodge", 100)
	check(is_equal_approx(state.dodge_chance(), 0.6), "Dodge is capped at 60 percent")
	state.add_primary_stat("dodge", -200)
	check(state.dodge_chance() == 0, "Negative dodge acts as zero")
	state.primary.reset()
	state.add_primary_stat("speed", -100)
	check(state.movement_speed() == 0, "Speed at minus 100 percent stops movement")
	state.primary.reset()
	var relic := RelicData.new()
	relic.id = "stat_test"
	relic.display_name = "Stat Test"
	relic.primary_stats = PrimaryStatsData.new()
	relic.primary_stats.max_hp = 20
	relic.primary_stats.luck = 30
	state.loadout.add_relic(relic)
	check(state.effective_max_health() == 120 and state.stat_value("luck") == 30, "Equipped relic contributes primary stats")
	state.loadout.clear_relics()
	state.primary.reset()
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena: Node = current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	arena.player.controls.set_physics_process(false)
	var player: Node2D = arena.player
	player.health.initialize(100, 50)
	state.add_primary_stat("armor", 15)
	player.receive_damage(10)
	check(player.health.current == 45, "Player takes armor-reduced damage in actual combat")
	player.invulnerability = 0
	state.add_primary_stat("armor", -30)
	player.receive_damage(10)
	check(player.health.current == 30, "Negative armor increases actual damage")
	state.primary.reset()
	state.add_primary_stat("crit_chance", 100)
	state.add_primary_stat("life_steal", 100)
	player.health.initialize(100, 50)
	var target := _enemy(arena, player.global_position + Vector2(45, 0))
	target.health.initialize(100)
	player.apply_weapon_hit(target, melee)
	check(is_equal_approx(target.health.current, 47.5) and player.health.current == 51, "Guaranteed critical weapon hit deals multiplied damage and heals one")
	player.apply_weapon_hit(target, melee)
	check(player.health.current == 51, "Life-steal global cooldown prevents repeated healing within 0.1 seconds")
	for i in 9: await physics_frame
	var another := _enemy(arena, player.global_position + Vector2(50, 10))
	another.health.initialize(100)
	player.apply_weapon_hit(another, melee)
	check(player.health.current == 52, "Life steal can activate again after its timer")
	state.primary.reset()
	state.add_primary_stat("hp_regeneration", 10)
	check(is_equal_approx(state.regeneration_interval(), 1.0) and is_equal_approx(player.regen_timer.wait_time, 1.0), "Ten regeneration points heal one HP each second")
	player.health.initialize(100, 40)
	paused = true
	var remaining: float = player.regen_timer.time_left
	for i in 10: await physics_frame
	check(is_equal_approx(player.regen_timer.time_left, remaining) and player.health.current == 40, "Regeneration timer pauses with combat")
	paused = false
	for i in 70: await physics_frame
	check(player.health.current == 41, "Primary regeneration heals one HP on its timer")
	state.primary.reset()
	state.stats_changed.emit()
	state.rng.seed = 123456
	var normal_high := 0
	for i in 4000:
		if state.roll_rarity(4) >= 2: normal_high += 1
	state.add_primary_stat("luck", 100)
	state.rng.seed = 123456
	var lucky_high := 0
	for i in 4000:
		if state.roll_rarity(4) >= 2: lucky_high += 1
	check(lucky_high > normal_high, "Luck increases upgrade and shop rarity probabilities with identical random draws")
	var offers := PrimaryStatUpgrades.create_offers(state)
	check(offers.size() == 4, "Level offers display four distinct brain organs out of the five")
	var seen_organs := {}
	for opt in offers:
		seen_organs[opt.id] = true
		check(PrimaryStatUpgrades.ORGANS.has(opt.id) and opt.stats.size() == 3 and opt.bonuses.size() == 3 and opt.tier >= 1 and opt.tier <= 5, "Brain organ offer contains three governed stats and independent tier 1-5")
	check(seen_organs.size() == 4, "Four offered brain organs are distinct")
	var w_low := PrimaryStatUpgrades.level_rarity_weights(1, 0.0)
	var w_high := PrimaryStatUpgrades.level_rarity_weights(15, 0.0)
	check(w_low[0] > w_high[0] and w_high[3] > w_low[3] and w_high[4] > w_low[4], "1-5 rarity probabilities shift upward across player level brackets")
	state.primary.reset()
	state.upgrade_offers = [offers[0]]
	state.pending_upgrades = 1
	state.apply_upgrade(offers[0].id)
	var all_three_applied := true
	for stat_id in offers[0].bonuses.keys():
		var expected_val := float(offers[0].bonuses[stat_id])
		var actual_val := state.effective_max_health() - 100.0 if str(stat_id) == "max_hp" else state.stat_value(str(stat_id))
		if not is_equal_approx(actual_val, expected_val):
			all_three_applied = false
	check(all_three_applied and state.pending_upgrades == 0, "Selecting a brain organ upgrade applies all three governed primary stats at its tier")
	state.primary.reset()
	state.upgrade_offers.clear()
	state.upgrade_offers.append({"id": "crit_chance", "amount": 6.0, "tier": 2})
	state.pending_upgrades = 1
	state.apply_upgrade("crit_chance")
	check(state.stat_value("crit_chance") == 6 and state.pending_upgrades == 0, "Selected rarity's primary attribute bonus is applied")
	var drops := _enemy(arena, player.global_position + Vector2(100, 0))
	drops.data = drops.data.duplicate(true)
	drops.data.consumable_drop_chance = 0.5
	drops.data.relic_drop_chance = 0.5
	var before_pickups: int = arena.get_node("Pickups").get_child_count()
	arena._enemy_defeated(drops)
	check(arena.get_node("Pickups").get_child_count() == before_pickups + 3, "Luck increases actual consumable and relic-crate drop chances")
	var crates := 0
	var consumables := 0
	for pickup in arena.get_node("Pickups").get_children():
		if pickup.is_relic_crate: crates += 1
		if pickup.heal_value > 0: consumables += 1
	check(crates == 1 and consumables == 1, "Different bonus drops create a relic crate and healing consumable")
	player.health.initialize(100, 40)
	for pickup in arena.get_node("Pickups").get_children():
		if pickup.heal_value > 0: pickup.collect()
	check(player.health.current == 43, "Healing consumable restores health when collected")
	var relic_count: int = state.loadout.relics.size()
	for pickup in arena.get_node("Pickups").get_children():
		if pickup.is_relic_crate: pickup.collect()
	check(state.loadout.relics.size() == relic_count + 1, "Relic crate awards a saved player relic")
	state.loadout.clear_relics()
	for pickup in arena.get_node("Pickups").get_children(): pickup.queue_free()
	for unit in get_nodes_in_group("enemies"):
		unit.remove_from_group("enemies")
		unit.queue_free()
	await process_frame
	state.primary.reset()
	state.completed_waves = 0
	state.gold = 0
	state.experience = 0
	state.pending_upgrades = 0
	state.add_primary_stat("harvesting", 5)
	var rule := GroupSpawnSchedule.new()
	rule.group = load("res://resources/groups/guard.tres")
	var encounter := EncounterData.new()
	encounter.preparation_time = 0.05
	encounter.group_interval = 0.15
	encounter.schedules.append(rule)
	arena.director.encounter = encounter
	arena.director.begin()
	for i in 35: await physics_frame
	var group1: Node2D
	var group2: Node2D
	for unit in get_nodes_in_group("enemies"):
		if unit.get_meta("group_index", 0) == 1: group1 = unit
		if unit.get_meta("group_index", 0) == 2: group2 = unit
	check(is_instance_valid(group1) and is_instance_valid(group2) and state.completed_waves == 0, "Overlapping groups do not pay harvesting before being cleared")
	if is_instance_valid(group1) and is_instance_valid(group2):
		group2.receive_damage(9999)
		check(state.gold == 5 and state.experience == 5 and state.stat_value("harvesting") == 6 and state.completed_waves == 1, "Clearing one overlapping group pays harvest once and grows it by 5 percent")
		group1.receive_damage(9999)
		check(state.gold == 11 and state.experience == 11 and state.stat_value("harvesting") == 7 and state.completed_waves == 2, "Second group independently pays the increased harvest")
	print("PRIMARY STATS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
