extends SceneTree

const EditorPanel = preload("res://addons/enemy_editor/enemy_editor_dock.gd")

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var panel: Control = EditorPanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.request_open("res://resources/enemies/boss.tres")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/qa"))
	for index in 3:
		panel._tabs.current_tab = index
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/qa/enemy_editor_%d.png" % index)
	print("Enemy editor previews captured.")
	quit()
