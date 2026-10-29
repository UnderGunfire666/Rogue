class_name ExpeditionMapGenerator
extends RefCounted
## Pure generation rules for one dream-expedition map. Produces a runtime MapData
## with directed routes; exploration state and presentation live elsewhere.
##
## Cells sit on an integer lattice of LATTICE_WIDTH columns so that "down-left /
## down / down-right" means column x-1 / x / x+1 in the next layer. The last
## route layer converges on the single BOSS cell.

const LAYER_WIDTHS: PackedInt32Array = [1, 3, 5, 7, 9, 10, 8, 6, 4, 1]
const DEPTH_COUNT := 10
const LATTICE_WIDTH := 10
## A route may contain at most this many reward (or event) cells in a row.
const MAX_CONSECUTIVE := 2
const MAX_ATTEMPTS := 24
const RANDOM_KINDS: Array[int] = [MapCellData.Kind.NORMAL_BATTLE, MapCellData.Kind.REWARD, MapCellData.Kind.EVENT]

static func lattice_offset(width: int) -> int:
	return (LATTICE_WIDTH - width) / 2

static func cell_id(depth: int, column: int) -> String:
	return "d%d_x%d" % [depth, column]

static func generate(template: MapTemplateData, difficulty: MapDifficultyData, rng: RandomNumberGenerator) -> MapData:
	var map: MapData
	for attempt in MAX_ATTEMPTS:
		map = _build(template, difficulty, rng)
		if validation_errors(map, template).is_empty():
			return map
	push_error("Expedition map generation exhausted retries: " + "; ".join(validation_errors(map, template)))
	return map

## Target counts for the 52 random cells; rounding remainder goes to battles.
static func target_counts(difficulty: MapDifficultyData, total: int) -> Dictionary:
	var reward := maxi(1, roundi(total * difficulty.reward_ratio))
	var event := maxi(1, roundi(total * difficulty.event_ratio))
	var battle := maxi(1, total - reward - event)
	return {MapCellData.Kind.NORMAL_BATTLE: battle, MapCellData.Kind.REWARD: reward, MapCellData.Kind.EVENT: event}

static func _build(template: MapTemplateData, difficulty: MapDifficultyData, rng: RandomNumberGenerator) -> MapData:
	var layers: Array = []
	for d in DEPTH_COUNT:
		var width := LAYER_WIDTHS[d]
		var offset := lattice_offset(width)
		var row: Array[MapCellData] = []
		for i in width:
			var cell := MapCellData.new()
			cell.depth = d + 1
			cell.grid_position = Vector2i(offset + i, d)
			cell.view_position = Vector2(i + (LATTICE_WIDTH - width) / 2.0, d)
			cell.id = cell_id(d + 1, offset + i)
			row.append(cell)
		layers.append(row)
	_connect(layers, template, rng)
	_assign_kinds(layers, template, difficulty, rng)
	_assign_content(layers, template, rng)
	var map := MapData.new()
	map.display_name = template.display_name
	map.directed_routes = true
	map.starting_cell_id = layers[0][0].id
	map.boss_cell_id = layers[DEPTH_COUNT - 1][0].id
	for row in layers:
		for cell in row:
			map.cells.append(cell)
	return map

# --- Routes -------------------------------------------------------------------

