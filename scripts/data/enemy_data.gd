@tool
class_name EnemyData
extends Resource

enum Category { NORMAL, ELITE, BOSS }
enum Movement { FOLLOW, KEEP_DISTANCE, CASTER }
@export var id: String = ""
@export var display_name: String = ""
@export var category: Category = Category.NORMAL
@export var movement: Movement = Movement.FOLLOW
@export var texture: Texture2D
@export var max_health: float = 32.0
@export var movement_speed: float = 144.0
@export var safety_distance: float = 150.0
@export var can_attack_while_retreating: bool = false
@export var equipment: EnemyEquipmentData
@export var relic: RelicData
@export var skill: SkillData
@export var experience_reward: int = 4
@export var gold_reward: int = 3
## Base gold fragments dropped in Dream Expedition mode (10 fragments = 1 gold).
## Defaults to gold_reward * 10 when <= 0 so authored values map cleanly.
@export var fragment_reward: int = 0
@export_range(0.0, 1.0) var consumable_drop_chance: float = 0.1
@export_range(0.0, 1.0) var relic_drop_chance: float = 0.02

func effective_fragment_reward() -> int:
	return fragment_reward if fragment_reward > 0 else gold_reward * 10

func required_spawn_margin() -> float:
	if texture == null:
		return 28.0
	var size := texture.get_size()
	var scale := 1.5 if category == Category.BOSS else 1.15 if category == Category.ELITE else 1.0
	return maxf(size.x, size.y) * scale + 4.0

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if max_health <= 0.0 or movement_speed <= 0.0:
		errors.append("%s 的生命与移速必须大于 0。" % display_name)
	if consumable_drop_chance < 0.0 or consumable_drop_chance > 1.0 or relic_drop_chance < 0.0 or relic_drop_chance > 1.0:
		errors.append("掉落概率必须在 0% 到 100% 之间。")
	if equipment == null or equipment.recipient != ItemDefinition.Recipient.ENEMY:
		errors.append("%s 需要一件敌人专用装备。" % display_name)
	elif equipment.attacks.is_empty():
		errors.append("%s 的装备没有攻击配置。" % display_name)
	else:
		errors.append_array(CombatDataValidation.item_errors(equipment))
		if movement == Movement.CASTER and equipment.first_attack(AttackProfileData.Kind.SPELL) == null:
			errors.append("施法类敌人需要至少一个施法攻击或治疗配置。")
	if relic != null and relic.recipient != ItemDefinition.Recipient.ENEMY:
		errors.append("%s 不能使用玩家遗物。" % display_name)
	if skill != null:
		errors.append_array(skill.validation_errors())
	return errors
