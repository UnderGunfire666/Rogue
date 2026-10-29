extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _screen(path: String, filename: String) -> void:
	paused = false
	change_scene_to_file(path)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	print(filename, " body=", current_scene.body.get_global_rect(), " footer=", current_scene.footer_label.get_global_rect(), " root=", root.get_visible_rect())
	root.get_texture().get_image().save_png("res://.godot/qa/" + filename + ".png")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/qa")
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	await _screen("res://scenes/app/title_screen.tscn", "title")
	await _screen("res://scenes/app/loadout_select.tscn", "loadout")
	await _screen("res://scenes/map/map_screen.tscn", "map")
	state.gold = 84
	await _screen("res://scenes/ui/shop_screen.tscn", "shop")
	state.current_cell_id = "shrine"
	await _screen("res://scenes/map/cell_resolution.tscn", "event")
	state.equip_weapon("cleaver", 0)
	state.equip_weapon("pistol", 1)
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	for definition in [["melee", Vector2(400, 245)], ["melee", Vector2(430, 220)], ["melee", Vector2(550, 320)], ["ranged", Vector2(650, 210)], ["healer", Vector2(610, 355)]]:
		var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
		unit.data = load("res://resources/enemies/%s.tres" % definition[0])
		unit.player = arena.player
		unit.position = definition[1]
		arena.get_node("Enemies").add_child(unit)
		unit.health.take_damage(5)
		unit.set_physics_process(false)
	arena.hud.update_group_progress(1, 3, "战斗中")
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/qa/arena.png")
	arena.player.skill.toggle_targeting()
	arena.get_viewport().warp_mouse(Vector2(600, 300))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/qa/skill.png")
	paused = true
	arena.overlay.show_upgrades()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/qa/upgrade.png")
	print("PREVIEWS SAVED")
	quit()
