class_name EncounterDirector
extends Node

signal progress_changed(index: int, total: int, text: String)
signal group_started(index: int)
signal group_generation_completed(index: int)
signal group_cleared(index: int)
signal boss_entered(unit: EnemyActor)
signal enemy_spawned(unit: EnemyActor)
signal enemy_defeated(unit: EnemyActor)
signal enemy_despawned(unit: EnemyActor)
signal edge_warning_triggered(edge: int, point: Vector2, span: float, duration: float, group_index: int)
signal encounter_completed
signal configuration_error(message: String)
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")
const EDGE_WARNING_DURATION: float = 1.0
const BATCH_EDGE_SPAN: float = 120.0
const DEFAULT_MAX_ACTIVE_ENEMIES: int = 80
@export var encounter: EncounterData
@export var max_active_enemies: int = DEFAULT_MAX_ACTIVE_ENEMIES
var player: PlayerActor
var enemy_root: Node2D
var visible_bounds := Rect2(0, 0, 960, 540)
var arena_bounds := Rect2(25, 77, 910, 410)
var active: bool = false
var started_groups: int = 0
var generated_groups: int = 0
var generating_groups: int = 0
var alive_count: int = 0
var alive_regular_count: int = 0
var total_spawned: int = 0
var despawned_count: int = 0
var warnings_emitted: int = 0
var waiting_for_boss: bool = false
var boss_has_spawned: bool = false
var boss_alive: bool = false
var elapsed: bool = false
var duration_timer: Timer
var warning_timer: Timer
var rng := RandomNumberGenerator.new()
var group_alive: Dictionary = {}
var group_generated: Dictionary = {}
var cleared_groups: Dictionary = {}
var pending_batch_plan: Dictionary = {}
var group_batch_plans: Dictionary = {}
var active_regular_enemies: Array[EnemyActor] = []
@onready var timer: Timer = $Timer

func _ready() -> void:
	rng.randomize()
	timer.timeout.connect(_launch_next)
	duration_timer = Timer.new()
	duration_timer.one_shot = true
	duration_timer.timeout.connect(_time_expired)
	add_child(duration_timer)
	warning_timer = Timer.new()
	warning_timer.one_shot = true
	warning_timer.timeout.connect(_emit_pending_edge_warning)
	add_child(warning_timer)

func begin() -> void:
	var errors := encounter.validation_errors()
	if not errors.is_empty():
		configuration_error.emit("\n".join(errors))
		return
	elapsed = false
	started_groups = 0
	generated_groups = 0
	generating_groups = 0
	alive_count = 0
	alive_regular_count = 0
	total_spawned = 0
	despawned_count = 0
	warnings_emitted = 0
	waiting_for_boss = false
	boss_has_spawned = false
	boss_alive = false
	group_alive.clear()
	group_generated.clear()
	cleared_groups.clear()
	pending_batch_plan.clear()
	group_batch_plans.clear()
	active_regular_enemies.clear()
	active = true
	_update_caption("敌群即将抵达")
	_schedule_next_group(maxf(0.001, encounter.preparation_time))

func stop() -> void:
	active = false
	timer.stop()
	warning_timer.stop()
	duration_timer.stop()
	pending_batch_plan.clear()
	for child in get_children():
		if child is GroupSpawner:
			child.process_mode = Node.PROCESS_MODE_DISABLED
			child.queue_free()

func _schedule_next_group(delay: float) -> void:
	if not active or elapsed or encounter == null or encounter.schedules.is_empty():
		return
	var next_index := started_groups + 1
	var rule := encounter.schedules[started_groups % encounter.schedules.size()]
	var plan := _create_batch_spawn_plan(rule.location, next_index)
	pending_batch_plan = plan
	group_batch_plans[next_index] = plan
	var wait_time := maxf(0.001, delay)
	if wait_time > EDGE_WARNING_DURATION:
		warning_timer.start(wait_time - EDGE_WARNING_DURATION)
	else:
		warning_timer.stop()
		_emit_pending_edge_warning()
	timer.start(wait_time)

func _emit_pending_edge_warning() -> void:
	if not active or pending_batch_plan.is_empty() or bool(pending_batch_plan.get("emitted", false)):
		return
	pending_batch_plan["emitted"] = true
	warnings_emitted += 1
	edge_warning_triggered.emit(
		int(pending_batch_plan["edge"]),
		Vector2(pending_batch_plan["warning_point"]),
		float(pending_batch_plan["span"]),
		EDGE_WARNING_DURATION,
		int(pending_batch_plan["group_index"])
	)

