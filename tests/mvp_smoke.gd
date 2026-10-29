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
	state.new_run()
	state.start_with("pistol", "seed")
	check(is_equal_approx(state.movement_speed(), 180.0), "Player effective movement speed is 1.5x while the base stat remains 5 units")
	for path in [
		"res://scenes/app/title_screen.tscn", "res://scenes/app/character_select.tscn",
		"res://scenes/app/loadout_select.tscn", "res://scenes/map/map_screen.tscn",
		"res://scenes/ui/shop_screen.tscn", "res://scenes/app/result_screen.tscn"]:
		var screen := await _scene(path)
		check(screen != null, "Screen loads: " + path)
		if path.ends_with("map_screen.tscn"):
			var fixture := ContentCatalog.map().find_cell("crossing")
			fixture.kind = MapCellData.Kind.BOSS_BATTLE
			screen._enter_cell("crossing")
			check(state.current_cell_id == "camp", "Invalid encounter configuration does not move player or lock map navigation")
			fixture.kind = MapCellData.Kind.NORMAL_BATTLE
	state.current_cell_id = "cache"
	await _scene("res://scenes/map/cell_resolution.tscn")
	check(current_scene.entry.kind == MapCellData.Kind.REWARD, "Reward node loads")
	state.current_cell_id = "shrine"
	await _scene("res://scenes/map/cell_resolution.tscn")
	check(current_scene.entry.kind == MapCellData.Kind.EVENT, "Event node loads")
	check(current_scene.entry.event.actions.is_empty(), "Initial event displays text without gameplay effects")
	check(ContentCatalog.map().validation_errors().is_empty(), "Map and every authored encounter have valid category and content configuration")
	state.current_cell_id = "crossing"
	var arena := await _scene("res://scenes/run/arena.tscn")
	check(arena != null and arena.player.health.current == 100.0, "Arena and player initialize")
	await _combat_checks(arena)
	await _full_run_checks()
	await _schedule_and_loadout_checks()
	await _partial_generation_check()
	await _event_context_checks()
	print("MVP SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _enemy(arena: Node, type: String, point: Vector2, hp: float = -1.0) -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/%s.tres" % type)
	unit.player = arena.player
	unit.position = point
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	if hp > 0:
		unit.health.current = hp
	return unit

