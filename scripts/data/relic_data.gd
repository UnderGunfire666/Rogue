@tool
class_name RelicData
extends ItemDefinition

@export var regeneration: float = 0.0
@export var melee_attack_speed_bonus: float = 0.0
@export var movement_bonus: float = 0.0
@export var damage_bonus: float = 0.0
@export var primary_stats: PrimaryStatsData
@export var skill: SkillData
@export_range(0, 100000, 1, "or_greater") var base_price: int = 25
## Zero means unlimited copies of this relic.
@export_range(0, 100000, 1, "or_greater") var copy_limit: int = 0
@export var tags: PackedStringArray = []
