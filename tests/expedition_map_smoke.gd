extends SceneTree

var failures: int = 0
var checks: int = 0
var state: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _scene(path: String) -> Node:
	paused = false
	change_scene_to_file(path)
	await process_frame
	await process_frame
	return current_scene

func _run() -> void:
	state = root.get_node("RunState")
	_check_templates_and_difficulties()
	_check_generator_invariants()
	await _check_expedition_progression_and_ui()
	await _check_level_multipliers()
	_check_rarity_tables_and_harvesting()
	await _check_fragments_and_combat_settlement()
	await _check_reward_cell_and_boss_loot()
	await _check_event_rules_and_durations()
	await _check_five_slot_shop_and_gifting()
	_check_brainwave_arbitration()
	print("EXPEDITION MAP SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check_templates_and_difficulties() -> void:
	var templates := ContentCatalog._items("res://resources/expedition/templates")
	check(templates.size() == 3, "Exactly three map templates exist (one per level, not duplicated per difficulty)")
	for level in [1, 2, 3]:
		var template := ContentCatalog.map_template(level)
		check(template != null and template.validation_errors().is_empty(), "Level %d template is valid" % level)
		check(is_equal_approx(template.level_multiplier, float(level)), "Level %d template multiplier is x%d" % [level, level])
	var difficulties := ContentCatalog.map_difficulties()
	check(difficulties.size() == 3, "Three difficulties (easy / normal / hard) exist")
	var expected := {"easy": [0.6, 0.2, 0.2], "normal": [0.7, 0.15, 0.15], "hard": [0.8, 0.1, 0.1]}
	for item in difficulties:
		check(item.validation_errors().is_empty() and expected.has(item.id), "Difficulty %s is valid" % item.id)
		var ratios: Array = expected[item.id]
		check(is_equal_approx(item.battle_ratio, ratios[0]) and is_equal_approx(item.reward_ratio, ratios[1]) and is_equal_approx(item.event_ratio, ratios[2]), "Difficulty %s uses confirmed ratios" % item.id)

func _check_generator_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	var template := ContentCatalog.map_template(1)
	var difficulties := ContentCatalog.map_difficulties()
	var valid_runs := 0
	var unbounded_counts := {1: 0, 2: 0, 3: 0}
	var elite_in_late_depths := 0
	var battle_in_late_depths := 0
	for i in 36:
		var difficulty := difficulties[i % difficulties.size()]
		var map := ExpeditionMapGenerator.generate(template, difficulty, rng)
		if ExpeditionMapGenerator.validation_errors(map, template).is_empty() and map.validation_errors().is_empty():
			valid_runs += 1
		var by_id := {}
		for cell in map.cells:
			by_id[cell.id] = cell
		for cell in map.cells:
			if cell.depth >= 6 and cell.depth <= 9 and cell.is_battle():
				battle_in_late_depths += 1
				if cell.kind == MapCellData.Kind.ELITE_BATTLE:
					elite_in_late_depths += 1
			if cell.depth >= 9:
				continue
			var possible := 0
			for other in map.cells:
				if other.depth == cell.depth + 1 and absi(other.grid_position.x - cell.grid_position.x) <= 1:
					possible += 1
			if possible == 3:
				unbounded_counts[cell.next_cell_ids.size()] += 1
	check(valid_runs == 36, "All 36 generated maps across difficulties satisfy reachability, dead-end, depth and consecutive-type rules")
	var unbounded_total: int = unbounded_counts[1] + unbounded_counts[2] + unbounded_counts[3]
	check(unbounded_counts[3] > unbounded_counts[2] and unbounded_counts[2] > unbounded_counts[1] and unbounded_counts[1] > 0, "Unbounded cells generate 3 / 2 / 1 routes in descending frequency (%d total)" % unbounded_total)
	var elite_rate := float(elite_in_late_depths) / maxf(1.0, battle_in_late_depths)
	check(elite_rate > 0.30 and elite_rate < 0.70, "Depth 6-9 battle cells spawn elites at ~50%% (actual %.0f%%)" % (elite_rate * 100.0))

func _check_expedition_progression_and_ui() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	var select_screen := await _scene("res://scenes/map/map_select.tscn")
	check(select_screen.cards.size() == 1 and select_screen.cards.has("normal"), "First map offers only normal / mindscape difficulty")
	var card_text: String = select_screen.cards["normal"].description.text
	check(not card_text.contains("%") and not card_text.contains("赤牙"), "Map select hides backend probabilities and enemy previews")
	select_screen._confirm()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path.ends_with("map_screen.tscn") and state.expedition.level == 1, "Confirming map 1 enters the generated map")
	var map: MapData = state.current_map()
	check(state.current_cell_id == map.starting_cell_id and state.is_cell_revealed(map.starting_cell_id), "Party starts at depth-1 start cell")
	check(state.is_cell_revealed(map.boss_cell_id), "BOSS destination is visible when inspecting the whole map")
	var canvas: Control = current_scene.body.get_child(1)
	var start_cell: MapCellData = map.find_cell(state.current_cell_id)
	check(canvas._screen_point(start_cell).distance_to(canvas.size * 0.5) < 1.0, "Map UI keeps current cell at the viewport centre")
	var unrevealed := 0
	for cell in map.cells:
		if not state.is_cell_revealed(cell.id):
			unrevealed += 1
	check(unrevealed > 40, "Unvisited distant cells remain covered by fog")
	var next_id: String = state.available[0]
	var next_cell: MapCellData = map.find_cell(next_id)
	var next_button: Button = canvas._buttons[next_id]
	check(state.is_cell_revealed(next_id) and next_button.text.begins_with(next_cell.type_name()) and not next_button.text.contains(next_cell.display_name), "Revealed unentered cell shows only its type, not its content name")
	canvas.set_zoom(0.4)
	canvas.pan_offset = Vector2(60, -40)
	canvas._layout()
	check(is_equal_approx(canvas.zoom, 0.4) and canvas.pan_offset == Vector2(60, -40), "Map supports zooming and panning")
	canvas.show_overview()
	var boss_point: Vector2 = canvas._screen_point(map.find_cell(map.boss_cell_id))
	check(Rect2(Vector2.ZERO, canvas.size).has_point(boss_point), "Overview zoom brings the depth-10 BOSS cell into view")
	canvas.center_on_current()
	check(is_equal_approx(canvas.zoom, 1.0) and canvas.pan_offset == Vector2.ZERO, "Recentring returns to the current cell")
	# Capability hooks: expand reveal radius and relocate party.
	var revealed_before: int = state.expedition.exploration.revealed.size()
	state.add_reveal_radius(1)
	check(state.expedition.exploration.revealed.size() > revealed_before, "Reveal-radius hook reveals further layers")
	var depth3_id := ""
	for cell in map.cells:
		if cell.depth == 3:
			depth3_id = cell.id
			break
	check(state.relocate_party(depth3_id, true) and state.current_cell_id == depth3_id, "Relocation hook moves the party and reveals neighbors")
	# Complete map 1 BOSS -> shop -> map 2 select (all 3 difficulties) -> full heal.
	state.health = 35.0
	state.gold = 40
	state.relocate_party(map.boss_cell_id)
	state.complete_current_cell()
	check(not state.won_run and state.expedition.needs_map_selection(), "Clearing map 1 BOSS unlocks next map selection without ending the run")
	var shop := await _scene("res://scenes/ui/shop_screen.tscn")
	check(shop != null and state.route_scene().ends_with("map_select.tscn"), "Post-BOSS shop routes to map selection")
	select_screen = await _scene(state.route_scene())
	check(select_screen.cards.size() == 3, "Second map offers easy, normal and hard")
	check(state.enter_expedition_map("normal") and state.expedition.level == 2, "Second map allows selecting the same difficulty again")
	check(is_equal_approx(state.health, state.effective_max_health()) and state.gold == 40, "Entering a new map restores full health and preserves gold")
	check(state.expedition.used_art["normal"].size() == 2 and state.expedition.used_art["normal"][0] != state.expedition.used_art["normal"][1], "Same theme does not repeat placeholder artwork within one expedition")
	# Map 2 -> Map 3 -> final victory.
	state.relocate_party(state.current_map().boss_cell_id)
	state.complete_current_cell()
	check(state.enter_expedition_map("hard") and state.expedition.level == 3, "Third map enters level 3")
	state.relocate_party(state.current_map().boss_cell_id)
	state.complete_current_cell()
	check(state.won_run, "Clearing level-3 BOSS completes the expedition")