func _combat_checks(arena: Node) -> void:
	arena.director.stop()
	arena.player.set_physics_process(false)
	arena.player.controls.set_physics_process(false)
	for equipped_weapon in arena.player.inventory.equipped: equipped_weapon.set_physics_process(false)
	var center: Vector2 = arena.player.global_position
	var low := _enemy(arena, "melee", center + Vector2(52, 0), 9.0)
	var near := _enemy(arena, "melee", center + Vector2(30, 0), 22.0)
	var far := _enemy(arena, "melee", center + Vector2(150, 0), 1.0)
	var units: Array[Node2D] = [low, near, far]
	check(CombatTargeting.nearest(center, 68, units) == near, "Single melee prioritizes nearest target inside reach")
	var test_weapon: Node2D = load("res://scenes/combat/weapon.tscn").instantiate()
	test_weapon.data = ContentCatalog.weapon("needle")
	test_weapon.holder = arena.player
	arena.player.add_child(test_weapon)
	test_weapon.set_physics_process(false)
	test_weapon._try_direct_attack()
	for i in 70: await physics_frame
	check(not is_instance_valid(low) and not is_instance_valid(near), "Thrust aimed at the nearest enemy also hits enemies along its path")
	test_weapon.queue_free()
	for unit in [far]:
		unit.queue_free()
	await process_frame
	var a := _enemy(arena, "melee", center + Vector2(50, -30))
	var b := _enemy(arena, "melee", center + Vector2(50, 10))
	var c := _enemy(arena, "melee", center + Vector2(-65, 0))
	var cluster: Array[Node2D] = [a, b, c]
	var best := CombatTargeting.best_circle_center(center, 80, 36, cluster)
	var coverage: int = 0
	for unit in cluster:
		if best.distance_to(unit.position) <= 36.05:
			coverage += 1
	check(coverage == 2 and best.distance_to(center) <= 80.05, "Area melee selects maximum circle coverage within reach")
	test_weapon = load("res://scenes/combat/weapon.tscn").instantiate()
	test_weapon.data = ContentCatalog.weapon("cleaver")
	test_weapon.holder = arena.player
	arena.player.add_child(test_weapon)
	test_weapon.set_physics_process(false)
	test_weapon._try_direct_attack()
	for i in 30: await physics_frame
	check(a.health.current == 11.0 and b.health.current == 11.0 and c.health.current == 32.0, "Area attack damages the selected cluster only")
	test_weapon.queue_free()
	for unit in cluster:
		unit.queue_free()
	await process_frame
	var ranged := _enemy(arena, "ranged", center + Vector2(100, 0))
	ranged.entered_arena = true
	ranged._physics_process(1.0 / 60.0)
	check(ranged.velocity.x > 0.0, "Ranged enemy immediately retreats inside its range")
	check(ranged.loadout_controller.equipped[0].attacks[0].cooldown.is_stopped(), "Ranged enemy does not attack while retreating by default")
	ranged.data.can_attack_while_retreating = true
	ranged._physics_process(1.0 / 60.0)
	check(not ranged.loadout_controller.equipped[0].attacks[0].cooldown.is_stopped(), "Enemy can opt in to attacking while retreating")
	ranged.loadout_controller.equipped[0].attacks[0].cooldown.stop()
	ranged.data.can_attack_while_retreating = false
	ranged.position = center + Vector2(165, 0)
	ranged._physics_process(1.0 / 60.0)
	check(ranged.velocity.is_zero_approx(), "Ranged enemy stops exactly at its attack range")
	check(not ranged.loadout_controller.equipped[0].attacks[0].cooldown.is_stopped(), "Ranged enemy attacks after reaching its configured range")
	ranged.queue_free()
	var healer := _enemy(arena, "healer", center + Vector2(80, 0), 10.0)
	var patient := _enemy(arena, "melee", center + Vector2(110, 0), 10.0)
	healer.entered_arena = true
	healer._physics_process(0.1)
	check(healer.velocity.x > 0.0 and patient.health.current > 10.0, "Healer retreats and heals simultaneously")
	check(healer.health.current == 10.0, "Healer cannot heal itself")
	healer.queue_free()
	patient.queue_free()
	await process_frame
	healer = _enemy(arena, "healer", center + Vector2(220, 0))
	var patients: Array[Node2D] = []
	for i in 4:
		patients.append(_enemy(arena, "melee", center + Vector2(210 + i * 14, 20), 5.0 + i))
	healer.loadout_controller.tick(1.0)
	check(patients[0].health.current == 10.0 and patients[2].health.current == 12.0 and patients[3].health.current == 8.0, "Healer respects healing-per-second and target-count attributes")
	for patient_node in patients:
		patient_node.queue_free()
	healer.queue_free()
	await process_frame
	var boss := _enemy(arena, "boss", center + Vector2(30, 0))
	boss.entered_arena = true
	arena.player.invulnerability = 0.0
	var projectile_count: int = arena.get_node("Projectiles").get_child_count()
	boss.loadout_controller.tick(1.0 / 60.0)
	var attacks: Array = boss.loadout_controller.equipped[0].attacks
	check(not attacks[0].cooldown.is_stopped() and not attacks[1].cooldown.is_stopped() and arena.get_node("Projectiles").get_child_count() == projectile_count + 8, "Single boss equipment executes ranged and melee profiles with independent cooldowns")
	check(arena.player.health.current == 82.0, "Boss melee profile applies its own configured damage")
	boss.health.current = 100.0
	boss._physics_process(0.25)
	check(is_equal_approx(boss.health.current, 100.25) and is_equal_approx(boss.velocity.length(), 118.8), "One boss relic simultaneously applies fixed movement speed and regeneration during runtime")
	boss.queue_free()
	for bullet in arena.get_node("Projectiles").get_children():
		bullet.queue_free()
	arena.player.health.initialize(100.0)
	arena.player.invulnerability = 0.0
	await process_frame
	var target := _enemy(arena, "melee", center + Vector2(80, 0))
	var gun: Node2D = arena.player.inventory.equipped[0]
	gun.set_physics_process(false)
	gun._physics_process(0.016)
	check(not gun.cooldown.is_stopped(), "Gun fires automatically when an enemy is in range")
	for i in 30:
		await physics_frame
	check(target.health.current == 18.0, "Projectile collision delivers configured bullet damage")
	gun.cooldown.start(1.0)
	var remaining: float = gun.cooldown.time_left
	paused = true
	for i in 5:
		await physics_frame
	check(is_equal_approx(remaining, gun.cooldown.time_left), "Pausing freezes weapon cooldown")
	paused = false
	for i in 95:
		await physics_frame
	check(gun.cooldown.is_stopped(), "Weapon cooldown completes without reload")
	var skill: Node2D = arena.player.skill
	check(skill.data == null, "Character has no innate skill without skill-bearing items")
	state.equip_weapon("cleaver", 0)
	skill.toggle_targeting()
	check(skill.targeting, "Skill key enters targeting mode")
	arena.player.controls.set_physics_process(false)
	arena.player.set_physics_process(true)
	Input.action_press("move_right")
	var before: Vector2 = arena.player.position
	for i in 4:
		await physics_frame
	Input.action_release("move_right")
	check(arena.player.position.x > before.x and skill.targeting, "Movement continues while skill is being aimed")
	var skill_center: Vector2 = arena.player.position + Vector2(110, 80)
	var inside := _enemy(arena, "melee", skill_center)
	var outside := _enemy(arena, "melee", skill_center + Vector2(85, 0))
	check(skill.try_cast_at(skill_center) and not skill.cooldown.is_stopped(), "Skill confirmation begins cooldown")
	check(inside.health.current == 0.0 and outside.health.current == 32.0, "Circular skill damages only enemies within its radius")
	skill.toggle_targeting()
	check(not skill.targeting, "Skill cannot be armed during cooldown")
	skill.cooldown.stop()
	skill.toggle_targeting()
	test_weapon = load("res://scenes/combat/weapon.tscn").instantiate()
	test_weapon.data = ContentCatalog.weapon("needle")
	test_weapon.holder = arena.player
	arena.player.add_child(test_weapon)
	var auto_target := _enemy(arena, "melee", arena.player.position + Vector2(0, -40))
	# Keep unrelated projectile/skill fixtures outside this automatic-melee scenario.
	target.position = arena.player.position + Vector2(300, 0)
	outside.position = arena.player.position + Vector2(300, 100)
	arena.player.set_physics_process(false)
	test_weapon._try_direct_attack()
	for i in 35: await physics_frame
	check(not is_instance_valid(auto_target) and skill.targeting, "Automatic melee continues during skill targeting (targeting %s)" % [skill.targeting])
	test_weapon.queue_free()
	if is_instance_valid(auto_target): auto_target.queue_free()
	outside.queue_free()
	skill.cancel_targeting()
	arena.player.set_physics_process(false)
	target.queue_free()
	await process_frame
	_set_relics(["fury"])
	check(is_equal_approx(state.melee_speed_multiplier(), 1.5), "Melee relic increases attack frequency by 50 percent")
	_set_relics(["feather"])
	check(is_equal_approx(state.movement_speed(), 189.0), "Movement relic applies five percent bonus to the new starting speed")
	_set_relics(["seed", "seed", "fury", "feather"])
	check(state.relics.size() == 4 and state.regeneration() == 2.0, "Relics have no cap and repeated effects stack")
	var idle_weapon: Node2D = load("res://scenes/combat/weapon.tscn").instantiate()
	idle_weapon.data = ContentCatalog.weapon("needle")
	idle_weapon.holder = arena.player
	arena.player.add_child(idle_weapon)
	idle_weapon.set_physics_process(false)
	idle_weapon._try_direct_attack()
	check(idle_weapon.cooldown.is_stopped(), "Melee waits without consuming cooldown when no enemies are in range")
	idle_weapon.queue_free()
	for i in 50:
		var point: Vector2 = arena.director.random_spawn_position()
		check(not Rect2(0, 0, 960, 540).has_point(point), "Spawn remains outside fixed viewport")

