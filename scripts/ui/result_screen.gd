extends ScreenFrame

func _ready() -> void:
	super._ready()
	var victory: bool = RunState.won_run
	heading("旅途完成" if victory else "旅途止步于此", "枯冠倒下，荒地重新沉静。" if victory else "整理行囊，下一次选择新的构筑再出发。")
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var result := UiKit.label(content, "VICTORY" if victory else "FALLEN", 40, Color("#e6c58f") if victory else Color("#dc8b85"))
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stats := UiKit.label(content, "等级 %d    /    金币 %d    /    已完成格子 %d    /    遗物 %d" % [RunState.level, RunState.gold, RunState.completed_cells.size(), RunState.relics.size()], 18)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gear := UiKit.label(content, UiKit.inventory_text(), 16)
	gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var restart := UiKit.button(body, "返回开始界面  →", func(): RunState.go_to("res://scenes/app/title_screen.tscn"))
	restart.grab_focus()
