extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func make_arena(threshold: int = 0) -> Node:
	paused = false
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crown"
	var encounter: EncounterData = load("res://resources/encounters/boss.tres").duplicate(true)
	encounter.preparation_time = 0.01
	encounter.duration = 0.8
	encounter.group_interval = 0.2
	encounter.boss_after_group_count = threshold
	state.active_encounter = encounter
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	current_scene.player.invulnerability = 9999
	for weapon in current_scene.player.inventory.equipped: weapon.set_physics_process(false)
	return current_scene

func _run() -> void:
	var state := root.get_node("RunState")
	var arena := await make_arena()
	for i in 8: await physics_frame
	check(arena.director.boss_has_spawned and arena.director.boss_alive, "Boss spawns before timeout")
	var count: int = state.loadout.relics.size()
	for i in 60: await physics_frame
	check(arena.encounter_won and arena.director.boss_alive, "Surviving boss still permits victory at timeout")
	check(state.loadout.relics.size() == count, "Surviving boss grants no boss chest reward")
	check(arena.overlay.mode == "victory", "Surviving boss produces victory overlay")
	arena = await make_arena(1)
	count = state.loadout.relics.size()
	for i in 68: await physics_frame
	check(arena.encounter_won and not arena.director.boss_has_spawned, "Timeout wins even when the pre-boss group has not been cleared")
	check(state.loadout.relics.size() == count, "No boss chest is awarded when the boss never entered")
	arena = await make_arena()
	for i in 8: await physics_frame
	var boss: Node2D
	for unit in get_nodes_in_group("enemies"):
		if unit.data.category == EnemyData.Category.BOSS: boss = unit
	check(is_instance_valid(boss), "Boss exists in defeat scenario")
	count = state.loadout.relics.size()
	if is_instance_valid(boss): boss.receive_damage(99999)
	var boss_crates := 0
	for pickup in arena.get_node("Pickups").get_children():
		if pickup.is_boss_crate: boss_crates += 1
	check(boss_crates == 1 and not arena.encounter_won, "Boss defeat creates exactly one large chest without ending the timer")
	for i in 60: await physics_frame
	check(arena.encounter_won and not arena.director.boss_alive, "Defeated boss settles at the time limit")
	check(state.loadout.relics.size() == count + 1, "Large chest is collected at victory and grants one relic")
	print("BOSS TIMEOUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