static func _connect(layers: Array, template: MapTemplateData, rng: RandomNumberGenerator) -> void:
	for d in DEPTH_COUNT - 1:
		var row: Array = layers[d]
		var next: Array = layers[d + 1]
		if d + 1 == DEPTH_COUNT - 1:
			for cell: MapCellData in row:
				cell.next_cell_ids = PackedStringArray([next[0].id])
			continue
		var by_column := {}
		for child: MapCellData in next:
			by_column[child.grid_position.x] = child
		var has_parent := {}
		for cell: MapCellData in row:
			var candidates: Array = []
			for dx in [-1, 0, 1]:
				var column: int = cell.grid_position.x + dx
				if by_column.has(column):
					candidates.append(by_column[column])
			# Edge cells are limited by the map boundary; inner cells may also lose routes.
			var count := mini(_roll_route_count(template, rng), candidates.size())
			_shuffle(candidates, rng)
			var links := PackedStringArray()
			for k in count:
				links.append(candidates[k].id)
				has_parent[candidates[k].id] = true
			cell.next_cell_ids = links
		# Every cell must be reachable: give orphans a link from an adjacent parent.
		for child: MapCellData in next:
			if has_parent.has(child.id):
				continue
			var parents: Array = []
			for cell: MapCellData in row:
				if absi(cell.grid_position.x - child.grid_position.x) <= 1:
					parents.append(cell)
			var parent: MapCellData = parents[rng.randi_range(0, parents.size() - 1)]
			var links := parent.next_cell_ids
			links.append(child.id)
			parent.next_cell_ids = links
		for cell: MapCellData in row:
			cell.next_cell_ids = _sorted_by_column(cell.next_cell_ids, by_column)

static func _roll_route_count(template: MapTemplateData, rng: RandomNumberGenerator) -> int:
	var weights := template.route_count_weights
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, weight)
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= maxf(0.0, weights[i])
		if roll < 0.0:
			return i + 1
	return weights.size()

static func _sorted_by_column(ids: PackedStringArray, by_column: Dictionary) -> PackedStringArray:
	var columns: Array[int] = []
	var lookup := {}
	for column: int in by_column:
		lookup[by_column[column].id] = column
	for id in ids:
		columns.append(lookup[id])
	columns.sort()
	var result := PackedStringArray()
	for column in columns:
		result.append(by_column[column].id)
	return result

# --- Cell kinds ---------------------------------------------------------------

static func _assign_kinds(layers: Array, template: MapTemplateData, difficulty: MapDifficultyData, rng: RandomNumberGenerator) -> void:
	layers[0][0].kind = MapCellData.Kind.START
	layers[DEPTH_COUNT - 1][0].kind = MapCellData.Kind.BOSS_BATTLE
	var random_cells := 0
	for d in range(1, DEPTH_COUNT - 1):
		random_cells += layers[d].size()
	var bag: Array[int] = []
	var counts := target_counts(difficulty, random_cells)
	for kind: int in counts:
		for i in counts[kind]:
			bag.append(kind)
	var parents := _parent_lookup(layers)
	var reward_run := {}
	var event_run := {}
	# Topological order (layer by layer) so each parent's run length is known.
	for d in range(1, DEPTH_COUNT - 1):
		var row: Array = layers[d].duplicate()
		_shuffle(row, rng)
		for cell: MapCellData in row:
			var previous_reward := 0
			var previous_event := 0
			for parent_id in parents.get(cell.id, []):
				previous_reward = maxi(previous_reward, reward_run.get(parent_id, 0))
				previous_event = maxi(previous_event, event_run.get(parent_id, 0))
			var allowed := func(kind: int) -> bool:
				if kind == MapCellData.Kind.REWARD: return previous_reward < MAX_CONSECUTIVE
				if kind == MapCellData.Kind.EVENT: return previous_event < MAX_CONSECUTIVE
				return true
			var kind := MapCellData.Kind.NORMAL_BATTLE
			if not bag.is_empty():
				var index := rng.randi_range(0, bag.size() - 1)
				if not allowed.call(bag[index]):
					var options: Array[int] = []
					for i in bag.size():
						if allowed.call(bag[i]): options.append(i)
					index = options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else -1
				if index >= 0:
					kind = bag[index]
					bag.remove_at(index)
			cell.kind = kind
			reward_run[cell.id] = previous_reward + 1 if kind == MapCellData.Kind.REWARD else 0
			event_run[cell.id] = previous_event + 1 if kind == MapCellData.Kind.EVENT else 0
	_ensure_kind(layers, MapCellData.Kind.REWARD, rng)
	_ensure_kind(layers, MapCellData.Kind.EVENT, rng)
	var elite_candidates: Array = []
	var has_elite := false
	for d in range(template.elite_min_depth - 1, DEPTH_COUNT - 1):
		for cell: MapCellData in layers[d]:
			if cell.kind != MapCellData.Kind.NORMAL_BATTLE:
				continue
			elite_candidates.append(cell)
			if rng.randf() < template.elite_chance:
				cell.kind = MapCellData.Kind.ELITE_BATTLE
				has_elite = true
	if not has_elite and not elite_candidates.is_empty():
		elite_candidates[rng.randi_range(0, elite_candidates.size() - 1)].kind = MapCellData.Kind.ELITE_BATTLE

