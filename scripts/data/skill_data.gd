@tool
class_name SkillData
extends Resource

enum Kind {
	AOE_DAMAGE,
	CHARGE_DASH,
	PROJECTILE_BURST,
	BUFF_AURA,
	SUMMON_MINION,
	CHAIN_LIGHTNING,
	DEFENSIVE_SURGE,
	FIRE_WHIRL
}

@export var id: String = "ember_burst"
@export var display_name: String = "余烬爆破"
@export_multiline var description: String = ""
@export var kind: Kind = Kind.AOE_DAMAGE
@export var damage: float = 42.0
@export var elemental_scaling: float = 1.0
@export var cast_range: float = 240.0
@export var radius: float = 64.0
@export var cooldown: float = 9.0
@export var duration: float = 0.0
@export var projectile_count: int = 3
@export var spread_angle: float = 35.0
@export var dash_speed: float = 520.0
@export var buff_move_speed_bonus: float = 0.4
@export var buff_attack_speed_bonus: float = 0.3
@export var summon_enemy_id: String = "melee"
@export var icon: Texture2D

static func kind_labels() -> Array[String]:
	return [
		"范围爆破 AOE_DAMAGE",
		"野蛮冲撞 CHARGE_DASH",
		"弹幕散射 PROJECTILE_BURST",
		"战意光环 BUFF_AURA",
		"虫巢召唤 SUMMON_MINION",
		"连环落雷 CHAIN_LIGHTNING",
		"护盾闪步 DEFENSIVE_SURGE",
		"烈焰漩涡 FIRE_WHIRL"
	]

static func kind_label(value: int) -> String:
	var labels := kind_labels()
	return labels[clampi(value, 0, labels.size() - 1)]

func summary_text() -> String:
	return "%s [%s] · %s\n伤害 %.0f · 射程 %.0f · 半径 %.0f · 冷却 %.1fs" % [
		display_name, id, kind_label(kind), damage, cast_range, radius, cooldown
	]

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if display_name.strip_edges().is_empty():
		errors.append("技能显示名称不能为空。")
	if kind < 0 or kind > Kind.FIRE_WHIRL:
		errors.append("技能类型无效。")
	if not is_finite(damage) or damage < 0.0 or not is_finite(elemental_scaling) or elemental_scaling < 0.0:
		errors.append("技能伤害与属性系数须为非负有限数值。")
	if not is_finite(cast_range) or cast_range <= 0.0 or not is_finite(radius) or radius <= 0.0 or not is_finite(cooldown) or cooldown <= 0.0:
		errors.append("技能施放距离、半径和冷却须为正的有限数值。")
	if not is_finite(duration) or duration < 0.0:
		errors.append("技能持续时间不能为负数。")
	if projectile_count < 1:
		errors.append("投射物/召唤/弹跳数量须至少为 1。")
	if not is_finite(spread_angle) or spread_angle < 0.0 or spread_angle > 360.0:
		errors.append("散射/横扫角度须在 0–360 度之间。")
	if not is_finite(dash_speed) or dash_speed <= 0.0:
		errors.append("冲刺速度须大于 0。")
	return errors
