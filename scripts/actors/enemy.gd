class_name EnemyActor
extends CharacterBody2D

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")
signal defeated(unit: EnemyActor)
signal combat_effect(point: Vector2, radius: float, kind: String, text: String)
@export var data: EnemyData
var player: PlayerActor
var loadout := ActorLoadout.new(ItemDefinition.Recipient.ENEMY, 1, 1)
var healing_destination := Vector2.ZERO
var entered_arena: bool = false
var burn: BurnStatus
var charmed := false
var charm_timer: Timer
var normal_color: Color
var arena_bounds := Rect2(30, 80, 900, 405)
var skill_cooldown_timer: Timer
var skill_windup_remaining: float = 0.0
var skill_windup_total: float = 0.0
var skill_dash_remaining: float = 0.0
var skill_dash_direction := Vector2.RIGHT
var skill_dash_hit_done := false
var skill_target_point := Vector2.ZERO
var buff_move_speed_bonus: float = 0.0
var buff_attack_speed_bonus: float = 0.0
var buff_timer: Timer
@onready var health: HealthComponent = $Health
@onready var visual: ActorVisual = $Visual
@onready var think_timer: Timer = $ThinkTimer
@onready var health_bar: ProgressBar = $HealthBar
@onready var loadout_controller: CombatLoadoutController = $Loadout

func _ready() -> void:
	add_to_group("enemies")
	health.initialize(data.max_health * RunState.combat_rules().enemy_health_multiplier * RunState.enemy_stat_multiplier())
	visual.set_actor_texture(data.texture)
	loadout.equip(data.equipment, 0)
	if data.relic != null:
		loadout.add_relic(data.relic)
	loadout_controller.configure(loadout, self)
	loadout_controller.attack_performed.connect(func(point: Vector2, radius: float, kind: String):
		combat_effect.emit(point, radius, kind, ""))
	if data.category == EnemyData.Category.BOSS:
		visual.scale = Vector2(1.5, 1.5)
		$CollisionShape2D.scale = Vector2(1.8, 1.8)
		health_bar.position = Vector2(-32, -55)
		health_bar.size = Vector2(64, 5)
	elif data.category == EnemyData.Category.ELITE:
		visual.modulate = Color("#efc78c")
		visual.scale = Vector2(1.15, 1.15)
	normal_color = visual.modulate
	charm_timer = Timer.new()
	charm_timer.one_shot = true
	charm_timer.timeout.connect(func():
		charmed = false
		_refresh_tint())
	add_child(charm_timer)
	skill_cooldown_timer = Timer.new()
	skill_cooldown_timer.one_shot = true
	add_child(skill_cooldown_timer)
	buff_timer = Timer.new()
	buff_timer.one_shot = true
	buff_timer.timeout.connect(_clear_buff)
	add_child(buff_timer)
	health_bar.max_value = health.maximum
	health_bar.value = health.current
	health_bar.visible = data.category != EnemyData.Category.NORMAL
	health.changed.connect(func(current: float, _maximum: float):
		health_bar.value = current
		health_bar.visible = current < health.maximum or data.category != EnemyData.Category.NORMAL)
	health.damaged.connect(func(amount: float):
		visual.flash()
		combat_effect.emit(global_position + Vector2(0, -18), 0.0, "damage", str(int(ceil(amount)))))
	health.depleted.connect(_die)
	healing_destination = position
	think_timer.timeout.connect(_plan_healing_position)
	think_timer.start()
	_plan_healing_position()

func _refresh_tint() -> void:
	if charmed:
		visual.modulate = Color("#94e8c1")
	elif buff_move_speed_bonus > 0.0 or buff_attack_speed_bonus > 0.0:
		visual.modulate = Color(1.0, 0.68, 0.50)
	else:
		visual.modulate = normal_color

func apply_buff(move_bonus: float, attack_bonus: float, duration: float) -> void:
	if duration <= 0.0 or not health.is_alive():
		return
	buff_move_speed_bonus = maxf(buff_move_speed_bonus, move_bonus)
	buff_attack_speed_bonus = maxf(buff_attack_speed_bonus, attack_bonus)
	_refresh_tint()
	buff_timer.start(maxf(duration, buff_timer.time_left))

