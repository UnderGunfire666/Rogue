extends SceneTree

const ItemPanel = preload("res://addons/content_editor/item_editor_panel.gd")
const ItemStore = preload("res://addons/content_editor/item_editor_store.gd")
const WEAPON_PATH := "res://resources/weapons/qa_content_weapon.tres"
const RELIC_PATH := "res://resources/relics/qa_content_relic.tres"
const ENEMY_ITEM_PATH := "res://resources/enemy_equipment/qa_content_equipment.tres"
const REWARD_PATH := "res://resources/qa_content_reward.tres"
var state: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	for path in [WEAPON_PATH, RELIC_PATH, ENEMY_ITEM_PATH, REWARD_PATH]:
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite fixture: " + path)
			quit(1)
			return
	state = root.get_node("RunState")
	var variants := [[false, false], [false, false], [false, false]]
	for id in ContentCatalog.weapon_ids():
		var item := ContentCatalog.weapon(id)
		check(CombatDataValidation.item_errors(item).is_empty(), "Weapon example validates: " + id)
		var count := item.projectile_count if item.kind == WeaponData.Kind.RANGED else item.target_count
		variants[item.kind][0 if count == 1 else 1] = true
	for index in 3:
		check(variants[index][0] and variants[index][1], "Each weapon kind includes single and group examples: " + str(index))
	await _editor_checks()
	await _combat_checks()
	print("CONTENT EDITORS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _editor_checks() -> void:
	var panel: Control = ItemPanel.new()
	panel.kind = "equipment"
	root.add_child(panel)
	check(panel._list.item_count >= 6, "Equipment library lists saved items with an empty search")
	panel._recipient.select(1)
	panel._type_filter.select(3)
	panel._refresh_list()
	check(panel._list.item_count == 2, "Equipment library filters player spell examples")
	panel._recipient.select(0)
	panel._type_filter.select(0)
	panel._refresh_list()
	panel._new_item(0)
	panel.draft.id = "qa_content_weapon"
	panel.draft.kind = WeaponData.Kind.SPELL
	panel.draft.target_count = 3
	panel._rebuild()
	var damage := panel._details.find_child("damage", true, false) as SpinBox
	damage.value = 17
	check(panel.draft.damage == 17 and panel.is_dirty(), "Equipment editor custom fields update the draft")
	check(panel.save_current(false), "Equipment editor creates player spell resource")
	check(ContentCatalog.weapon_ids().has("qa_content_weapon") and ContentCatalog.weapon("qa_content_weapon").damage == 17, "New player equipment is discovered without editing a hardcoded catalog")
	panel.draft.id = "qa_content_weapon_renamed"
	panel._changed()
	check(panel.save_current(false) and panel.selected_path == WEAPON_PATH, "Editing ID preserves the existing file path")
	check(ContentCatalog.weapon("qa_content_weapon_renamed") != null, "Runtime lookup uses Resource ID rather than filename")
	panel._reload()
	check(panel.draft.kind == WeaponData.Kind.SPELL and panel.draft.target_count == 3 and panel.draft.damage == 17, "Equipment editor reopens all spell parameters")
	panel._new_item(1)
	panel.draft.id = "qa_content_equipment"
	panel.draft.attacks[0].kind = AttackProfileData.Kind.SPELL
	panel.draft.attacks[0].effect = AttackProfileData.Effect.HEAL
	panel.draft.attacks[0].attack_range = 88
	panel.draft.attacks[0].target_count = 3
	panel._add_attack(AttackProfileData.Kind.RANGED)
	check(panel.save_current(false) and panel.draft.attacks.size() == 2, "Enemy equipment supports healing spell plus a ranged profile")
	check(panel.draft.attacks[0].effect == AttackProfileData.Effect.HEAL and panel.draft.attacks[0].target_count == 3, "Enemy spell effect and healing unit limit survive reload")
	panel.draft.attacks[1].projectile_count = 0
	check(not panel.store.validate(panel.draft, panel.selected_path).is_empty(), "Invalid projectile count cannot be saved")
	panel._reload()
	var shared := load("res://resources/enemy_equipment/healing_staff.tres")
	check(shared.healing_spell() != null, "Old healer equipment is migrated to a spell healing effect")
	var equipment_store := ItemStore.new()
	check(not equipment_store.delete_item("res://resources/enemy_equipment/healing_staff.tres").ok, "Referenced enemy equipment is protected from deletion")
	panel.queue_free()
	await process_frame
	var relic_panel: Control = ItemPanel.new()
	relic_panel.kind = "relic"
	root.add_child(relic_panel)
	check(relic_panel._list.item_count >= 5, "Relic library lists both player and enemy resources")
	relic_panel._new_item(0)
	relic_panel.draft.id = "qa_content_relic"
	var movement := relic_panel._details.find_child("movement_bonus", true, false) as SpinBox
	var regeneration := relic_panel._details.find_child("regeneration", true, false) as SpinBox
	var price := relic_panel._identity.find_child("base_price", true, false) as SpinBox
	var limit := relic_panel._identity.find_child("copy_limit", true, false) as SpinBox
	var tags := relic_panel._identity.find_child("tags", true, false) as LineEdit
	movement.value = 25
	regeneration.value = 2
	price.value = 42
	limit.value = 2
	tags.text = "Speed, Test"
	tags.text_changed.emit(tags.text)
	check(relic_panel.save_current(false), "Relic editor creates a composite passive relic")
	check(ContentCatalog.relic_ids().has("qa_content_relic") and is_equal_approx(ContentCatalog.relic("qa_content_relic").movement_bonus, 0.25) and is_equal_approx(ContentCatalog.relic("qa_content_relic").regeneration, 2), "Relic percentages and regeneration persist and enter runtime catalog")
	var saved_relic := ContentCatalog.relic("qa_content_relic")
	check(saved_relic.base_price == 42 and saved_relic.copy_limit == 2 and saved_relic.tags == PackedStringArray(["Speed", "Test"]), "Relic editor persists price, copy limit and tags")
	var reward := RewardData.new()
	reward.equipment.append(load(WEAPON_PATH))
	reward.relics.append(load(RELIC_PATH))
	check(ResourceSaver.save(reward, REWARD_PATH) == OK, "Reference fixture saved")
	check(not equipment_store.delete_item(WEAPON_PATH).ok and not relic_panel.store.delete_item(RELIC_PATH).ok, "Reward references protect both weapon and relic from deletion")
	var draft_copy: ItemDefinition = relic_panel.store.io.copy_definition(relic_panel.draft)
	draft_copy.movement_bonus = -1.0
	check(not relic_panel.store.validate(draft_copy, RELIC_PATH).is_empty(), "Relic editor rejects invalid negative speed multiplier")
	draft_copy = relic_panel.store.io.copy_definition(relic_panel.draft)
	check(not relic_panel.store.save_item(draft_copy, RELIC_PATH, "outdated").ok, "External changes block item overwrite")
	relic_panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REWARD_PATH))
	var relic_store := ItemStore.new()
	relic_store.kind = "relic"
	check(equipment_store.delete_item(WEAPON_PATH).ok and equipment_store.delete_item(ENEMY_ITEM_PATH).ok and relic_store.delete_item(RELIC_PATH).ok, "Unreferenced fixtures delete cleanly from both libraries")
	check(not ContentCatalog.weapon_ids().has("qa_content_weapon_renamed") and not ContentCatalog.relic_ids().has("qa_content_relic"), "Deleted items leave the dynamic runtime catalog")

