extends ScreenFrame

const SLOT_COUNT := 5
const SINGLE_REROLL_COST := 2
const FULL_REROLL_COST := 8

## 5 shop slots: each element is {"kind": "weapon"/"relic", "id": String, "price": int, "locked": bool, "sold": bool}
var slots: Array[Dictionary] = []
var weapon_offers := PackedStringArray()
var relic_offers := PackedStringArray()
var rerolls := 0

func _ready() -> void:
	super._ready()
	RunState.gifted_teammates_this_shop.clear()
	_initialize_slots()
	_render()

func _initialize_slots() -> void:
	slots.clear()
	for i in SLOT_COUNT:
		slots.append({"kind": "weapon" if i < 2 else "relic", "id": "", "price": 0, "locked": false, "sold": false})
	# Slot 4 (5th slot) randomly chooses equipment or relic while preserving >=2 weapons and >=2 relics.
	slots[4]["kind"] = "weapon" if RunState.rng.randf() < 0.5 else "relic"
	# Restore previously locked items first.
	var used_weapons := PackedStringArray()
	var used_relics := PackedStringArray()
	for saved in RunState.locked_shop_slots:
		var idx := int(saved.get("slot", -1))
		if idx >= 0 and idx < SLOT_COUNT:
			slots[idx] = saved.duplicate()
			if slots[idx]["kind"] == "weapon":
				used_weapons.append(str(slots[idx]["id"]))
			else:
				used_relics.append(str(slots[idx]["id"]))
	# Also honor legacy locked_weapon_prices / locked_relic_prices dictionaries.
	for wid: String in RunState.locked_weapon_prices:
		if not used_weapons.has(wid) and ContentCatalog.weapon_ids().has(wid):
			for i in SLOT_COUNT:
				if not slots[i]["locked"] and slots[i]["id"].is_empty() and slots[i]["kind"] == "weapon":
					slots[i] = {"kind": "weapon", "id": wid, "price": int(RunState.locked_weapon_prices[wid]), "locked": true, "sold": false}
					used_weapons.append(wid)
					break
	for rid: String in RunState.locked_relic_prices:
		if not used_relics.has(rid) and ContentCatalog.relic_ids().has(rid):
			for i in SLOT_COUNT:
				if not slots[i]["locked"] and slots[i]["id"].is_empty() and slots[i]["kind"] == "relic":
					slots[i] = {"kind": "relic", "id": rid, "price": int(RunState.locked_relic_prices[rid]), "locked": true, "sold": false}
					used_relics.append(rid)
					break
	_fill_unlocked_slots(used_weapons, used_relics, false)
	_sync_legacy_arrays()

func _fill_unlocked_slots(exclude_weapons: PackedStringArray, exclude_relics: PackedStringArray, reroll_sold: bool) -> void:
	# Ensure at least 2 weapon slots and 2 relic slots across the 5 slots.
	var w_slots := 0
	var r_slots := 0
	for i in SLOT_COUNT:
		if slots[i]["kind"] == "weapon": w_slots += 1
		else: r_slots += 1
	if w_slots < 2:
		for i in SLOT_COUNT:
			if not slots[i]["locked"] and slots[i]["kind"] == "relic":
				slots[i]["kind"] = "weapon"
				w_slots += 1
				r_slots -= 1
				if w_slots >= 2: break
	elif r_slots < 2:
		for i in SLOT_COUNT:
			if not slots[i]["locked"] and slots[i]["kind"] == "weapon":
				slots[i]["kind"] = "relic"
				r_slots += 1
				w_slots -= 1
				if r_slots >= 2: break
	var taken_w := exclude_weapons.duplicate()
	var taken_r := exclude_relics.duplicate()
	for i in SLOT_COUNT:
		if slots[i]["locked"] and not str(slots[i]["id"]).is_empty():
			if slots[i]["kind"] == "weapon" and not taken_w.has(slots[i]["id"]):
				taken_w.append(slots[i]["id"])
			elif slots[i]["kind"] == "relic" and not taken_r.has(slots[i]["id"]):
				taken_r.append(slots[i]["id"])
	for i in SLOT_COUNT:
		if slots[i]["locked"]:
			continue
		if slots[i]["sold"] and not reroll_sold:
			continue
		var is_equip: bool = slots[i]["kind"] == "weapon"
		var id := _roll_one_offer(is_equip, taken_w if is_equip else taken_r)
		var price := _default_price(id, is_equip)
		slots[i] = {"kind": slots[i]["kind"], "id": id, "price": price, "locked": false, "sold": id.is_empty()}
		if not id.is_empty():
			if is_equip: taken_w.append(id)
			else: taken_r.append(id)

