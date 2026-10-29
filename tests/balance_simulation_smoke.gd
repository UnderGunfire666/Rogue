extends SceneTree
## Automated combat & economy balance simulation across all 6 player weapons and map levels.

var checks: int = 0
var failures: int = 0
var state: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _scene(path: String) -> Node:
	paused = false
	change_scene_to_file(path)
	await process_frame
	await process_frame
	return current_scene

func _run() -> void:
	state = root.get_node("RunState")
	print("=== 1. MELEE BLIND-SPOT & TRAJECTORY COVERAGE VERIFICATION ===")
	await _verify_melee_zero_blind_spot()
	print("=== 2. WEAPON COMBAT & ECONOMY BALANCE SIMULATION ===")
	await _simulate_weapons_balance()
	print("BALANCE SIMULATION SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _spawn_dummy(arena: Node, offset: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = arena.player
	unit.position = arena.player.global_position + offset
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.entered_arena = true
	return unit

func _verify_melee_zero_blind_spot() -> void:
	state.new_run()
	state.start_with("cleaver", "seed")
	state.current_cell_id = "crossing"
	var arena := await _scene("res://scenes/run/arena.tscn")
	arena.director.stop()
	arena.player.set_physics_process(false)
	var sweep_weapon: Node2D = arena.player.inventory.equipped[0]
	sweep_weapon.set_physics_process(false)
	# Place enemies across the entire radial distance [0, 8, 18, 30, 44, 58, 70] and angles [-45, -20, 0, 20, 45]
	var targets: Array[Node2D] = []
	for r: float in [0.0, 8.0, 18.0, 30.0, 44.0, 58.0, 70.0]:
		for deg: float in [-40.0, 0.0, 40.0]:
			if r == 0.0 and deg != 0.0:
				continue
			var offset := Vector2.RIGHT.rotated(deg_to_rad(deg)) * r
			targets.append(_spawn_dummy(arena, offset))
	await physics_frame
	var interval: float = state.weapon_attack_interval(sweep_weapon.data)
	sweep_weapon.melee.begin(sweep_weapon.data, Vector2.RIGHT, state.effective_weapon_range(sweep_weapon.data), interval)
	for i in 65:
		await physics_frame
	var hit_count := 0
	for unit in targets:
		if not is_instance_valid(unit) or unit.health.current < 32.0:
			hit_count += 1
		if is_instance_valid(unit):
			unit.queue_free()
	check(hit_count == targets.size(), "Cleaver sweep fan hits 100%% of close/mid/far targets (%d/%d) with zero inner blind spot" % [hit_count, targets.size()])
	await physics_frame
	# Verify needle thrust hits point-blank (r=0, 6, 15, 30, 50, 64) regardless of weapon slot offset
	state.equip_weapon("needle", 0)
	var thrust_weapon: Node2D = load("res://scenes/combat/weapon.tscn").instantiate()
	thrust_weapon.data = ContentCatalog.weapon("needle")
	thrust_weapon.holder = arena.player
	thrust_weapon.position = Vector2(-19, 5)
	arena.player.add_child(thrust_weapon)
	thrust_weapon.set_physics_process(false)
	var line_targets: Array[Node2D] = []
	for r: float in [0.0, 6.0, 15.0, 30.0, 50.0, 64.0]:
		line_targets.append(_spawn_dummy(arena, Vector2(r, 0.0)))
	await physics_frame
	thrust_weapon._try_direct_attack()
	for i in 55:
		await physics_frame
	var line_kills := 0
	for unit in line_targets:
		if not is_instance_valid(unit) or not unit.health.is_alive():
			line_kills += 1
		if is_instance_valid(unit):
			unit.queue_free()
	thrust_weapon.queue_free()
	check(line_kills == line_targets.size(), "Needle thrust hits and one-shots 100%% of point-blank to max-range enemies (%d/%d)" % [line_kills, line_targets.size()])

func _simulate_weapons_balance() -> void:
	var weapon_ids := ["needle", "cleaver", "pistol", "scattergun", "arcane_staff", "storm_tome"]
	for wid in weapon_ids:
		var w := ContentCatalog.weapon(wid)
		var single_dps := w.damage / w.attack_interval
		var multi_count := w.projectile_count if w.kind == WeaponData.Kind.RANGED else w.target_count
		var max_dps := (w.damage * multi_count) / w.attack_interval
		print("Weapon [%s (%s)]: BaseDmg=%.0f, Interval=%.2fs, Range=%.0f, SingleTargetDPS=%.1f, MultiTargetDPS=%.1f" % [
			w.display_name, wid, w.damage, w.attack_interval, w.attack_range, single_dps, max_dps
		])
		check(is_equal_approx(max_dps, 70.0), "Weapon %s theoretical multi-target DPS reaches 70.0 (got %.1f)" % [wid, max_dps])
	var pairs := [
		["needle", "cleaver", "Melee"],
		["pistol", "scattergun", "Ranged"],
		["arcane_staff", "storm_tome", "Spell"]
	]
	for pair in pairs:
		var single_w := ContentCatalog.weapon(pair[0])
		var multi_w := ContentCatalog.weapon(pair[1])
		var single_dps := single_w.damage / single_w.attack_interval
		var multi_single_dps := multi_w.damage / multi_w.attack_interval
		check(multi_w.attack_interval > single_w.attack_interval and multi_single_dps < single_dps,
			"%s multi-target weapon (%s) has slower attack speed (%.2fs > %.2fs) and lower single-target DPS (%.1f < %.1f) than single-target (%s)" % [
				pair[2], pair[1], multi_w.attack_interval, single_w.attack_interval, multi_single_dps, single_dps, pair[0]
			])
	# Simulate shortened 10s combat encounters on Level 1 in Dream Expedition for each weapon with simple kiting AI
	for wid in weapon_ids:
		state.new_run()
		state.rng.seed = 202610
		state.start_with(wid, "seed")
		state.begin_expedition()
		state.enter_expedition_map("normal")
		var enc: EncounterData = load("res://resources/encounters/training.tres").duplicate(true)
		enc.preparation_time = 0.2
		enc.duration = 6.5
		enc.group_interval = 3.0
		state.active_encounter = enc
		var arena := await _scene("res://scenes/run/arena.tscn")
		arena.player.controls.set_physics_process(false)
		var stats := {"kills": 0}
		arena.director.enemy_defeated.connect(func(_u: Node2D): stats["kills"] += 1)
		for frame in 450:
			await physics_frame
			if not is_instance_valid(arena) or arena.encounter_won or arena.defeated:
				break
			# Simple AI: move toward nearest enemy up to comfortable weapon distance, kite away if too close
			var p: Node2D = arena.player
			var enemies := CombatTargeting.living_enemies(self)
			var nearest := CombatTargeting.nearest(p.global_position, 2000.0, enemies)
			if nearest != null:
				var dist := p.global_position.distance_to(nearest.global_position)
				var w_data := ContentCatalog.weapon(wid)
				var desired := maxf(38.0, w_data.attack_range * 0.72)
				var dir := p.global_position.direction_to(nearest.global_position)
				if dist > desired + 12.0:
					p.velocity = dir * state.movement_speed()
				elif dist < desired - 12.0:
					p.velocity = -dir * state.movement_speed()
				else:
					p.velocity = dir.orthogonal() * state.movement_speed() * 0.6
				p.move_and_slide()
				p.position = p.position.clamp(p.movement_bounds.position, p.movement_bounds.end)
		while state.pending_upgrades > 0:
			arena._upgrade_chosen(state.upgrade_offers[0].id)
		var kills: int = stats["kills"]
		print("Sim [%s]: Won=%s, Kills=%d, EndHP=%.0f/100, Gold=%d, Lv=%d (XP=%d)" % [
			wid, str(arena.encounter_won), kills, arena.player.health.current, state.gold, state.level, state.experience
		])
		check(arena.encounter_won and arena.player.health.current > 0.0 and kills >= 3, "Weapon %s clears simulated expedition wave and kills enemies (%d kills)" % [wid, kills])
