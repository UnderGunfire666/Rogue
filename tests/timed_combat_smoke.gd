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
	state.start_with("pistol", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	var player: Node2D = arena.player
	player.set_physics_process(false)
	for item in player.inventory.equipped: item.set_physics_process(false)
	var gun: Node2D = player.inventory.equipped[0]
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = player
	unit.position = player.position + Vector2(0, 100)
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.entered_arena = true
	var before: int = arena.get_node("Projectiles").get_child_count()
	gun._physics_process(0.016)
	check(arena.get_node("Projectiles").get_child_count() == before + 1, "Ranged weapon automatically fires without input")
	var bullet: Node2D = arena.get_node("Projectiles").get_child(before)
	check(bullet.direction.y > 0.99, "Automatic projectile aims at the enemy")
	check(not gun.cooldown.is_stopped(), "Automatic attacks respect cooldown")
	var start: Vector2 = bullet.position
	unit.position = player.position + Vector2(100, 0)
	for i in 5: await physics_frame
	check(is_instance_valid(bullet) and is_equal_approx(bullet.position.x, start.x) and bullet.position.y > start.y, "Projectile keeps its straight trajectory after its target moves")
	unit.queue_free()
	bullet.queue_free()
	await process_frame
	state.gain_loot(100, 0)
	await process_frame
	check(state.pending_upgrades > 1 and not paused and arena.overlay.mode != "upgrade", "Experience queues multiple levels without interrupting combat")
	state.pending_upgrades = 2
	state.experience = 0
	var rule := GroupSpawnSchedule.new()
	rule.group = load("res://resources/groups/guard.tres")
	var encounter := EncounterData.new()
	encounter.preparation_time = 0.01
	encounter.duration = 1.2
	encounter.group_interval = 0.25
	encounter.schedules.append(rule)
	arena.director.encounter = encounter
	arena.director.begin()
	for i in 95: await physics_frame
	check(arena.encounter_won and arena.director.started_groups >= 4, "Fixed duration repeats group beyond the configured category list")
	check(arena.director.elapsed and not arena.director.active, "Time limit completes normal encounter")
	check(arena.overlay.mode == "upgrade" and state.pending_upgrades == 2, "All accumulated upgrades appear after victory")
	var first: String = state.upgrade_offers[0].id
	arena._upgrade_chosen(first)
	check(arena.overlay.mode == "upgrade" and state.pending_upgrades == 1, "Multiple levels are settled one at a time")
	var second: String = state.upgrade_offers[0].id
	arena._upgrade_chosen(second)
	check(arena.overlay.mode == "victory" and state.pending_upgrades == 0, "Victory is shown only after the final upgrade")
	await process_frame
	check(arena.get_node("Enemies").get_child_count() == 0, "Time limit clears surviving enemies")
	print("TIMED COMBAT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
