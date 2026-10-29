extends Node2D

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("#0b141e"))
	for row in 18:
		for column in 31:
			var point := Vector2(column * 32, row * 32)
			var parity := (column * 7 + row * 13) % 9
			if parity < 3:
				draw_rect(Rect2(point + Vector2(12, 5), Vector2(2, 2)), Color("#182a31"))
			if parity == 5:
				draw_line(point + Vector2(5, 25), point + Vector2(8, 20), Color("#1a3034"), 2.0)
	draw_rect(Rect2(0, 0, 960, 4), Color("#b98a57"))
	draw_line(Vector2(32, 494), Vector2(928, 494), Color("#263c42"), 1.0)
