@tool
class_name WeaponData
extends EquipmentData

enum Kind { MELEE, RANGED, SPELL }
enum MeleeMotion { THRUST, SWEEP }
@export var kind: Kind = Kind.MELEE
@export var damage: float = 20.0
@export var attack_range: float = 48.0
@export var attack_interval: float = 0.7
@export var area_radius: float = 24.0
@export var melee_motion: MeleeMotion = MeleeMotion.THRUST
@export_range(1.0, 360.0, 1.0) var sweep_angle: float = 120.0
@export_range(1.0, 100.0, 1.0) var melee_hit_radius: float = 12.0
@export var weapon_tags: PackedStringArray = []
@export var target_count: int = 1
@export var projectile_count: int = 1
@export_range(0.0, 360.0) var spread_degrees: float = 0.0
@export var projectile_speed: float = 380.0
@export var stat_scaling: float = 1.0
@export var base_crit_chance: float = 0.0
@export var crit_multiplier: float = 1.5
@export var base_life_steal: float = 0.0
@export_range(0, 100, 1) var pierce_count: int = 0
@export_range(0, 100, 1) var bounce_count: int = 0
@export var bounce_range: float = 250.0
@export var explosion_radius: float = 0.0
@export var burn_damage: float = 0.0
@export var burn_duration: float = 0.0
@export_range(0.0, 1.0, 0.01) var charm_chance: float = 0.0
@export var charm_duration: float = 0.0
@export_range(0.0, 1.0, 0.01) var charm_health_threshold: float = 1.0
