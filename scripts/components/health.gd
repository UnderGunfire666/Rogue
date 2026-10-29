class_name HealthComponent
extends Node

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal depleted

@export var maximum: float = 100.0
var current: float = 100.0

func initialize(maximum_value: float, current_value: float = -1.0) -> void:
	maximum = maximum_value
	current = maximum if current_value < 0.0 else clampf(current_value, 0.0, maximum)
	changed.emit(current, maximum)

func take_damage(amount: float) -> void:
	if current <= 0.0 or amount <= 0.0:
		return
	var actual := minf(current, amount)
	current -= actual
	damaged.emit(actual)
	changed.emit(current, maximum)
	if current <= 0.0:
		depleted.emit()

func heal(amount: float) -> void:
	if get_parent().is_in_group("players") and not RunState.combat_rules().can_heal:
		return
	if current <= 0.0 or amount <= 0.0:
		return
	var actual := minf(maximum - current, amount)
	if actual <= 0.0:
		return
	current += actual
	healed.emit(actual)
	changed.emit(current, maximum)

func is_alive() -> bool:
	return current > 0.0
