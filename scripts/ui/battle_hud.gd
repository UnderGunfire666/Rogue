extends CanvasLayer

var player: PlayerActor
var group_caption: String = "准备"
var total_groups: int = 3
var director: EncounterDirector
@onready var life: ProgressBar = $Root/Top/Margin/Content/LifeColumn/Life
@onready var life_text: Label = $Root/Top/Margin/Content/LifeColumn/HealthText
@onready var wave: Label = $Root/Top/Margin/Content/Wave
@onready var resources_label: Label = $Root/Top/Margin/Content/Resources
@onready var ammo: Label = $Root/Bottom/Margin/Content/Ammo
@onready var skill_label: Label = $Root/Bottom/Margin/Content/Skill

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	life.max_value = player.health.maximum
	life.value = player.health.current
	life_text.text = "%s   %.0f / %.0f" % [ContentCatalog.character(RunState.character_id).display_name, player.health.current, player.health.maximum]
	resources_label.text = "金币 %d   Lv.%d   经验 %d/%d" % [RunState.gold, RunState.level, RunState.experience, RunState.experience_needed()]
	ammo.text = player.inventory.ranged_status()
	var skill: SkillController = player.skill
	var parts := PackedStringArray()
	if skill.data != null:
		if skill.targeting:
			parts.append("[左键] 释放 %s  [Q] 切换  [右键] 取消" % skill.data.display_name)
		elif skill.cooldown.is_stopped():
			parts.append("[Q] %s · 就绪" % skill.data.display_name)
		else:
			parts.append("[Q] %s · 冷却 %.1fs" % [skill.data.display_name, skill.cooldown.time_left])
	if skill.character_skill != null and skill.character_cooldown != null:
		if skill.character_cooldown.is_stopped():
			parts.append("[E/空格] %s · 就绪" % skill.character_skill.display_name)
		else:
			parts.append("[E/空格] %s · 冷却 %.1fs" % [skill.character_skill.display_name, skill.character_cooldown.time_left])
	skill_label.text = "   |   ".join(parts) if not parts.is_empty() else "未装备主动技能"
	var remaining := director.duration_timer.time_left if is_instance_valid(director) and not director.duration_timer.is_stopped() else 0.0
	wave.text = group_caption + " · %.0fs · 敌人 %d" % [ceilf(remaining), get_tree().get_nodes_in_group("enemies").size()]

func update_group_progress(index: int, total: int, status: String) -> void:
	group_caption = "敌人组 %d · %s" % [index, status]
	total_groups = total
