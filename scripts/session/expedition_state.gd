class_name ExpeditionState
extends RefCounted
## Progress through one dream expedition: three maps of levels 1, 2 and 3.
## Owns the generated map and its exploration state; RunState keeps position
## and completion records as for any other map.

const LEVEL_COUNT := 3
const FIRST_MAP_DIFFICULTY := "normal"

## 0 before the first map is entered, then 1..3.
var level: int = 0
var map: MapData
var template: MapTemplateData
var difficulty: MapDifficultyData
var exploration := MapExploration.new()
var difficulty_history: Array[String] = []
## Set when the current map's BOSS cell is completed; cleared on entering the next map.
var map_cleared: bool = false
## Placeholder artwork bookkeeping: theme id -> used indices, plus current offers.
var used_art: Dictionary = {}
var art_offers: Dictionary = {}
var art_index: int = -1

func next_level() -> int:
	return level + 1 if map == null or map_cleared else level

func needs_map_selection() -> bool:
	return map == null or map_cleared

func is_final_map() -> bool:
	return level >= LEVEL_COUNT

func level_multiplier() -> float:
	return template.level_multiplier if template != null else 1.0

## The first map is fixed to normal; maps 2 and 3 offer every difficulty.
func offered_difficulties() -> Array[MapDifficultyData]:
	var result: Array[MapDifficultyData] = []
	for item in ContentCatalog.map_difficulties():
		if next_level() > 1 or item.id == FIRST_MAP_DIFFICULTY:
			result.append(item)
	return result

## Picks (once per selection screen) an unused placeholder art slot per theme.
func offered_art_index(item: MapDifficultyData, rng: RandomNumberGenerator) -> int:
	if art_offers.has(item.id):
		return art_offers[item.id]
	var used: Array = used_art.get(item.id, [])
	var free: Array[int] = []
	for i in item.art_count:
		if not used.has(i): free.append(i)
	var index := free[rng.randi_range(0, free.size() - 1)] if not free.is_empty() else rng.randi_range(0, item.art_count - 1)
	art_offers[item.id] = index
	return index

func enter_map(difficulty_id: String, rng: RandomNumberGenerator) -> bool:
	if not needs_map_selection() or next_level() > LEVEL_COUNT:
		return false
	var chosen: MapDifficultyData
	for item in offered_difficulties():
		if item.id == difficulty_id: chosen = item
	var next_template := ContentCatalog.map_template(next_level())
	if chosen == null or next_template == null or not next_template.validation_errors().is_empty():
		return false
	art_index = offered_art_index(chosen, rng)
	if not used_art.has(chosen.id): used_art[chosen.id] = []
	used_art[chosen.id].append(art_index)
	art_offers.clear()
	level = next_level()
	template = next_template
	difficulty = chosen
	difficulty_history.append(chosen.id)
	map = ExpeditionMapGenerator.generate(template, difficulty, rng)
	map_cleared = false
	exploration.reset(map)
	return true
