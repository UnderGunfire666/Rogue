@tool
class_name CharacterEquipmentRules
extends Resource

@export_range(0, 24, 1) var slots: int = 2
@export var allow_melee: bool = true
@export var allow_ranged: bool = true
@export var allow_spell: bool = true
@export_range(1, 5, 1) var minimum_rarity: int = 1
@export_range(1, 5, 1) var maximum_rarity: int = 5
@export var allow_duplicates: bool = true