func _full_run_checks() -> void:
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	var arena := await _scene("res://scenes/run/arena.tscn")
	arena.player.invulnerability = 9999
	var composition: Dictionary = {"melee": 0, "ranged": 0, "healer": 0}
	arena.director.enemy_spawned.connect(func(unit: Node2D):
		composition[unit.data.id] += 1
		unit.receive_damage.call_deferred(9999.0))
	for i in 2600:
		await physics_frame
		if arena.overlay.mode == "upgrade":
			check(paused, "Upgrade selection pauses simulation")
			arena._upgrade_chosen("vitality")
		if arena.encounter_won and arena.overlay.mode == "victory":
			break
	check(arena.encounter_won and arena.director.generated_groups >= 2, "Timed initial encounter completes after repeated groups")
	check(composition.melee >= 10 and composition.ranged >= 4 and composition.healer >= 2, "Repeated groups contain melee, ranged and healing enemies")
	check(arena.overlay.mode == "victory" and paused, "Victory waits for player confirmation")
	arena._continue_route()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path.ends_with("shop_screen.tscn"), "Battle victory enters shop")
	check(state.available.has("camp") and state.available.has("cache") and state.available.has("shrine"), "Completed battle permits four-direction movement and backtracking")
	var coins: int = state.gold
	current_scene._buy_weapon("pistol", 0)
	check(state.weapons == ["pistol", "needle"] and state.gold == coins - 18, "Shop equips second weapon in chosen left-hand slot")
	state.current_cell_id = "cache"
	var reward := await _scene("res://scenes/map/cell_resolution.tscn")
	reward._choose_reward(reward.entry.reward_options[2])
	await process_frame
	await process_frame
	check(state.available.has("crown") and state.relics.has("fury"), "Reward grants relic and permits movement to adjacent boss cell")
	check(not state.move_to_cell("shrine"), "Diagonal movement is rejected")
	var coins_before_return: int = state.gold
	current_scene._enter_cell("crossing")
	check(state.current_cell_id == "crossing" and current_scene.scene_file_path.ends_with("map_screen.tscn"), "Returning to completed battle does not replay encounter")
	check(not state.move_to_cell("crown"), "Non-adjacent movement is rejected")
	current_scene._enter_cell("cache")
	check(state.gold == coins_before_return and current_scene.scene_file_path.ends_with("map_screen.tscn"), "Returning to reward cell does not grant duplicate reward")
	state.current_cell_id = "crown"
	arena = await _scene("res://scenes/run/arena.tscn")
	arena.player.invulnerability = 9999
	arena.director.enemy_spawned.connect(func(unit: Node2D):
		unit.receive_damage.call_deferred(9999.0))
	for i in 3400:
		await physics_frame
		if arena.overlay.mode == "upgrade":
			arena._upgrade_chosen("power")
		if arena.encounter_won:
			break
	check(arena.encounter_won and arena.director.boss_has_spawned and not arena.director.boss_alive, "Boss encounter finishes after its timer and the boss is defeated")
	arena._continue_route()
	await process_frame
	await process_frame
	check(state.won_run and current_scene.scene_file_path.ends_with("result_screen.tscn"), "Boss victory reaches run completion")
	state.new_run()
	state.start_with("cleaver", "seed")
	state.current_cell_id = "crossing"
	arena = await _scene("res://scenes/run/arena.tscn")
	arena.player.receive_damage(1000)
	check(arena.defeated and arena.overlay.mode == "defeat" and paused, "Player death reaches defeat overlay")
	arena.overlay.leave_requested.emit()
	await process_frame
	await process_frame
	check(not paused and current_scene.scene_file_path.ends_with("title_screen.tscn"), "Defeat returns to start with simulation unpaused")

