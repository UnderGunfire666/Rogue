@tool
class_name ContentCatalog
extends RefCounted

const PIXELS_PER_UNIT: float = 24.0
const PLAYER_BASE_SPEED: float = 5.0 * PIXELS_PER_UNIT
const PLAYER_STARTING_SPEED_MULTIPLIER: float = 1.5

static func weapon(id: String) -> WeaponData:
	for item in _items("res://resources/weapons"):
		if item is WeaponData and item.recipient == ItemDefinition.Recipient.PLAYER and item.id == id:
			return item
	return null

static func weapon_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in _items("res://resources/weapons"):
		if item is WeaponData and item.recipient == ItemDefinition.Recipient.PLAYER: ids.append(item.id)
	return _ordered(ids, ["needle", "cleaver", "pistol"])

static func character(id: String) -> CharacterData:
	for item in _items("res://resources/characters"):
		if item is CharacterData and item.id == id: return item
	return null

static func character_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in _items("res://resources/characters"):
		if item is CharacterData: ids.append(item.id)
	return _ordered(ids, ["wanderer"])

static func relic(id: String) -> RelicData:
	# Most resources use their ID as filename. Fall back to the dynamic scan so
	# renamed IDs and subdirectories created by the editor continue to work.
	var direct_path := "res://resources/relics/%s.tres" % id
	if ResourceLoader.exists(direct_path):
		var direct := load(direct_path) as RelicData
		if direct != null and direct.recipient == ItemDefinition.Recipient.PLAYER and direct.id == id:
			return direct
	for item in _items("res://resources/relics"):
		if item is RelicData and item.recipient == ItemDefinition.Recipient.PLAYER and item.id == id:
			return item
	return null

static func relic_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in _items("res://resources/relics"):
		if item is RelicData and item.recipient == ItemDefinition.Recipient.PLAYER: ids.append(item.id)
	return _ordered(ids, ["seed", "fury", "feather"])

static func _items(directory: String) -> Array[Resource]:
	var items: Array[Resource] = []
	for file in ResourceLoader.list_directory(directory):
		if file.ends_with("/"):
			items.append_array(_items(directory.path_join(file.trim_suffix("/"))))
		elif file.get_extension() in ["tres", "res"]:
			var item := load(directory.path_join(file))
			if item != null: items.append(item)
	return items

static func _ordered(ids: PackedStringArray, preferred: PackedStringArray) -> PackedStringArray:
	ids.sort()
	var result := PackedStringArray()
	for id in preferred:
		if ids.has(id): result.append(id)
	for id in ids:
		if not result.has(id): result.append(id)
	return result

static func map() -> MapData:
	return load("res://resources/maps/ember_map.tres") as MapData

## One template per map level (1–3) for the dream expedition.
static func map_template(level: int) -> MapTemplateData:
	for item in _items("res://resources/expedition/templates"):
		if item is MapTemplateData and item.level == level: return item
	return null

static func map_difficulties() -> Array[MapDifficultyData]:
	var result: Array[MapDifficultyData] = []
	for item in _items("res://resources/expedition/difficulties"):
		if item is MapDifficultyData: result.append(item)
	result.sort_custom(func(a: MapDifficultyData, b: MapDifficultyData): return a.order < b.order)
	return result

static func skill(id: String = "ember_burst") -> SkillData:
	var direct_path := "res://resources/skills/%s.tres" % id
	if ResourceLoader.exists(direct_path):
		var direct := load(direct_path) as SkillData
		if direct != null:
			return direct
	for item in _items("res://resources/skills"):
		if item is SkillData and item.id == id:
			return item
	return load("res://resources/skills/ember_burst.tres") as SkillData

static func skill_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in _items("res://resources/skills"):
		if item is SkillData and not item.id.is_empty():
			ids.append(item.id)
	return _ordered(ids, ["ember_burst"])

static func enemy(id: String) -> EnemyData:
	var direct_path := "res://resources/enemies/%s.tres" % id
	if ResourceLoader.exists(direct_path):
		var direct := load(direct_path) as EnemyData
		if direct != null:
			return direct
	for item in _items("res://resources/enemies"):
		if item is EnemyData and item.id == id:
			return item
	return null