func _check_level_multipliers() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	state.expedition.level = 2
	state.expedition.template = ContentCatalog.map_template(2)
	var map: MapData = state.current_map()
	for id in state.available:
		var cell: MapCellData = map.find_cell(id)
		if not cell.is_battle():
			cell.kind = MapCellData.Kind.NORMAL_BATTLE
			cell.encounter = load("res://resources/encounters/training.tres")
		state.move_to_cell(id)
		break
	state.begin_cell_encounter()
	var arena := await _scene("res://scenes/run/arena.tscn")
	arena.director.stop()
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	var melee: EnemyData = load("res://resources/enemies/melee.tres")
	unit.data = melee
	unit.player = arena.player
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	check(is_equal_approx(unit.health.maximum, melee.max_health * 2.0), "Level 2 map doubles enemy health")
	check(is_equal_approx(unit.get_damage_multiplier(), 2.0), "Level 2 map doubles enemy damage")
	arena._enemy_defeated(unit)
	await process_frame
	var pickup: Node2D
	for child in arena.get_node("Pickups").get_children():
		if child.get("experience_value") != null and child.experience_value > 0:
			pickup = child
	check(pickup != null and pickup.experience_value == melee.experience_reward * 2 and pickup.gold_value == melee.gold_reward * 2, "Level 2 map doubles enemy experience and material drops")
	check(pickup != null and pickup.fragment_value == melee.effective_fragment_reward() * 2, "Level 2 map doubles enemy base gold fragments")
	check(is_equal_approx(unit.get_movement_speed(), melee.movement_speed), "Enemy base movement speed remains locked across map levels")
	# Verify per-combat-cell linear growth (+5% HP/Attack, +5% XP/Gold, speed invariant) and reset on next map
	state.complete_current_cell()
	check(state.combats_completed_in_map == 1, "Completing 1st battle cell increments map combat counter to 1")
	check(is_equal_approx(state.enemy_stat_multiplier(), 2.0 * 1.05), "2nd battle cell on Level 2 scales enemy HP & damage by +5% (2.10x)")
	check(is_equal_approx(state.enemy_reward_multiplier(), 2.0 * 1.05), "2nd battle cell on Level 2 scales enemy XP & gold rewards by +5% (2.10x)")
	var unit_b2: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit_b2.data = melee
	unit_b2.player = arena.player
	arena.get_node("Enemies").add_child(unit_b2)
	unit_b2.set_physics_process(false)
	check(is_equal_approx(unit_b2.health.maximum, melee.max_health * 2.1) and is_equal_approx(unit_b2.get_damage_multiplier(), 2.1), "Enemy spawned in 2nd battle cell receives +5% HP and damage")
	check(is_equal_approx(unit_b2.get_movement_speed(), melee.movement_speed), "Enemy movement speed remains locked during combat cell progression")
	state.expedition.map_cleared = true
	check(state.enter_expedition_map("hard") and state.combats_completed_in_map == 0, "Entering next map resets combat cell counter to 0")
	check(is_equal_approx(state.enemy_stat_multiplier(), 3.0) and is_equal_approx(state.enemy_reward_multiplier(), 3.0), "New map starts from its base multiplier (3.0x) on 1st battle")
	await _check_edge_warning_and_enemy_cap(arena)

