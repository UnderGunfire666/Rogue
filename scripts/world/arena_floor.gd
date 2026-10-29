extends TileMapLayer

var bounds := Rect2(17, 68, 926, 429)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 82031
	var scale: float = RunState.combat_rules().arena_size_multiplier
	var center := bounds.get_center()
	bounds = Rect2(center - bounds.size * scale * 0.5, bounds.size * scale)
	var view_scale := maxf(1.0, scale)
	var offset := Vector2(480, 270) - Vector2(960, 540) * view_scale * 0.5
	var start_x := floori(offset.x / 16.0) - 1
	var start_y := floori(offset.y / 16.0) - 1
	var width := ceili(960.0 * view_scale / 16.0) + 3
	var height := ceili(540.0 * view_scale / 16.0) + 3
	for y in range(start_y, start_y + height):
		for x in range(start_x, start_x + width):
			var tile := rng.randi_range(1, 3) if rng.randf() < 0.22 else 0
			set_cell(Vector2i(x, y), 0, Vector2i(tile, 0))
	queue_redraw()

func _draw() -> void:
	draw_rect(bounds, Color("#49716a"), false, 2)
	draw_rect(bounds.grow(-4), Color("#253e3f"), false, 1)
	for i in 9:
		var point := Vector2(bounds.position.x + 28 + i * (bounds.size.x - 56) / 8.0, bounds.position.y + 10)
		draw_rect(Rect2(point, Vector2(6, 8)), Color("#48534b"))
		draw_rect(Rect2(point + Vector2(0, bounds.size.y - 33), Vector2(6, 8)), Color("#48534b"))
