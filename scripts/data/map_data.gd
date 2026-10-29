class_name MapData
extends Resource

@export var display_name: String = ""
@export var starting_cell_id: String = ""
@export var cells: Array[MapCellData] = []
## false: authored grid map, four-direction adjacency in both directions.
## true: route map, movement follows each cell's next_cell_ids only.
@export var directed_routes: bool = false
@export var boss_cell_id: String = ""

func find_cell(id: String) -> MapCellData:
	for cell in cells:
		if cell.id == id:
			return cell
	return null

func neighbors(id: String) -> Array[String]:
	var result: Array[String] = []
	var source := find_cell(id)
	if source == null:
		return result
	if directed_routes:
		for next_id in source.next_cell_ids:
			result.append(next_id)
		return result
	for cell in cells:
		var offset := cell.grid_position - source.grid_position
		if absi(offset.x) + absi(offset.y) == 1:
			result.append(cell.id)
	return result

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary = {}
	var positions: Dictionary = {}
	for cell in cells:
		if cell == null:
			errors.append("地图格子不能为空。")
			continue
		if ids.has(cell.id) or cell.id.is_empty():
			errors.append("地图格子 ID 必须非空且唯一。")
		if positions.has(cell.grid_position):
			errors.append("地图格子坐标必须唯一。")
		ids[cell.id] = true
		positions[cell.grid_position] = true
		errors.append_array(cell.validation_errors())
	if find_cell(starting_cell_id) == null:
		errors.append("地图缺少起点格子。")
	return errors
