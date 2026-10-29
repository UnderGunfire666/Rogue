@tool
extends "res://addons/content_editor/item_editor_plugin.gd"

func _editor_kind() -> String:
	return "equipment"

func _get_plugin_name() -> String:
	return "Equipment Editor"