func _check_edge_warning_and_enemy_cap(arena: Node) -> void:
	# 1. Verify 80 active enemy cap despawns oldest normal enemy without dropping XP/gold/fragments
	for child in arena.get_node("Enemies").get_children():
		child.queue_free()
	for child in arena.get_node("Pickups").get_children():
		child.queue_free()
	await process_frame
	arena.director.active = true
	arena.director.alive_count = 0
	arena.director.alive_regular_count = 0
	arena.director.despawned_count = 0
	arena.director.active_regular_enemies.clear()
	var melee: EnemyData = load("res://resources/enemies/melee.tres")
	var elite_data: EnemyData = load("res://resources/enemies/elite.tres")
	var loc := SpawnLocationData.new()
	# Spawn 1 elite first (oldest), then 80 normal enemies -> total 81 attempts
	arena.director._spawn_regular(elite_data, loc, 1)
	var elite_ref: Node2D = arena.director.active_regular_enemies[0]
	var first_normal: Node2D = null
	for i in 80:
		arena.director._spawn_regular(melee, loc, 1)
		if i == 0:
			first_normal = arena.director.active_regular_enemies[1]
	await process_frame
	check(arena.director.max_active_enemies == 80 and arena.director.alive_regular_count == 80, "Active regular enemy count is capped at 80")
	check(arena.director.despawned_count == 1 and not is_instance_valid(first_normal) and is_instance_valid(elite_ref), "Exceeding 80 cap despawns oldest normal enemy while protecting elite enemy")
	check(arena.get_node("Pickups").get_child_count() == 0, "Despawned enemy drops 0 XP, 0 gold, and 0 fragments")
	# 2. Verify 1.0s red flashing batch edge warning and off-screen batch entry
	arena.director.stop()
	for child in arena.get_node("Enemies").get_children():
		child.queue_free()
	for child in arena.get_node("Effects").get_children():
		child.queue_free()
	await process_frame
	var plan: Dictionary = arena.director._create_batch_spawn_plan(loc, 2)
	var fx: Node2D = arena.effects.present_edge_warning(int(plan["edge"]), Vector2(plan["warning_point"]), float(plan["span"]), EncounterDirector.EDGE_WARNING_DURATION, 2)
	check(fx != null and fx.kind == "edge_warning" and is_equal_approx(fx.lifetime, 1.0), "Batch edge warning spawns a 1.0s red flashing effect at the entry edge")
	for edge_id in [SpawnLocationData.Edge.LEFT, SpawnLocationData.Edge.RIGHT, SpawnLocationData.Edge.TOP, SpawnLocationData.Edge.BOTTOM]:
		var edge_loc := SpawnLocationData.new()
		edge_loc.edges = PackedInt32Array([edge_id])
		var edge_plan: Dictionary = arena.director._create_batch_spawn_plan(edge_loc, 1)
		var warn_pt := Vector2(edge_plan["warning_point"])
		check(arena.director.arena_bounds.has_point(warn_pt) and warn_pt.y > 70.0, "Edge warning for edge %d is inside playable arena bounds and never hidden under top HUD" % edge_id)
	var all_on_warned_edge := true
	for i in 6:
		var pt: Vector2 = arena.director.random_spawn_position(loc, melee, plan)
		if Rect2(0, 0, 960, 540).has_point(pt):
			all_on_warned_edge = false
	check(all_on_warned_edge, "All enemies in warned batch spawn off-screen outside the warned edge region")
	# 3. Verify 35s first battle cell wave schedule (Waves 1-2 have 6 enemies each, later waves ramp up) and multi-enemy groups in later battle cells
	var training_enc: EncounterData = load("res://resources/encounters/training.tres")
	var w1_total := 0
	var w2_total := 0
	var w_last_total := 0
	for e in training_enc.schedules[0].group.entries: w1_total += e.count
	for e in training_enc.schedules[1].group.entries: w2_total += e.count
	for e in training_enc.schedules[training_enc.schedules.size() - 1].group.entries: w_last_total += e.count
	check(is_equal_approx(training_enc.duration, 35.0) and w1_total == 6 and w2_total == 6 and w_last_total >= 12, "First battle cell lasts 35s, starts with 6 enemies in waves 1-2, and ramps up in the second half")
	var elite_enc: EncounterData = load("res://resources/encounters/elite.tres")
	var min_elite_wave_count := 999
	for sched in elite_enc.schedules:
		var c := 0
		for e in sched.group.entries: c += e.count
		min_elite_wave_count = mini(min_elite_wave_count, c)
	check(is_equal_approx(elite_enc.duration, 35.0) and min_elite_wave_count >= 8, "Elite battle cell waves each contain >= 8 enemies (never 1 enemy per wave)")
	# 4. Verify 10 sample skills, Character innate skill independent hotkey, and 4 new Brotato-style skill-bearing enemies
	var expected_skills := ["ember_burst", "charger_dash", "spitter_burst", "spawner_hatch", "buffer_totem", "slasher_cleave", "shredder_rocket", "lightning_strike", "ghost_step", "fire_whirl"]
	var all_skills_valid := true
	for s_id in expected_skills:
		var sk := ContentCatalog.skill(s_id)
		if sk == null or sk.id != s_id or not sk.validation_errors().is_empty():
			all_skills_valid = false
	check(all_skills_valid and ContentCatalog.skill_ids().size() >= 10, "All 10 Brotato-inspired sample skills exist and pass validation")
	check(arena.player.skill.character_skill != null and arena.player.skill.character_skill.id == "ghost_step", "Wanderer character carries innate Ghost Step skill on independent slot")
	var pos_before_dash: Vector2 = arena.player.global_position
	check(arena.player.skill.try_cast_character_skill_at(pos_before_dash + Vector2(90, 0)) and arena.player.invulnerability >= 0.8, "Independent character skill casts Ghost Step dash and grants invulnerability")
	for e_id in ["charger", "spitter", "spawner", "buffer"]:
		var e_def := ContentCatalog.enemy(e_id)
		check(e_def != null and e_def.skill != null and e_def.validation_errors().is_empty(), "New Brotato enemy '%s' has a valid skill and passes validation" % e_id)
	var deep_enc := ExpeditionMapGenerator._build_depth_normal_encounter(training_enc, 6)
	var has_new_enemies := false
	for sched in deep_enc.schedules:
		for e in sched.group.entries:
			if e.enemy.id in ["charger", "spitter", "spawner", "buffer"]:
				has_new_enemies = true
	check(has_new_enemies, "Deeper combat cells progressively unlock Charger, Spitter, Buffer, and Spawner enemies")
	arena.director.stop()

