@tool
class_name CharacterCombatRules
extends Resource

@export var xp_gain_multiplier: float = 1.0
@export var xp_requirement_multiplier: float = 1.0
@export var material_gain_multiplier: float = 1.0
@export var enemy_material_multiplier: float = 1.0
@export var item_price_multiplier: float = 1.0
@export var weapon_price_multiplier: float = 1.0
@export var enemy_count_multiplier: float = 1.0
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0
@export var pickup_range_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.01) var dodge_cap: float = 0.6
@export var consumable_heal_bonus: float = 0.0
@export var can_heal: bool = true
@export var can_attack_while_moving: bool = true
@export var elite_boss_damage_multiplier: float = 1.0
@export_range(0, 50, 1) var environment_tree_count: int = 0
@export var tree_hp_regeneration: float = 0.0
@export var tree_materials_at_combat_end: int = 0
@export var tree_xp_at_combat_end: int = 0
@export_range(0.5, 2.0, 0.01) var arena_size_multiplier: float = 1.0
@export var gain_weapon_slot_on_level: bool = false
@export_range(1, 24, 1) var maximum_weapon_slots: int = 24
@export var harvesting_growth_bonus: float = 0.0
@export var one_hit_death: bool = false
@export var excluded_relic_tags: PackedStringArray = []