## Fallback for pathological draws: convert a battle cell without breaking the
## consecutive-cell rule. Deviation from the target ratio is acceptable here.
static func _ensure_kind(layers: Array, kind: int, rng: RandomNumberGenerator) -> void:
	var battles: Array = []
	for d in range(1, DEPTH_COUNT - 1):
		for cell: MapCellData in layers[d]:
			if cell.kind == kind:
				return
			if cell.kind == MapCellData.Kind.NORMAL_BATTLE:
				battles.append(cell)
	_shuffle(battles, rng)
	for cell: MapCellData in battles:
		cell.kind = kind
		if _longest_run(layers, kind) <= MAX_CONSECUTIVE:
			return
		cell.kind = MapCellData.Kind.NORMAL_BATTLE

static func _parent_lookup(layers: Array) -> Dictionary:
	var parents := {}
	for row in layers:
		for cell: MapCellData in row:
			for next_id in cell.next_cell_ids:
				if not parents.has(next_id):
					parents[next_id] = []
				parents[next_id].append(cell.id)
	return parents

static func _longest_run(layers: Array, kind: int) -> int:
	var parents := _parent_lookup(layers)
	var run := {}
	var longest := 0
	for row in layers:
		for cell: MapCellData in row:
			var best := 0
			for parent_id in parents.get(cell.id, []):
				best = maxi(best, run.get(parent_id, 0))
			run[cell.id] = best + 1 if cell.kind == kind else 0
			longest = maxi(longest, run[cell.id])
	return longest

# --- Content ------------------------------------------------------------------

static func _assign_content(layers: Array, template: MapTemplateData, rng: RandomNumberGenerator) -> void:
	var events: Array = template.events.duplicate()
	var pool := _default_event_pool(template)
	var seen_ids := {}
	for ev: EventData in events:
		if ev != null and not ev.id.is_empty():
			seen_ids[ev.id] = true
	for ev: EventData in pool:
		if not seen_ids.has(ev.id):
			events.append(ev)
			seen_ids[ev.id] = true
	_shuffle(events, rng)
	var event_index := 0
	for row in layers:
		for cell: MapCellData in row:
			match cell.kind:
				MapCellData.Kind.START:
					cell.display_name = template.start_name
					cell.description = "远征从这里开始。"
				MapCellData.Kind.NORMAL_BATTLE:
					cell.display_name = "梦境战斗"
					var base_normal: EncounterData = _pick(template.normal_encounters, rng)
					cell.encounter = base_normal if cell.depth <= 2 else _build_depth_normal_encounter(base_normal, cell.depth)
				MapCellData.Kind.ELITE_BATTLE:
					cell.display_name = "精英梦魇"
					cell.encounter = _pick(template.elite_encounters, rng)
				MapCellData.Kind.BOSS_BATTLE:
					cell.display_name = template.boss_name
					cell.encounter = template.boss_encounter
				MapCellData.Kind.REWARD:
					cell.display_name = "梦境遗藏"
					cell.description = "从下列奖励中选择一项。"
					cell.reward_options.assign(template.reward_options)
				MapCellData.Kind.EVENT:
					cell.display_name = "梦境回响"
					# Each event cell in the same map gets a distinct event.
					if event_index < events.size():
						cell.event = events[event_index]
						event_index += 1
					elif not events.is_empty():
						var copy: EventData = events[event_index % events.size()].duplicate(true)
						copy.id = "%s_%d" % [copy.id if not copy.id.is_empty() else "ev", event_index]
						cell.event = copy
						event_index += 1
			if cell.is_battle() and cell.encounter != null and cell.description.is_empty():
				cell.description = cell.encounter.display_name

