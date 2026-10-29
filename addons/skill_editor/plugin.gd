@tool
extends EditorPlugin

const SkillPanel = preload("res://addons/skill_editor/skill_editor_panel.gd")
var panel: Control

func _enter_tree() -> void:
	panel = SkillPanel.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	add_tool_menu_item("技能编辑器 / Skill Editor", _open)

func _exit_tree() -> void:
	remove_tool_menu_item("技能编辑器 / Skill Editor")
	if is_instance_valid(panel):
		panel.queue_free()

func _open() -> void:
	EditorInterface.set_main_screen_editor(_get_plugin_name())

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Skill Editor"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Resource", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = value
		if value and panel.has_method("ensure_loaded"):
			panel.ensure_loaded()

func _handles(object: Object) -> bool:
	return object is SkillData

func _edit(object: Object) -> void:
	if is_instance_valid(panel) and object is SkillData and not object.resource_path.is_empty() and not object.resource_path.contains("::"):
		panel.request_open(object.resource_path)

func _get_unsaved_status(for_scene: String) -> String:
	return "Skill Editor 有未保存草稿。" if for_scene.is_empty() and is_instance_valid(panel) and panel.is_dirty() else ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.is_dirty():
		panel.save_current(false)

