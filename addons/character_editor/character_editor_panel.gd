@tool
extends VBoxContainer
## Full custom Character Editor for authoring, copying, and managing selectable player characters.

const IO = preload("res://addons/enemy_editor/enemy_editor_store.gd")
const Fields = preload("res://addons/enemy_editor/enemy_form_fields.gd")
const DIRECTORY := "res://resources/characters"
var io := IO.new()
var fields := Fields.new()
var draft: CharacterData
var selected_path := ""
var fingerprint := ""
var dirty := false
var pending: Callable
var list: ItemList
var _search: LineEdit
var _filter: OptionButton
var _tabs: TabContainer
var form: VBoxContainer
var _equipment_tab: VBoxContainer
var _mechanics_tab: VBoxContainer
var _combat_tab: VBoxContainer
var _preview: TextureRect
var _speed_note: Label
var _validation: RichTextLabel
var status: Label
var confirm_discard: ConfirmationDialog
var confirm_delete: ConfirmationDialog
var message: AcceptDialog
var files: FileDialog
var texture_target: Resource
var texture_property: String
var texture_label: LineEdit

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	fields.changed = _changed
	fields.choose_texture = _choose_texture
	_build_ui()
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(func(): _refresh_list.call_deferred())
	_refresh_list()
	if selected_path.is_empty() and list.item_count > 0:
		_open(str(list.get_item_metadata(0)))
	else:
		_rebuild()

func ensure_loaded() -> void:
	_refresh_list()
	if draft == null and list.item_count > 0:
		_open(str(list.get_item_metadata(0)))

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "角色编辑器  /  CHARACTER EDITOR"
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)
	var toolbar := HFlowContainer.new()
	layout.add_child(toolbar)
	fields.button(toolbar, "新建角色", func(): _guard(_new_character))
	fields.button(toolbar, "复制为新角色", func(): _guard(_copy_character))
	fields.button(toolbar, "保存角色", func(): save_current(true))
	fields.button(toolbar, "放弃修改 / 重新载入", func(): _guard(_reload))
	fields.button(toolbar, "查看引用", _references)
	fields.button(toolbar, "删除角色", _request_delete)
	fields.button(toolbar, "刷新角色库", func(): _guard(_refresh))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 240
	layout.add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 220
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(library)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索角色名称、ID…"
	_search.text_changed.connect(func(_text: String): _refresh_list())
	library.add_child(_search)
	_filter = OptionButton.new()
	for label in ["全部角色", "默认旅人", "扩展可选角色"]:
		_filter.add_item(label)
	_filter.item_selected.connect(func(_index: int): _refresh_list())
	library.add_child(_filter)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(220, 260)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index: int): request_open(str(list.get_item_metadata(index))))
	library.add_child(list)
	fields.note(library, "保存后的角色会自动进入游戏「选择角色」列表；选中任意角色即可编辑、复制为新角色或删除。")
	var editing := VBoxContainer.new()
	editing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(editing)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editing.add_child(_tabs)
	form = _create_tab("基础与主属性")
	_equipment_tab = _create_tab("装备与开局配装")
	_mechanics_tab = _create_tab("换算、条件与事件")
	_combat_tab = _create_tab("战斗与经济规则")
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = false
	_validation.custom_minimum_size.y = 78
	_validation.size_flags_vertical = Control.SIZE_FILL
	editing.add_child(_validation)
	message = AcceptDialog.new()
	message.title = "角色编辑器"
	add_child(message)
	confirm_discard = ConfirmationDialog.new()
	confirm_discard.title = "放弃未保存修改？"
	confirm_discard.dialog_text = "当前角色有未保存的修改，确定放弃吗？"
	confirm_discard.confirmed.connect(func():
		var action := pending
		pending = Callable()
		if action.is_valid(): action.call())
	confirm_discard.canceled.connect(_refresh_list)
	add_child(confirm_discard)
	confirm_delete = ConfirmationDialog.new()
	confirm_delete.title = "删除角色资源"
	confirm_delete.confirmed.connect(_delete)
	add_child(confirm_delete)
	files = FileDialog.new()
	files.access = FileDialog.ACCESS_RESOURCES
	files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	files.filters = PackedStringArray(["*.png,*.webp,*.svg,*.jpg,*.tres,*.res ; Texture2D"])
	files.file_selected.connect(_texture_selected)
	add_child(files)

