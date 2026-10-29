@tool
class_name CharacterData
extends Resource

@export var id: String = "wanderer"
@export var display_name: String = "旅人"
@export_multiline var description: String = ""
@export var max_health: float = 100.0
@export var movement_units: float = 5.0
@export var primary_stats: PrimaryStatsData
## Additive change to the multiplier on non-starting stat gains, in percentage points.
@export var growth_modifiers: PrimaryStatsData
@export var stat_conversions: Array[StatConversionData] = []
@export var equipment_rules: CharacterEquipmentRules
@export var conditional_bonuses: Array[ConditionalStatBonus] = []
@export var combat_rules: CharacterCombatRules
@export var event_effects: Array[CharacterEventEffect] = []
@export var weapon_bonuses: Array[CharacterWeaponBonus] = []
@export var equipment_stat_bonuses: Array[EquipmentStatBonus] = []
@export var starting_weapons: PackedStringArray = []
@export var starting_relics: PackedStringArray = []
@export var skill: SkillData
@export var portrait: Texture2D