func _set_relics(ids: Array) -> void:
	state.loadout.clear_relics()
	for id in ids:
		state.add_relic(id)

func _advance(arena: Node, frames: int) -> void:
	for i in frames:
		await physics_frame
		if is_instance_valid(arena) and arena.overlay.mode == "upgrade":
			arena._upgrade_chosen("vitality")

func _rule(group_id: String, _count: int, _interval: float) -> GroupSpawnSchedule:
	var result := GroupSpawnSchedule.new()
	var grp: EnemyGroupData = load("res://resources/groups/%s.tres" % group_id).duplicate(true)
	grp.entries.resize(1)
	grp.entries[0].count = 1
	result.group = grp
	return result

func _schedule_and_loadout_checks() -> void:
	var player_loadout := ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1)
	var enemy_loadout := ActorLoadout.new(ItemDefinition.Recipient.ENEMY, 1, 1)
	var enemy_weapon: EquipmentData = load("res://resources/enemy_equipment/crown_arsenal.tres")
	var enemy_relic: RelicData = load("res://resources/enemy_relics/crown_vigor.tres")
	check(not player_loadout.equip(enemy_weapon, 0), "Players cannot equip enemy-specific equipment")
	check(not player_loadout.add_relic(enemy_relic), "Players cannot equip enemy-specific relics")
	check(enemy_loadout.equip(enemy_weapon, 0) and not enemy_loadout.equip(enemy_weapon, 1), "Enemy loadout has one equipment slot")
	check(not enemy_loadout.equip(ContentCatalog.weapon("needle"), 0), "Enemies cannot equip player equipment")
	check(enemy_loadout.add_relic(enemy_relic) and not enemy_loadout.add_relic(enemy_relic), "Enemy loadout has one relic slot")
	check(not enemy_loadout.add_relic(ContentCatalog.relic("seed")), "Enemies reject player relic definitions")
	check(enemy_loadout.regeneration() == 1.0 and is_equal_approx(enemy_loadout.movement_bonus(), 0.1), "Enemy relic combines speed and regeneration through shared effect calculations")
	var invalid_group: EnemyGroupData = load("res://resources/groups/guard.tres").duplicate(true)
	invalid_group.entries[0].enemy = load("res://resources/enemies/boss.tres")
	check(not invalid_group.validation_errors().is_empty(), "Regular enemy groups reject boss entries")
	var encounter: EncounterData = load("res://resources/encounters/boss.tres").duplicate(true)
	encounter.preparation_time = 0.01
	encounter.group_interval = 0.1
	encounter.boss_after_group_count = 6
	encounter.schedules.clear()
	encounter.schedules.append(_rule("guard", 6, 0.1))
	encounter.schedules.append(_rule("elite", 4, 0.1))
	check(encounter.validation_errors().is_empty(), "Boss encounter validates a repeating group list")
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crown"
	state.active_encounter = encounter
	var arena := await _scene("res://scenes/run/arena.tscn")
	arena.player.invulnerability = 9999
	arena.director.enemy_spawned.connect(func(unit: Node2D): unit.set_physics_process(false))
	await _advance(arena, 90)
	check(arena.director.started_groups == 6 and arena.director.generated_groups == 6, "Boss threshold stops later group generation after group six")
	check(arena.director.alive_regular_count == 6, "Time-based group spawning allows overlap with living earlier groups")
	check(arena.director.waiting_for_boss and not arena.director.boss_has_spawned, "Boss waits until every pre-threshold enemy dies")
	var units := get_nodes_in_group("enemies")
	for i in 5:
		units[i].receive_damage(9999)
	await _advance(arena, 5)
	check(not arena.director.boss_has_spawned, "One remaining regular enemy still prevents boss entry")
	units[5].receive_damage(9999)
	await _advance(arena, 3)
	check(arena.director.boss_has_spawned and arena.director.started_groups == 6, "Boss enters after clear, with no catch-up burst of paused groups")
	var boss: Node2D = null
	for unit in get_nodes_in_group("enemies"):
		if unit.data.category == EnemyData.Category.BOSS:
			boss = unit
	check(boss != null and boss.loadout.equipment.size() == 1 and boss.loadout.relics.size() == 1, "Boss is configured using the shared one-equipment one-relic loadout")
	check(boss.loadout_controller.equipped[0].attacks.size() == 2, "One boss equipment contains independent melee and ranged attack profiles")
	await _advance(arena, 40)
	check(arena.director.generated_groups >= 10 and arena.director.boss_alive and arena.director.alive_regular_count >= 4, "Groups keep spawning while boss remains alive")
	boss.receive_damage(9999)
	await _advance(arena, 3)
	check(not arena.encounter_won, "Defeating boss alone does not complete unfinished encounter")
	arena.director.duration_timer.start(0.05)
	await _advance(arena, 10)
	check(arena.encounter_won, "Boss defeated before time expires is settled when time ends")

