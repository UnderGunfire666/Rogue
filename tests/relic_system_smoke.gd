extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	var ids := ContentCatalog.relic_ids()
	check(ids.size() >= 67, "Reference relics and original relics are available")
	for id in ids:
		var relic := ContentCatalog.relic(id)
		check(relic != null and CombatDataValidation.item_errors(relic).is_empty(), "Relic validates: " + id)
	var bat := ContentCatalog.relic("brotato_bat")
	check(bat != null and bat.base_price == 20 and bat.rarity == 1 and bat.copy_limit == 0 and bat.tags.has("Life Steal"), "Reference metadata is preserved")
	check(bat.primary_stats.life_steal == 2 and bat.primary_stats.harvesting == -2, "Positive and negative reference effects are complete")
	check(state.add_relic(bat.id) and state.add_relic(bat.id), "Unlimited relics may stack")
	check(state.stat_value("life_steal") == 4 and state.stat_value("harvesting") == -4, "Stacked relic effects affect actual player attributes")
	bat.copy_limit = 2
	check(not state.add_relic(bat.id), "Copy limit blocks acquiring another relic")
	check(not state.roll_shop_items(PackedStringArray([bat.id]), false, 1).has(bat.id), "At-limit relics are excluded from random offers and crates")
	bat.copy_limit = 0
	change_scene_to_file("res://scenes/app/loadout_select.tscn")
	await process_frame
	await process_frame
	check(current_scene.relic_buttons.size() == 4 and current_scene.chosen_relic.is_empty(), "Loadout selection offers four relics and requires one explicit selection")
	for offered in current_scene.relic_buttons:
		check(ContentCatalog.relic(offered).rarity == 1, "Opening offers contain only tier one relics")
	state.new_run()
	state.start_with("needle", "seed")
	state.gold = 50
	change_scene_to_file("res://scenes/ui/shop_screen.tscn")
	await process_frame
	await process_frame
	var shop := current_scene
	shop._buy_relic(bat.id)
	check(state.gold == 30 and state.relics.has(bat.id), "Shop charges the selected relic's actual base price")
	print("RELIC SYSTEM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
