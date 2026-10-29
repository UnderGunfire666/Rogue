class_name CombatTargeting
extends RefCounted

static func living_enemies(tree: SceneTree) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for unit in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.health.is_alive() and not unit.charmed:
			result.append(unit)
	return result

static func attackable_targets(tree: SceneTree) -> Array[Node2D]:
	var targets := living_enemies(tree)
	for object in tree.get_nodes_in_group("destructibles"):
		if is_instance_valid(object) and not object.is_queued_for_deletion() and object.health.is_alive(): targets.append(object)
	return targets

static func lowest_health(origin: Vector2, reach: float, units: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	for unit in units:
		if origin.distance_to(unit.global_position) > reach:
			continue
		if best == null or unit.health.current < best.health.current:
			best = unit
		elif is_equal_approx(unit.health.current, best.health.current):
			if origin.distance_squared_to(unit.global_position) < origin.distance_squared_to(best.global_position):
				best = unit
	return best

static func nearest(origin: Vector2, reach: float, units: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var distance := reach * reach
	for unit in units:
		var candidate := origin.distance_squared_to(unit.global_position)
		if candidate <= distance and (best == null or candidate < distance):
			best = unit
			distance = candidate
	return best

static func direct_targets(origin: Vector2, reach: float, limit: int, radius: float, units: Array[Node2D]) -> Array[Node2D]:
	var candidates: Array[Node2D] = []
	for unit in units:
		if origin.distance_to(unit.global_position) <= reach:
			candidates.append(unit)
	if candidates.is_empty() or limit <= 0:
		return []
	if limit == 1:
		return [nearest(origin, reach, candidates)]
	var center := best_circle_center(origin, reach, radius, candidates)
	var covered: Array[Node2D] = []
	for unit in candidates:
		if center.distance_to(unit.global_position) <= radius + 0.05:
			covered.append(unit)
	covered.sort_custom(func(a: Node2D, b: Node2D):
		if not is_equal_approx(a.health.current, b.health.current):
			return a.health.current < b.health.current
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	if covered.size() > limit:
		covered.resize(limit)
	return covered

static func projectile_directions(direction: Vector2, count: int, spread_degrees: float) -> Array[Vector2]:
	var directions: Array[Vector2] = []
	for index in count:
		var angle := 0.0
		if count > 1:
			angle = TAU * index / count if spread_degrees >= 360 else deg_to_rad(spread_degrees) * (float(index) / (count - 1) - 0.5)
		directions.append(direction.rotated(angle))
	return directions

static func circle_intersections(a: Vector2, ar: float, b: Vector2, br: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var distance := a.distance_to(b)
	if distance < 0.001 or distance > ar + br + 0.001 or distance < absf(ar - br) - 0.001:
		return result
	var along := (ar * ar - br * br + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, ar * ar - along * along))
	var axis := (b - a) / distance
	var midpoint := a + axis * along
	result.append(midpoint + axis.orthogonal() * height)
	result.append(midpoint - axis.orthogonal() * height)
	return result

static func best_circle_center(origin: Vector2, reach: float, radius: float, units: Array[Node2D], avoid: Vector2 = Vector2.INF, safety: float = 0.0) -> Vector2:
	# The maximum coverage of equal circles occurs at a target center,
	# two coverage-boundary intersections, or the cast/safety boundary.
	var candidates: Array[Vector2] = [origin]
	for i in units.size():
		var point: Vector2 = units[i].global_position
		candidates.append(origin + (point - origin).limit_length(reach))
		candidates.append_array(circle_intersections(origin, reach, point, radius))
		if avoid.is_finite():
			candidates.append_array(circle_intersections(avoid, safety, point, radius))
		for j in range(i):
			candidates.append_array(circle_intersections(point, radius, units[j].global_position, radius))
	var best := origin
	var best_count: int = -1
	var best_distance: float = INF
	for point in candidates:
		if point.distance_to(origin) > reach + 0.05:
			continue
		if avoid.is_finite() and point.distance_to(avoid) < safety - 0.05:
			continue
		var count: int = 0
		for unit in units:
			if point.distance_to(unit.global_position) <= radius + 0.05:
				count += 1
		var distance := point.distance_squared_to(origin)
		if count > best_count or (count == best_count and distance < best_distance):
			best = point
			best_count = count
			best_distance = distance
	return best
