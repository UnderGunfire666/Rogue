class_name ScreenFrame
extends Control

@onready var body: VBoxContainer = $Margin/Layout/Body
@onready var title_label: Label = $Margin/Layout/Header/Title
@onready var summary_label: Label = $Margin/Layout/Header/Summary
@onready var footer_label: Label = $Margin/Layout/Footer

func _ready() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func heading(title: String, summary: String) -> void:
	title_label.text = title
	summary_label.text = summary

func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
