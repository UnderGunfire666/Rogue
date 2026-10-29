@tool
extends RefCounted
## Identical attack semantics and labels in the equipment and enemy editors.

static func build(fields: RefCounted, parent: Node, data: Resource, rebuild: Callable) -> void:
	var kinds: Array[String] = ["近战 Melee", "远程 Ranged", "施法 Spell"]
	fields.choice(parent, "攻击类型", data, "kind", kinds, rebuild)
	if data is AttackProfileData and data.kind == AttackProfileData.Kind.SPELL:
		var effects: Array[String] = ["必中伤害", "持续治疗友军"]
		fields.choice(parent, "施法效果", data, "effect", effects, rebuild)
	if data is AttackProfileData and data.kind == AttackProfileData.Kind.SPELL and data.effect == AttackProfileData.Effect.HEAL:
		fields.number(parent, "每目标每秒治疗量", data, "healing_per_second", 0.01, 0.1)
		fields.number(parent, "最多治疗对象数", data, "target_count", 1, 1)
		fields.number(parent, "治疗范围（像素）", data, "attack_range", 0.1, 1)
		fields.note(parent, "治疗是施法效果，移动与撤退期间持续治疗；此配置不造成伤害。")
		return
	fields.number(parent, "单投射物攻击力" if data.kind == 1 else "单次攻击攻击力", data, "damage", 0, 0.1)
	fields.number(parent, "发动攻击范围（像素）", data, "attack_range", 0.1, 1)
	fields.number(parent, "攻击间隔（秒）", data, "attack_interval", 0.01, 0.01)
	if data.kind == 1:
		fields.number(parent, "每次投射物数", data, "projectile_count", 1, 1)
		fields.number(parent, "弹速（像素/秒）", data, "projectile_speed", 0.1, 1)
		fields.number(parent, "散射总角度（度）", data, "spread_degrees", 0, 1)
		fields.note(parent, "1 发为单体，超过 1 发为多投射物；小于 360° 为对称扇形，360° 为环形。射程只控制发动攻击，子弹飞行距离与寿命不限，命中后消失。")
	elif data is WeaponData and data.kind == WeaponData.Kind.MELEE:
		var motions: Array[String] = ["突刺 Thrust", "挥砍 Sweep"]
		fields.choice(parent, "近战轨迹", data, "melee_motion", motions, rebuild)
		if data.melee_motion == WeaponData.MeleeMotion.SWEEP:
			var sweep: SpinBox = fields.number(parent, "挥砍角度（度）", data, "sweep_angle", 1, 1)
			sweep.max_value = 360
			sweep.allow_greater = false
		fields.number(parent, "武器判定半径（像素）", data, "melee_hit_radius", 1, 1)
		fields.note(parent, "锁定最近目标后按轨迹移动；攻击过程扫掠命中所有接触的敌人，同次攻击对每个敌人只造成一次伤害。")
	else:
		fields.number(parent, "最多攻击对象数", data, "target_count", 1, 1)
		fields.number(parent, "群体效果半径（像素）", data, "area_radius", 0, 1)
		fields.note(parent, "1 为单体，超过 1 为群体上限；单体自动选择最近敌人，群体先选择覆盖最多敌人的区域。近战挥砍和法术均必中，无飞行等待。")
	if data is WeaponData:
		if data.kind == WeaponData.Kind.RANGED:
			fields.number(parent, "额外穿透次数", data, "pierce_count", 0, 1)
			fields.number(parent, "额外弹跳次数", data, "bounce_count", 0, 1)
			fields.number(parent, "弹跳搜寻范围", data, "bounce_range", 1, 1)
		fields.number(parent, "爆炸半径（0 为无）", data, "explosion_radius", 0, 1)
		fields.number(parent, "燃烧每秒伤害（0 为无）", data, "burn_damage", 0, 0.1)
		fields.number(parent, "燃烧持续秒数", data, "burn_duration", 0, 0.1)
		var charm: SpinBox = fields.number(parent, "魅惑命中概率", data, "charm_chance", 0, 1, true)
		charm.max_value = 100
		charm.allow_greater = false
		fields.number(parent, "魅惑持续秒数", data, "charm_duration", 0, 0.1)
		var charm_hp: SpinBox = fields.number(parent, "魅惑目标生命阈值", data, "charm_health_threshold", 0, 1, true)
		charm_hp.max_value = 100
		charm_hp.allow_greater = false
		fields.number(parent, "对应伤害属性系数", data, "stat_scaling", 0, 0.05)
		var crit: SpinBox = fields.number(parent, "基础暴击率", data, "base_crit_chance", -1000, 1)
		crit.suffix = "%"
		fields.number(parent, "暴击伤害倍率", data, "crit_multiplier", 1, 0.05)
		var steal: SpinBox = fields.number(parent, "基础生命窃取率", data, "base_life_steal", -1000, 1)
		steal.suffix = "%"
		fields.note(parent, "近战、远程、施法分别按近战、远程、元素伤害缩放。基础暴击/窃取率与角色主属性相加。")
