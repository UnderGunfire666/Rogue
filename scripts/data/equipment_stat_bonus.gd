@tool
class_name EquipmentStatBonus
extends Resource

enum Source { WEAPON_COUNT, DISTINCT_WEAPONS, EMPTY_SLOTS }
@export var source: Source = Source.WEAPON_COUNT
@export_enum("max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting") var target: String = "damage"
@export var amount_per_unit: float = 1.0