func _launch_next() -> void:
	if not active:
		return
	if started_groups == 0 and duration_timer.is_stopped() and not elapsed:
		duration_timer.start(encounter.duration)
	if _at_boss_threshold():
		waiting_for_boss = true
		_update_caption("清空场上敌人，迎接 BOSS")
		_try_progress()
		return
	if elapsed: return
	if not pending_batch_plan.is_empty() and not bool(pending_batch_plan.get("emitted", false)):
		_emit_pending_edge_warning()
	var rule := encounter.schedules[started_groups % encounter.schedules.size()]
	started_groups += 1
	generating_groups += 1
	var index := started_groups
	if not group_batch_plans.has(index):
		group_batch_plans[index] = _create_batch_spawn_plan(rule.location, index)
	pending_batch_plan.clear()
	group_alive[index] = 0
	group_generated[index] = false
	var spawner := GroupSpawner.new()
	spawner.schedule = rule
	spawner.spawn_requested.connect(_spawn_regular.bind(index))
	spawner.generation_finished.connect(_group_finished.bind(index))
	add_child(spawner)
	group_started.emit(index)
	_update_caption("敌群进场")
	if _at_boss_threshold():
		waiting_for_boss = true
		_update_caption("前 %d 组进场后清场，BOSS 即将出现" % started_groups)
	else:
		_schedule_next_group(encounter.group_interval)

func _at_boss_threshold() -> bool:
	return encounter.kind == EncounterData.Kind.BOSS and not boss_has_spawned and started_groups >= encounter.boss_after_group_count

func _group_finished(index: int) -> void:
	generated_groups += 1
	generating_groups -= 1
	group_generated[index] = true
	group_generation_completed.emit(index)
	_check_group_cleared(index)
	_try_progress.call_deferred()

func _spawn_regular(definition: EnemyData, location: SpawnLocationData, group_index: int) -> void:
	if not active:
		return
	_enforce_active_enemy_cap()
	alive_regular_count += 1
	group_alive[group_index] = int(group_alive.get(group_index, 0)) + 1
	var unit := _spawn_unit(definition, location, group_index)
	active_regular_enemies.append(unit)

func _enforce_active_enemy_cap() -> void:
	var cap := maxi(1, max_active_enemies)
	for index in range(active_regular_enemies.size() - 1, -1, -1):
		if not is_instance_valid(active_regular_enemies[index]) or active_regular_enemies[index].is_queued_for_deletion():
			active_regular_enemies.remove_at(index)
	while alive_regular_count >= cap and not active_regular_enemies.is_empty():
		var victim: EnemyActor = null
		for candidate in active_regular_enemies:
			if is_instance_valid(candidate) and candidate.data != null and candidate.data.category == EnemyData.Category.NORMAL:
				victim = candidate
				break
		if victim == null:
			victim = active_regular_enemies[0]
		_despawn_regular_enemy(victim)

func _despawn_regular_enemy(victim: EnemyActor) -> void:
	if not is_instance_valid(victim):
		return
	active_regular_enemies.erase(victim)
	victim.set_meta("despawned", true)
	if victim.defeated.is_connected(_on_defeated):
		victim.defeated.disconnect(_on_defeated)
	victim.remove_from_group("enemies")
	alive_count = maxi(0, alive_count - 1)
	alive_regular_count = maxi(0, alive_regular_count - 1)
	despawned_count += 1
	if victim.has_meta("group_index"):
		var index: int = victim.get_meta("group_index")
		group_alive[index] = maxi(0, int(group_alive.get(index, 0)) - 1)
		_check_group_cleared(index)
	enemy_despawned.emit(victim)
	victim.queue_free()

func _spawn_unit(definition: EnemyData, location: SpawnLocationData, group_index: int = 0) -> EnemyActor:
	var unit: EnemyActor = ENEMY_SCENE.instantiate()
	unit.data = definition
	unit.player = player
	var batch_plan: Dictionary = group_batch_plans.get(group_index, {})
	unit.position = random_spawn_position(location, definition, batch_plan)
	if batch_plan.has("edge"):
		unit.set_meta("spawn_edge", int(batch_plan["edge"]))
	if group_index > 0: unit.set_meta("group_index", group_index)
	unit.defeated.connect(_on_defeated)
	alive_count += 1
	total_spawned += 1
	enemy_root.add_child(unit)
	enemy_spawned.emit(unit)
	return unit

