class_name RewardResolver
extends RefCounted
## Shared by Reward Cells and rewards triggered from Event Cells.

static func apply(state: Node, reward: RewardData, slots: PackedInt32Array) -> bool:
	if reward == null or not reward.validation_errors().is_empty() or slots.size() != reward.equipment.size():
		return false
	for slot in slots:
		if slot < 0 or slot >= state.loadout.equipment.size():
			return false
	var preview := ActorLoadout.new(state.loadout.recipient, state.loadout.equipment.size(), state.loadout.relic_slot_limit, state.loadout.equipment_rules)
	for index in state.loadout.equipment.size(): preview.equipment[index] = state.loadout.equipment[index]
	for i in reward.equipment.size():
		if not preview.equip(reward.equipment[i], slots[i]): return false
	for i in reward.equipment.size():
		state.loadout.equip(reward.equipment[i], slots[i])
	for relic in reward.relics:
		state.loadout.add_relic(relic)
	state.health = minf(state.health, state.effective_max_health())
	state.gold += reward.gold
	state.stats_changed.emit()
	return true
