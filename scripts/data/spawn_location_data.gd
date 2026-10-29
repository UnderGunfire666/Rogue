class_name SpawnLocationData
extends Resource

enum Edge { LEFT, RIGHT, TOP, BOTTOM }
@export var edges: PackedInt32Array = [0, 1, 2, 3]
@export var fixed_positions: PackedVector2Array = []
@export_range(24.0, 300.0) var margin: float = 36.0

func validation_errors(required_margin: float = 24.0) -> PackedStringArray:
	var errors := PackedStringArray()
	if fixed_positions.is_empty() and edges.is_empty():
		errors.append("生成位置需要至少一个屏幕外坐标或边界方向。")
	for edge in edges:
		if edge < 0 or edge > 3:
			errors.append("生成边界必须为 Left、Right、Top 或 Bottom。")
	for point in fixed_positions:
		if not point.is_finite() or Rect2(0, 0, 960, 540).grow(required_margin).has_point(point):
			errors.append("固定生成位置需要让完整敌人图像位于画面外。")
	return errors
