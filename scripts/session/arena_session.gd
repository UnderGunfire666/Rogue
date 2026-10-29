extends Node2D

const LOOT := preload("res://scenes/items/loot_pickup.tscn")
const TREE := preload("res://scripts/world/environment_tree.gd")
@onready var player: PlayerActor = $Player
@onready var director: EncounterDirector = $EncounterDirector
@onready var effects: Node2D = $Effects
@onready var hud: CanvasLayer = $HUD
@onready var overlay: CanvasLayer = $Overlay
var entry: MapCellData
var encounter_won: bool = false
var defeated: bool = false
var crates_by_group: Dictionary = {}

func _enter_tree() -> void:
	if RunState.active_encounter != null:
		return
	var cell := RunState.current_map().find_cell(RunState.current_cell_id)
	if cell != null and cell.is_battle() and RunState.begin_cell_encounter():
		return
	RunState.new_run()
	RunState.start_with("needle", "seed")
	RunState.current_cell_id = "crossing"
	RunState.begin_cell_encounter()

func _ready() -> void:
	add_to_group("arena_controller")
	var scale := RunState.combat_rules().arena_size_multiplier
	var base := Rect2(25, 77, 910, 410)
	var center := base.get_center()
	player.movement_bounds = Rect2(center - base.size * scale * 0.5, base.size * scale)
	var view_scale := maxf(1.0, scale)
	$Camera2D.zoom = Vector2.ONE / view_scale
	var view_center := Vector2(480, 270)
	director.visible_bounds = Rect2(view_center - Vector2(960, 540) * view_scale * 0.5, Vector2(960, 540) * view_scale)
	director.arena_bounds = player.movement_bounds
	$Projectiles.add_to_group("projectile_root")
	entry = RunState.current_map().find_cell(RunState.current_cell_id)
	director.player = player
	director.enemy_root = $Enemies
	director.encounter = RunState.active_encounter
	director.progress_changed.connect(hud.update_group_progress)
	director.enemy_spawned.connect(_enemy_spawned)
	director.enemy_defeated.connect(_enemy_defeated)
	director.edge_warning_triggered.connect(effects.present_edge_warning)
	director.group_cleared.connect(func(_index: int): RunState.finish_wave())
	director.encounter_completed.connect(_encounter_completed)
	director.configuration_error.connect(func(message: String):
		get_tree().paused = true
		overlay.show_configuration_error(message))
	player.combat_effect.connect(effects.present)
	player.died.connect(_player_died)
	hud.player = player
	hud.director = director
	overlay.resume_requested.connect(_resume)
	overlay.upgrade_chosen.connect(_upgrade_chosen)
	overlay.victory_confirmed.connect(_continue_route)
	overlay.leave_requested.connect(func(): RunState.go_to("res://scenes/app/title_screen.tscn"))
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	RunState.reset_combat_accumulators()
	_spawn_trees()
	director.begin()

func _spawn_trees() -> void:
	for index in RunState.combat_rules().environment_tree_count:
		var tree := TREE.new()
		var bounds: Rect2 = player.movement_bounds.grow(-30)
		tree.position = Vector2(RunState.rng.randf_range(bounds.position.x, bounds.end.x), RunState.rng.randf_range(bounds.position.y, bounds.end.y))
		if tree.position.distance_to(player.position) < 70: tree.position.x = bounds.position.x if tree.position.x > bounds.get_center().x else bounds.end.x
		tree.defeated.connect(_tree_defeated)
		$Enemies.add_child(tree)
	RunState.stats_changed.emit()

func _tree_defeated(tree: EnvironmentTree) -> void:
	var pickup: LootPickup = LOOT.instantiate()
	pickup.position = tree.global_position
	$Pickups.add_child(pickup)

func _enemy_spawned(unit: EnemyActor) -> void:
	unit.arena_bounds = player.movement_bounds.grow(-5)
	unit.combat_effect.connect(effects.present)

