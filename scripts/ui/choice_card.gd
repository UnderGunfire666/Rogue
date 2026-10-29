class_name ChoiceCard
extends PanelContainer

signal selected
@onready var title_label: Label = $Margin/Content/Title
@onready var description: Label = $Margin/Content/Description
@onready var icon: TextureRect = $Margin/Content/Icon
@onready var action: Button = $Margin/Content/Action

func _ready() -> void:
	action.pressed.connect(func(): selected.emit())

func configure(title: String, text: String, texture: Texture2D, button_text: String = "选择") -> void:
	title_label.text = title
	description.text = text
	icon.texture = texture
	icon.visible = texture != null
	action.text = button_text

func set_selected(value: bool) -> void:
	modulate = Color.WHITE if value else Color(0.70, 0.77, 0.77)
	action.text = "已选择 ✓" if value else "选择"