func _create_batch_spawn_plan(location: SpawnLocationData = null, group_index: int = 0) -> Dictionary:
	if location == null:
		location = SpawnLocationData.new()
	if not location.fixed_positions.is_empty():
		var fixed_pt: Vector2 = location.fixed_positions[rng.randi_range(0, location.fixed_positions.size() - 1)]
		var fixed_edge: int = SpawnLocationData.Edge.TOP
		if fixed_pt.x < visible_bounds.position.x:
			fixed_edge = SpawnLocationData.Edge.LEFT
		elif fixed_pt.x > visible_bounds.end.x:
			fixed_edge = SpawnLocationData.Edge.RIGHT
		elif fixed_pt.y > visible_bounds.end.y:
			fixed_edge = SpawnLocationData.Edge.BOTTOM
		var warn_pt := _edge_warning_point(fixed_edge, fixed_pt.y if fixed_edge in [SpawnLocationData.Edge.LEFT, SpawnLocationData.Edge.RIGHT] else fixed_pt.x)
		return {
			"group_index": group_index,
			"edge": fixed_edge,
			"center_coord": fixed_pt.y if fixed_edge in [SpawnLocationData.Edge.LEFT, SpawnLocationData.Edge.RIGHT] else fixed_pt.x,
			"span": BATCH_EDGE_SPAN,
			"warning_point": warn_pt,
			"fixed_point": fixed_pt,
			"emitted": false
		}
	var edges := location.edges if not location.edges.is_empty() else PackedInt32Array([0, 1, 2, 3])
	var edge: int = edges[rng.randi_range(0, edges.size() - 1)]
	var half_span := BATCH_EDGE_SPAN * 0.5
	var center_coord: float = 0.0
	if edge in [SpawnLocationData.Edge.LEFT, SpawnLocationData.Edge.RIGHT]:
		var min_y := arena_bounds.position.y + half_span + 8.0
		var max_y := arena_bounds.end.y - half_span - 8.0
		center_coord = rng.randf_range(minf(min_y, max_y), maxf(min_y, max_y))
	else:
		var min_x := arena_bounds.position.x + half_span + 16.0
		var max_x := arena_bounds.end.x - half_span - 16.0
		center_coord = rng.randf_range(minf(min_x, max_x), maxf(min_x, max_x))
	return {
		"group_index": group_index,
		"edge": edge,
		"center_coord": center_coord,
		"span": BATCH_EDGE_SPAN,
		"warning_point": _edge_warning_point(edge, center_coord),
		"emitted": false
	}

func _edge_warning_point(edge: int, coord: float) -> Vector2:
	var inset := 14.0
	var half_span := BATCH_EDGE_SPAN * 0.5
	match edge:
		SpawnLocationData.Edge.LEFT:
			return Vector2(arena_bounds.position.x + inset, clampf(coord, arena_bounds.position.y + half_span, arena_bounds.end.y - half_span))
		SpawnLocationData.Edge.RIGHT:
			return Vector2(arena_bounds.end.x - inset, clampf(coord, arena_bounds.position.y + half_span, arena_bounds.end.y - half_span))
		SpawnLocationData.Edge.TOP:
			return Vector2(clampf(coord, arena_bounds.position.x + half_span, arena_bounds.end.x - half_span), arena_bounds.position.y + inset)
		_:
			return Vector2(clampf(coord, arena_bounds.position.x + half_span, arena_bounds.end.x - half_span), arena_bounds.end.y - inset)