func _check_rarity_tables_and_harvesting() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	state.primary.reset()
	# Verify Harvesting appear-chance scaling: +1% relative per point up to +50% (50% -> 75% at 50)
	check(is_equal_approx(state.harvesting_item_appear_chance(0.5), 0.5), "Base reward item appear chance is 50%")
	state.add_primary_stat("harvesting", 50)
	check(is_equal_approx(state.harvesting_item_appear_chance(0.5), 0.75), "50 Harvesting raises 50% base appear chance to 75% (+50% relative)")
	check(is_equal_approx(state.harvesting_rarity_upgrade_chance(), 0.0), "Harvesting <= 50 gives 0% rarity upgrade overflow")
	state.add_primary_stat("harvesting", 30) # Total 80
	check(is_equal_approx(state.harvesting_item_appear_chance(0.5), 0.75), "Appear chance bonus caps at 50 Harvesting")
	check(is_equal_approx(state.harvesting_rarity_upgrade_chance(), 0.30), "Harvesting 80 gives 30% rarity upgrade chance")
	state.add_primary_stat("harvesting", 50) # Total 130 -> capped at 100
	check(is_equal_approx(state.effective_harvesting(), 100.0) and is_equal_approx(state.harvesting_rarity_upgrade_chance(), 0.50), "Harvesting caps at 100 (max 50% rarity upgrade chance)")
	state.primary.reset()
	# Verify Level 1/2/3 normal & BOSS rarity distributions without harvesting overflow
	state.rng.seed = 987654
	var l1_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var l3_boss_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for i in 2000:
		l1_counts[state.roll_expedition_rarity(false, 1)] += 1
		l3_boss_counts[state.roll_expedition_rarity(true, 3)] += 1
	check(l1_counts[1] > 1450 and l1_counts[2] > 300 and l1_counts[3] == 0 and l1_counts[4] == 0 and l1_counts[5] == 0, "Level 1 reward/elite rarity follows 80/20/0/0/0")
	check(l3_boss_counts[5] > 140 and l3_boss_counts[4] > 300 and l3_boss_counts[3] > 500, "Level 3 BOSS rarity follows 15/25/30/20/10 including tier 5")
	# Verify overflow upgrades tier up to max 5
	state.add_primary_stat("harvesting", 100)
	var l1_upgraded_tier3 := 0
	for i in 1000:
		var t: int = state.roll_expedition_rarity(false, 1)
		if t == 3:
			l1_upgraded_tier3 += 1
		check(t >= 1 and t <= 5, "Rarity never exceeds tier 5")
	check(l1_upgraded_tier3 > 50, "Harvesting overflow can upgrade Level 1 tier-2 rolls to tier 3")
	state.primary.reset()

