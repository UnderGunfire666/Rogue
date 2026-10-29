@tool
extends RefCounted
## Small native-Control field builders, bound to isolated Resource drafts.

var changed: Callable
var choose_texture: Callable

func row(parent: Node, label: String, control: Control) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 170
	line.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)
	parent.add_child(line)

func text(parent: Node, label: String, data: Resource, property: String, multiline: bool = false) -> Control:
	var control: Control
	if multiline:
		var field := TextEdit.new()
		field.text = str(data.get(property))
		field.custom_minimum_size.y = 76
		field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		field.text_changed.connect(func():
			data.set(property, field.text)
			changed.call())
		control = field
	else:
		var field := LineEdit.new()
		field.text = str(data.get(property))
		field.text_changed.connect(func(value: String):
			data.set(property, value)
			changed.call())
		control = field
	control.name = property
	row(parent, label, control)
	return control

func number(parent: Node, label: String, data: Resource, property: String, minimum: float = 0.0, step: float = 0.1, percent: bool = false) -> SpinBox:
	var field := SpinBox.new()
	field.name = property
	field.min_value = minimum
	field.max_value = 100000
	field.allow_greater = true
	# Range rounds relative to min_value. Align negative percent bounds as well.
	var quantum := step
	while not is_equal_approx(minimum / quantum, roundf(minimum / quantum)) and quantum > 0.000001:
		quantum /= 10.0
	field.step = quantum
	field.value = float(data.get(property)) * (100.0 if percent else 1.0)
	if percent:
		field.suffix = "%"
	field.value_changed.connect(func(value: float):
		data.set(property, value / 100.0 if percent else value)
		changed.call())
	row(parent, label, field)
	return field

func choice(parent: Node, label: String, data: Resource, property: String, labels: Array[String], rebuild: Callable = Callable()) -> OptionButton:
	var field := OptionButton.new()
	field.name = property
	for index in labels.size():
		field.add_item(labels[index], index)
	field.select(int(data.get(property)))
	field.item_selected.connect(func(index: int):
		data.set(property, index)
		changed.call()
		if rebuild.is_valid():
			rebuild.call_deferred())
	row(parent, label, field)
	return field

func toggle(parent: Node, label: String, data: Resource, property: String) -> CheckBox:
	var field := CheckBox.new()
	field.name = property
	field.text = "允许"
	field.button_pressed = bool(data.get(property))
	field.toggled.connect(func(value: bool):
		data.set(property, value)
		changed.call())
	row(parent, label, field)
	return field

func texture(parent: Node, label: String, data: Resource, property: String) -> void:
	var box := HBoxContainer.new()
	var path := LineEdit.new()
	path.name = property
	path.editable = false
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := data.get(property) as Texture2D
	path.text = current.resource_path if current != null else "（未选择）"
	box.add_child(path)
	button(box, "选择…", func():
		choose_texture.call(data, property, path))
	button(box, "清除", func():
		data.set(property, null)
		path.text = "（未选择）"
		changed.call())
	row(parent, label, box)

func item(parent: Node, data: ItemDefinition) -> void:
	text(parent, "物品 ID", data, "id")
	text(parent, "显示名称", data, "display_name")
	text(parent, "描述", data, "description", true)
	texture(parent, "物品图标", data, "icon")
	var rarity := number(parent, "稀有度（1–5）", data, "rarity", 1, 1)
	rarity.max_value = 5
	rarity.allow_greater = false

func button(parent: Node, label: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func note(parent: Node, message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
