class_name MapExploration
extends RefCounted
## Fog-of-war state for the current route map: which cells have their type
## revealed. Holds no map content and no presentation.

signal changed
const BASE_REVEAL_RADIUS := 1

## Extra route steps revealed on entering a cell. Hook for future relics or
## characters; it survives map changes while the revealed set does not.
var reveal_radius_bonus: int = 0
var revealed: Dictionary = {}

func reveal_radius() -> int:
	return maxi(0, BASE_REVEAL_RADIUS + reveal_radius_bonus)

## Called on map selection / map change. The BOSS location stays visible so the
## destination can be found when zooming out.
func reset(map: MapData) -> void:
	revealed.clear()
	if map != null and not map.boss_cell_id.is_empty():
		revealed[map.boss_cell_id] = true
	changed.emit()

func is_revealed(id: String) -> bool:
	return revealed.has(id)

func reveal(ids: Array) -> void:
	var updated := false
	for id in ids:
		if not revealed.has(id):
			revealed[id] = true
			updated = true
	if updated:
		changed.emit()

## Reveals the entered cell and every cell within the reveal radius along its
## downward routes.
func reveal_around(map: MapData, id: String, radius: int = -1) -> void:
	if map == null or map.find_cell(id) == null:
		return
	var steps := reveal_radius() if radius < 0 else radius
	var found: Array = [id]
	var frontier: Array = [id]
	for step in steps:
		var next_frontier: Array = []
		for current in frontier:
			for next_id in map.neighbors(current):
				if not found.has(next_id):
					found.append(next_id)
					next_frontier.append(next_id)
		frontier = next_frontier
	reveal(found)