func _clear_buff() -> void:
	buff_move_speed_bonus = 0.0
	buff_attack_speed_bonus = 0.0
	_refresh_tint()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.health.is_alive() or not health.is_alive():
		return
	var distance := global_position.distance_to(player.global_position)
	var direction := global_position.direction_to(player.global_position)
	var speed := get_movement_speed()
	if charmed:
		var target := attack_target()
		if is_instance_valid(target):
			var offset := global_position.distance_to(target.global_position)
			velocity = global_position.direction_to(target.global_position) * minf(speed, maxf(0.0, offset - 20.0) / delta)
		else: velocity = Vector2.ZERO
		move_and_slide()
		global_position = global_position.clamp(arena_bounds.position, arena_bounds.end)
		visual.update_motion(velocity)
		loadout_controller.tick(delta * (1.0 + buff_attack_speed_bonus))
		return
	var is_retreating := false
	if not entered_arena:
		if arena_bounds.has_point(global_position):
			entered_arena = true
		else:
			var safe_bounds := arena_bounds.grow(-35)
			var entry_point := player.global_position.clamp(safe_bounds.position, safe_bounds.end)
			velocity = global_position.direction_to(entry_point) * speed
			move_and_slide()
			visual.update_motion(velocity)
			return
	if _tick_enemy_skill(delta):
		health.heal(loadout.regeneration() * delta)
		return
	match data.movement:
		EnemyData.Movement.FOLLOW:
			velocity = direction * minf(speed, maxf(0.0, distance - 20.0) / delta)
		EnemyData.Movement.KEEP_DISTANCE:
			var profile := data.equipment.first_attack(AttackProfileData.Kind.RANGED)
			var desired := profile.attack_range if profile != null else data.safety_distance
			var offset := distance - desired
			is_retreating = offset < 0.0
			velocity = direction * signf(offset) * minf(speed, absf(offset) / delta)
		EnemyData.Movement.CASTER:
			is_retreating = distance < data.safety_distance
			if is_retreating:
				velocity = -direction * minf(speed, (data.safety_distance - distance) / delta)
			elif data.equipment.healing_spell() != null:
				velocity = global_position.direction_to(healing_destination) * minf(speed, global_position.distance_to(healing_destination) / delta)
			else:
				var spell := data.equipment.first_attack(AttackProfileData.Kind.SPELL)
				var reach := spell.attack_range if spell != null else data.safety_distance
				velocity = direction * minf(speed, maxf(0.0, distance - reach) / delta)
	move_and_slide()
	global_position = global_position.clamp(arena_bounds.position, arena_bounds.end)
	visual.update_motion(velocity)
	health.heal(loadout.regeneration() * delta)
	loadout_controller.tick(delta * (1.0 + buff_attack_speed_bonus), not is_retreating or data.can_attack_while_retreating)

func _tick_enemy_skill(delta: float) -> bool:
	if data == null or data.skill == null:
		return false
	var sk := data.skill
	if skill_dash_remaining > 0.0:
		skill_dash_remaining = maxf(0.0, skill_dash_remaining - delta)
		velocity = skill_dash_direction * sk.dash_speed
		move_and_slide()
		global_position = global_position.clamp(arena_bounds.position, arena_bounds.end)
		visual.update_motion(velocity)
		var tgt := attack_target()
		if not skill_dash_hit_done and is_instance_valid(tgt) and global_position.distance_to(tgt.global_position) <= sk.radius:
			skill_dash_hit_done = true
			tgt.receive_damage(sk.damage * get_damage_multiplier())
			combat_effect.emit(tgt.global_position, sk.radius, "melee", "")
		queue_redraw()
		return true
	if skill_windup_remaining > 0.0:
		skill_windup_remaining = maxf(0.0, skill_windup_remaining - delta)
		velocity = Vector2.ZERO
		queue_redraw()
		if skill_windup_remaining <= 0.0:
			_execute_enemy_skill()
		return true
	if skill_cooldown_timer != null and skill_cooldown_timer.is_stopped():
		var tgt := attack_target()
		if not is_instance_valid(tgt):
			return false
		var dist := global_position.distance_to(tgt.global_position)
		if sk.kind in [SkillData.Kind.BUFF_AURA, SkillData.Kind.SUMMON_MINION] or dist <= sk.cast_range:
			try_cast_skill(false)
			return skill_windup_remaining > 0.0 or skill_dash_remaining > 0.0
	return false

