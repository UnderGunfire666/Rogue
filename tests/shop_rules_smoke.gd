extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	state.gold = 100
	state.completed_waves = 5
	change_scene_to_file("res://scenes/ui/shop_screen.tscn")
	await process_frame
	await process_frame
	var shop := current_scene
	var id: String = shop.relic_offers[0]
	var old_price: int = shop._relic_price(id)
	shop._toggle_lock(id, false)
	var cost: int = shop._reroll_cost()
	var gold: int = state.gold
	shop._reroll()
	check(state.gold == gold - cost and shop._reroll_cost() > cost, "Reroll charges the displayed price and raises the next price")
	check(shop.relic_offers.has(id) and state.locked_relic_prices.has(id), "Locked item survives reroll")
	state.character.combat_rules = CharacterCombatRules.new()
	state.character.combat_rules.item_price_multiplier = 2
	check(shop._relic_price(id) == old_price, "Locked item keeps its locked price")
	shop._buy_relic(id)
	check(not state.locked_relic_prices.has(id) and state.relics.has(id), "Buying removes the lock and grants the item")
	gold = state.gold
	shop._recycle(1)
	check(state.weapons[1].is_empty() and state.gold == gold + 4, "Recycling removes the weapon and returns 25 percent of its price")
	state.new_run()
	check(state.locked_weapon_prices.is_empty() and state.locked_relic_prices.is_empty(), "New journey clears old shop locks")
	print("SHOP RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