func _check_fragments_and_combat_settlement() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	state.gold = 0
	state.experience = 0
	state.primary.reset()
	state.add_primary_stat("harvesting", 25) # +25% personal extra fragments
	state.reset_combat_accumulators()
	# Pick up 35 base fragments: 35 * 1.25 = 43.75 -> floor to 43 fragments -> 4 gold, 3 remainder discarded
	state.collect_combat_fragments(35)
	state.record_combat_enemy_xp(16)
	check(state.gold == 0 and state.experience == 0, "Fragments and XP are not settled mid-combat")
	var summary: Dictionary = state.settle_combat_economy(EncounterData.Kind.NORMAL)
	check(summary["fragments"] == 43 and summary["gold"] == 4 and state.gold == 4, "Fragments apply Harvesting (+1%/pt), floor to integer (43), and convert at 10:1 (4 gold)")
	check(state.combat_base_fragments == 0, "Remainder fragments do not carry over across combats")
	check(summary["xp"] == 16 and state.level == 2 and state.experience == 4, "Combat XP is settled at the end of battle and is unaffected by Harvesting")

func _check_reward_cell_and_boss_loot() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	for i in 50:
		var g1: int = state.roll_reward_cell_gold(1)
		var g2: int = state.roll_reward_cell_gold(2)
		var g3: int = state.roll_reward_cell_gold(3)
		if g1 < 20 or g1 > 25 or g2 < 30 or g2 > 40 or g3 < 45 or g3 > 60:
			check(false, "Reward cell gold out of level range")
			return
	check(true, "Reward cell gold ranges match 20-25 (L1), 30-40 (L2), 45-60 (L3)")
	var guaranteed_ok := true
	for i in 60:
		var candidates: Array[Resource] = state.generate_reward_cell_candidates()
		if candidates.is_empty() or candidates.size() > 2:
			guaranteed_ok = false
	check(guaranteed_ok, "Reward cell independently rolls equipment/relic and guarantees at least 1 candidate")
	var elite_loot: Array[Resource] = state.generate_post_battle_loot(EncounterData.Kind.ELITE)
	var elite_w := 0
	var elite_r := 0
	for item in elite_loot:
		if item is WeaponData: elite_w += 1
		elif item is RelicData: elite_r += 1
	check(elite_w == 1 and elite_r == 1, "Elite battle awards 1 equipment and 1 relic")
	var boss_loot: Array[Resource] = state.generate_post_battle_loot(EncounterData.Kind.BOSS)
	var boss_w := 0
	var boss_r := 0
	for item in boss_loot:
		if item is WeaponData: boss_w += 1
		elif item is RelicData: boss_r += 1
	check(boss_w == 2 and boss_r == 2, "BOSS battle awards 2 equipment and 2 relics")
	var abandoned_item: Resource = boss_loot[0]
	state.abandon_loot_to_shared_pool(abandoned_item)
	check(state.shared_loot_pool.has(abandoned_item) and state.pending_combat_loot.size() == 3, "Abandoned loot enters the party shared pool")

