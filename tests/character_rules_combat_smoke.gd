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
	state.select_character("sick")
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	for weapon in arena.player.inventory.equipped: weapon.set_physics_process(false)
	check(arena.player.health.current == 112, "Sick starts with increased max health")
	for i in 65: await physics_frame
	check(arena.player.health.current == 111, "Sick takes one direct damage every combat second")
	paused = true
	for i in 65: await physics_frame
	check(arena.player.health.current == 111, "Combat-second effects pause with the game")
	paused = false
	var rules := CharacterCombatRules.new()
	rules.can_heal = false
	rules.enemy_health_multiplier = 2
	rules.enemy_speed_multiplier = 0.5
	rules.enemy_damage_multiplier = 1.5
	state.character.combat_rules = rules
	arena.player.health.heal(10)
	check(arena.player.health.current == 111, "Healing prohibition affects player healing")
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = arena.player
	unit.position = arena.player.position + Vector2(200, 0)
	arena.get_node("Enemies").add_child(unit)
	unit.entered_arena = true
	unit.set_physics_process(false)
	check(unit.health.maximum == 64 and is_equal_approx(unit.get_damage_multiplier(), 1.5), "Enemy health and damage multipliers affect spawned enemies")
	unit._physics_process(1.0 / 60.0)
	check(is_equal_approx(unit.velocity.length(), 72.0), "Enemy speed multiplier applies during movement")
	state.new_run()
	state.select_character("wounded")
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	arena = current_scene
	arena.director.stop()
	arena.player.receive_damage(1)
	check(arena.defeated and not arena.player.health.is_alive(), "Wounded dies when a non-dodged attack lands")
	print("CHARACTER RULES COMBAT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
