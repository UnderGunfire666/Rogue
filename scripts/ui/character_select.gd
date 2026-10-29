extends ScreenFrame

var characters := PackedStringArray()
var selected := ""
var detail: VBoxContainer

func _ready() -> void:
	super._ready()
	heading("选择角色", "01 / 02 · 选择旅人，查看全部初始主属性。")
	characters = ContentCatalog.character_ids()
	var row := UiKit.row(body)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := ItemList.new()
	list.custom_minimum_size.x = 200
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(list)
	for id in characters: list.add_item(ContentCatalog.character(id).display_name)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	list.item_selected.connect(func(index: int): _select(characters[index]))
	if not characters.is_empty():
		list.select(0)
		_select(characters[0])
	var actions := UiKit.row(body)
	UiKit.button(actions, "← 返回", func(): RunState.go_to("res://scenes/app/title_screen.tscn"))
	var next := UiKit.button(actions, "选择角色，准备装备 →", func():
		if not selected.is_empty():
			RunState.select_character(selected)
			RunState.go_to("res://scenes/app/loadout_select.tscn"))
	next.disabled = characters.is_empty()
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _select(id: String) -> void:
	selected = id
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	var character := ContentCatalog.character(id)
	var stats: Dictionary = RunState.preview_character(id)
	UiKit.label(detail, character.display_name, 23, Color("#efd5a4"))
	if not character.description.is_empty():
		var description := UiKit.label(detail, character.description, 14)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.label(detail, "基础移动 %.1f · 实际 %.0f 像素/秒" % [character.movement_units, stats.actual_speed], 14)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for stat_id in PlayerPrimaryStats.IDS:
		var value := float(stats[stat_id])
		if stat_id == "max_hp": value = maxf(1.0, value)
		var display := "%.0f" % value if stat_id == "max_hp" else PlayerPrimaryStats.format_value(stat_id, value)
		UiKit.label(grid, PlayerPrimaryStats.label(stat_id) + "  " + display, 15)