func _check_event_rules_and_durations() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	state.health = 15.0
	state.apply_event_health_cost(50.0)
	check(is_equal_approx(state.health, 1.0), "Event health loss clamps to minimum 1 HP and never kills the player")
	var base_atk_spd: float = state.stat_value("attack_speed")
	var base_armor: float = state.stat_value("armor")
	var base_dmg: float = state.stat_value("damage")
	state.add_event_stat_modifier("attack_speed", 20.0, EventActionData.Duration.COMBAT, 2)
	state.add_event_stat_modifier("armor", 5.0, EventActionData.Duration.MAP, 1)
	state.add_event_stat_modifier("damage", 12.0, EventActionData.Duration.EXPEDITION, 1)
	check(is_equal_approx(state.stat_value("attack_speed"), base_atk_spd + 20.0) and is_equal_approx(state.stat_value("armor"), base_armor + 5.0) and is_equal_approx(state.stat_value("damage"), base_dmg + 12.0), "Event stat modifiers apply immediately")
	state.finish_combat_events()
	check(is_equal_approx(state.stat_value("attack_speed"), base_atk_spd + 20.0), "2-combat event modifier remains active after 1st combat")
	state.finish_combat_events()
	check(is_equal_approx(state.stat_value("attack_speed"), base_atk_spd), "2-combat event modifier expires after 2nd combat")
	state.expedition.map_cleared = true
	state.enter_expedition_map("hard")
	check(is_equal_approx(state.stat_value("armor"), base_armor) and is_equal_approx(state.stat_value("damage"), base_dmg + 12.0), "Map-duration modifier expires on next map while expedition-duration modifier persists")

