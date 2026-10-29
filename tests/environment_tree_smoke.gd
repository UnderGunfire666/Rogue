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
	state.character.combat_rules = CharacterCombatRules.new()
	state.character.combat_rules.environment_tree_count = 2
	state.character.combat_rules.tree_hp_regeneration = 3
	state.character.combat_rules.tree_materials_at_combat_end = 12
	state.character.combat_rules.tree_xp_at_combat_end = 12
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	for weapon in arena.player.inventory.equipped: weapon.set_physics_process(false)
	var trees := get_nodes_in_group("environment_trees")
	check(trees.size() == 2 and state.stat_value("hp_regeneration") == 6, "Living trees contribute configured regeneration")
	var tree: Node2D = trees[0]
	tree.position = arena.player.position + Vector2(45, 0)
	await physics_frame
	check(CombatTargeting.attackable_targets(self).has(tree), "Tree participates in player weapon targeting")
	var weapon: Node2D = arena.player.inventory.equipped[0]
	weapon.data = weapon.data.duplicate()
	weapon.data.damage = 23.0
	weapon._try_direct_attack()
	for i in 65: await physics_frame
	check(is_instance_valid(tree) and tree.health.current == 7, "Weapon trajectory damages a destructible tree")
	tree.receive_damage(100)
	check(state.stat_value("hp_regeneration") == 3 and arena.get_node("Pickups").get_child_count() == 1, "Destroyed tree removes its bonus and drops a pickup")
	arena._encounter_completed()
	check(state.gold == 24 and state.experience == 0 and state.pending_upgrades == 1, "One surviving tree grants configured end-of-combat currency and experience")
	print("ENVIRONMENT TREES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