func _partial_generation_check() -> void:
	state.new_run()
	state.start_with("pistol", "seed")
	state.current_cell_id = "crown"
	var encounter: EncounterData = load("res://resources/encounters/boss.tres").duplicate(true)
	encounter.preparation_time = 0.1
	encounter.group_interval = 0.1
	encounter.boss_after_group_count = 1
	encounter.schedules.clear()
	var first := _rule("guard", 1, 0.1)
	first.group = first.group.duplicate(true)
	first.group.entry_interval = 0.4
	first.group.entries[0].count = 2
	encounter.schedules.append(first)
	encounter.schedules.append(_rule("elite", 1, 0.1))
	state.active_encounter = encounter
	var arena := await _scene("res://scenes/run/arena.tscn")
	arena.player.invulnerability = 9999
	arena.director.enemy_spawned.connect(func(unit: Node2D):
		unit.set_physics_process(false)
		if unit.data.category != EnemyData.Category.BOSS:
			unit.receive_damage.call_deferred(9999))
	for i in 30:
		await _advance(arena, 1)
		if arena.director.total_spawned > 0:
			break
	await _advance(arena, 3)
	check(arena.director.alive_regular_count == 0 and arena.director.generating_groups == 1, "A partially emitted group can be temporarily clear without being generated completely")
	check(not arena.director.boss_has_spawned, "Boss waits for every member of threshold group to enter, even if earlier members are dead")
	await _advance(arena, 40)
	check(arena.director.boss_has_spawned, "Boss enters after the last member is generated and defeated")
	var boss_data: EnemyData = load("res://resources/enemies/boss.tres")
	var point: Vector2 = arena.director.random_spawn_position(null, boss_data)
	check(not Rect2(0, 0, 960, 540).grow(boss_data.required_spawn_margin() - 1.0).has_point(point), "Random spawn margin keeps the complete boss sprite offscreen")
	var invalid_location := SpawnLocationData.new()
	invalid_location.fixed_positions.append(Vector2(480, -40))
	check(not invalid_location.validation_errors(boss_data.required_spawn_margin()).is_empty(), "Fixed spawn validation detects partially visible boss sprites")