func _enemy(arena: Node, point: Vector2, data_id: String = "melee") -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/%s.tres" % data_id).duplicate(true)
	unit.player = arena.player
	unit.position = point
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.entered_arena = true
	return unit

func _weapon(arena: Node, id: String) -> Node2D:
	var weapon: Node2D = load("res://scenes/combat/weapon.tscn").instantiate()
	weapon.data = ContentCatalog.weapon(id)
	weapon.holder = arena.player
	arena.player.add_child(weapon)
	weapon.set_physics_process(false)
	return weapon

func _clear_enemies() -> void:
	for unit in get_nodes_in_group("enemies"):
		unit.remove_from_group("enemies")
		unit.queue_free()
	await process_frame

func _combat_checks() -> void:
	state.new_run()
	state.start_with("pistol", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena: Node = current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	arena.player.controls.set_physics_process(false)
	for weapon in arena.player.inventory.equipped: weapon.set_physics_process(false)
	var center: Vector2 = arena.player.position
	var melee := _enemy(arena, center + Vector2(240, 0))
	melee._physics_process(1.0 / 60)
	check(is_equal_approx(melee.velocity.length(), 144), "Migrated melee uses fixed 0.8 x 180 = 144 speed")
	state.base_movement_speed = 500
	state.movement_bonus = 2.0
	melee._physics_process(1.0 / 60)
	check(is_equal_approx(melee.velocity.length(), 144), "Enemy speed ignores player base stat and upgrades")
	state.base_movement_speed = 120
	state.movement_bonus = 0
	check(load("res://resources/enemies/ranged.tres").movement_speed == 108 and load("res://resources/enemies/healer.tres").movement_speed == 108, "Ranged and caster have fixed migrated speed 108")
	await _clear_enemies()
	var close := _enemy(arena, center + Vector2(180, 0))
	var weak := _enemy(arena, center + Vector2(210, 0))
	weak.health.current = 25
	var spell := _weapon(arena, "arcane_staff")
	var bullet_count: int = arena.get_node("Projectiles").get_child_count()
	spell._try_direct_attack()
	check(weak.health.current == 25 and not is_instance_valid(close), "Single spell directly hits only the nearest target")
	check(arena.get_node("Projectiles").get_child_count() == bullet_count, "Spell hit has no traveling projectile")
	spell.queue_free()
	await _clear_enemies()
	var group: Array[Node2D] = []
	for index in 4: group.append(_enemy(arena, center + Vector2(130 + index * 8, 0)))
	var outside := _enemy(arena, center + Vector2(210, 0))
	spell = _weapon(arena, "storm_tome")
	spell._try_direct_attack()
	var hit := 0
	for unit in group:
		if unit.health.current == 4: hit += 1
	check(hit == 3 and outside.health.current == 32, "Group spell respects three-target cap and activation range")
	spell.queue_free()
	await _clear_enemies()
	for index in 4: _enemy(arena, center + Vector2(55 + index * 5, 0))
	var cleaver := _weapon(arena, "cleaver")
	cleaver._try_direct_attack()
	for frame in 70: await physics_frame
	hit = 0
	for unit in get_nodes_in_group("enemies"):
		if unit.health.current == 11: hit += 1
	check(hit == 4, "Melee sweep hits all four enemies along its path")
	cleaver.queue_free()
	await _clear_enemies()
	var shotgun := _weapon(arena, "scattergun")
	check(not shotgun.try_fire(center + Vector2(100, 0)), "Ranged activation waits for enemies inside its attack range")
	_enemy(arena, center + Vector2(100, 0))
	bullet_count = arena.get_node("Projectiles").get_child_count()
	shotgun._physics_process(0.016)
	check(not shotgun.cooldown.is_stopped(), "Automatic multishot weapon activates inside range")
	check(arena.get_node("Projectiles").get_child_count() == bullet_count + 3, "One automatic attack emits configured projectile count")
	for bullet in arena.get_node("Projectiles").get_children():
		check(bullet.damage == 14, "Each scatter projectile carries its own configured damage")
		bullet.queue_free()
	shotgun.queue_free()
	await _clear_enemies()
	_enemy(arena, center + Vector2(0, 100))
	var far := _enemy(arena, center + Vector2(650, 0))
	var gun := _weapon(arena, "pistol")
	gun.try_fire(far.position)
	var persistent: Node2D = load("res://scenes/combat/projectile.tscn").instantiate()
	persistent.position = center + Vector2(0, 240)
	persistent.direction = Vector2.DOWN
	persistent.speed = 100
	arena.get_node("Projectiles").add_child(persistent)
	var start: Vector2 = persistent.position
	for frame in 370: await physics_frame
	check(far.health.current == 18, "Bullet can hit beyond its weapon's activation range")
	check(is_instance_valid(persistent) and persistent.position.distance_to(start) > 600, "Missed projectile survives beyond five seconds with unlimited travel")
	persistent.queue_free()
	gun.queue_free()
	await _clear_enemies()
	var caster := _enemy(arena, center + Vector2(190, 0), "healer")
	caster.data.equipment = load("res://resources/enemy_equipment/curse_staff.tres")
	caster.loadout.equip(caster.data.equipment, 0)
	caster.loadout_controller.configure(caster.loadout, caster)
	arena.player.health.initialize(100)
	arena.player.invulnerability = 0
	bullet_count = arena.get_node("Projectiles").get_child_count()
	caster._physics_process(1.0 / 60)
	check(caster.velocity.is_zero_approx() and arena.player.health.current == 91, "Caster behavior supports an instant damaging spell and stops within range")
	check(arena.get_node("Projectiles").get_child_count() == bullet_count, "Enemy spell also guarantees hit without a projectile")