func try_cast_skill(instant: bool = false) -> bool:
	if data == null or data.skill == null:
		return false
	if skill_cooldown_timer != null and not skill_cooldown_timer.is_stopped() and not instant:
		return false
	var sk := data.skill
	var tgt := attack_target()
	var tgt_pos := tgt.global_position if is_instance_valid(tgt) else (global_position + Vector2.RIGHT * sk.cast_range)
	var dir := (tgt_pos - global_position).normalized() if tgt_pos.distance_to(global_position) > 1.0 else Vector2.RIGHT
	skill_dash_direction = dir
	skill_target_point = global_position + (tgt_pos - global_position).limit_length(sk.cast_range)
	if instant or sk.kind in [SkillData.Kind.BUFF_AURA, SkillData.Kind.DEFENSIVE_SURGE]:
		skill_windup_remaining = 0.0
		skill_windup_total = 0.0
		_execute_enemy_skill()
		return true
	skill_windup_total = 0.40 if sk.kind == SkillData.Kind.CHARGE_DASH else 0.30
	skill_windup_remaining = skill_windup_total
	queue_redraw()
	return true

func _execute_enemy_skill() -> void:
	if data == null or data.skill == null:
		return
	var sk := data.skill
	if skill_cooldown_timer != null:
		skill_cooldown_timer.start(sk.cooldown)
	var dmg := sk.damage * get_damage_multiplier()
	var tgt := attack_target()
	match sk.kind:
		SkillData.Kind.CHARGE_DASH:
			skill_dash_remaining = maxf(0.25, sk.duration if sk.duration > 0.0 else 0.35)
			skill_dash_hit_done = false
			if is_instance_valid(tgt) and global_position.distance_to(tgt.global_position) <= sk.radius:
				skill_dash_hit_done = true
				tgt.receive_damage(dmg)
			combat_effect.emit(global_position, sk.radius, "melee", "")
		SkillData.Kind.PROJECTILE_BURST:
			var count := maxi(1, sk.projectile_count)
			var spread_rad := deg_to_rad(sk.spread_angle)
			var base_dir := skill_dash_direction
			var root := get_tree().get_first_node_in_group("projectile_root") if is_inside_tree() else null
			if root != null:
				for i in count:
					var t := 0.0 if count == 1 else (float(i) / float(count - 1) - 0.5)
					var shot_dir := base_dir.rotated(t * spread_rad)
					var bullet: CombatProjectile = PROJECTILE.instantiate()
					bullet.global_position = global_position + shot_dir * 18.0
					bullet.direction = shot_dir
					bullet.speed = 320.0
					bullet.friendly = charmed
					bullet.attacker = self
					bullet.damage = maxf(1.0, dmg)
					root.add_child(bullet)
			elif is_instance_valid(tgt) and global_position.distance_to(tgt.global_position) <= sk.cast_range:
				tgt.receive_damage(dmg)
			combat_effect.emit(global_position + base_dir * 20.0, maxf(20.0, sk.radius), "ranged", "")
		SkillData.Kind.BUFF_AURA:
			var dur := maxf(2.0, sk.duration if sk.duration > 0.0 else 4.0)
			apply_buff(sk.buff_move_speed_bonus, sk.buff_attack_speed_bonus, dur)
			if is_inside_tree():
				for ally in CombatTargeting.living_enemies(get_tree()):
					if ally != self and global_position.distance_to(ally.global_position) <= sk.radius and ally.has_method("apply_buff"):
						ally.apply_buff(sk.buff_move_speed_bonus, sk.buff_attack_speed_bonus, dur)
			combat_effect.emit(global_position, sk.radius, "heal", "")
		SkillData.Kind.SUMMON_MINION:
			var summon_def := ContentCatalog.enemy(sk.summon_enemy_id)
			if summon_def == null:
				summon_def = load("res://resources/enemies/melee.tres") as EnemyData
			var count := maxi(1, sk.projectile_count)
			var arena := get_tree().get_first_node_in_group("arena_controller") if is_inside_tree() else null
			var parent_node := get_parent()
			if summon_def != null and parent_node != null:
				for i in count:
					var angle := TAU * float(i) / float(count)
					var spawn_pos := (global_position + Vector2.RIGHT.rotated(angle) * 32.0).clamp(arena_bounds.position, arena_bounds.end)
					if arena != null and arena.get("director") != null and arena.director.active:
						if arena.director.alive_regular_count >= arena.director.max_active_enemies:
							break
						var unit: EnemyActor = ENEMY_SCENE.instantiate()
						unit.data = summon_def
						unit.player = player
						unit.position = spawn_pos
						unit.entered_arena = true
						arena.director.alive_count += 1
						arena.director.alive_regular_count += 1
						arena.director.total_spawned += 1
						arena.director.active_regular_enemies.append(unit)
						unit.defeated.connect(arena.director._unit_defeated)
						parent_node.add_child(unit)
						arena.director.enemy_spawned.emit(unit)
					else:
						var unit: EnemyActor = ENEMY_SCENE.instantiate()
						unit.data = summon_def
						unit.player = player
						unit.position = spawn_pos
						unit.entered_arena = true
						parent_node.add_child(unit)
			combat_effect.emit(global_position, sk.radius, "spell", "")
		SkillData.Kind.DEFENSIVE_SURGE:
			health.heal(maxf(5.0, dmg))
			apply_buff(0.3, 0.2, maxf(1.5, sk.duration))
			combat_effect.emit(global_position, sk.radius, "heal", "")
		_:
			var center := global_position + skill_dash_direction * minf(sk.cast_range * 0.5, 45.0) if sk.cast_range <= 120.0 else skill_target_point
			if is_instance_valid(tgt) and center.distance_to(tgt.global_position) <= sk.radius:
				tgt.receive_damage(dmg)
			combat_effect.emit(center, sk.radius, "blast", "")
	queue_redraw()

