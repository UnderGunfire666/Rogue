extends ScreenFrame

var entry: MapCellData
var pending_reward: RewardData
var chosen_slots := PackedInt32Array()
var reward_event_action_id: String = ""
var taking_reward: bool = false
var expedition_reward_gold_awarded: int = 0
var expedition_reward_candidates: Array[Resource] = []
var pending_expedition_weapon: WeaponData = null
var pending_sacrifice_action: EventActionData = null

func _ready() -> void:
	super._ready()
	entry = RunState.current_map().find_cell(RunState.current_cell_id)
	if entry == null or entry.is_battle():
		RunState.go_to("res://scenes/map/map_screen.tscn")
		return
	if RunState.expedition != null and entry.kind == MapCellData.Kind.REWARD and not RunState.completed_cells.has(entry.id):
		expedition_reward_gold_awarded = RunState.roll_reward_cell_gold()
		RunState.gold += expedition_reward_gold_awarded
		RunState.stats_changed.emit()
		expedition_reward_candidates = RunState.generate_reward_cell_candidates()
	_render()

func _render() -> void:
	clear_body()
	heading(entry.display_name, entry.description)
	if entry.kind == MapCellData.Kind.REWARD:
		if RunState.expedition != null:
			_show_expedition_rewards()
		else:
			_show_rewards(entry.reward_options)
	else:
		_show_event()

func _show_expedition_rewards() -> void:
	var top_bar := UiKit.row(body)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	var corner_gold := UiKit.label(top_bar, "奖励金币 +%d（已即时到账 · 当前金币 %d）" % [expedition_reward_gold_awarded, RunState.gold], 15, Color("#efd5a4"))
	corner_gold.name = "RewardGoldCorner"
	if expedition_reward_candidates.is_empty():
		_finish_cell()
		return
	var row := UiKit.row(body)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for item in expedition_reward_candidates:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		if item is WeaponData:
			UiKit.card(column, item.display_name, UiKit.weapon_stats(item), item.icon, _claim_expedition_weapon.bind(item), "领取装备")
		elif item is RelicData:
			var card := UiKit.card(column, item.display_name, UiKit.relic_stats(item), item.icon, _claim_expedition_relic.bind(item), "领取遗物")
			card.action.disabled = not RunState.loadout.can_add_relic(item)
		UiKit.button(column, "放弃（进入全队共享池）", _abandon_expedition_item.bind(item))

func _claim_expedition_weapon(item: WeaponData) -> void:
	pending_expedition_weapon = item
	clear_body()
	UiKit.label(body, "将 %s 放入哪个装备槽？" % item.display_name, 22, Color("#efd5a4"))
	var row := UiKit.weapon_grid(body)
	for slot in RunState.loadout.equipment.size():
		var old: EquipmentData = RunState.loadout.equipment[slot]
		var caption := "槽位 %d：%s" % [slot + 1, "空槽" if old == null else old.display_name]
		var button := UiKit.button(row, caption, func():
			if RunState.equip_weapon(item.id, slot):
				expedition_reward_candidates.erase(item)
				pending_expedition_weapon = null
				_render())
		button.disabled = not RunState.loadout.can_equip_weapon(item, slot)
	UiKit.button(body, "取消领取", func():
		pending_expedition_weapon = null
		_render())

func _claim_expedition_relic(item: RelicData) -> void:
	if RunState.add_relic(item.id):
		expedition_reward_candidates.erase(item)
		_render()

func _abandon_expedition_item(item: Resource) -> void:
	RunState.abandon_loot_to_shared_pool(item)
	expedition_reward_candidates.erase(item)
	_render()