func _check_five_slot_shop_and_gifting() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.begin_expedition()
	state.enter_expedition_map("normal")
	state.gold = 200
	var shop := await _scene("res://scenes/ui/shop_screen.tscn")
	check(shop.slots.size() == 5, "Expedition shop has exactly 5 item slots")
	var w_count := 0
	var r_count := 0
	for s in shop.slots:
		if s["kind"] == "weapon": w_count += 1
		else: r_count += 1
	check(w_count >= 2 and r_count >= 2, "Shop guarantees at least 2 equipment and 2 relics")
	check(shop._single_reroll_cost() == 2 and shop._reroll_cost() == 8, "Single-slot reroll costs 2 gold and full-shop reroll costs 8 gold")
	# Lock slot 0, buy slot 2, single-reroll slot 1, then full-reroll
	var locked_id: String = shop.slots[0]["id"]
	shop._toggle_slot_lock(0)
	check(bool(shop.slots[0]["locked"]), "Slot 0 is locked")
	var gold_before_single: int = state.gold
	shop._reroll_slot(1)
	check(state.gold == gold_before_single - 2, "Single-slot reroll deducts 2 gold")
	var relic_slot := -1
	for i in 5:
		if shop.slots[i]["kind"] == "relic" and not bool(shop.slots[i]["locked"]):
			relic_slot = i
			break
	shop._buy_relic_slot(relic_slot)
	check(bool(shop.slots[relic_slot]["sold"]), "Purchased shop slot becomes empty and does not restock immediately")
	var gold_before_full: int = state.gold
	shop._reroll()
	check(state.gold == gold_before_full - 8 and shop.slots[0]["id"] == locked_id and not bool(shop.slots[relic_slot]["sold"]), "Full-shop reroll charges full 8 gold regardless of locked/empty slots, keeps locked slot, and restocks empty slot")
	# Test gold gifting fee (10% ceil, min 1) and once-per-teammate per shop phase
	state.gold = 50
	check(state.gift_fee(5) == 1 and state.gift_fee(15) == 2 and state.gift_fee(20) == 2, "Gift fee is 10% rounded up with minimum 1 gold")
	var gift_res: Dictionary = state.gift_gold_to_teammate("ally_2", 15)
	check(bool(gift_res["ok"]) and state.gold == 33, "Gifting 15 gold deducts 15 + 2 fee = 17 gold immediately")
	check(not state.can_gift_gold("ally_2", 5), "Cannot gift to the same teammate twice in one shop phase")
	check(state.can_gift_gold("ally_3", 30) and not state.can_gift_gold("ally_3", 31), "Sender must have enough gold to cover both gift amount and 10% fee (30 + 3 = 33)")

func _check_brainwave_arbitration() -> void:
	# Unanimous choice needs no tiebreak
	var unanimous = state.resolve_brainwave_vote({"p1": "cell_a", "p2": "cell_a"})
	check(unanimous == "cell_a", "Unanimous choice executes directly")
	# Cyclic RPS: 0 beats 1, 1 beats 2, 2 beats 0
	var rps_win = state.resolve_brainwave_vote({"p1": "cell_a", "p2": "cell_b"}, func(pid: String, _r: int): return 0 if pid == "p1" else 1)
	check(rps_win == "cell_a", "Brainwave symbol 0 beats symbol 1")
	# Tie in round 0, resolved in round 1
	var round2_win = state.resolve_brainwave_vote({"p1": "cell_a", "p2": "cell_b"}, func(pid: String, r: int):
		if r == 0: return 2
		return 1 if pid == "p2" else 2)
	check(round2_win == "cell_b", "Brainwave tie re-rolls and resolves in subsequent round")
	# 3 consecutive ties fall back to random among tied choices
	var tie_fallback = state.resolve_brainwave_vote({"p1": "cell_a", "p2": "cell_b"}, func(_pid: String, _r: int): return 0)
	check(tie_fallback in ["cell_a", "cell_b"], "Three consecutive ties resolve by random selection among tied choices")
