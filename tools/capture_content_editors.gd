extends SceneTree

const ItemPanel = preload("res://addons/content_editor/item_editor_panel.gd")
const EnemyPanel = preload("res://addons/enemy_editor/enemy_editor_dock.gd")

func _initialize() -> void:
	_capture.call_deferred()

func _shot(name: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/qa/" + name + ".png")

func _capture() -> void:
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/qa"))
	var equipment: Control = ItemPanel.new()
	root.add_child(equipment)
	equipment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment.request_open("res://resources/weapons/storm_tome.tres")
	equipment._tabs.current_tab = 1
	await _shot("equipment_editor_spell")
	equipment.request_open("res://resources/weapons/scattergun.tres")
	await _shot("equipment_editor_ranged")
	equipment.request_open("res://resources/enemy_equipment/healing_staff.tres")
	await _shot("equipment_editor_healing")
	equipment.queue_free()
	await process_frame
	var relic: Control = ItemPanel.new()
	relic.kind = "relic"
	root.add_child(relic)
	relic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	relic.request_open("res://resources/enemy_relics/crown_vigor.tres")
	relic._tabs.current_tab = 1
	await _shot("relic_editor")
	relic.queue_free()
	await process_frame
	var enemy: Control = EnemyPanel.new()
	root.add_child(enemy)
	enemy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy.request_open("res://resources/enemies/healer.tres")
	await _shot("enemy_editor_fixed_speed")
	enemy.queue_free()
	await process_frame
	root.size = Vector2i(960, 540)
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	change_scene_to_file("res://scenes/app/loadout_select.tscn")
	await _shot("six_weapon_loadout")
	state.gold = 100
	change_scene_to_file("res://scenes/ui/shop_screen.tscn")
	await _shot("six_weapon_shop")
	print("Content editor and six-weapon UI previews captured.")
	quit()