func _show_event() -> void:
	if not entry.event.title.is_empty():
		var scope_tag := "【全队事件】" if entry.event.scope == EventData.Scope.PARTY else "【个人事件】"
		UiKit.label(body, "%s %s" % [scope_tag, entry.event.title], 18, Color("#7fd1bc"))
	var text := UiKit.label(body, entry.event.text, 16)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var has_active_options := false
	for action in entry.event.actions:
		if not RunState.event_action_completed(action.id):
			has_active_options = true
		var caption := _format_event_action_label(action)
		var button := UiKit.button(body, caption, _execute_event_action.bind(action))
		button.disabled = RunState.event_action_completed(action.id) or not RunState.can_pay_event_action(action)
	if entry.event.actions.is_empty() or not has_active_options or RunState.expedition == null:
		UiKit.button(body, "继续行进  →", _finish_cell)

func _format_event_action_label(action: EventActionData) -> String:
	var parts: Array[String] = [action.label]
	if action.gold_cost > 0:
		parts.append("消耗 %d 金币%s" % [action.gold_cost, "（金币不足）" if RunState.gold < action.gold_cost else ""])
	if action.health_cost > 0.0:
		parts.append("失去 %.0f 生命（最低保留 1）" % action.health_cost)
	if action.requires_sacrifice_equipment:
		parts.append("交出 1 件装备")
	if action.gold_gain > 0:
		parts.append("获得 %d 金币" % action.gold_gain)
	if action.heal_amount > 0.0:
		parts.append("恢复 %.0f 生命" % action.heal_amount)
	if not action.stat_id.is_empty() and not is_zero_approx(action.stat_amount):
		var dur_text: String = ["持续 %d 场战斗" % action.duration_combats, "持续当前地图", "持续本次远征"][action.duration_kind]
		parts.append("%s %s（%s）" % [PlayerPrimaryStats.label(action.stat_id), PlayerPrimaryStats.format_value(action.stat_id, action.stat_amount), dur_text])
	return " · ".join(parts)

func _show_rewards(options: Array[RewardOptionData], action_id: String = "") -> void:
	clear_body()
	var row := UiKit.row(body)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for option in options:
		var icon: Texture2D = option.icon
		if icon == null and option.reward != null:
			if not option.reward.equipment.is_empty():
				icon = option.reward.equipment[0].icon
			elif not option.reward.relics.is_empty():
				icon = option.reward.relics[0].icon
			elif option.reward.gold > 0:
				icon = load("res://assets/art/loot.svg")
		UiKit.card(row, option.title, option.description, icon, _choose_reward.bind(option, action_id), "领取奖励")
	if not action_id.is_empty():
		UiKit.button(body, "← 返回事件", _render)

func _choose_reward(option: RewardOptionData, action_id: String = "") -> void:
	if taking_reward or option.reward == null:
		return
	if action_id.is_empty() and RunState.completed_cells.has(entry.id):
		return
	if not action_id.is_empty() and RunState.event_action_completed(action_id):
		return
	var errors := option.reward.validation_errors()
	if not errors.is_empty():
		summary_label.text = "；".join(errors)
		return
	taking_reward = true
	pending_reward = option.reward
	reward_event_action_id = action_id
	chosen_slots.clear()
	_choose_next_equipment_slot()

func _choose_next_equipment_slot() -> void:
	if chosen_slots.size() == pending_reward.equipment.size():
		_grant_reward()
		return
	var item := pending_reward.equipment[chosen_slots.size()]
	clear_body()
	UiKit.label(body, "将 %s 放入哪个装备槽？" % item.display_name, 22, Color("#efd5a4"))
	var row := UiKit.weapon_grid(body)
	for slot in RunState.loadout.equipment.size():
		var old: EquipmentData = RunState.loadout.equipment[slot]
		var caption := "槽位 %d：%s" % [slot + 1, "空槽" if old == null else old.display_name]
		var button := UiKit.button(row, caption, _confirm_slot.bind(slot))
		button.disabled = not RunState.loadout.can_equip_weapon(item, slot)
	UiKit.button(body, "取消领取", func():
		taking_reward = false
		pending_reward = null
		_render())

func _confirm_slot(slot: int) -> void:
	chosen_slots.append(slot)
	_choose_next_equipment_slot()

