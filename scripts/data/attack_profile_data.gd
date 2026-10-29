@tool
class_name AttackProfileData
extends Resource

enum Kind { MELEE, RANGED, SPELL }
enum Effect { DAMAGE, HEAL }
@export var kind: Kind = Kind.MELEE
@export var effect: Effect = Effect.DAMAGE
@export var damage: float = 8.0
@export var attack_range: float = 25.0
@export var attack_interval: float = 1.0
@export var target_count: int = 1
@export var area_radius: float = 36.0
@export var projectile_speed: float = 145.0
@export var projectile_count: int = 1
@export_range(0.0, 360.0) var spread_degrees: float = 0.0
@export var healing_per_second: float = 5.0
