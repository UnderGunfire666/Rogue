@tool
class_name StatConversionData
extends Resource

@export_enum("max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting") var source: String = "armor"
@export_enum("max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting") var target: String = "melee_damage"
@export var factor: float = 1.0
## Zero means continuous; positive values count whole source-attribute steps.
@export var source_step: float = 0.0
