extends SceneTree

const Store = preload("res://addons/enemy_editor/enemy_editor_store.gd")
const ItemStore = preload("res://addons/content_editor/item_editor_store.gd")
const EditorPanel = preload("res://addons/enemy_editor/enemy_editor_dock.gd")
const ENEMY_PATH := "res://resources/enemies/qa_editor_smoke.tres"
const LEGACY_PATH := "res://resources/enemies/qa_legacy_enemy.tres"
const EQUIPMENT_PATH := "res://resources/enemy_equipment/qa_enemy_equipment.tres"
const RELIC_PATH := "res://resources/enemy_relics/qa_enemy_relic.tres"
const GROUP_PATH := "res://resources/groups/qa_editor_smoke.tres"
const ENCOUNTER_PATH := "res://resources/encounters/qa_editor_smoke.tres"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _picker_index(picker: OptionButton, path: String) -> int:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == path: return index
	return -1

func _run() -> void:
	for path in [ENEMY_PATH, LEGACY_PATH, EQUIPMENT_PATH, RELIC_PATH, GROUP_PATH, ENCOUNTER_PATH]:
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite existing fixture: " + path)
			quit(1)
			return
	var store := Store.new()
	var equipment_store := ItemStore.new()
	var relic_store := ItemStore.new()
	relic_store.kind = "relic"
	var original := load("res://resources/enemies/boss.tres") as EnemyData
	var original_damage := original.equipment.attacks[0].damage
	var weapon := store.copy_definition(original.equipment) as EnemyEquipmentData
	weapon.id = "qa_enemy_equipment"
	var relic := store.copy_definition(original.relic) as RelicData
	relic.id = "qa_enemy_relic"
	check(equipment_store.save_item(weapon, "").ok and relic_store.save_item(relic, "").ok, "Independent enemy items are saved to the item libraries")
	var empty := store.new_enemy()
	check(empty.equipment == null and empty.relic == null and not store.validate(empty).is_empty(), "New enemy requires a saved equipment selection")
	var edited := store.copy_enemy(original)
	edited.id = "qa_editor_smoke"
	edited.display_name = "QA Enemy"
	edited.max_health = 777
	edited.equipment = load(EQUIPMENT_PATH)
	edited.relic = load(RELIC_PATH)
	check(original.max_health != edited.max_health and original.equipment.attacks[0].damage == original_damage, "Enemy draft isolates scalar changes from saved source")
	check(store.validate(edited).is_empty(), "Saved enemy-only items can be assigned to the draft")
	var first := store.save_enemy(edited, "")
	check(first.ok and first.path == ENEMY_PATH, "Enemy saves with selected assets")
	if not first.ok:
		quit(1)
		return
	var saved := ResourceLoader.load(ENEMY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyData
	check(saved.equipment.resource_path == EQUIPMENT_PATH and saved.relic.resource_path == RELIC_PATH, "Independent reload preserves external item resource paths")
	check(store.references(EQUIPMENT_PATH).has(ENEMY_PATH) and store.references(RELIC_PATH).has(ENEMY_PATH), "Godot dependency graph records both item references")
	check(not equipment_store.delete_item(EQUIPMENT_PATH).ok and not relic_store.delete_item(RELIC_PATH).ok, "Referenced equipment and relic cannot be deleted")
	var copied := store.copy_enemy(saved)
	check(copied.equipment == saved.equipment and copied.relic == saved.relic, "Copying an enemy preserves shared equipment and relic references")
	var invalid := store.copy_enemy(saved)
	invalid.equipment = store.copy_definition(saved.equipment)
	check(not store.validate(invalid, ENEMY_PATH).is_empty(), "Unsaved temporary equipment is rejected")
	invalid = store.copy_enemy(saved)
	invalid.relic = load("res://resources/relics/seed.tres")
	check(not store.validate(invalid, ENEMY_PATH).is_empty(), "Player relic cannot be assigned to enemy")
	var fingerprint := store.fingerprint(ENEMY_PATH)
	edited.can_attack_while_retreating = true
	check(not store.save_enemy(edited, ENEMY_PATH, "stale").ok and store.fingerprint(ENEMY_PATH) == fingerprint, "External file conflict cannot overwrite enemy")
	check(store.save_enemy(edited, ENEMY_PATH, fingerprint).ok, "Existing enemy can be saved with references")
	var grouped := store.copy_enemy(load("res://resources/enemies/melee.tres"))
	grouped.category = EnemyData.Category.BOSS
	check(not store.validate(grouped, "res://resources/enemies/melee.tres").is_empty(), "Referenced group member cannot change to Boss")
	var assigned_boss := store.copy_enemy(original)
	assigned_boss.category = EnemyData.Category.NORMAL
	check(not store.validate(assigned_boss, "res://resources/enemies/boss.tres").is_empty(), "Boss referenced by encounter cannot change to Normal")
	var entry := EnemyGroupEntry.new()
	entry.enemy = load(ENEMY_PATH)
	var group := EnemyGroupData.new()
	group.entries.append(entry)
	check(ResourceSaver.save(group, GROUP_PATH) == OK, "Group reference fixture saved")
	var schedule := GroupSpawnSchedule.new()
	schedule.group = load(GROUP_PATH)
	var encounter := EncounterData.new()
	encounter.schedules.append(schedule)
	check(ResourceSaver.save(encounter, ENCOUNTER_PATH) == OK, "Encounter reference fixture saved")
	var references := store.references(ENEMY_PATH)
	check(references.has(GROUP_PATH) and references.has(ENCOUNTER_PATH), "Enemy dependency scan finds direct and transitive references")
	check(not store.delete_enemy(ENEMY_PATH).ok, "Referenced enemy deletion is blocked")
	var panel: Control = EditorPanel.new()
	root.add_child(panel)
	panel.request_open(ENEMY_PATH)
	check(panel.draft.equipment.resource_path == EQUIPMENT_PATH and panel.draft.relic.resource_path == RELIC_PATH, "Editor loads saved references")
	check(_picker_index(panel._equipment_picker, EQUIPMENT_PATH) >= 0 and _picker_index(panel._relic_picker, RELIC_PATH) >= 0, "Dropdowns contain existing enemy resources")
	check(_picker_index(panel._equipment_picker, "res://resources/weapons/pistol.tres") < 0 and _picker_index(panel._relic_picker, "res://resources/relics/seed.tres") < 0, "Player-only items are not offered")
	var health_field := panel._basics.find_child("max_health", true, false) as SpinBox
	health_field.value = 888
	check(panel.draft.max_health == 888 and panel.is_dirty(), "Enemy form edits only draft")
	panel._select_equipment(_picker_index(panel._equipment_picker, "res://resources/enemy_equipment/rifle.tres"))
	await process_frame
	check(panel.draft.equipment.resource_path == "res://resources/enemy_equipment/rifle.tres", "Equipment dropdown selects the actual resource")
	panel._select_relic(0)
	await process_frame
	check(panel.draft.relic == null, "Optional relic can be cleared")
	panel._select_equipment(_picker_index(panel._equipment_picker, EQUIPMENT_PATH))
	panel._select_relic(_picker_index(panel._relic_picker, RELIC_PATH))
	await process_frame
	check(panel.save_current(false), "Enemy editor saves selected item references")
	panel._reload_current()
	check(panel.draft.max_health == 888 and panel.draft.equipment.resource_path == EQUIPMENT_PATH and panel.draft.relic.resource_path == RELIC_PATH, "Editor reopens with saved equipment and relic selection")
	panel._duplicate_enemy()
	check(panel.selected_path.is_empty() and panel.draft.equipment.resource_path == EQUIPMENT_PATH and panel.draft.relic.resource_path == RELIC_PATH, "Duplicated enemy retains selected assets")
	var weapon_edit := store.copy_definition(load(EQUIPMENT_PATH)) as EnemyEquipmentData
	weapon_edit.attacks[0].damage = 37
	check(equipment_store.save_item(weapon_edit, EQUIPMENT_PATH, store.fingerprint(EQUIPMENT_PATH)).ok, "Shared equipment edit saves")
	var relic_edit := store.copy_definition(load(RELIC_PATH)) as RelicData
	relic_edit.regeneration = 12
	check(relic_store.save_item(relic_edit, RELIC_PATH, store.fingerprint(RELIC_PATH)).ok, "Shared relic edit saves")
	saved = ResourceLoader.load(ENEMY_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyData
	check(saved.equipment.attacks[0].damage == 37 and saved.relic.regeneration == 12, "Reopened enemy reads updated shared items")
	check(original.equipment.attacks[0].damage == original_damage, "Editing saved QA item does not mutate unrelated original resource")
	var legacy := store.copy_definition(original) as EnemyData
	legacy.id = "qa_legacy_enemy"
	check(ResourceSaver.save(legacy, LEGACY_PATH) == OK, "Legacy embedded enemy fixture saved")
	panel._open(LEGACY_PATH)
	check(not store.validate(panel.draft, LEGACY_PATH).is_empty(), "Legacy embedded item must be migrated before save")
	var legacy_fingerprint := store.fingerprint(LEGACY_PATH)
	panel._export_old_item(panel.draft.equipment, true)
	var migrated_equipment: String = panel.draft.equipment.resource_path
	panel._export_old_item(panel.draft.relic, false)
	var migrated_relic: String = panel.draft.relic.resource_path
	check(store.is_saved_item(panel.draft.equipment, Store.EQUIPMENT_DIR) and store.is_saved_item(panel.draft.relic, Store.RELIC_DIR), "Legacy equipment and relic can be saved as real library resources")
	check(panel.draft.equipment.attacks[0].damage == original_damage and panel.draft.relic.regeneration == original.relic.regeneration, "Legacy migration preserves item values")
	check(store.fingerprint(LEGACY_PATH) == legacy_fingerprint, "Creating independent items leaves original enemy file untouched until save")
	check(panel.save_current(false), "Migrated enemy can be saved referencing independent items")
	panel.queue_free()
	await process_frame
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena: Node = current_scene
	arena.director.stop()
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load(ENEMY_PATH)
	unit.player = arena.player
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	check(unit.loadout_controller.equipped[0].attacks[0].data.damage == 37 and unit.loadout.regeneration() == 12, "New enemy instance uses updated shared item effects")
	unit.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ENCOUNTER_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GROUP_PATH))
	check(store.delete_enemy(ENEMY_PATH).ok and store.delete_enemy(LEGACY_PATH).ok, "Unreferenced test enemies can be removed")
	check(equipment_store.delete_item(EQUIPMENT_PATH).ok and relic_store.delete_item(RELIC_PATH).ok, "Items can be removed after their enemy references are gone")
	check(equipment_store.delete_item(migrated_equipment).ok and relic_store.delete_item(migrated_relic).ok, "Migrated fixture resources can be removed after enemy deletion")
	check(not store.delete_enemy("res://scripts/actors/enemy.gd").ok, "Deletion is restricted to the enemy library")
	print("ENEMY EDITOR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
