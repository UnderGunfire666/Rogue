class_name EventData
extends Resource

enum Scope { PERSONAL, PARTY }
@export var id: String = ""
@export var title: String = ""
@export var scope: Scope = Scope.PERSONAL
@export_multiline var text: String = ""
@export var actions: Array[EventActionData] = []

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var needs_abandon := false
	var has_abandon := false
	for action in actions:
		if action == null:
			errors.append("事件动作不能为空。")
			continue
		errors.append_array(action.validation_errors())
		if action.kind == EventActionData.Kind.ENCOUNTER and scope != Scope.PARTY:
			errors.append("进入战斗的选项只能出现在全队事件中。")
		if action.has_cost() and scope != Scope.PERSONAL:
			errors.append("付出代价换取奖励的事件必须为个人选择事件。")
		if action.has_cost():
			needs_abandon = true
		if action.is_abandon or action.label.contains("放弃") or action.label.contains("离开"):
			has_abandon = true
	if needs_abandon and not has_abandon:
		errors.append("包含代价选项的事件必须提供“放弃”选项。")
	return errors
