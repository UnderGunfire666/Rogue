extends SceneTree

const CharacterPanel = preload("res://addons/character_editor/character_editor_panel.gd")
const ItemPanel = preload("res://addons/content_editor/item_editor_panel.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.select_character("well_rounded")
	check(state.effective_max_health() == 105 and state.health == 105, "Reference character starts at full increased health")
	check(state.stat_value("speed") == 5 and state.stat_value("harvesting") == 8, "Reference character has its complete supported bonuses")
	change_scene_to_file("res://scenes/app/character_select.tscn")
	await process_frame
	await process_frame
	check(current_scene.characters.has("well_rounded"), "Character selection discovers reference character")
	current_scene._select("well_rounded")
	var grids: Array[Node] = current_scene.detail.find_children("*", "GridContainer", true, false)
	check(grids.size() == 1 and grids[0].get_child_count() == 15, "Selection displays every primary attribute")
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	var controller: Node2D = arena.player.skill
	check(controller.data == null and controller.entries.is_empty(), "Default character has no intrinsic skill")
	state.equip_weapon("cleaver", 0)
	check(controller.entries.size() == 1 and controller.data != null, "Equipping an item installs its bound skill")
	controller.toggle_targeting()
	state.stats_changed.emit()
	check(controller.targeting, "Unrelated stat updates preserve active skill targeting")
	check(controller.try_cast_at(arena.player.global_position), "Bound weapon skill can be cast")
	var weapon_timer: Timer = controller.cooldown
	var relic := RelicData.new()
	relic.id = "skill_fixture"
	relic.skill = SkillData.new()
	relic.skill.display_name = "Relic Skill"
	state.loadout.add_relic(relic)
	state.stats_changed.emit()
	check(controller.entries.size() == 2 and not weapon_timer.is_stopped(), "Adding relic skill preserves weapon cooldown")
	controller.toggle_targeting()
	check(controller.targeting and controller.data.display_name == "Relic Skill" and controller.cooldown.is_stopped(), "Q switches from cooling weapon skill to ready relic skill")
	check(controller.try_cast_at(arena.player.global_position) and not controller.cooldown.is_stopped(), "Relic skill has independent cooldown")
	state.loadout.clear_relics()
	state.stats_changed.emit()
	check(controller.entries.size() == 1 and controller.cooldown == weapon_timer, "Removing relic removes only its own skill")
	var panel := CharacterPanel.new()
	root.add_child(panel)
	check(panel.list.item_count >= 17 and panel.draft != null and panel.draft.id == "wanderer", "Character editor lists all 17 selectable characters and opens default character automatically")
	panel._copy_character()
	check(panel.draft.id == "wanderer_copy" and panel.dirty, "Character editor duplicates selected character into a new editable draft")
	panel._new_character()
	panel.draft.id = "qa_character_skill"
	panel.draft.display_name = "测试角色"
	panel.draft.primary_stats.armor = 7
	check(panel.save_current(), "Character editor saves a new character")
	var path: String = panel.selected_path
	check(ContentCatalog.character_ids().has("qa_character_skill") and ContentCatalog.character("qa_character_skill").primary_stats.armor == 7, "Saved character is selectable with its attributes")
	panel.draft.primary_stats.armor = 9
	check(panel.save_current() and ContentCatalog.character("qa_character_skill").primary_stats.armor == 9, "Editing a saved character updates runtime resource")
	panel._delete()
	check(not FileAccess.file_exists(path), "Character editor deletes unreferenced character")
	panel.queue_free()
	var item_panel := ItemPanel.new()
	item_panel.kind = "relic"
	root.add_child(item_panel)
	item_panel._new_item(0)
	var toggles := item_panel._details.find_children("*", "CheckBox", true, false)
	check(not toggles.is_empty(), "Relic editor provides a skill binding control")
	if not toggles.is_empty():
		toggles[0].button_pressed = true
		await process_frame
		check(item_panel.draft.skill != null and item_panel._details.find_child("damage", true, false) != null, "Skill fields appear when a relic binds a skill")
		item_panel.draft.id = "qa_skill_relic"
		item_panel.draft.skill.damage = 27
		check(item_panel.save_current(false) and ContentCatalog.relic("qa_skill_relic").skill.damage == 27, "Relic editor saves and reloads bound skill data")
		var saved_path: String = item_panel.selected_path
		check(item_panel.store.delete_item(saved_path).ok, "Temporary relic fixture can be deleted")
	item_panel.queue_free()
	print("CHARACTER AND SKILL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
