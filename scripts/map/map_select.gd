extends ScreenFrame
## Dream-expedition map selection. Shows only difficulty, theme, one placeholder
## artwork and a short description — never backend ratios or enemy previews.

var chosen_difficulty: String = ""
var cards: Dictionary = {}
var enter_button: Button

func _ready() -> void:
	super._ready()
	if RunState.expedition == null or not RunState.expedition.needs_map_selection():
		RunState.begin_expedition()
	var next_level := RunState.expedition.next_level()
	var template := ContentCatalog.map_template(next_level)
	var map_name := template.display_name if template != null else "梦境"
	var options := RunState.expedition.offered_difficulties()
	var subtitle := "远征 %d / %d  ·  %s  ·  %s" % [
		next_level, ExpeditionState.LEVEL_COUNT, map_name,
		"首张地图固定为心象（普通难度）。" if options.size() == 1 else "选择下一张地图的难度与主题；进入新地图时生命值完全恢复。"
	]
	heading("选择远征地图", subtitle)
	var row := UiKit.row(body, 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for item in options:
		var art_slot := RunState.expedition.offered_art_index(item, RunState.rng) + 1
		var caption := "主题：%s  ·  难度：%s\n原画占位 #%d\n\n%s" % [item.theme_name, item.display_name, art_slot, item.description]
		var card := UiKit.card(row, "%s · %s" % [item.theme_name, item.display_name], caption, item.placeholder_art, _select.bind(item.id))
		card.get_node("Margin/Content/Icon").custom_minimum_size.y = 110
		cards[item.id] = card
	if not options.is_empty():
		chosen_difficulty = options[0].id
	var actions := UiKit.row(body)
	UiKit.button(actions, "结束旅途", func(): RunState.go_to("res://scenes/app/title_screen.tscn"))
	enter_button = UiKit.button(actions, "踏入梦境  →", _confirm)
	enter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh()

func _select(id: String) -> void:
	chosen_difficulty = id
	_refresh()

func _confirm() -> void:
	if not RunState.enter_expedition_map(chosen_difficulty):
		summary_label.text = "地图模板配置无效。"
		return
	RunState.go_to("res://scenes/map/map_screen.tscn")

func _refresh() -> void:
	enter_button.disabled = chosen_difficulty.is_empty()
	for id: String in cards:
		cards[id].set_selected(id == chosen_difficulty)
