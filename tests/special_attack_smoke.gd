extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + text)

func make_enemy(arena: Node, offset: Vector2) -> Node2D:
	var unit: Node2D = load("res://scenes/actors/enemy.tscn").instantiate()
	unit.data = load("res://resources/enemies/melee.tres")
	unit.player = arena.player
	unit.position = arena.player.position + offset
	arena.get_node("Enemies").add_child(unit)
	unit.set_physics_process(false)
	unit.health.initialize(100)
	return unit

func _run() -> void:
	var state := root.get_node("RunState")
	state.new_run()
	state.start_with("pistol", "seed")
	state.current_cell_id = "crossing"
	change_scene_to_file("res://scenes/run/arena.tscn")
	await process_frame
	await process_frame
	var arena := current_scene
	arena.director.stop()
	arena.player.set_physics_process(false)
	for item in arena.player.inventory.equipped: item.set_physics_process(false)
	var first := make_enemy(arena, Vector2(100, 0))
	var second := make_enemy(arena, Vector2(120, 30))
	var data := ContentCatalog.weapon("pistol").duplicate() as WeaponData
	data.damage = 10
	data.explosion_radius = 60
	data.burn_damage = 2
	data.burn_duration = 2.5
	arena.player.apply_weapon_hit(first, data)
	check(first.health.current == 90 and second.health.current == 90, "Explosion hits nearby targets once")
	check(is_instance_valid(first.burn) and is_instance_valid(second.burn), "Burn is applied to both explosion targets")
	for i in 130: await physics_frame
	check(first.health.current == 86 and second.health.current == 86, "Burn inflicts damage once per second")
	data.explosion_radius = 0
	data.burn_damage = 0
	data.burn_duration = 0
	var bullet: Node2D = load("res://scenes/combat/projectile.tscn").instantiate()
	bullet.attacker = arena.player
	bullet.weapon = data
	bullet.pierce_remaining = 1
	arena.get_node("Projectiles").add_child(bullet)
	bullet.set_physics_process(false)
	bullet._on_body_entered(first)
	check(not bullet.consumed and bullet.pierce_remaining == 0, "A piercing projectile continues after its first hit")
	bullet._on_body_entered(second)
	check(bullet.consumed and first.health.current == 76 and second.health.current == 76, "Piercing projectile hits distinct targets and stops after its last hit")
	var bounce: Node2D = load("res://scenes/combat/projectile.tscn").instantiate()
	bounce.attacker = arena.player
	bounce.weapon = data
	bounce.position = first.position
	bounce.bounce_remaining = 1
	arena.get_node("Projectiles").add_child(bounce)
	bounce.set_physics_process(false)
	bounce._on_body_entered(first)
	check(not bounce.consumed and bounce.bounce_remaining == 0 and bounce.direction.y > 0.5, "Bounce changes direction once at impact toward the next enemy")
	var before_health: float = second.health.current
	first.apply_charm(0.3)
	check(first.charmed and not CombatTargeting.living_enemies(self).has(first), "Charmed enemy becomes friendly and is excluded from enemy targeting")
	second.position = first.position + Vector2(15, 0)
	first.loadout_controller.tick(1.0 / 60.0)
	check(second.health.current < before_health, "Charmed enemy attacks a hostile enemy instead of the player")
	for i in 25: await physics_frame
	check(not first.charmed and CombatTargeting.living_enemies(self).has(first), "Charm expires and restores the enemy faction")
	print("SPECIAL ATTACKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