func _grant_reward() -> void:
	if not RewardResolver.apply(RunState, pending_reward, chosen_slots):
		taking_reward = false
		summary_label.text = "奖励配置无效。"
		return
	pending_reward = null
	taking_reward = false
	if reward_event_action_id.is_empty():
		_finish_cell()
	else:
		RunState.mark_event_action_completed(reward_event_action_id)
		reward_event_action_id = ""
		if RunState.expedition != null:
			_finish_cell()
		else:
			_render()

func _execute_event_action(action: EventActionData) -> void:
	var errors := action.validation_errors()
	if not errors.is_empty():
		summary_label.text = "；".join(errors)
		return
	if RunState.event_action_completed(action.id) or not RunState.can_pay_event_action(action):
		return
	if action.is_abandon:
		RunState.mark_event_action_completed(action.id)
		if RunState.expedition != null:
			_finish_cell()
		else:
			_render()
		return
	if action.requires_sacrifice_equipment:
		_choose_sacrifice_slot(action)
		return
	_apply_event_action_after_sacrifice(action)

func _choose_sacrifice_slot(action: EventActionData) -> void:
	pending_sacrifice_action = action
	clear_body()
	UiKit.label(body, "选择要交出的装备：", 22, Color("#efd5a4"))
	var row := UiKit.weapon_grid(body)
	for slot in RunState.loadout.equipment.size():
		var item: EquipmentData = RunState.loadout.equipment[slot]
		if item != null:
			UiKit.button(row, "交出槽位 %d：%s" % [slot + 1, item.display_name], func():
				RunState.loadout.equip(null, slot)
				RunState.stats_changed.emit()
				var act := pending_sacrifice_action
				pending_sacrifice_action = null
				_apply_event_action_after_sacrifice(act))
	UiKit.button(body, "← 返回事件", func():
		pending_sacrifice_action = null
		_render())

func _apply_event_action_after_sacrifice(action: EventActionData) -> void:
	if action.gold_cost > 0:
		RunState.gold = maxi(0, RunState.gold - action.gold_cost)
	if action.health_cost > 0.0:
		RunState.apply_event_health_cost(action.health_cost)
	if action.gold_gain > 0:
		RunState.gold += action.gold_gain
	if action.heal_amount > 0.0 and RunState.combat_rules().can_heal:
		RunState.health = minf(RunState.effective_max_health(), RunState.health + action.heal_amount)
	if not action.stat_id.is_empty() and not is_zero_approx(action.stat_amount):
		RunState.add_event_stat_modifier(action.stat_id, action.stat_amount, action.duration_kind, action.duration_combats)
	if action.grant_random_relic:
		var r_ids := RunState.roll_shop_items(ContentCatalog.relic_ids(), false, 1)
		if not r_ids.is_empty():
			RunState.add_relic(r_ids[0])
	if action.grant_random_equipment:
		var w_ids := RunState.roll_shop_items(ContentCatalog.weapon_ids(), true, 1)
		if not w_ids.is_empty():
			var weapon := ContentCatalog.weapon(w_ids[0])
			var opt := RewardOptionData.new()
			opt.title = weapon.display_name
			opt.reward = RewardData.new()
			opt.reward.equipment.append(weapon)
			_choose_reward(opt, action.id)
			return
	RunState.stats_changed.emit()
	match action.kind:
		EventActionData.Kind.TEXT:
			summary_label.text = action.text
			RunState.mark_event_action_completed(action.id)
			if RunState.expedition != null:
				_finish_cell()
			else:
				_render()
		EventActionData.Kind.EFFECT:
			summary_label.text = action.text
			RunState.mark_event_action_completed(action.id)
			if RunState.expedition != null:
				_finish_cell()
			else:
				_render()
		EventActionData.Kind.REWARD:
			_show_rewards(action.reward_options, action.id)
		EventActionData.Kind.ENCOUNTER:
			if RunState.begin_event_encounter(action):
				RunState.go_to("res://scenes/run/arena.tscn")

func _finish_cell() -> void:
	RunState.complete_current_cell()
	RunState.go_to("res://scenes/map/map_screen.tscn")
