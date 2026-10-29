@tool
class_name ConditionalStatBonus
extends Resource

enum Condition { MOVING, STANDING_STILL, BELOW_HEALTH_FRACTION }
@export_enum("max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting") var stat: String = "damage"
@export var condition: Condition = Condition.MOVING
@export var amount: float = 0.0
@export_range(0.0, 1.0, 0.01) var health_fraction: float = 0.5
