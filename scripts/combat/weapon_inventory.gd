class_name WeaponInventory
extends CombatLoadoutController

func _ready() -> void:
	configure(RunState.loadout, get_parent())

func ranged_status() -> String:
	return "武器自动攻击 · 范围内有敌人时发动"
