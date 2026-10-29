extends SceneTree

var failures := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func enemy(arena: Node, offset: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = arena.player
	unit.position = arena.player.position + offset
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.entered_arena = true
	return unit

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("needle", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	var weapon: Node2D = arena.player.inventory.equipped[0]
	weapon.set_physics_process(false)
	var front := enemy(arena, Vector2(55, 0))
	var side := enemy(arena, Vector2(48, 40))
	await physics_frame
	weapon._try_direct_attack()
	check(weapon.melee.active and front.health.current == 32, "Thrust begins with windup rather than immediate damage")
	var initial_strike: float = weapon.melee.strike_time
	paused = true
	for i in 10: await physics_frame
	check(front.health.current == 32 and weapon.melee.elapsed == 0.0, "Pausing freezes the attack trajectory")
	paused = false
	for i in 70: await physics_frame
	check(not is_instance_valid(front) and side.health.current == 32, "Thrust hits its straight path (one-shotting 32 HP melee enemy) and excludes an enemy to the side")
	check(not weapon.melee.active, "Thrust returns to rest")
	state.add_primary_stat("attack_speed", 100)
	weapon.melee.begin(weapon.data, Vector2.RIGHT, 68, 0.50)
	check(weapon.melee.strike_time < initial_strike, "Attack speed shortens the strike animation")
	var fast_strike: float = weapon.melee.strike_time
	weapon.melee.begin(weapon.data, Vector2.RIGHT, 136, 0.50)
	check(weapon.melee.strike_time > fast_strike, "Additional range lengthens the strike animation")
	weapon.melee.active = false
	state.primary.reset()
	if is_instance_valid(front): front.queue_free()
	side.queue_free()
	await physics_frame
	# Verify needle guaranteed hit even when locked target dodges laterally during windup
	var dodging := enemy(arena, Vector2(55, 0))
	await physics_frame
	weapon._try_direct_attack()
	dodging.position = arena.player.position + Vector2(10, 62)
	for i in 70: await physics_frame
	check(not is_instance_valid(dodging), "Needle guarantees hitting its locked target even when target moves laterally")
	await physics_frame
	state.equip_weapon("cleaver", 0)
	var sweep: Node2D = load("res://scenes/combat/weapon.tscn").instantiate()
	sweep.data = ContentCatalog.weapon("cleaver")
	sweep.holder = arena.player
	arena.player.add_child(sweep)
	sweep.set_physics_process(false)
	var first := enemy(arena, Vector2(65, 0))
	var second := enemy(arena, Vector2(45, 46))
	var close_inner := enemy(arena, Vector2(18, 5))
	var behind := enemy(arena, Vector2(-65, 0))
	await physics_frame
	sweep._try_direct_attack()
	for i in 70: await physics_frame
	check(first.health.current == 11 and second.health.current == 11 and close_inner.health.current == 11, "Sweep hits enemies across the full fan sector including close range once")
	check(behind.health.current == 32, "Sweep does not hit enemies behind the arc")
	check(not sweep.melee.active, "Sweep returns to rest")
	check(first.health.current == 11 and second.health.current == 11, "One attack damages each target only once")
	print("MELEE TRAJECTORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
