class_name UiKit
extends RefCounted

const CARD := preload("res://scenes/ui/choice_card.tscn")

static func label(parent: Node, text: String, size: int = 16, color: Color = Color("#d9e3d9")) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	parent.add_child(control)
	return control

static func button(parent: Node, text: String, callback: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

static func row(parent: Node, spacing: int = 12) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.add_theme_constant_override("separation", spacing)
	parent.add_child(control)
	return control

static func card(parent: Node, title: String, text: String, texture: Texture2D, callback: Callable, action: String = "选择") -> ChoiceCard:
	var control: ChoiceCard = CARD.instantiate()
	parent.add_child(control)
	control.configure(title, text, texture, action)
	control.selected.connect(callback)
	return control

static func weapon_stats(data: WeaponData) -> String:
	var skill_note := "\n技能：" + data.skill.display_name if data.skill != null else ""
	if data.kind == WeaponData.Kind.RANGED:
		return ("T%d · %s\n每弹 %.0f × %d · 发动范围 %.0f\n自动射击 · 间隔 %.2fs" % [data.rarity, data.description, data.damage, data.projectile_count, data.attack_range, data.attack_interval]) + skill_note
	if data.kind == WeaponData.Kind.MELEE:
		return ("T%d · %s\n%s %.0f · 距离 %.0f\n间隔 %.2fs · 路径命中" % [data.rarity, data.description, "突刺" if data.melee_motion == WeaponData.MeleeMotion.THRUST else "挥砍", data.damage, data.attack_range, data.attack_interval]) + skill_note
	return ("T%d · %s\n%s %.0f · 距离 %.0f\n间隔 %.2fs · 最多 %d 目标" % [data.rarity, data.description, "必中法术" if data.kind == WeaponData.Kind.SPELL else "必中挥砍", data.damage, data.attack_range, data.attack_interval, data.target_count]) + skill_note

static func relic_stats(data: RelicData) -> String:
	var limit := "无限" if data.copy_limit == 0 else str(data.copy_limit)
	var skill_note := "\n技能：" + data.skill.display_name if data.skill != null else ""
	return ("T%d · 基础价格 %d · 上限 %s\n%s\n标签：%s" % [data.rarity, data.base_price, limit, data.description, "、".join(data.tags) if not data.tags.is_empty() else "无"]) + skill_note

static func weapon_grid(parent: Node) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	return grid

static func inventory_text() -> String:
	var names: Array[String] = []
	for id in RunState.weapons:
		names.append("空槽" if id.is_empty() else ContentCatalog.weapon(id).display_name)
	if names.is_empty(): return "无武器槽"
	return " / ".join(names)
