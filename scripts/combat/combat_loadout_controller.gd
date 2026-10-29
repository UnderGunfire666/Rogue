class_name CombatLoadoutController
extends Node2D

signal attack_performed(point: Vector2, radius: float, kind: String)
const PLAYER_RUNTIME := preload("res://scenes/combat/weapon.tscn")
const ENEMY_RUNTIME := preload("res://scenes/combat/enemy_equipment.tscn")
var equipped: Array[Node2D] = []
var loadout: ActorLoadout

func configure(value: ActorLoadout, actor: Node2D) -> void:
	loadout = value
	for item in equipped:
		remove_child(item)
		item.queue_free()
	equipped.clear()
	for slot in loadout.equipment.size():
		var definition: EquipmentData = loadout.equipment[slot]
		if definition == null:
			continue
		var runtime: Node2D
		if definition is WeaponData:
			runtime = PLAYER_RUNTIME.instantiate()
		elif definition is EnemyEquipmentData:
			runtime = ENEMY_RUNTIME.instantiate()
		else:
			push_error("Unsupported equipment definition: " + definition.id)
			continue
		runtime.data = definition
		runtime.holder = actor
		runtime.loadout = loadout
		if loadout.equipment.size() <= 2:
			runtime.position = Vector2(-19 if slot == 0 else 19, 5)
		else:
			runtime.position = Vector2.RIGHT.rotated(TAU * slot / loadout.equipment.size()) * 24.0
		runtime.attack_performed.connect(func(point: Vector2, radius: float, kind: String):
			attack_performed.emit(point, radius, kind))
		add_child(runtime)
		equipped.append(runtime)

func tick(delta: float, allow_attacks: bool = true) -> void:
	for runtime in equipped:
		if runtime.has_method("tick"):
			runtime.tick(delta, allow_attacks)
