extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + text)

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.select_character("old")
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	check(is_equal_approx(arena.player.movement_bounds.size.x, 910 * 0.67), "Old character shrinks arena movement bounds")
	check(arena.get_node("Camera2D").zoom == Vector2.ONE, "Shrunk arena keeps original camera scale")
	state.character.combat_rules.arena_size_multiplier = 2.0
	state.active_encounter = null
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene
	check(arena.get_node("Camera2D").zoom == Vector2(0.5, 0.5), "Expanded arena adjusts the camera")
	var boss: EnemyData = load("res://resources/enemies/boss.tres")
	var fixed: SpawnLocationData = load("res://resources/spawns/boss_north.tres")
	for i in 15:
		var point: Vector2 = arena.director.random_spawn_position(fixed, boss)
		check(not arena.director.visible_bounds.grow(boss.required_spawn_margin()).has_point(point), "Expanded view keeps entire boss outside the camera")
	print("ARENA SIZE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
