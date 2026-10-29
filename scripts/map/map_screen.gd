extends ScreenFrame

const MAP_CANVAS := preload("res://scripts/map/map_canvas.gd")

func _ready() -> void:
	super._ready()
	_render()

func _render() -> void:
	clear_body()
	var map := RunState.current_map()
	var title := "行进地图 · " + map.display_name
	var subtitle := "沿上下左右相邻格移动。完成过的格子可以返回，内容只触发一次。"
	if RunState.expedition != null:
		var cell := map.find_cell(RunState.current_cell_id)
		var depth_text := "第 %d / %d 层" % [cell.depth, ExpeditionMapGenerator.DEPTH_COUNT] if cell != null else ""
		title = "梦境远征 %d / %d · %s · %s（%s）" % [
			RunState.expedition.level, ExpeditionState.LEVEL_COUNT, map.display_name,
			RunState.expedition.difficulty.theme_name, RunState.expedition.difficulty.display_name
		]
		subtitle = "%s · 选择下方已揭示的相邻格前进；滚轮缩放、拖拽浏览整张地图与底部 BOSS 终点。" % depth_text
	heading(title, subtitle)
	var status := UiKit.row(body, 14)
	UiKit.label(status, "生命 %.0f / %.0f    金币 %d    等级 %d    遗物 %d" % [RunState.health, RunState.effective_max_health(), RunState.gold, RunState.level, RunState.relics.size()], 15, Color("#efd5a4"))
	var status_spacer := Control.new()
	status_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(status_spacer)
	var canvas := Control.new()
	canvas.set_script(MAP_CANVAS)
	canvas.custom_minimum_size = Vector2(0, 228)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	canvas.cell_chosen.connect(_enter_cell)
	UiKit.button(status, "当前位置", canvas.center_on_current)
	UiKit.button(status, "全图 / BOSS", canvas.show_overview)
	UiKit.button(status, "放大 +", func(): canvas.set_zoom(canvas.zoom * 1.2))
	UiKit.button(status, "缩小 −", func(): canvas.set_zoom(canvas.zoom / 1.2))
	var legend := UiKit.row(body, 20)
	for kind in [MapCellData.Kind.NORMAL_BATTLE, MapCellData.Kind.ELITE_BATTLE, MapCellData.Kind.BOSS_BATTLE, MapCellData.Kind.REWARD, MapCellData.Kind.EVENT]:
		var sample := MapCellData.new()
		sample.kind = kind
		UiKit.label(legend, sample.type_name(), 12, sample.type_color())
	var row := UiKit.row(body)
	UiKit.label(row, UiKit.inventory_text(), 14)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	UiKit.button(row, "结束旅途", func(): RunState.go_to("res://scenes/app/title_screen.tscn"))

func _enter_cell(id: String) -> void:
	if not RunState.available.has(id):
		return
	var cell := RunState.current_map().find_cell(id)
	if not RunState.completed_cells.has(id):
		var errors := cell.validation_errors()
		if not errors.is_empty():
			summary_label.text = "格子配置无效：" + "；".join(errors)
			return
	if not RunState.move_to_cell(id):
		return
	if RunState.completed_cells.has(id):
		_render()
		return
	if cell.is_battle():
		if RunState.begin_cell_encounter():
			RunState.go_to("res://scenes/run/arena.tscn")
		else:
			summary_label.text = "格子配置无效：" + "；".join(cell.validation_errors())
	else:
		RunState.go_to("res://scenes/map/cell_resolution.tscn")
