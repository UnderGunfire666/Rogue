extends ScreenFrame

var chosen_weapon: String = "needle"
var chosen_relic: String = ""
var weapon_cards: Dictionary = {}
var relic_buttons: Dictionary = {}
var start_button: Button
var weapon_choice_required := true

func _ready() -> void:
	super._ready()
	heading("准备初始装备", "02 / 02    ·    选择初始武器与遗物，武器必须符合角色限制。")
	var preview := ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, RunState.character.equipment_rules)
	for id in RunState.character.starting_weapons:
		for slot in preview.equipment.size():
			if preview.equipment[slot] == null and preview.equip(ContentCatalog.weapon(id), slot): break
	var weapon_ids := PackedStringArray()
	for id in ContentCatalog.weapon_ids():
		for slot in preview.equipment.size():
			if preview.equipment[slot] == null and preview.can_equip_weapon(ContentCatalog.weapon(id), slot):
				weapon_ids.append(id)
				break
	weapon_choice_required = preview.equipment.has(null)
	var pool := PackedStringArray()
	for id in ContentCatalog.relic_ids():
		if ContentCatalog.relic(id).rarity == 1: pool.append(id)
	var relic_ids := PackedStringArray()
	while relic_ids.size() < 4 and not pool.is_empty():
		var index: int = RunState.rng.randi_range(0, pool.size() - 1)
		relic_ids.append(pool[index])
		pool.remove_at(index)
	if not weapon_ids.has(chosen_weapon): chosen_weapon = weapon_ids[0] if not weapon_ids.is_empty() else ""
	var row := UiKit.weapon_grid(body)
	for id in weapon_ids:
		var data := ContentCatalog.weapon(id)
		var card := UiKit.card(row, data.display_name, UiKit.weapon_stats(data), data.icon, _choose_weapon.bind(id))
		weapon_cards[id] = card
	var relic_row := UiKit.weapon_grid(body)
	for id in relic_ids:
		var data := ContentCatalog.relic(id)
		var button := UiKit.button(relic_row, data.display_name + " · T%d\n" % data.rarity + data.description + ("\n技能：" + data.skill.display_name if data.skill else ""), _choose_relic.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = UiKit.relic_stats(data)
		relic_buttons[id] = button
	var actions := UiKit.row(body)
	UiKit.button(actions, "← 角色", func(): RunState.go_to("res://scenes/app/character_select.tscn"))
	start_button = UiKit.button(actions, "携带装备，踏入梦境  →", func():
		RunState.start_with(chosen_weapon, chosen_relic)
		RunState.begin_expedition()
		RunState.go_to("res://scenes/map/map_select.tscn"))
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh()

func _choose_weapon(id: String) -> void:
	chosen_weapon = id
	_refresh()

func _choose_relic(id: String) -> void:
	chosen_relic = id
	_refresh()

func _refresh() -> void:
	start_button.disabled = (chosen_weapon.is_empty() and weapon_choice_required) or chosen_relic.is_empty()
	for id: String in weapon_cards:
		weapon_cards[id].set_selected(id == chosen_weapon)
	for id: String in relic_buttons:
		relic_buttons[id].modulate = Color("#f7d69b") if id == chosen_relic else Color("#8b9b9a")
