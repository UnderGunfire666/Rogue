@tool
class_name CharacterEventEffect
extends Resource

enum Trigger { LEVEL_UP, DAMAGED, HEALED, DODGED, MATERIAL_PICKUP, CONSUMABLE_PICKUP, COMBAT_END, COMBAT_SECOND, ENEMY_KILLED, CRITICAL_HIT, MOVE_STEP, BOSS_KILLED }
enum Effect { ADD_STAT, HEAL, SELF_DAMAGE, DAMAGE_RANDOM_ENEMY, GAIN_MATERIALS }
@export var trigger: Trigger = Trigger.LEVEL_UP
@export var effect: Effect = Effect.ADD_STAT
@export_enum("max_hp", "hp_regeneration", "life_steal", "damage", "melee_damage", "ranged_damage", "elemental_damage", "attack_speed", "crit_chance", "weapon_range", "armor", "dodge", "speed", "luck", "harvesting") var stat: String = "damage"
@export var amount: float = 1.0
@export_range(0.0, 1.0, 0.01) var probability: float = 1.0
@export var temporary_until_combat_end: bool = false
@export_range(1, 100000, 1, "or_greater") var every_n: int = 1
@export var only_at_full_health: bool = false
