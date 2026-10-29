extends Control
## Renders a MapData and its fog of war. Keeps the current cell centred unless
## the player pans/zooms to inspect the map; a button or Home recentres.
## Content is hidden before a cell is entered — only the revealed type is shown.

signal cell_chosen(id: String)
const MIN_ZOOM := 0.28
const MAX_ZOOM := 1.4
const OVERVIEW_ZOOM := 0.34
var map: MapData
var zoom: float = 1.0
var pan_offset := Vector2.ZERO
var _dragging := false
var _dragged := false
var _buttons := {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	map = RunState.current_map()
	var step := _step()
	var box := _box()
	for cell in map.cells:
		var button := Button.new()
		button.size = box
		button.add_theme_font_size_override("font_size", 11 if map.directed_routes else 12)
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.pressed.connect(func():
			if not _dragged: cell_chosen.emit(cell.id))
		add_child(button)
		_buttons[cell.id] = button
	resized.connect(_layout)
	if RunState.expedition != null:
		RunState.expedition.exploration.changed.connect(_layout)
	_layout()

func center_on_current() -> void:
	pan_offset = Vector2.ZERO
	zoom = 1.0
	_layout()

func show_overview() -> void:
	if map == null or map.cells.is_empty():
		return
	var bounds := Rect2(_local_point(map.cells[0]), Vector2.ZERO)
	for cell in map.cells:
		bounds = bounds.expand(_local_point(cell))
	var anchor := map.find_cell(RunState.current_cell_id)
	var anchor_point := _local_point(anchor) if anchor != null else bounds.get_center()
	zoom = OVERVIEW_ZOOM
	pan_offset = (anchor_point - bounds.get_center()) * zoom
	_layout()

func set_zoom(value: float) -> void:
	var next := clampf(value, MIN_ZOOM, MAX_ZOOM)
	pan_offset *= next / zoom
	zoom = next
	_layout()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_zoom(zoom * 1.15)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_zoom(zoom / 1.15)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
			if event.pressed: _dragged = false
	elif event is InputEventMouseMotion and _dragging:
		if event.relative.length_squared() > 4.0:
			_dragged = true
		pan_offset += event.relative
		_layout()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		center_on_current()

func _step() -> Vector2:
	return Vector2(96, 74) if map.directed_routes else Vector2(215, 116)

func _box() -> Vector2:
	return Vector2(82, 46) if map.directed_routes else Vector2(160, 82)

func _local_point(cell: MapCellData) -> Vector2:
	if map.directed_routes:
		return cell.view_position * _step()
	return Vector2(cell.grid_position - Vector2i(0, 1)) * _step()

func _screen_point(cell: MapCellData) -> Vector2:
	var anchor := map.find_cell(RunState.current_cell_id)
	var center := size * 0.5 if size.x > 0.0 and size.y > 0.0 else Vector2(440, 120)
	var anchor_point := _local_point(anchor) if anchor != null else Vector2.ZERO
	return center + pan_offset + (_local_point(cell) - anchor_point) * zoom

func _layout() -> void:
	if map == null:
		return
	var box := _box()
	for cell in map.cells:
		var button: Button = _buttons[cell.id]
		var point := _screen_point(cell)
		button.scale = Vector2.ONE * zoom
		button.position = point - box * zoom * 0.5
		_configure_button(cell, button)
	queue_redraw()

func _configure_button(cell: MapCellData, button: Button) -> void:
	var current := RunState.current_cell_id == cell.id
	var complete := RunState.completed_cells.has(cell.id)
	var reachable := RunState.available.has(cell.id)
	var revealed := RunState.is_cell_revealed(cell.id)
	button.disabled = not reachable
	if not revealed:
		button.text = "迷雾\n???"
		button.tooltip_text = "未揭示的梦境区域。"
		var fog := Color("#3a4b52")
		button.add_theme_color_override("font_color", fog)
		button.add_theme_color_override("font_disabled_color", fog)
		return
	var color := cell.type_color()
	if map.directed_routes:
		# Before entering a cell, show only its type — never its specific content.
		var status := "当前位置" if current else "已通过" if complete else "可前往" if reachable else "已揭示"
		var detail := cell.display_name if current or complete else status
		button.text = "%s\n%s" % [cell.type_name(), detail]
		button.tooltip_text = cell.description if current or complete else "%s（进入后揭晓具体内容）" % cell.type_name()
	else:
		var status := "当前位置" if current else "已完成 · 可返回" if complete else "可前往" if reachable else "未抵达"
		button.text = "%s\n%s · %s" % [cell.display_name, cell.type_name(), status]
		button.tooltip_text = cell.description
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.2))
	button.add_theme_color_override("font_focus_color", color.lightened(0.2))
	button.add_theme_color_override("font_disabled_color", Color(color, 0.85 if complete or current else 0.48))

func _draw() -> void:
	if map == null:
		return
	var box := _box() * zoom
	for cell in map.cells:
		var from_revealed := RunState.is_cell_revealed(cell.id)
		for neighbor_id in map.neighbors(cell.id):
			if not map.directed_routes and neighbor_id < cell.id:
				continue
			var neighbor := map.find_cell(neighbor_id)
			var both_revealed := from_revealed and RunState.is_cell_revealed(neighbor.id)
			var active := cell.id == RunState.current_cell_id and RunState.available.has(neighbor.id)
			var traversed := RunState.completed_cells.has(cell.id) and RunState.completed_cells.has(neighbor.id)
			var color := Color("#e7c68d") if active else Color("#527f72") if traversed else Color("#2f4a55") if both_revealed else Color("#18242b")
			draw_line(_screen_point(cell), _screen_point(neighbor), color, maxf(1.5, (3.0 if active else 2.2) * zoom))
	for cell in map.cells:
		var point := _screen_point(cell)
		if not RunState.is_cell_revealed(cell.id):
			draw_rect(Rect2(point - box * 0.5, box), Color(0.05, 0.08, 0.10, 0.72), true)
		if cell.id == RunState.current_cell_id:
			var pad := Vector2(3, 3) * zoom
			draw_rect(Rect2(point - box * 0.5 - pad, box + pad * 2.0), Color("#e7c68d"), false, maxf(1.5, 2.0 * zoom))