func _event_context_checks() -> void:
	state.new_run()
	state.start_with("pistol", "seed")
	state.current_cell_id = "shrine"
	var screen := await _scene("res://scenes/map/cell_resolution.tscn")
	var original_kind: int = screen.entry.kind
	var action := EventActionData.new()
	action.id = "test_battle"
	action.kind = EventActionData.Kind.ENCOUNTER
	action.encounter = load("res://resources/encounters/training.tres").duplicate(true)
	action.encounter.preparation_time = 0.01
	action.encounter.duration = 0.1
	action.encounter.group_interval = 0.1
	action.encounter.schedules.clear()
	action.encounter.schedules.append(_rule("guard", 1, 0.1))
	screen._execute_event_action(action)
	await process_frame
	await process_frame
	var arena: Node = current_scene
	check(state.current_cell_id == "shrine" and state.encounter_from_event, "Event starts a non-boss encounter without moving player")
	arena.director.enemy_spawned.connect(func(unit: Node2D): unit.receive_damage.call_deferred(9999))
	for unit in get_nodes_in_group("enemies"):
		unit.receive_damage.call_deferred(9999)
	await _advance(arena, 20)
	check(arena.encounter_won, "Event-triggered battle uses the ordinary encounter lifecycle")
	arena._continue_route()
	await process_frame
	await process_frame
	check(state.current_cell_id == "shrine" and current_scene.scene_file_path.ends_with("cell_resolution.tscn"), "Event battle returns to the original event cell")
	check(ContentCatalog.map().find_cell("shrine").kind == original_kind and not state.completed_cells.has("shrine"), "Event battle does not replace or prematurely complete its map cell")
	check(state.event_action_completed("test_battle"), "Event action is recorded once per run")
	var reward_action := EventActionData.new()
	reward_action.id = "test_reward"
	reward_action.kind = EventActionData.Kind.REWARD
	var option := RewardOptionData.new()
	option.title = "Test reward"
	option.reward = RewardData.new()
	option.reward.gold = 7
	option.reward.relics.append(ContentCatalog.relic("feather"))
	reward_action.reward_options.append(option)
	var before_gold: int = state.gold
	current_scene._execute_event_action(reward_action)
	current_scene._choose_reward(option, reward_action.id)
	check(state.gold == before_gold + 7 and state.relics.has("feather"), "Event rewards use the shared reward resolver")
	check(state.current_cell_id == "shrine" and current_scene.entry.kind == MapCellData.Kind.EVENT, "Event reward preserves map position and cell identity")
	current_scene._execute_event_action(reward_action)
	check(state.gold == before_gold + 7, "Completed event actions cannot be farmed repeatedly")
	var equipment_option := RewardOptionData.new()
	equipment_option.reward = RewardData.new()
	equipment_option.reward.equipment.append(ContentCatalog.weapon("cleaver"))
	current_scene._choose_reward(equipment_option, "test_equipment")
	current_scene._confirm_slot(0)
	check(state.weapons == ["cleaver", "pistol"] and state.current_cell_id == "shrine", "Equipment rewards select a shared loadout slot while preserving event context")
	var forbidden := EventActionData.new()
	forbidden.kind = EventActionData.Kind.ENCOUNTER
	forbidden.encounter = load("res://resources/encounters/boss.tres")
	check(not forbidden.validation_errors().is_empty() and not state.begin_event_encounter(forbidden), "Event actions reject boss encounters")
	current_scene._finish_cell()
	await process_frame
	await process_frame
	check(state.completed_cells.has("shrine") and state.current_cell_id == "shrine", "Leaving event completes it without moving the player")