static func _build_depth_normal_encounter(base: EncounterData, depth: int) -> EncounterData:
	if base == null:
		return null
	var enc: EncounterData = base.duplicate(true)
	enc.duration = 35.0
	enc.preparation_time = 2.0
	enc.group_interval = maxf(3.5, 4.0 - float(maxi(0, depth - 3)) * 0.08)
	var extra_melee := maxi(1, (depth - 1) / 2)
	var extra_ranged := maxi(0, (depth - 2) / 3)
	var charger_def := ContentCatalog.enemy("charger")
	var spitter_def := ContentCatalog.enemy("spitter")
	var buffer_def := ContentCatalog.enemy("buffer")
	var spawner_def := ContentCatalog.enemy("spawner")
	for wave_idx in enc.schedules.size():
		var schedule := enc.schedules[wave_idx]
		if schedule == null or schedule.group == null:
			continue
		for entry in schedule.group.entries:
			if entry == null or entry.enemy == null:
				continue
			if entry.enemy.id == "melee":
				entry.count += extra_melee
			elif entry.enemy.id == "ranged":
				entry.count += extra_ranged
		if depth >= 3 and charger_def != null and wave_idx >= 1:
			var ch_entry := EnemyGroupEntry.new()
			ch_entry.enemy = charger_def
			ch_entry.count = 1 if depth < 6 else 2
			schedule.group.entries.append(ch_entry)
		if depth >= 4 and spitter_def != null and wave_idx % 2 == 1:
			var sp_entry := EnemyGroupEntry.new()
			sp_entry.enemy = spitter_def
			sp_entry.count = 1 if depth < 7 else 2
			schedule.group.entries.append(sp_entry)
		if depth >= 5 and buffer_def != null and wave_idx >= 2 and wave_idx % 2 == 0:
			var bf_entry := EnemyGroupEntry.new()
			bf_entry.enemy = buffer_def
			bf_entry.count = 1
			schedule.group.entries.append(bf_entry)
		if depth >= 6 and spawner_def != null and wave_idx >= 3 and wave_idx % 3 == 0:
			var sw_entry := EnemyGroupEntry.new()
			sw_entry.enemy = spawner_def
			sw_entry.count = 1
			schedule.group.entries.append(sw_entry)
	return enc

