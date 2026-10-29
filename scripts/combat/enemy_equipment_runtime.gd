extends Node2D

signal attack_performed(point: Vector2, radius: float, kind: String)
var data: EnemyEquipmentData
var holder: Node2D
var loadout: ActorLoadout
var attacks: Array[EnemyAttackRuntime] = []

func _ready() -> void:
	for profile in data.attacks:
		var runtime := EnemyAttackRuntime.new()
		runtime.data = profile
		runtime.holder = holder
		runtime.loadout = loadout
		runtime.attack_performed.connect(func(point: Vector2, radius: float, kind: String):
			attack_performed.emit(point, radius, kind))
		add_child(runtime)
		attacks.append(runtime)

func tick(delta: float, allow_attacks: bool = true) -> void:
	for attack in attacks:
		attack.tick(delta, allow_attacks)
