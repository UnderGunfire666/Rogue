@tool
extends EditorPlugin

const EnemyEditorDock = preload("res://addons/enemy_editor/enemy_editor_dock.gd")
var panel: Control

func _enter_tree() -> void:
	panel = EnemyEditorDock.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	add_tool_menu_item("敌人编辑器 / Enemy Editor", _open_editor)

func _exit_tree() -> void:
	remove_tool_menu_item("敌人编辑器 / Enemy Editor")
	if is_instance_valid(panel):
		panel.queue_free()

func _open_editor() -> void:
	EditorInterface.set_main_screen_editor("Enemy Editor")

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Enemy Editor"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("CharacterBody2D", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = value

func _handles(object: Object) -> bool:
	return object is EnemyData

func _edit(object: Object) -> void:
	if is_instance_valid(panel) and object is EnemyData and not object.resource_path.is_empty():
		panel.request_open(object.resource_path)

func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(panel) and panel.is_dirty():
		return "敌人编辑器有未保存草稿，请保存或放弃修改。"
	return ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.is_dirty():
		panel.save_current(false)
