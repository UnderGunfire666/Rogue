class_name MeleeTrajectory
extends Node2D
## Physics-driven attack trajectory. The visual and collision use the same points.

signal target_hit(target: Node2D)
signal motion_updated(offset: Vector2, angle: float)
signal motion_finished

var active := false
var data: WeaponData
var direction := Vector2.RIGHT
var locked_target: Node2D = null
var reach := 0.0
var elapsed := 0.0
var windup := 0.08
var strike_time := 0.2
var recovery := 0.12
var previous_progress := 0.0
var hit_ids: Dictionary = {}
var cast: ShapeCast2D

func _ready() -> void:
	cast = ShapeCast2D.new()
	cast.enabled = false
	cast.collision_mask = 2
	cast.collide_with_bodies = true
	cast.max_results = 256
	cast.target_position = Vector2.ZERO
	add_child(cast)

func begin(definition: WeaponData, aim: Vector2, max_reach: float, interval: float, target: Node2D = null) -> void:
	data = definition
	locked_target = target
	direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	reach = max_reach
	# Publicly documented range/attack-speed relationship; windup is an
	# adjustable approximation because exact original weapon timings vary.
	var speed: float = (RunState.stat_value("attack_speed") + RunState.weapon_bonus(data, "attack_speed")) / 100.0 + RunState.loadout.melee_speed_multiplier() - 1.0
	var range_factor := reach / clampf(70.0 * (1.0 + speed / 3.0), 70.0, 120.0)
	windup = minf(0.08, interval * 0.25)
	strike_time = maxf(0.01, 0.2 - speed / 10.0) + range_factor * 0.15
	recovery = 0.2 / (1.0 + maxf(0.0, speed) * 3.0)
	var shape := CircleShape2D.new()
	shape.radius = data.melee_hit_radius
	cast.shape = shape
	hit_ids.clear()
	elapsed = 0.0
	previous_progress = 0.0
	active = true

func _holder_global_position() -> Vector2:
	var parent_node := get_parent()
	if parent_node != null and parent_node.get("holder") != null and is_instance_valid(parent_node.holder):
		return parent_node.holder.global_position
	return global_position

func _update_thrust_tracking() -> void:
	if data == null or data.melee_motion != WeaponData.MeleeMotion.THRUST:
		return
	if is_instance_valid(locked_target) and locked_target.get("health") != null and locked_target.health.is_alive():
		var to_target := locked_target.global_position - _holder_global_position()
		if not to_target.is_zero_approx():
			direction = to_target.normalized()

func _guarantee_locked_thrust_hit(progress: float) -> void:
	if data == null or data.melee_motion != WeaponData.MeleeMotion.THRUST:
		return
	if progress < 0.5 or not is_instance_valid(locked_target):
		return
	if locked_target.get("health") == null or not locked_target.health.is_alive():
		return
	if locked_target.is_in_group("enemies") and locked_target.get("charmed") == true:
		return
	var id := locked_target.get_instance_id()
	if hit_ids.has(id):
		return
	hit_ids[id] = true
	target_hit.emit(locked_target)

func _physics_process(delta: float) -> void:
	if not active: return
	var old_elapsed := elapsed
	elapsed += delta
	_update_thrust_tracking()
	if elapsed < windup:
		motion_updated.emit(_visual_offset(0.0) * (elapsed / windup), _angle(0.0))
		return
	if old_elapsed < windup + strike_time:
		var progress := clampf((elapsed - windup) / strike_time, 0.0, 1.0)
		_sweep(previous_progress, progress)
		_guarantee_locked_thrust_hit(progress)
		previous_progress = progress
		motion_updated.emit(_visual_offset(progress), _angle(progress))
	if elapsed >= windup + strike_time:
		var t := clampf((elapsed - windup - strike_time) / recovery, 0.0, 1.0)
		var point := _visual_offset(1.0) * (1.0 - t)
		motion_updated.emit(point, _angle(1.0))
		if t >= 1.0:
			active = false
			locked_target = null
			motion_finished.emit()

func _angle(progress: float) -> float:
	if data.melee_motion == WeaponData.MeleeMotion.THRUST:
		return direction.angle()
	return (direction.rotated(deg_to_rad(data.sweep_angle) * (progress - 0.5))).angle()

func _visual_offset(progress: float) -> Vector2:
	# Keep weapon hilt attached to player center while sweeping/thrusting outward.
	var radial := Vector2.RIGHT.rotated(_angle(progress))
	if data.melee_motion == WeaponData.MeleeMotion.THRUST:
		var hilt_base := 10.0
		return radial * lerpf(hilt_base, maxf(hilt_base, reach - 8.0), progress)
	var hilt_radius := clampf(reach * 0.35, 12.0, 22.0)
	return radial * hilt_radius

func _point(progress: float) -> Vector2:
	if data.melee_motion == WeaponData.MeleeMotion.THRUST:
		return direction * reach * progress
	var angle := deg_to_rad(data.sweep_angle) * (progress - 0.5)
	return direction.rotated(angle) * maxf(0.0, reach - data.melee_hit_radius)

func _origin_offset() -> Vector2:
	var parent_node := get_parent()
	if parent_node != null and parent_node.get("holder") != null and is_instance_valid(parent_node.holder):
		return parent_node.holder.global_position - global_position
	return Vector2.ZERO

func _sweep(from_progress: float, to_progress: float) -> void:
	# Radial segment Sweep/Thrust from the player center to the tip eliminates close-range blind spots.
	var path_length := reach * (to_progress - from_progress)
	if data.melee_motion == WeaponData.MeleeMotion.SWEEP:
		path_length = maxf(0.0, reach - data.melee_hit_radius) * deg_to_rad(data.sweep_angle) * (to_progress - from_progress)
	var arc_samples := maxi(1, ceili(path_length / maxf(1.0, data.melee_hit_radius * 0.5)))
	var origin := _origin_offset()
	cast.target_position = Vector2.ZERO
	for index in range(arc_samples + 1):
		var tip := _point(lerpf(from_progress, to_progress, float(index) / arc_samples))
		var radial_steps := maxi(1, ceili(tip.length() / maxf(1.0, data.melee_hit_radius * 0.75)))
		for r_step in range(radial_steps + 1):
			cast.position = origin + tip * (float(r_step) / radial_steps)
			cast.force_shapecast_update()
			for collision in cast.get_collision_count():
				var target := cast.get_collider(collision) as Node2D
				if target == null or (not target.is_in_group("enemies") and not target.is_in_group("destructibles")) or not target.health.is_alive(): continue
				if target.is_in_group("enemies") and target.charmed: continue
				var id := target.get_instance_id()
				if hit_ids.has(id): continue
				hit_ids[id] = true
				target_hit.emit(target)