func _draw() -> void:
	if data == null or data.skill == null:
		return
	var sk := data.skill
	if skill_windup_remaining > 0.0:
		var pulse := 0.55 + 0.35 * sin(skill_windup_remaining * 28.0)
		if sk.kind == SkillData.Kind.CHARGE_DASH:
			var local_end := skill_dash_direction * sk.cast_range
			draw_line(Vector2.ZERO, local_end, Color(1.0, 0.22, 0.22, pulse), maxf(6.0, sk.radius * 0.45))
			draw_line(Vector2.ZERO, local_end, Color(1.0, 0.86, 0.72, pulse), 2.0)
		else:
			draw_arc(Vector2.ZERO, sk.radius * 0.65, 0.0, TAU, 32, Color(1.0, 0.28, 0.22, pulse), 2.5)

func get_movement_speed() -> float:
	return data.movement_speed * (1.0 + loadout.movement_bonus() + buff_move_speed_bonus) * RunState.combat_rules().enemy_speed_multiplier

func get_damage_multiplier() -> float:
	return (1.0 + loadout.damage_bonus()) * RunState.combat_rules().enemy_damage_multiplier * RunState.enemy_stat_multiplier()

func apply_burn(amount: float, duration: float) -> void:
	if amount <= 0 or duration <= 0 or not health.is_alive(): return
	if not is_instance_valid(burn) or burn.is_queued_for_deletion():
		burn = BurnStatus.new()
		burn.target = self
		add_child(burn)
	burn.apply(amount, duration)

func apply_charm(duration: float) -> void:
	if duration <= 0 or not health.is_alive(): return
	charmed = true
	_refresh_tint()
	charm_timer.start(maxf(duration, charm_timer.time_left))

func attack_target() -> Node2D:
	if not charmed: return player
	return CombatTargeting.nearest(global_position, INF, CombatTargeting.living_enemies(get_tree()))

func get_combat_loadout() -> ActorLoadout:
	return loadout

func wounded_allies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for unit in CombatTargeting.living_enemies(get_tree()):
		var ally_health: HealthComponent = unit.get_node("Health")
		if unit != self and ally_health.current < ally_health.maximum:
			result.append(unit)
	return result

func _plan_healing_position() -> void:
	if data.movement != EnemyData.Movement.CASTER or not is_instance_valid(player):
		return
	var healing := data.equipment.healing_spell()
	if healing == null:
		return
	var allies := wounded_allies()
	var away := player.global_position.direction_to(global_position)
	if away.is_zero_approx():
		away = Vector2.RIGHT
	healing_destination = player.global_position + away * (data.safety_distance + 12.0)
	if not allies.is_empty():
		healing_destination = CombatTargeting.best_circle_center(global_position, 350.0, healing.attack_range, allies, player.global_position, data.safety_distance + 4.0)
	healing_destination = healing_destination.clamp(arena_bounds.position, arena_bounds.end)

func receive_damage(amount: float) -> void:
	health.take_damage(amount)

func _die() -> void:
	remove_from_group("enemies")
	defeated.emit(self)
	queue_free()