func _enemy_defeated(unit: EnemyActor) -> void:
	if unit.get_meta("despawned", false):
		return
	RunState.trigger_character_event(CharacterEventEffect.Trigger.ENEMY_KILLED)
	if unit.data.category == EnemyData.Category.BOSS:
		RunState.trigger_character_event(CharacterEventEffect.Trigger.BOSS_KILLED)
		var boss_crate: LootPickup = LOOT.instantiate()
		boss_crate.experience_value = 0
		boss_crate.gold_value = 0
		boss_crate.is_boss_crate = true
		boss_crate.position = unit.global_position
		$Pickups.add_child(boss_crate)
	var pickup: LootPickup = LOOT.instantiate()
	var reward_scale: float = RunState.enemy_reward_multiplier()
	var xp_reward := roundi(unit.data.experience_reward * reward_scale)
	pickup.experience_value = xp_reward
	var expected_materials: float = maxf(0.0, unit.data.gold_reward * reward_scale * RunState.combat_rules().enemy_material_multiplier)
	pickup.gold_value = floori(expected_materials)
	if expected_materials > pickup.gold_value and RunState.rng.randf() < expected_materials - pickup.gold_value:
		pickup.gold_value += 1
	var expected_fragments: float = maxf(0.0, unit.data.effective_fragment_reward() * reward_scale * RunState.combat_rules().enemy_material_multiplier)
	pickup.fragment_value = floori(expected_fragments)
	if expected_fragments > pickup.fragment_value and RunState.rng.randf() < expected_fragments - pickup.fragment_value:
		pickup.fragment_value += 1
	if RunState.expedition != null:
		RunState.record_combat_enemy_xp(xp_reward)
	pickup.position = unit.global_position
	$Pickups.add_child(pickup)
	var luck_factor := maxf(0.0, 1.0 + RunState.stat_value("luck") / 100.0)
	if RunState.rng.randf() < clampf(unit.data.consumable_drop_chance * luck_factor, 0.0, 1.0):
		var consumable: LootPickup = LOOT.instantiate()
		consumable.experience_value = 0
		consumable.gold_value = 0
		consumable.heal_value = 3
		consumable.position = unit.global_position + Vector2(12, 0)
		$Pickups.add_child(consumable)
	var group_index: int = unit.get_meta("group_index", 0)
	var crate_count := int(crates_by_group.get(group_index, 0))
	if RunState.rng.randf() < clampf(unit.data.relic_drop_chance * luck_factor / (1.0 + crate_count), 0.0, 1.0):
		var crate: LootPickup = LOOT.instantiate()
		crate.experience_value = 0
		crate.gold_value = 0
		crate.is_relic_crate = true
		crate.position = unit.global_position + Vector2(-12, 0)
		$Pickups.add_child(crate)
		crates_by_group[group_index] = crate_count + 1

func _upgrade_chosen(id: String) -> void:
	RunState.apply_upgrade(id)
	if RunState.pending_upgrades > 0:
		overlay.show_upgrades()
	elif encounter_won:
		_show_post_upgrade_screen()
	else:
		_resume()

func _show_post_upgrade_screen() -> void:
	if not RunState.pending_combat_loot.is_empty():
		overlay.show_combat_loot(director.encounter.kind == EncounterData.Kind.BOSS, director.boss_has_spawned and not director.boss_alive)
	else:
		overlay.show_victory(director.encounter.kind == EncounterData.Kind.BOSS, director.boss_has_spawned and not director.boss_alive)

func _encounter_completed() -> void:
	if defeated:
		return
	var count := get_tree().get_nodes_in_group("environment_trees").size()
	RunState.gain_loot(count * RunState.combat_rules().tree_xp_at_combat_end, count * RunState.combat_rules().tree_materials_at_combat_end)
	if RunState.expedition != null:
		RunState.settle_combat_economy(director.encounter.kind if director.encounter != null else 0)
	else:
		RunState.gold += 12
	RunState.finish_combat_events()
	if defeated: return
	encounter_won = true
	get_tree().paused = true
	player.skill.cancel_targeting()
	if RunState.pending_upgrades > 0:
		overlay.show_upgrades()
	else:
		_show_post_upgrade_screen()

func _player_died() -> void:
	defeated = true
	RunState.won_run = false
	get_tree().paused = true
	player.skill.cancel_targeting()
	overlay.show_defeat()

func toggle_pause() -> void:
	if encounter_won or defeated or overlay.mode == "upgrade":
		return
	if get_tree().paused:
		_resume()
	else:
		get_tree().paused = true
		overlay.show_pause()

func _resume() -> void:
	overlay.close()
	get_tree().paused = false

func _continue_route() -> void:
	RunState.health = player.health.current
	var from_event: bool = RunState.encounter_from_event
	var in_expedition: bool = RunState.expedition != null
	RunState.finish_encounter()
	if RunState.won_run:
		RunState.go_to("res://scenes/app/result_screen.tscn")
	elif from_event and not in_expedition:
		RunState.go_to("res://scenes/map/cell_resolution.tscn")
	else:
		RunState.go_to("res://scenes/ui/shop_screen.tscn")