func _create_tab(tab_title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	return content

func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func is_dirty() -> bool:
	return dirty

func _changed() -> void:
	dirty = true
	_update_status()

func _guard(action: Callable) -> void:
	if dirty:
		pending = action
		confirm_discard.popup_centered()
	else:
		action.call()

func request_open(path: String) -> void:
	if path == selected_path and draft != null:
		return
	_guard(func(): _open(path))

func _open(path: String) -> void:
	var character := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as CharacterData
	if character == null:
		_show("无法载入角色资源：" + path)
		return
	draft = io.copy_definition(character) as CharacterData
	_ensure_subresources(draft)
	selected_path = path
	fingerprint = io.fingerprint(path)
	dirty = false
	_refresh_list()
	_rebuild()

func _ensure_subresources(target: CharacterData) -> void:
	if target == null:
		return
	if target.primary_stats == null:
		target.primary_stats = PrimaryStatsData.new()
	if target.growth_modifiers == null:
		target.growth_modifiers = PrimaryStatsData.new()
	if target.equipment_rules == null:
		target.equipment_rules = CharacterEquipmentRules.new()
	if target.combat_rules == null:
		target.combat_rules = CharacterCombatRules.new()

func _unique_id(prefix: String) -> String:
	var used: Dictionary = {}
	for path in _ordered_character_paths():
		var item := load(path) as CharacterData
		if item != null:
			used[item.id] = true
	var candidate := prefix
	var suffix := 2
	while used.has(candidate) or FileAccess.file_exists(DIRECTORY.path_join(candidate + ".tres")):
		candidate = "%s_%d" % [prefix, suffix]
		suffix += 1
	return candidate

func _new_character() -> void:
	draft = CharacterData.new()
	draft.id = _unique_id("new_character")
	draft.display_name = "新角色"
	draft.portrait = load("res://assets/art/wanderer.svg") as Texture2D
	_ensure_subresources(draft)
	selected_path = ""
	fingerprint = ""
	dirty = true
	_refresh_list()
	_rebuild()

func _copy_character() -> void:
	if draft == null:
		_show("请先在左侧列表选择一个要复制的角色。")
		return
	draft = io.copy_definition(draft) as CharacterData
	_ensure_subresources(draft)
	draft.id = _unique_id(draft.id + "_copy")
	draft.display_name += " 副本"
	selected_path = ""
	fingerprint = ""
	dirty = true
	_refresh_list()
	_rebuild()

func _reload() -> void:
	if not selected_path.is_empty():
		_open(selected_path)
	else:
		draft = null
		dirty = false
		_rebuild()

func _refresh() -> void:
	_refresh_list()
	if not selected_path.is_empty():
		_open(selected_path)
	elif list.item_count > 0:
		_open(str(list.get_item_metadata(0)))
	else:
		_reload()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

func _ordered_character_paths() -> Array[String]:
	var raw_paths := io.resource_paths(DIRECTORY)
	var default_path := DIRECTORY.path_join("wanderer.tres")
	var ordered: Array[String] = []
	if raw_paths.has(default_path):
		ordered.append(default_path)
	for path in raw_paths:
		if path != default_path:
			ordered.append(path)
	return ordered

func _refresh_list() -> void:
	if list == null:
		return
	list.clear()
	var query := _search.text.strip_edges().to_lower() if is_instance_valid(_search) else ""
	var filter_idx := _filter.selected if is_instance_valid(_filter) else 0
	for path in _ordered_character_paths():
		var item := load(path) as CharacterData
		if item == null:
			continue
		if filter_idx == 1 and item.id != "wanderer":
			continue
		if filter_idx == 2 and item.id == "wanderer":
			continue
		var slots_count := item.equipment_rules.slots if item.equipment_rules != null else 2
		var label := "%s [%s]\nHP %.0f · 移速 %.1f · %d 武器槽" % [item.display_name, item.id, item.max_health, item.movement_units, slots_count]
		if not query.is_empty() and not label.to_lower().contains(query) and not item.description.to_lower().contains(query):
			continue
		list.add_item(label)
		var index := list.item_count - 1
		list.set_item_metadata(index, path)
		list.set_item_tooltip(index, (item.description + "\n" if not item.description.is_empty() else "") + path)
		if path == selected_path:
			list.select(index)

func _rebuild() -> void:
	for tab in [form, _equipment_tab, _mechanics_tab, _combat_tab]:
		_clear(tab)
	if is_instance_valid(_tabs):
		_tabs.visible = draft != null
	if draft == null:
		status.text = "选择左侧角色，或点击「新建角色」。"
		if is_instance_valid(_validation):
			_validation.text = "所有编辑均在独立草稿中进行，点击「保存角色」后写入资源文件。"
		return
	_ensure_subresources(draft)
	_build_basics_tab()
	_build_equipment_tab()
	_build_mechanics_tab()
	_build_combat_tab()
	_update_status()

func _build_basics_tab() -> void:
	fields.text(form, "角色 ID", draft, "id")
	fields.text(form, "显示名称", draft, "display_name")
	fields.text(form, "角色特性说明", draft, "description", true)
	fields.texture(form, "角色肖像", draft, "portrait")
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(96, 88)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	form.add_child(_preview)
	fields.number(form, "基础最大生命", draft, "max_health", 1, 1)
	fields.number(form, "基础移动数值", draft, "movement_units", 0, 0.1)
	_speed_note = fields.note(form, "")
	form.add_child(HSeparator.new())
	fields.note(form, "初始主属性加成：相对基础生命（100）和基础移速（5）的起始修正；百分比以百分点输入。")
	for id in PlayerPrimaryStats.IDS:
		var field := fields.number(form, PlayerPrimaryStats.label(id), draft.primary_stats, id, -100000, 1)
		if PlayerPrimaryStats.PERCENT_IDS.has(id):
			field.suffix = "%"
	form.add_child(HSeparator.new())
	fields.note(form, "成长倍率修正：仅作用于后续升级和遗物增减，0% 为正常，-100% 为无效，+50% 为 1.5 倍。")
	for id in PlayerPrimaryStats.IDS:
		var field := fields.number(form, PlayerPrimaryStats.label(id) + " 成长修正", draft.growth_modifiers, id, -100, 1)
		field.suffix = "%"

func _build_equipment_tab() -> void:
	fields.note(_equipment_tab, "装备规则：武器槽数量、允许武器类别、稀有度范围和重复装备限制。")
	var rules := draft.equipment_rules
	var slots: SpinBox = fields.number(_equipment_tab, "武器槽数量", rules, "slots", 0, 1)
	slots.max_value = 24
	slots.allow_greater = false
	fields.toggle(_equipment_tab, "允许近战武器", rules, "allow_melee")
	fields.toggle(_equipment_tab, "允许远程武器", rules, "allow_ranged")
	fields.toggle(_equipment_tab, "允许施法武器", rules, "allow_spell")
	fields.toggle(_equipment_tab, "允许重复武器", rules, "allow_duplicates")
	var min_tier: SpinBox = fields.number(_equipment_tab, "最低稀有度", rules, "minimum_rarity", 1, 1)
	min_tier.max_value = 5
	min_tier.allow_greater = false
	var max_tier: SpinBox = fields.number(_equipment_tab, "最高稀有度", rules, "maximum_rarity", 1, 1)
	max_tier.max_value = 5
	max_tier.allow_greater = false
	_equipment_tab.add_child(HSeparator.new())
	fields.note(_equipment_tab, "固定开局物品：填写已保存的玩家物品 ID（逗号分隔）；未填满的空武器槽仍由玩家在开局界面自选。")
	_packed_field(_equipment_tab, "固定开局武器 ID", "starting_weapons")
	_packed_field(_equipment_tab, "固定开局遗物 ID", "starting_relics")
	_equipment_tab.add_child(HSeparator.new())
	fields.note(_equipment_tab, "角色专属主动技能（战斗中通过独立快捷键 E / 空格 释放）：")
	var skill_picker := OptionButton.new()
	skill_picker.name = "skill_picker"
	skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_picker.add_item("不携带角色专属技能")
	skill_picker.set_item_metadata(0, "")
	var current_skill_path := draft.skill.resource_path if draft.skill != null else ""
	var selected_skill_idx := 0
	for skill_path in io.resource_paths(IO.SKILL_DIR):
		if Engine.is_editor_hint() and not io.dependencies_ready(skill_path, {}): continue
		var sk := load(skill_path) as SkillData
		if sk == null: continue
		skill_picker.add_item("%s [%s] · %s" % [sk.display_name, sk.id, SkillData.kind_label(sk.kind)])
		var s_idx := skill_picker.item_count - 1
		skill_picker.set_item_metadata(s_idx, skill_path)
		skill_picker.set_item_tooltip(s_idx, skill_path)
		if skill_path == current_skill_path: selected_skill_idx = s_idx
	skill_picker.select(selected_skill_idx)
	skill_picker.item_selected.connect(func(idx: int):
		var s_path := str(skill_picker.get_item_metadata(idx))
		draft.skill = load(s_path) as SkillData if not s_path.is_empty() else null
		_changed()
		_rebuild.call_deferred())
	fields.row(_equipment_tab, "角色专属技能", skill_picker)
	var skill_actions := HFlowContainer.new()
	_equipment_tab.add_child(skill_actions)
	fields.button(skill_actions, "打开技能编辑器", func():
		if not Engine.is_editor_hint(): return
		if draft.skill != null and not draft.skill.resource_path.contains("::"):
			EditorInterface.edit_resource(draft.skill)
		EditorInterface.set_main_screen_editor("Skill Editor"))
	if draft.skill != null:
		fields.note(_equipment_tab, "%s\n%s" % [draft.skill.summary_text(), draft.skill.description])
	_equipment_tab.add_child(HSeparator.new())
	fields.note(_equipment_tab, "武器标签加成：仅作用于持有对应标签（如 Precise、Heavy、Gun、Magic）的武器。")
	for index in draft.weapon_bonuses.size():
		var bonus := draft.weapon_bonuses[index]
		var block := VBoxContainer.new()
		_equipment_tab.add_child(block)
		fields.text(block, "武器标签", bonus, "tag")
		for property in ["attack_speed", "weapon_range", "damage", "crit_chance", "life_steal"]:
			fields.number(block, PlayerPrimaryStats.label(property), bonus, property, -100000, 1)
		fields.button(block, "删除武器标签加成", func():
			draft.weapon_bonuses.remove_at(index)
			_changed()
			_rebuild.call_deferred())
	fields.button(_equipment_tab, "添加武器标签加成", func():
		draft.weapon_bonuses.append(CharacterWeaponBonus.new())
		_changed()
		_rebuild.call_deferred())
	_equipment_tab.add_child(HSeparator.new())
	fields.note(_equipment_tab, "按武器数量、不同武器数量或空槽数量动态增加主属性。")
	for index in draft.equipment_stat_bonuses.size():
		var bonus := draft.equipment_stat_bonuses[index]
		var block := VBoxContainer.new()
		_equipment_tab.add_child(block)
		var sources: Array[String] = ["武器数量", "不同武器数量", "空槽数量"]
		fields.choice(block, "计数对象", bonus, "source", sources)
		var picker := OptionButton.new()
		for id in PlayerPrimaryStats.IDS:
			picker.add_item(PlayerPrimaryStats.label(id))
		picker.select(PlayerPrimaryStats.IDS.find(bonus.target))
		picker.item_selected.connect(func(selection: int):
			bonus.target = PlayerPrimaryStats.IDS[selection]
			_changed())
		fields.row(block, "影响属性", picker)
		fields.number(block, "每个对象的加成", bonus, "amount_per_unit", -100000, 0.1)
		fields.button(block, "删除数量加成", func():
			draft.equipment_stat_bonuses.remove_at(index)
			_changed()
			_rebuild.call_deferred())
	fields.button(_equipment_tab, "添加数量加成", func():
		draft.equipment_stat_bonuses.append(EquipmentStatBonus.new())
		_changed()
		_rebuild.call_deferred())

func _build_mechanics_tab() -> void:
	fields.note(_mechanics_tab, "属性换算：目标增加来源属性 × 系数。为避免循环计算，不能建立直接或间接循环。")
	for index in draft.stat_conversions.size():
		var rule := draft.stat_conversions[index]
		var row := HBoxContainer.new()
		_mechanics_tab.add_child(row)
		for property in ["source", "target"]:
			var picker := OptionButton.new()
			for id in PlayerPrimaryStats.IDS:
				picker.add_item(PlayerPrimaryStats.label(id))
			picker.select(PlayerPrimaryStats.IDS.find(rule.get(property)))
			picker.item_selected.connect(func(selection: int):
				rule.set(property, PlayerPrimaryStats.IDS[selection])
				_changed())
			row.add_child(picker)
		var factor := SpinBox.new()
		factor.min_value = -1000
		factor.max_value = 1000
		factor.step = 0.01
		factor.value = rule.factor
		factor.value_changed.connect(func(value: float):
			rule.factor = value
			_changed())
		row.add_child(factor)
		var step := SpinBox.new()
		step.min_value = 0
		step.max_value = 10000
		step.step = 0.1
		step.suffix = " 每 N 点"
		step.value = rule.source_step
		step.value_changed.connect(func(value: float):
			rule.source_step = value
			_changed())
		row.add_child(step)
		fields.button(row, "删除", func():
			draft.stat_conversions.remove_at(index)
			_changed()
			_rebuild.call_deferred())
	fields.button(_mechanics_tab, "添加属性换算", func():
		draft.stat_conversions.append(StatConversionData.new())
		_changed()
		_rebuild.call_deferred())
	_mechanics_tab.add_child(HSeparator.new())
	fields.note(_mechanics_tab, "条件加成：移动、静止或生命低于指定比例时生效。")
	for index in draft.conditional_bonuses.size():
		var bonus := draft.conditional_bonuses[index]
		var row := HBoxContainer.new()
		_mechanics_tab.add_child(row)
		var stat_picker := OptionButton.new()
		for id in PlayerPrimaryStats.IDS:
			stat_picker.add_item(PlayerPrimaryStats.label(id))
		stat_picker.select(PlayerPrimaryStats.IDS.find(bonus.stat))
		stat_picker.item_selected.connect(func(selection: int):
			bonus.stat = PlayerPrimaryStats.IDS[selection]
			_changed())
		row.add_child(stat_picker)
		var condition_picker := OptionButton.new()
		for label in ["移动", "静止", "低生命"]:
			condition_picker.add_item(label)
		condition_picker.select(bonus.condition)
		condition_picker.item_selected.connect(func(selection: int):
			bonus.condition = selection
			_changed())
		row.add_child(condition_picker)
		var amount := SpinBox.new()
		amount.min_value = -10000
		amount.max_value = 10000
		amount.value = bonus.amount
		amount.value_changed.connect(func(value: float):
			bonus.amount = value
			_changed())
		row.add_child(amount)
		var fraction := SpinBox.new()
		fraction.min_value = 0
		fraction.max_value = 100
		fraction.suffix = "% 生命"
		fraction.value = bonus.health_fraction * 100.0
		fraction.value_changed.connect(func(value: float):
			bonus.health_fraction = value / 100.0
			_changed())
		row.add_child(fraction)
		fields.button(row, "删除", func():
			draft.conditional_bonuses.remove_at(index)
			_changed()
			_rebuild.call_deferred())
	fields.button(_mechanics_tab, "添加条件加成", func():
		draft.conditional_bonuses.append(ConditionalStatBonus.new())
		_changed()
		_rebuild.call_deferred())
	_mechanics_tab.add_child(HSeparator.new())
	fields.note(_mechanics_tab, "角色事件：升级、受伤、回血、闪避、拾取、战斗结束或战斗中的每秒触发。")
	for index in draft.event_effects.size():
		var effect := draft.event_effects[index]
		var block := VBoxContainer.new()
		_mechanics_tab.add_child(block)
		var triggers: Array[String] = ["升级", "受伤", "回血", "闪避", "拾取材料", "拾取消耗品", "战斗结束", "战斗每秒", "击杀敌人", "暴击", "移动一步", "击杀 BOSS"]
		var effects: Array[String] = ["增加属性", "回血", "自身受伤", "伤害随机敌人", "获得金币"]
		fields.choice(block, "触发条件", effect, "trigger", triggers)
		fields.choice(block, "效果", effect, "effect", effects)
		var stat_picker := OptionButton.new()
		for id in PlayerPrimaryStats.IDS:
			stat_picker.add_item(PlayerPrimaryStats.label(id))
		stat_picker.select(PlayerPrimaryStats.IDS.find(effect.stat))
		stat_picker.item_selected.connect(func(selection: int):
			effect.stat = PlayerPrimaryStats.IDS[selection]
			_changed())
		fields.row(block, "影响属性", stat_picker)
		fields.number(block, "效果数值", effect, "amount", -100000, 0.1)
		fields.number(block, "每 N 次触发", effect, "every_n", 1, 1)
		var chance: SpinBox = fields.number(block, "触发概率", effect, "probability", 0, 1, true)
		chance.max_value = 100
		chance.allow_greater = false
		fields.toggle(block, "战斗结束清除加成", effect, "temporary_until_combat_end")
		fields.toggle(block, "仅在满生命时触发", effect, "only_at_full_health")
		fields.button(block, "删除事件", func():
			draft.event_effects.remove_at(index)
			_changed()
			_rebuild.call_deferred())
	fields.button(_mechanics_tab, "添加角色事件", func():
		draft.event_effects.append(CharacterEventEffect.new())
		_changed()
		_rebuild.call_deferred())

func _build_combat_tab() -> void:
	fields.note(_combat_tab, "战斗与经济倍率：100% 为默认值；敌人数量按每组条目计算，小数部分按概率生成。")
	var combat := draft.combat_rules
	var labels := {
		"xp_gain_multiplier": "经验获得倍率", "xp_requirement_multiplier": "升级所需经验倍率",
		"material_gain_multiplier": "金币获得倍率", "enemy_material_multiplier": "敌人金币掉落倍率", "item_price_multiplier": "遗物价格倍率", "weapon_price_multiplier": "武器价格倍率",
		"enemy_count_multiplier": "敌人数量倍率", "enemy_health_multiplier": "敌人生命倍率", "enemy_damage_multiplier": "敌人伤害倍率", "enemy_speed_multiplier": "敌人速度倍率",
		"pickup_range_multiplier": "拾取范围倍率", "dodge_cap": "闪避上限", "elite_boss_damage_multiplier": "对精英和 BOSS 伤害倍率"
	}
	for property in labels:
		fields.number(_combat_tab, labels[property], combat, property, 0, 1, true)
	fields.number(_combat_tab, "消耗品额外治疗", combat, "consumable_heal_bonus", -1000, 1)
	fields.toggle(_combat_tab, "允许回血", combat, "can_heal")
	fields.toggle(_combat_tab, "被命中即死亡", combat, "one_hit_death")
	var excluded := LineEdit.new()
	excluded.text = ", ".join(combat.excluded_relic_tags)
	excluded.text_changed.connect(func(value: String):
		var tags := PackedStringArray()
		for part in value.split(",", false):
			if not part.strip_edges().is_empty():
				tags.append(part.strip_edges())
		combat.excluded_relic_tags = tags
		_changed())
	fields.row(_combat_tab, "商店和宝箱排除的遗物标签", excluded)
	fields.toggle(_combat_tab, "允许移动时攻击", combat, "can_attack_while_moving")
	fields.number(_combat_tab, "收获增长额外比例", combat, "harvesting_growth_bonus", -100, 1, true)
	fields.toggle(_combat_tab, "升级增加武器槽而非属性选择", combat, "gain_weapon_slot_on_level")
	var max_slots: SpinBox = fields.number(_combat_tab, "升级增加武器槽上限", combat, "maximum_weapon_slots", 1, 1)
	max_slots.max_value = 24
	max_slots.allow_greater = false
	var tree_count: SpinBox = fields.number(_combat_tab, "可破坏树木数量", combat, "environment_tree_count", 0, 1)
	tree_count.max_value = 50
	tree_count.allow_greater = false
	fields.number(_combat_tab, "每棵存活树木的生命再生", combat, "tree_hp_regeneration", -10000, 0.1)
	fields.number(_combat_tab, "战斗结束每棵树的金币", combat, "tree_materials_at_combat_end", 0, 1)
	fields.number(_combat_tab, "战斗结束每棵树的经验", combat, "tree_xp_at_combat_end", 0, 1)
	var arena_size: SpinBox = fields.number(_combat_tab, "竞技场尺寸倍率", combat, "arena_size_multiplier", 50, 1, true)
	arena_size.max_value = 200
	arena_size.allow_greater = false

func _packed_field(parent: Node, label: String, property: String) -> void:
	var input := LineEdit.new()
	input.text = ", ".join(draft.get(property))
	input.text_changed.connect(func(value: String):
		var result := PackedStringArray()
		for part in value.split(",", false):
			if not part.strip_edges().is_empty():
				result.append(part.strip_edges())
		draft.set(property, result)
		_changed())
	fields.row(parent, label, input)

func validate_draft() -> PackedStringArray:
	var errors := PackedStringArray()
	if draft == null:
		errors.append("尚未选择角色。")
		return errors
	if selected_path.ends_with("/wanderer.tres") and draft.id != "wanderer":
		errors.append("默认角色 ID 用于新旅程，不能更改；请复制为新角色。")
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(draft.id) == null or not draft.id.is_valid_filename() or draft.display_name.strip_edges().is_empty():
		errors.append("角色 ID 须以小写字母开头，仅包含小写字母、数字和下划线；名称不能为空。")
	if not is_finite(draft.max_health) or draft.max_health <= 0 or not is_finite(draft.movement_units) or draft.movement_units < 0:
		errors.append("基础生命须大于零，移动数值须非负。")
	for id in PlayerPrimaryStats.IDS:
		if not is_finite(float(draft.primary_stats.get(id))):
			errors.append("主属性必须为有限数值。")
			break
		if draft.growth_modifiers != null and (not is_finite(float(draft.growth_modifiers.get(id))) or float(draft.growth_modifiers.get(id)) < -100):
			errors.append("成长倍率修正必须为有限数值且不低于 -100%。")
			break
	for rule in draft.stat_conversions:
		if rule == null or rule.source not in PlayerPrimaryStats.IDS or rule.target not in PlayerPrimaryStats.IDS or not is_finite(rule.factor) or not is_finite(rule.source_step) or rule.source_step < 0 or _conversion_cycle(rule.source, rule.target, {}):
			errors.append("属性换算无效或存在循环。")
			break
	for bonus in draft.conditional_bonuses:
		if bonus == null or bonus.stat not in PlayerPrimaryStats.IDS or bonus.condition not in [0, 1, 2] or not is_finite(bonus.amount) or not is_finite(bonus.health_fraction) or bonus.health_fraction < 0 or bonus.health_fraction > 1:
			errors.append("条件加成配置无效。")
			break
	for effect in draft.event_effects:
		if effect == null or effect.trigger not in range(12) or effect.effect not in range(5) or effect.stat not in PlayerPrimaryStats.IDS or effect.every_n < 1 or not is_finite(effect.amount) or not is_finite(effect.probability) or effect.probability < 0 or effect.probability > 1 or (effect.effect != CharacterEventEffect.Effect.ADD_STAT and effect.amount < 0):
			errors.append("角色事件配置无效。")
			break
	for bonus in draft.weapon_bonuses:
		if bonus == null or bonus.tag.strip_edges().is_empty():
			errors.append("武器标签加成必须指定标签。")
			break
		for property in ["attack_speed", "weapon_range", "damage", "crit_chance", "life_steal"]:
			if not is_finite(float(bonus.get(property))):
				errors.append("武器标签加成必须为有限数值。")
				break
	for bonus in draft.equipment_stat_bonuses:
		if bonus == null or bonus.source not in range(3) or bonus.target not in PlayerPrimaryStats.IDS or not is_finite(bonus.amount_per_unit):
			errors.append("装备数量加成配置无效。")
			break
	var initial := ActorLoadout.new(ItemDefinition.Recipient.PLAYER, 2, -1, draft.equipment_rules)
	for id in draft.starting_weapons:
		var equipped := false
		for slot in initial.equipment.size():
			if initial.equipment[slot] == null and initial.equip(ContentCatalog.weapon(id), slot):
				equipped = true
				break
		if not equipped:
			errors.append("固定武器不存在、没有可用槽位或违反装备限制：" + id)
	for id in draft.starting_relics:
		if not initial.add_relic(ContentCatalog.relic(id)):
			errors.append("固定遗物不存在或超出其上限：" + id)
	if draft.equipment_rules != null:
		var rules := draft.equipment_rules
		if rules.slots < 0 or rules.slots > 24 or rules.minimum_rarity < 1 or rules.maximum_rarity > 5 or rules.minimum_rarity > rules.maximum_rarity:
			errors.append("武器槽数量或稀有度范围无效。")
	if draft.combat_rules != null:
		if not is_finite(draft.combat_rules.harvesting_growth_bonus) or draft.combat_rules.harvesting_growth_bonus < -1:
			errors.append("收获增长额外比例无效。")
		if draft.combat_rules.environment_tree_count < 0 or draft.combat_rules.environment_tree_count > 50 or draft.combat_rules.maximum_weapon_slots < 1 or draft.combat_rules.maximum_weapon_slots > 24 or not is_finite(draft.combat_rules.tree_hp_regeneration) or draft.combat_rules.tree_materials_at_combat_end < 0 or draft.combat_rules.tree_xp_at_combat_end < 0 or not is_finite(draft.combat_rules.arena_size_multiplier) or draft.combat_rules.arena_size_multiplier < 0.5 or draft.combat_rules.arena_size_multiplier > 2.0:
			errors.append("环境树木或竞技场尺寸规则无效。")
		for property in ["xp_gain_multiplier", "xp_requirement_multiplier", "material_gain_multiplier", "enemy_material_multiplier", "item_price_multiplier", "weapon_price_multiplier", "enemy_count_multiplier", "enemy_health_multiplier", "enemy_damage_multiplier", "enemy_speed_multiplier", "pickup_range_multiplier", "dodge_cap", "elite_boss_damage_multiplier"]:
			var value: float = draft.combat_rules.get(property)
			if not is_finite(value) or value < 0 or (property == "dodge_cap" and value > 1) or (property == "enemy_health_multiplier" and value <= 0):
				errors.append("战斗与经济倍率无效。")
				break
	for path in io.resource_paths(DIRECTORY):
		var existing := load(path) as CharacterData
		if path != selected_path and existing != null and existing.id == draft.id:
			errors.append("角色 ID 已存在：" + path)
	return errors

func _update_status() -> void:
	if draft == null:
		return
	status.text = ("新角色（尚未保存）" if selected_path.is_empty() else selected_path) + ("  ● 有未保存修改" if dirty else "  ✓ 已保存")
	if is_instance_valid(_preview):
		_preview.texture = draft.portrait
	if is_instance_valid(_speed_note):
		var speed_pct := float(draft.primary_stats.speed) if draft.primary_stats != null else 0.0
		var actual_px := draft.movement_units * ContentCatalog.PIXELS_PER_UNIT * ContentCatalog.PLAYER_STARTING_SPEED_MULTIPLIER * maxf(0.0, 1.0 + speed_pct / 100.0)
		_speed_note.text = "基础移速 %.1f 单位（×24×1.5），结合初始移速加成 %+.0f%% 后实际开局移速 %.1f 像素/秒。" % [draft.movement_units, speed_pct, actual_px]
	if is_instance_valid(_validation):
		var errors := validate_draft()
		_validation.text = "配置有效。保存后角色将立即同步至「选择角色」界面。" if errors.is_empty() else "配置问题（%d）：\n• %s" % [errors.size(), "\n• ".join(errors)]
		_validation.modulate = Color("#aadbb6") if errors.is_empty() else Color("#f5bd8a")

func save_current(show_result: bool = false) -> bool:
	if draft == null:
		return false
	var errors := validate_draft()
	if not errors.is_empty():
		_show("\n".join(errors))
		return false
	var path := selected_path if not selected_path.is_empty() else DIRECTORY.path_join(draft.id + ".tres")
	if selected_path.is_empty() and FileAccess.file_exists(path):
		_show("目标文件已存在：" + path)
		return false
	if not selected_path.is_empty() and (not FileAccess.file_exists(path) or io.fingerprint(path) != fingerprint):
		_show("文件已被其他位置修改或删除，请重新载入。")
		return false
	var creating := selected_path.is_empty()
	var target: CharacterData = io.copy_definition(draft) as CharacterData if creating else load(path) as CharacterData
	var backup := io.copy_definition(target)
	io._assign(draft, target)
	var result := ResourceSaver.save(target, path)
	if result != OK:
		io._assign(backup, target)
		_show("保存失败：" + error_string(result))
		return false
	if creating:
		target.take_over_path(path)
	target.emit_changed()
	selected_path = path
	fingerprint = io.fingerprint(path)
	dirty = false
	_refresh_list()
	_update_status()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	if show_result:
		_show("角色已保存：" + path)
	return true

func _conversion_cycle(source: String, current: String, visited: Dictionary) -> bool:
	if source == current:
		return true
	if visited.has(current):
		return false
	visited[current] = true
	for rule in draft.stat_conversions:
		if rule != null and rule.source == current and _conversion_cycle(source, rule.target, visited):
			return true
	return false

func _references() -> void:
	if selected_path.is_empty():
		_show("新角色尚未保存，没有资源引用。")
		return
	var references := io.references(selected_path)
	_show("暂无资源引用。" if references.is_empty() else "以下资源引用此角色：\n" + "\n".join(references))

func _request_delete() -> void:
	if selected_path.is_empty():
		_show("请先在左侧选择已保存的角色。")
		return
	if selected_path.ends_with("/wanderer.tres"):
		_show("默认角色「旅人」用于新旅程，不能删除。")
		return
	confirm_delete.dialog_text = "确定永久删除角色资源 " + selected_path + " 吗？"
	confirm_delete.popup_centered()

func _delete() -> void:
	if selected_path.is_empty():
		return
	if selected_path.ends_with("/wanderer.tres"):
		_show("默认角色「旅人」用于新旅程，不能删除。")
		return
	var refs := io.references(selected_path)
	if not refs.is_empty():
		_show("角色仍被以下资源引用：\n" + "\n".join(refs))
		return
	if io.fingerprint(selected_path) != fingerprint:
		_show("文件已被修改，请重新载入。")
		return
	var result := DirAccess.remove_absolute(ProjectSettings.globalize_path(selected_path))
	if result != OK:
		_show(error_string(result))
		return
	selected_path = ""
	draft = null
	dirty = false
	_refresh_list()
	if list.item_count > 0:
		_open(str(list.get_item_metadata(0)))
	else:
		_rebuild()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

func _show(text: String) -> void:
	message.dialog_text = text
	if is_inside_tree():
		message.popup_centered(Vector2i(580, 200))

func _choose_texture(target: Resource, property: String, label: LineEdit) -> void:
	texture_target = target
	texture_property = property
	texture_label = label
	files.popup_centered_ratio(0.7)

func _texture_selected(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		_show("请选择有效的 Texture2D 纹理资源。")
		return
	texture_target.set(texture_property, texture)
	texture_label.text = path
	_changed()
