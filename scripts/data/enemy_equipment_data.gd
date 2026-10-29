@tool
class_name EnemyEquipmentData
extends EquipmentData

@export var attacks: Array[AttackProfileData] = []

func first_attack(kind: AttackProfileData.Kind) -> AttackProfileData:
	for attack in attacks:
		if attack != null and attack.kind == kind:
			return attack
	return null

func healing_spell() -> AttackProfileData:
	for attack in attacks:
		if attack != null and attack.kind == AttackProfileData.Kind.SPELL and attack.effect == AttackProfileData.Effect.HEAL:
			return attack
	return null