func random_spawn_position(location: SpawnLocationData = null, definition: EnemyData = null, batch_plan: Dictionary = {}) -> Vector2:
	if location == null:
		location = SpawnLocationData.new()
	if not location.fixed_positions.is_empty():
		var choices := PackedVector2Array()
		var required_margin: float = maxf(location.margin, definition.required_spawn_margin() if definition != null else 24.0)
		for point in location.fixed_positions:
			if not visible_bounds.grow(required_margin).has_point(point): choices.append(point)
		if not choices.is_empty(): return choices[rng.randi_range(0, choices.size() - 1)]
	var margin: float = location.margin
	if definition != null:
		margin = maxf(margin, definition.required_spawn_margin())
	margin += 1.0
	var edges := location.edges if not location.edges.is_empty() else PackedInt32Array([0, 1, 2, 3])
	var edge: int = int(batch_plan["edge"]) if batch_plan.has("edge") else edges[rng.randi_range(0, edges.size() - 1)]
	var has_batch_region := batch_plan.has("center_coord") and batch_plan.has("span")
	var half_span: float = float(batch_plan.get("span", BATCH_EDGE_SPAN)) * 0.5
	var center_coord: float = float(batch_plan.get("center_coord", 0.0))
	match edge:
		SpawnLocationData.Edge.LEFT:
			var y_min := clampf(center_coord - half_span, visible_bounds.position.y + 40, visible_bounds.end.y - 40) if has_batch_region else visible_bounds.position.y + 40
			var y_max := clampf(center_coord + half_span, visible_bounds.position.y + 40, visible_bounds.end.y - 40) if has_batch_region else visible_bounds.end.y - 40
			return Vector2(visible_bounds.position.x - margin, rng.randf_range(y_min, y_max))
		SpawnLocationData.Edge.RIGHT:
			var y_min := clampf(center_coord - half_span, visible_bounds.position.y + 40, visible_bounds.end.y - 40) if has_batch_region else visible_bounds.position.y + 40
			var y_max := clampf(center_coord + half_span, visible_bounds.position.y + 40, visible_bounds.end.y - 40) if has_batch_region else visible_bounds.end.y - 40
			return Vector2(visible_bounds.end.x + margin, rng.randf_range(y_min, y_max))
		SpawnLocationData.Edge.TOP:
			var x_min := clampf(center_coord - half_span, visible_bounds.position.x + 40, visible_bounds.end.x - 40) if has_batch_region else visible_bounds.position.x + 40
			var x_max := clampf(center_coord + half_span, visible_bounds.position.x + 40, visible_bounds.end.x - 40) if has_batch_region else visible_bounds.end.x - 40
			return Vector2(rng.randf_range(x_min, x_max), visible_bounds.position.y - margin)
		_:
			var x_min := clampf(center_coord - half_span, visible_bounds.position.x + 40, visible_bounds.end.x - 40) if has_batch_region else visible_bounds.position.x + 40
			var x_max := clampf(center_coord + half_span, visible_bounds.position.x + 40, visible_bounds.end.x - 40) if has_batch_region else visible_bounds.end.x - 40
			return Vector2(rng.randf_range(x_min, x_max), visible_bounds.end.y + margin)

func _on_defeated(unit: EnemyActor) -> void:
	active_regular_enemies.erase(unit)
	alive_count = maxi(0, alive_count - 1)
	if unit.data.category == EnemyData.Category.BOSS:
		boss_alive = false
	else:
		alive_regular_count = maxi(0, alive_regular_count - 1)
	enemy_defeated.emit(unit)
	if unit.has_meta("group_index"):
		var index: int = unit.get_meta("group_index")
		group_alive[index] = maxi(0, int(group_alive.get(index, 0)) - 1)
		_check_group_cleared(index)
	_try_progress.call_deferred()

func _check_group_cleared(index: int) -> void:
	if active and bool(group_generated.get(index, false)) and int(group_alive.get(index, 0)) == 0 and not cleared_groups.has(index):
		cleared_groups[index] = true
		group_cleared.emit(index)

func _try_progress() -> void:
	if not active:
		return
	if waiting_for_boss:
		if generating_groups == 0 and alive_regular_count == 0:
			waiting_for_boss = false
			boss_has_spawned = true
			boss_alive = true
			get_tree().call_group("pickups", "collect")
			var boss_plan := _create_batch_spawn_plan(encounter.boss_location, 0)
			warnings_emitted += 1
			edge_warning_triggered.emit(
				int(boss_plan["edge"]),
				Vector2(boss_plan["warning_point"]),
				float(boss_plan["span"]),
				EDGE_WARNING_DURATION,
				0
			)
			var unit := _spawn_unit(encounter.boss, encounter.boss_location)
			boss_entered.emit(unit)
			_update_caption("BOSS 已进场")
			if not elapsed:
				_schedule_next_group(encounter.group_interval)
		return

func _time_expired() -> void:
	if not active: return
	elapsed = true
	timer.stop()
	warning_timer.stop()
	pending_batch_plan.clear()
	for child in get_children():
		if child is GroupSpawner:
			child.process_mode = Node.PROCESS_MODE_DISABLED
			child.queue_free()
	_complete()

func _complete() -> void:
	active = false
	timer.stop()
	warning_timer.stop()
	duration_timer.stop()
	pending_batch_plan.clear()
	active_regular_enemies.clear()
	get_tree().call_group("pickups", "collect")
	for unit in enemy_root.get_children(): unit.queue_free()
	encounter_completed.emit()

func _update_caption(text: String) -> void:
	progress_changed.emit(started_groups, 0, text)