static func _default_event_pool(template: MapTemplateData) -> Array[EventData]:
	var normal_enc: EncounterData = template.normal_encounters[0] if not template.normal_encounters.is_empty() else load("res://resources/encounters/training.tres")
	var elite_enc: EncounterData = template.elite_encounters[0] if not template.elite_encounters.is_empty() else load("res://resources/encounters/elite.tres")
	var specs := [
		{"id": "blood_altar", "title": "鲜血祭坛", "scope": EventData.Scope.PERSONAL, "text": "古老的祭坛渴求温热的血液，作为回报，它将赋予你遗留的梦境结晶。", "actions": [
			{"id": "pay_hp_relic", "label": "献出鲜血换取遗物", "kind": EventActionData.Kind.EFFECT, "hp_cost": 25.0, "relic": true},
			{"id": "abandon", "label": "放弃离开", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "wandering_merchant", "title": "游商残影", "scope": EventData.Scope.PERSONAL, "text": "披着斗篷的梦境行商向你展示包裹中的货物，只需支付金币即可交易。", "actions": [
			{"id": "buy_relic", "label": "购买神秘遗物", "kind": EventActionData.Kind.EFFECT, "gold_cost": 15, "relic": true},
			{"id": "buy_weapon", "label": "购买随机武器", "kind": EventActionData.Kind.EFFECT, "gold_cost": 18, "equip": true},
			{"id": "abandon", "label": "放弃交易", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "forge_anvil", "title": "余烬铁砧", "scope": EventData.Scope.PERSONAL, "text": "炉火仍在熊熊燃烧。将一件武器投入熔炉，可以淬炼出持久的锋芒或换取金币。", "actions": [
			{"id": "melt_for_damage", "label": "熔炼武器强化伤害", "kind": EventActionData.Kind.EFFECT, "sacrifice_equip": true, "stat": "damage", "amount": 15.0, "dur": EventActionData.Duration.EXPEDITION},
			{"id": "melt_for_gold", "label": "熔炼武器换取金币", "kind": EventActionData.Kind.EFFECT, "sacrifice_equip": true, "gold_gain": 25},
			{"id": "abandon", "label": "放弃熔炼", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "dream_spring", "title": "微光泉眼", "scope": EventData.Scope.PARTY, "text": "澄澈的泉水在石缝间流淌，全队可以在此休整或汲取泉水强化体魄。", "actions": [
			{"id": "drink_heal", "label": "饮用泉水恢复生命", "kind": EventActionData.Kind.EFFECT, "heal": 30.0},
			{"id": "bath_max_hp", "label": "淬炼体魄提升最大生命", "kind": EventActionData.Kind.EFFECT, "stat": "max_hp", "amount": 12.0, "dur": EventActionData.Duration.MAP}
		]},
		{"id": "rift_ambush", "title": "裂隙躁动", "scope": EventData.Scope.PARTY, "text": "前方的梦境裂隙正涌出敌群，全队共同决定是迎战敌群以获取战利品，还是绕道避开。", "actions": [
			{"id": "fight_normal", "label": "迎战普通敌群", "kind": EventActionData.Kind.ENCOUNTER, "encounter": normal_enc},
			{"id": "fight_elite", "label": "挑战精英梦魇", "kind": EventActionData.Kind.ENCOUNTER, "encounter": elite_enc},
			{"id": "bypass", "label": "全队屏息绕行", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "crimson_pact", "title": "绯红契约", "scope": EventData.Scope.PERSONAL, "text": "契约书页无风自动，签下名字会损耗生命，却能在接下来的战斗中爆发惊人攻速。", "actions": [
			{"id": "sign_pact", "label": "签署契约", "kind": EventActionData.Kind.EFFECT, "hp_cost": 18.0, "stat": "attack_speed", "amount": 30.0, "dur": EventActionData.Duration.COMBAT, "combats": 2},
			{"id": "abandon", "label": "放弃签署", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "golden_shrine", "title": "黄金神龛", "scope": EventData.Scope.PERSONAL, "text": "向神龛投入金币，便能得到收获与幸运的祝福。", "actions": [
			{"id": "pray_harvest", "label": "祈求丰收", "kind": EventActionData.Kind.EFFECT, "gold_cost": 10, "stat": "harvesting", "amount": 15.0, "dur": EventActionData.Duration.EXPEDITION},
			{"id": "pray_luck", "label": "祈求幸运", "kind": EventActionData.Kind.EFFECT, "gold_cost": 10, "stat": "luck", "amount": 15.0, "dur": EventActionData.Duration.MAP},
			{"id": "abandon", "label": "放弃祈祷", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "stone_guardian", "title": "石像守卫的试炼", "scope": EventData.Scope.PARTY, "text": "沉默的石像挡在路中央，全队可以选择接受战斗试炼或聆听古训。", "actions": [
			{"id": "trial_battle", "label": "接受战斗试炼", "kind": EventActionData.Kind.ENCOUNTER, "encounter": normal_enc},
			{"id": "listen_armor", "label": "聆听古训稳固护甲", "kind": EventActionData.Kind.EFFECT, "stat": "armor", "amount": 3.0, "dur": EventActionData.Duration.MAP}
		]},
		{"id": "shadow_gamble", "title": "暗影博弈", "scope": EventData.Scope.PERSONAL, "text": "暗影向你伸出双手，你可以用生命换取沉甸甸的金币袋。", "actions": [
			{"id": "trade_hp_gold", "label": "以血换金", "kind": EventActionData.Kind.EFFECT, "hp_cost": 20.0, "gold_gain": 22},
			{"id": "abandon", "label": "放弃博弈", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "starlight_obelisk", "title": "星辉方尖碑", "scope": EventData.Scope.PARTY, "text": "方尖碑散发出柔和的星辉，照亮了队伍前行的道路。", "actions": [
			{"id": "absorb_speed", "label": "沐浴星辉提升移速", "kind": EventActionData.Kind.EFFECT, "stat": "speed", "amount": 8.0, "dur": EventActionData.Duration.MAP},
			{"id": "absorb_crit", "label": "凝视星芒提升暴击", "kind": EventActionData.Kind.EFFECT, "stat": "crit_chance", "amount": 8.0, "dur": EventActionData.Duration.COMBAT, "combats": 2}
		]},
		{"id": "cursed_chest", "title": "荆棘秘匣", "scope": EventData.Scope.PERSONAL, "text": "布满荆棘的秘匣紧锁着，强行徒手开启会划伤双手，但里面藏着完好的装备。", "actions": [
			{"id": "open_thorns", "label": "徒手开启秘匣", "kind": EventActionData.Kind.EFFECT, "hp_cost": 15.0, "equip": true},
			{"id": "abandon", "label": "放弃开启", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]},
		{"id": "echo_library", "title": "回响书斋", "scope": EventData.Scope.PERSONAL, "text": "书架上残留着可维持数场战斗的战术卷轴，支付少量金币即可研读。", "actions": [
			{"id": "read_melee", "label": "研读近战卷轴", "kind": EventActionData.Kind.EFFECT, "gold_cost": 8, "stat": "melee_damage", "amount": 6.0, "dur": EventActionData.Duration.COMBAT, "combats": 3},
			{"id": "read_ranged", "label": "研读远程卷轴", "kind": EventActionData.Kind.EFFECT, "gold_cost": 8, "stat": "ranged_damage", "amount": 6.0, "dur": EventActionData.Duration.COMBAT, "combats": 3},
			{"id": "abandon", "label": "放弃研读", "kind": EventActionData.Kind.EFFECT, "abandon": true}
		]}
	]
	var result: Array[EventData] = []
	for item in specs:
		var ev := EventData.new()
		ev.id = item["id"]
		ev.title = item["title"]
		ev.scope = item["scope"]
		ev.text = item["text"]
		for act_spec in item["actions"]:
			var act := EventActionData.new()
			act.id = act_spec["id"]
			act.label = act_spec["label"]
			act.kind = act_spec["kind"]
			act.is_abandon = bool(act_spec.get("abandon", false))
			act.gold_cost = int(act_spec.get("gold_cost", 0))
			act.health_cost = float(act_spec.get("hp_cost", 0.0))
			act.requires_sacrifice_equipment = bool(act_spec.get("sacrifice_equip", false))
			act.gold_gain = int(act_spec.get("gold_gain", 0))
			act.heal_amount = float(act_spec.get("heal", 0.0))
			act.stat_id = str(act_spec.get("stat", ""))
			act.stat_amount = float(act_spec.get("amount", 0.0))
			act.duration_kind = int(act_spec.get("dur", EventActionData.Duration.EXPEDITION))
			act.duration_combats = int(act_spec.get("combats", 1))
			act.grant_random_equipment = bool(act_spec.get("equip", false))
			act.grant_random_relic = bool(act_spec.get("relic", false))
			act.encounter = act_spec.get("encounter", null)
			ev.actions.append(act)
		result.append(ev)
	return result

static func _pick(items: Array, rng: RandomNumberGenerator) -> Variant:
	return null if items.is_empty() else items[rng.randi_range(0, items.size() - 1)]

static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap

# --- Validation ---------------------------------------------------------------

## Checks every structural rule of a generated route map. Used after generation
## and by tests; returns an empty array when the map is valid.
static func validation_errors(map: MapData, template: MapTemplateData = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if map == null or not map.directed_routes:
		errors.append("不是路线地图。")
		return errors
	var elite_min_depth := template.elite_min_depth if template != null else 6
	var by_id := {}
	var per_depth := {}
	for cell in map.cells:
		by_id[cell.id] = cell
		per_depth[cell.depth] = int(per_depth.get(cell.depth, 0)) + 1
	for d in DEPTH_COUNT:
		if int(per_depth.get(d + 1, 0)) != LAYER_WIDTHS[d]:
			errors.append("第 %d 层格子数应为 %d。" % [d + 1, LAYER_WIDTHS[d]])
	if map.cells.size() != 54:
		errors.append("地图总格子数应为 54。")
	var start: MapCellData = by_id.get(map.starting_cell_id)
	var boss: MapCellData = by_id.get(map.boss_cell_id)
	if start == null or start.depth != 1 or start.kind != MapCellData.Kind.START:
		errors.append("起点必须位于第 1 层。")
	if boss == null or boss.depth != DEPTH_COUNT or boss.kind != MapCellData.Kind.BOSS_BATTLE:
		errors.append("BOSS 必须位于第 10 层。")
	if not errors.is_empty():
		return errors
	var counts := {}
	var event_keys := {}
	for cell in map.cells:
		counts[cell.kind] = int(counts.get(cell.kind, 0)) + 1
		if cell.kind == MapCellData.Kind.EVENT and cell.event != null:
			var ev_key: String = cell.event.id if not cell.event.id.is_empty() else cell.event.text
			if event_keys.has(ev_key):
				errors.append("同一张地图内不得重复出现相同事件：%s" % ev_key)
			event_keys[ev_key] = true
		if cell.kind == MapCellData.Kind.START and cell != start:
			errors.append("只能有一个起点。")
		if cell.kind == MapCellData.Kind.BOSS_BATTLE and cell != boss:
			errors.append("只能有一个 BOSS 格。")
		if cell.kind == MapCellData.Kind.ELITE_BATTLE and cell.depth < elite_min_depth:
			errors.append("%s 位于深度 %d，精英战只能出现在深度 %d 之后。" % [cell.id, cell.depth, elite_min_depth])
		if cell == boss:
			if not cell.next_cell_ids.is_empty():
				errors.append("BOSS 格不能有后续路线。")
		elif cell.next_cell_ids.is_empty() or cell.next_cell_ids.size() > 3:
			errors.append("%s 必须有 1–3 条下行路线。" % cell.id)
		for next_id in cell.next_cell_ids:
			var next: MapCellData = by_id.get(next_id)
			if next == null or next.depth != cell.depth + 1:
				errors.append("%s 的路线必须连接到下一层。" % cell.id)
			elif next != boss and absi(next.grid_position.x - cell.grid_position.x) > 1:
				errors.append("%s 的路线只能向左下、正下或右下。" % cell.id)
		errors.append_array(cell.validation_errors())
	for kind in [MapCellData.Kind.REWARD, MapCellData.Kind.EVENT, MapCellData.Kind.ELITE_BATTLE]:
		if int(counts.get(kind, 0)) < 1:
			var sample := MapCellData.new()
			sample.kind = kind
			errors.append("地图至少需要一个%s格。" % sample.type_name())
	var reachable := _reach(map.starting_cell_id, func(id: String): return by_id[id].next_cell_ids)
	if reachable.size() != map.cells.size():
		errors.append("存在无法从起点到达的格子。")
	var parents := {}
	for cell in map.cells:
		for next_id in cell.next_cell_ids:
			if not parents.has(next_id): parents[next_id] = []
			parents[next_id].append(cell.id)
	var reaches_boss := _reach(map.boss_cell_id, func(id: String): return parents.get(id, []))
	if reaches_boss.size() != map.cells.size():
		errors.append("存在无法通往 BOSS 的死路。")
	var layers: Array = []
	for d in DEPTH_COUNT:
		layers.append([])
	for cell in map.cells:
		layers[cell.depth - 1].append(cell)
	for kind in [MapCellData.Kind.REWARD, MapCellData.Kind.EVENT]:
		if _longest_run(layers, kind) > MAX_CONSECUTIVE:
			errors.append("存在连续 3 个或以上相同类型（奖励／事件）的路线。")
	return errors

static func _reach(origin: String, links: Callable) -> Dictionary:
	var seen := {origin: true}
	var frontier: Array[String] = [origin]
	while not frontier.is_empty():
		var id: String = frontier.pop_back()
		for next_id in links.call(id):
			if not seen.has(next_id):
				seen[next_id] = true
				frontier.append(next_id)
	return seen
