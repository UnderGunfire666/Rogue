extends CanvasLayer

signal resume_requested
signal upgrade_chosen(id: String)
signal victory_confirmed
signal leave_requested
var mode: String = ""
@onready var root: Control = $Root
@onready var content: VBoxContainer = $Root/Center/Panel/Content

func _ready() -> void:
	root.hide()

func close() -> void:
	mode = ""
	root.hide()

func _clear(title: String, subtitle: String) -> void:
	root.show()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var title_label := UiKit.label(content, title, 28, Color("#efd5a4"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var description := UiKit.label(content, subtitle, 14)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func show_pause() -> void:
	mode = "pause"
	_clear("旅途暂停", "歇息片刻，战斗会在继续后恢复。")
	var resume := UiKit.button(content, "继续战斗", func(): resume_requested.emit())
	resume.grab_focus()
	UiKit.button(content, "查看角色主属性", show_stats)
	UiKit.button(content, "返回开始界面", func(): leave_requested.emit())

func show_stats() -> void:
	mode = "stats"
	_clear("角色主属性", "按当前装备与遗物计算；百分比为百分点。")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for id in PlayerPrimaryStats.IDS:
		var value: float = RunState.effective_max_health() if id == "max_hp" else RunState.stat_value(id)
		var formatted := "%.0f" % value if id == "max_hp" else PlayerPrimaryStats.format_value(id, value)
		if id == "dodge": formatted += "（生效 %.0f%%）" % (RunState.dodge_chance() * 100.0)
		if id == "armor": formatted += "（承伤 %.0f%%）" % (RunState.armor_damage_multiplier() * 100.0)
		var label := UiKit.label(grid, PlayerPrimaryStats.label(id) + "  " + formatted, 16)
		label.custom_minimum_size.x = 220
	var button := UiKit.button(content, "返回暂停菜单", show_pause)
	button.grab_focus()

func show_upgrades() -> void:
	mode = "upgrade"
	_clear("等级提升 · Lv.%d" % RunState.level, "选择要强化的脑部器官（同时提升其分管的 3 项属性）。战斗已暂停。")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	content.add_child(row)
	RunState.upgrade_offers = PrimaryStatUpgrades.create_offers(RunState)
	for option in RunState.upgrade_offers:
		var id: String = str(option.get("id", ""))
		var caption := PrimaryStatUpgrades.format_offer(option)
		var button := UiKit.button(row, caption, _select_upgrade.bind(id))
		button.custom_minimum_size = Vector2(180, 110)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		if option == RunState.upgrade_offers[0]:
			button.grab_focus()

func _select_upgrade(id: String) -> void:
	upgrade_chosen.emit(id)

func show_combat_loot(boss: bool, boss_defeated: bool = false) -> void:
	if RunState.pending_combat_loot.is_empty():
		show_victory(boss, boss_defeated)
		return
	mode = "loot"
	var item: Resource = RunState.pending_combat_loot[0]
	var remaining := RunState.pending_combat_loot.size()
	_clear("战利品分配（剩余 %d 件）" % remaining, "你可以领取该战利品，或放弃使其进入全队共享池。")
	if item is WeaponData:
		UiKit.label(content, "装备：%s（T%d）" % [item.display_name, item.rarity], 20, Color("#efd5a4"))
		UiKit.label(content, UiKit.weapon_stats(item), 14)
		var slot_row := UiKit.row(content)
		for slot in RunState.loadout.equipment.size():
			var existing: String = RunState.weapons[slot]
			var caption := "装备到槽位 %d（%s）" % [slot + 1, "空槽" if existing.is_empty() else ContentCatalog.weapon(existing).display_name]
			var btn := UiKit.button(slot_row, caption, func():
				if RunState.equip_weapon(item.id, slot):
					RunState.pending_combat_loot.pop_front()
					show_combat_loot(boss, boss_defeated))
			btn.disabled = not RunState.loadout.can_equip_weapon(item, slot)
	elif item is RelicData:
		UiKit.label(content, "遗物：%s（T%d）" % [item.display_name, item.rarity], 20, Color("#efd5a4"))
		UiKit.label(content, UiKit.relic_stats(item), 14)
		var btn := UiKit.button(content, "领取遗物", func():
			RunState.add_relic(item.id)
			RunState.pending_combat_loot.pop_front()
			show_combat_loot(boss, boss_defeated))
		btn.disabled = not RunState.loadout.can_add_relic(item)
	var abandon_btn := UiKit.button(content, "放弃（放入全队共享池）", func():
		RunState.abandon_loot_to_shared_pool(item)
		show_combat_loot(boss, boss_defeated))
	abandon_btn.grab_focus()

func show_victory(boss: bool, boss_defeated: bool = false) -> void:
	mode = "victory"
	_clear(("BOSS 已击败" if boss_defeated else "BOSS 战时间结束") if boss else "战斗胜利", "本场战斗的掉落已收集。")
	var ends_run := boss and (RunState.expedition == null or RunState.expedition.is_final_map())
	var button := UiKit.button(content, "完成旅途  →" if ends_run else "进入战后商店  →", func(): victory_confirmed.emit())
	button.grab_focus()

func show_defeat() -> void:
	mode = "defeat"
	_clear("旅途暂止", "你倒在了荒地。带着新的选择，再试一次。")
	var button := UiKit.button(content, "返回开始界面", func(): leave_requested.emit())
	button.grab_focus()

func show_configuration_error(message: String) -> void:
	mode = "error"
	_clear("战斗配置无效", message)
	UiKit.button(content, "返回开始界面", func(): leave_requested.emit())

func _unhandled_input(event: InputEvent) -> void:
	if mode in ["pause", "stats"] and event.is_action_pressed("pause_game"):
		if mode == "stats": show_pause()
		else: resume_requested.emit()
		get_viewport().set_input_as_handled()
