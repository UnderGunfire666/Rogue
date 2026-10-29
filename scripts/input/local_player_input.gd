class_name LocalPlayerInput
extends Node

signal fire_requested
signal skill_requested
signal character_skill_requested
signal cancel_or_pause_requested
signal cancel_skill_requested

func movement() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				fire_requested.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_skill_requested.emit()
	if event.is_action_pressed("skill"):
		skill_requested.emit()
	if event.is_action_pressed("character_skill"):
		character_skill_requested.emit()
	if event.is_action_pressed("pause_game"):
		cancel_or_pause_requested.emit()