func _roll_one_offer(equipment: bool, exclude: PackedStringArray) -> String:
	var pool := ContentCatalog.weapon_ids() if equipment else ContentCatalog.relic_ids()
	var candidates := pool.duplicate()
	for id in exclude:
		if candidates.has(id):
			candidates.remove_at(candidates.find(id))
	if candidates.is_empty():
		candidates = pool.duplicate()
	var rolled: PackedStringArray = RunState.roll_shop_items(candidates, equipment, 1)
	if rolled.is_empty() and candidates.size() < pool.size():
		rolled = RunState.roll_shop_items(pool, equipment, 1)
	return rolled[0] if not rolled.is_empty() else ""

func _default_price(id: String, equipment: bool) -> int:
	if id.is_empty():
		return 0
	if equipment:
		return int(RunState.locked_weapon_prices.get(id, RunState.shop_weapon_price()))
	var item := ContentCatalog.relic(id)
	return int(RunState.locked_relic_prices.get(id, RunState.shop_relic_price(item))) if item != null else 0

func _sync_legacy_arrays() -> void:
	weapon_offers.clear()
	relic_offers.clear()
	RunState.locked_shop_slots.clear()
	for i in SLOT_COUNT:
		var s: Dictionary = slots[i]
		var id := str(s.get("id", ""))
		if not bool(s.get("sold", false)) and not id.is_empty():
			if s["kind"] == "weapon":
				weapon_offers.append(id)
			else:
				relic_offers.append(id)
		if bool(s.get("locked", false)) and not bool(s.get("sold", false)) and not id.is_empty():
			var copy := s.duplicate()
			copy["slot"] = i
			RunState.locked_shop_slots.append(copy)
			if s["kind"] == "weapon":
				RunState.locked_weapon_prices[id] = int(s["price"])
			else:
				RunState.locked_relic_prices[id] = int(s["price"])

