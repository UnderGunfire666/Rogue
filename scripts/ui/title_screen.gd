extends ScreenFrame

func _ready() -> void:
	super._ready()
	heading("余烬之路", "在荒地中选择前路，带着你的武器与遗物，抵达枯冠之门。")
	var row := UiKit.row(body, 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var introduction := VBoxContainer.new()
	introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	introduction.add_theme_constant_override("separation", 14)
	row.add_child(introduction)
	UiKit.label(introduction, "一人，一段短途冒险。", 25, Color("#efd5a4"))
	UiKit.label(introduction, "选择武器和遗物，在敌群中存活。\n沿地图探索奖励、事件与精英格，挑战关底首领。", 16)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	introduction.add_child(spacer)
	var play := UiKit.button(introduction, "开始旅途  →", func():
		RunState.new_run()
		RunState.go_to("res://scenes/app/character_select.tscn"))
	play.custom_minimum_size.y = 48
	play.grab_focus()
	UiKit.button(introduction, "退出", func(): get_tree().quit())
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(330, 0)
	row.add_child(preview)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	preview.add_child(column)
	var image := TextureRect.new()
	image.texture = load("res://assets/art/wanderer.svg")
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.custom_minimum_size = Vector2(0, 140)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(image)
	var name_label := UiKit.label(column, "W A N D E R E R", 17, Color("#80c7b5"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var version := UiKit.label(column, "短波次战斗 / 路线选择 / 构筑", 12)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