func _render() -> void:
	clear_body()
	heading("战后整备（5 商品位）", "金币 %d    ·    生命 %.0f / %.0f    ·    %s" % [RunState.gold, RunState.health, RunState.effective_max_health(), UiKit.inventory_text()])
	var row := UiKit.row(body, 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in SLOT_COUNT:
		_render_slot_card(row, i)
	var actions := UiKit.row(body)
	var reroll := UiKit.button(actions, "全店刷新 · %d 金币" % _reroll_cost(), _reroll)
	reroll.disabled = RunState.gold < _reroll_cost()
	UiKit.button(actions, "回收武器", _recycle_screen)
	var heal := UiKit.button(actions, "补给 · 10 金币 / 恢复 25 生命", _buy_heal)
	heal.disabled = not RunState.combat_rules().can_heal or RunState.gold < 10 or RunState.health >= RunState.effective_max_health()
	var to_map_select := RunState.expedition != null and RunState.expedition.needs_map_selection()
	var next := UiKit.button(actions, ("选择下一张地图  →" if to_map_select else "完成整备，回到地图  →"), func(): RunState.go_to(RunState.route_scene()))
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _render_slot_card(parent: Node, slot_index: int) -> void:
	var s: Dictionary = slots[slot_index]
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var id := str(s.get("id", ""))
	var sold := bool(s.get("sold", false)) or id.is_empty()
	var locked := bool(s.get("locked", false))
	var is_equip: bool = s.get("kind", "weapon") == "weapon"
	if sold:
		var empty_btn := UiKit.button(column, "商品位 #%d\n【已售罄 / 空位】\n购买后不立即补货" % (slot_index + 1), func(): pass)
		empty_btn.disabled = true
		empty_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	elif is_equip:
		var data := ContentCatalog.weapon(id)
		var price := int(s.get("price", _weapon_price(id)))
		var buy_btn := UiKit.button(column, "【装备】%s · T%d\n%d 金币\n%s" % [data.display_name, data.rarity, price, UiKit.weapon_stats(data)], _select_slot.bind(id, slot_index))
		buy_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		buy_btn.clip_text = true
		buy_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buy_btn.disabled = RunState.gold < price
	else:
		var data := ContentCatalog.relic(id)
		var price := int(s.get("price", _relic_price(id)))
		var buy_btn := UiKit.button(column, "【遗物】%s · T%d\n%d 金币\n%s%s" % [data.display_name, data.rarity, price, data.description, "\n技能：" + data.skill.display_name if data.skill else ""], _buy_relic_slot.bind(slot_index))
		buy_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		buy_btn.clip_text = true
		buy_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buy_btn.tooltip_text = UiKit.relic_stats(data)
		buy_btn.disabled = RunState.gold < price or not RunState.loadout.can_add_relic(data)
	var slot_actions := UiKit.row(column, 6)
	var lock_btn := UiKit.button(slot_actions, "解锁" if locked else "锁定", _toggle_slot_lock.bind(slot_index))
	lock_btn.disabled = sold
	lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var single_reroll := UiKit.button(slot_actions, "刷新单格(%dG)" % _single_reroll_cost(), _reroll_slot.bind(slot_index))
	single_reroll.disabled = RunState.gold < _single_reroll_cost()
	single_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _select_slot(id: String, shop_slot_index: int = -1) -> void:
	var price := int(slots[shop_slot_index]["price"]) if shop_slot_index >= 0 and shop_slot_index < slots.size() else _weapon_price(id)
	if RunState.gold < price:
		return
	clear_body()
	UiKit.label(body, "将 %s 放入哪个装备槽？" % ContentCatalog.weapon(id).display_name, 23, Color("#efd5a4"))
	UiKit.label(body, "替换不会返还金币；不可用的槽位不符合角色装备限制。", 15)
	var row := UiKit.weapon_grid(body)
	for equip_slot in RunState.loadout.equipment.size():
		var existing: String = RunState.weapons[equip_slot]
		var text := "槽位 %d：%s" % [equip_slot + 1, "空槽" if existing.is_empty() else ContentCatalog.weapon(existing).display_name]
		var button := UiKit.button(row, text + "\n买入并装备 · %d 金币" % price, _buy_weapon.bind(id, equip_slot, shop_slot_index))
		button.disabled = not RunState.loadout.can_equip_weapon(ContentCatalog.weapon(id), equip_slot)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 100
	UiKit.button(body, "← 返回商店", _render)

func _buy_weapon(id: String, equip_slot: int, shop_slot_index: int = -1) -> void:
	var target_shop_slot := shop_slot_index
	if target_shop_slot < 0:
		for i in slots.size():
			if slots[i]["kind"] == "weapon" and str(slots[i]["id"]) == id and not bool(slots[i]["sold"]):
				target_shop_slot = i
				break
	var price := int(slots[target_shop_slot]["price"]) if target_shop_slot >= 0 and target_shop_slot < slots.size() else _weapon_price(id)
	if RunState.gold < price:
		return
	if RunState.equip_weapon(id, equip_slot):
		RunState.gold -= price
		RunState.locked_weapon_prices.erase(id)
		if target_shop_slot >= 0 and target_shop_slot < slots.size():
			slots[target_shop_slot]["sold"] = true
			slots[target_shop_slot]["locked"] = false
		_sync_legacy_arrays()
	_render()

func _buy_relic_slot(shop_slot_index: int) -> void:
	if shop_slot_index < 0 or shop_slot_index >= slots.size():
		return
	_buy_relic(str(slots[shop_slot_index]["id"]), shop_slot_index)

func _buy_relic(id: String, shop_slot_index: int = -1) -> void:
	var data := ContentCatalog.relic(id)
	var target_shop_slot := shop_slot_index
	if target_shop_slot < 0:
		for i in slots.size():
			if slots[i]["kind"] == "relic" and str(slots[i]["id"]) == id and not bool(slots[i]["sold"]):
				target_shop_slot = i
				break
	var price := int(slots[target_shop_slot]["price"]) if target_shop_slot >= 0 and target_shop_slot < slots.size() else _relic_price(id)
	if data == null or RunState.gold < price:
		return
	if RunState.add_relic(id):
		RunState.gold -= price
		RunState.locked_relic_prices.erase(id)
		if target_shop_slot >= 0 and target_shop_slot < slots.size():
			slots[target_shop_slot]["sold"] = true
			slots[target_shop_slot]["locked"] = false
		_sync_legacy_arrays()
	_render()

func _weapon_price(id: String) -> int:
	for s in slots:
		if s["kind"] == "weapon" and str(s["id"]) == id and not bool(s["sold"]):
			return int(s["price"])
	return int(RunState.locked_weapon_prices.get(id, RunState.shop_weapon_price()))

func _relic_price(id: String) -> int:
	for s in slots:
		if s["kind"] == "relic" and str(s["id"]) == id and not bool(s["sold"]):
			return int(s["price"])
	var item := ContentCatalog.relic(id)
	return int(RunState.locked_relic_prices.get(id, RunState.shop_relic_price(item))) if item != null else 0

func _toggle_slot_lock(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	var s: Dictionary = slots[slot_index]
	if bool(s.get("sold", false)) or str(s.get("id", "")).is_empty():
		return
	var id := str(s["id"])
	var equipment: bool = s["kind"] == "weapon"
	_toggle_lock(id, equipment, slot_index)

func _toggle_lock(id: String, equipment: bool, slot_index: int = -1) -> void:
	var target_slot := slot_index
	if target_slot < 0:
		for i in slots.size():
			if (slots[i]["kind"] == ("weapon" if equipment else "relic")) and str(slots[i]["id"]) == id:
				target_slot = i
				break
	var locked: Dictionary = RunState.locked_weapon_prices if equipment else RunState.locked_relic_prices
	if target_slot >= 0 and target_slot < slots.size():
		var next_state := not bool(slots[target_slot]["locked"])
		slots[target_slot]["locked"] = next_state
		if next_state:
			locked[id] = int(slots[target_slot]["price"])
		else:
			locked.erase(id)
	else:
		if locked.has(id): locked.erase(id)
		else: locked[id] = _weapon_price(id) if equipment else _relic_price(id)
	_sync_legacy_arrays()
	_render()

func _single_reroll_cost() -> int:
	return SINGLE_REROLL_COST

func _reroll_cost() -> int:
	if RunState.expedition != null:
		return FULL_REROLL_COST
	var wave := maxi(1, RunState.completed_waves)
	var increase := maxi(1, floori(0.4 * wave))
	return floori(0.75 * wave) + increase * (1 + rerolls)

func _reroll_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	var cost := _single_reroll_cost()
	if RunState.gold < cost:
		return
	RunState.gold -= cost
	var s: Dictionary = slots[slot_index]
	var old_id := str(s.get("id", ""))
	var is_equip: bool = s["kind"] == "weapon"
	if bool(s.get("locked", false)):
		s["locked"] = false
		if is_equip: RunState.locked_weapon_prices.erase(old_id)
		else: RunState.locked_relic_prices.erase(old_id)
	var exclude := PackedStringArray([old_id])
	for i in slots.size():
		if i != slot_index and slots[i]["kind"] == s["kind"] and not str(slots[i]["id"]).is_empty():
			exclude.append(str(slots[i]["id"]))
	var new_id := _roll_one_offer(is_equip, exclude)
	slots[slot_index] = {
		"kind": s["kind"],
		"id": new_id,
		"price": _default_price(new_id, is_equip),
		"locked": false,
		"sold": new_id.is_empty()
	}
	_sync_legacy_arrays()
	_render()

func _reroll() -> void:
	var cost := _reroll_cost()
	if RunState.gold < cost: return
	RunState.gold -= cost
	rerolls += 1
	var old_w := PackedStringArray()
	var old_r := PackedStringArray()
	for s in slots:
		var id := str(s.get("id", ""))
		if not id.is_empty():
			if s["kind"] == "weapon": old_w.append(id)
			else: old_r.append(id)
	_fill_unlocked_slots(old_w, old_r, true)
	_sync_legacy_arrays()
	_render()

func _recycle_screen() -> void:
	clear_body()
	UiKit.label(body, "回收武器：获得当前价格的 25%", 22)
	var grid := UiKit.weapon_grid(body)
	for slot in RunState.loadout.equipment.size():
		var item: EquipmentData = RunState.loadout.equipment[slot]
		if item != null: UiKit.button(grid, "%s · 回收 %d 金币" % [item.display_name, floori(RunState.shop_weapon_price() * 0.25)], _recycle.bind(slot))
	UiKit.button(body, "← 返回商店", _render)

func _recycle(slot: int) -> void:
	if slot < 0 or slot >= RunState.loadout.equipment.size() or RunState.loadout.equipment[slot] == null: return
	RunState.loadout.equip(null, slot)
	RunState.gold += floori(RunState.shop_weapon_price() * 0.25)
	RunState.stats_changed.emit()
	_recycle_screen()

func _buy_heal() -> void:
	if RunState.gold < 10 or not RunState.combat_rules().can_heal:
		return
	RunState.gold -= 10
	RunState.health = minf(RunState.effective_max_health(), RunState.health + 25.0)
	_render()
