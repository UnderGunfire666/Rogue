@tool
extends VBoxContainer
## Full custom editor: no dependency on the Inspector for authoring.

const Store = preload("res://addons/enemy_editor/enemy_editor_store.gd")
const Fields = preload("res://addons/enemy_editor/enemy_form_fields.gd")
const ItemStore = preload("res://addons/content_editor/item_editor_store.gd")
var store := Store.new()
var fields := Fields.new()
var draft: EnemyData
var selected_path := ""
var _fingerprint := ""
var _dirty := false
var _pending_action: Callable
var _pending_delete := ""
var _texture_target: Resource
var _texture_property := ""
var _texture_label: LineEdit
var _search: LineEdit
var _filter: OptionButton
var _list: ItemList
var _status: Label
var _validation: RichTextLabel
var _tabs: TabContainer
var _basics: VBoxContainer
var _equipment: VBoxContainer
var _relic: VBoxContainer
var _skill: VBoxContainer
var _preview: TextureRect
var _statistics: Label
var _equipment_picker: OptionButton
var _relic_picker: OptionButton
var _skill_picker: OptionButton
var _message: AcceptDialog
var _discard_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _file_dialog: FileDialog

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	fields.changed = _changed
	fields.choose_texture = _choose_texture
	_build_ui()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_refresh_items_deferred)
	_refresh_list()
	_rebuild_forms()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var heading := Label.new()
	heading.text = "敌人编辑器  /  ENEMY EDITOR"
	heading.add_theme_font_size_override("font_size", 21)
	layout.add_child(heading)
	var toolbar := HFlowContainer.new()
	layout.add_child(toolbar)
	fields.button(toolbar, "新建敌人", func(): _guard(_new_enemy))
	fields.button(toolbar, "复制为新敌人", _duplicate_enemy)
	fields.button(toolbar, "保存敌人", func(): save_current())
	fields.button(toolbar, "放弃修改 / 重新载入", func(): _guard(_reload_current))
	fields.button(toolbar, "查看引用", _show_references)
	fields.button(toolbar, "删除敌人", _request_delete)
	fields.button(toolbar, "刷新资源库", func(): _guard(_refresh_library))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 230
	layout.add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 180
	split.add_child(library)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称、ID…"
	_search.text_changed.connect(func(_text: String): _refresh_list())
	library.add_child(_search)
	_filter = OptionButton.new()
	for label in ["全部类别", "普通 Normal", "精英 Elite", "BOSS"]:
		_filter.add_item(label)
	_filter.item_selected.connect(func(_index: int): _refresh_list())
	library.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int): request_open(str(_list.get_item_metadata(index))))
	library.add_child(_list)
	fields.note(library, "创建后需将敌人加入 Enemy Group；BOSS 在 Encounter 中单独配置。")
	var editing := VBoxContainer.new()
	editing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editing)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editing.add_child(_tabs)
	_basics = _create_tab("基础与外观")
	_equipment = _create_tab("装备与攻击")
	_relic = _create_tab("遗物与被动")
	_skill = _create_tab("主动技能")
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = false
	_validation.custom_minimum_size.y = 100
	_validation.size_flags_vertical = Control.SIZE_FILL
	editing.add_child(_validation)
	_message = AcceptDialog.new()
	_message.title = "敌人编辑器"
	add_child(_message)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "放弃未保存修改？"
	_discard_dialog.dialog_text = "当前草稿有未保存修改。继续将放弃这些修改。"
	_discard_dialog.confirmed.connect(func():
		var action := _pending_action
		_pending_action = Callable()
		if action.is_valid(): action.call())
	_discard_dialog.canceled.connect(_refresh_list)
	add_child(_discard_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除敌人资源"
	_delete_dialog.confirmed.connect(_delete_confirmed)
	add_child(_delete_dialog)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.png,*.svg,*.webp,*.jpg,*.jpeg,*.tres,*.res ; Texture2D"])
	_file_dialog.file_selected.connect(_texture_selected)
	add_child(_file_dialog)

func _create_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	return content

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _rebuild_forms() -> void:
	for form in [_basics, _equipment, _relic, _skill]:
		_clear(form)
	_tabs.visible = draft != null
	if draft == null:
		_status.text = "选择左侧敌人，或点击“新建敌人”。"
		_validation.text = "所有编辑均在草稿中进行，点击保存后才会写入资源。"
		return
	_build_basics()
	_build_equipment()
	_build_relic()
	_build_skill()
	_update_status()

func _build_basics() -> void:
	fields.text(_basics, "敌人 ID", draft, "id")
	fields.text(_basics, "显示名称", draft, "display_name")
	fields.choice(_basics, "类别", draft, "category", ["普通 Normal", "精英 Elite", "BOSS"])
	fields.choice(_basics, "移动行为", draft, "movement", ["近战追击 Follow", "远程保持距离 Keep Distance", "施法类 Caster"])
	fields.number(_basics, "最大生命", draft, "max_health", 0.1, 1)
	fields.number(_basics, "固定移速（像素/秒）", draft, "movement_speed", 0.01, 1)
	fields.number(_basics, "安全距离（像素）", draft, "safety_distance", 0, 1)
	fields.toggle(_basics, "撤退时发起攻击", draft, "can_attack_while_retreating")
	fields.note(_basics, "保持距离行为采用第一个远程攻击的射程作为安全距离；没有远程攻击时采用上方安全距离。治疗在移动中继续生效，不受攻击开关影响。")
	fields.texture(_basics, "敌人贴图", draft, "texture")
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(120, 110)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_basics.add_child(_preview)
	_statistics = fields.note(_basics, "")
	fields.number(_basics, "击败经验奖励", draft, "experience_reward", 0, 1)
	fields.number(_basics, "击败金币奖励", draft, "gold_reward", 0, 1)
	fields.number(_basics, "击败金币碎片（0 按金币×10）", draft, "fragment_reward", 0, 1)
	var consumable := fields.number(_basics, "消耗品基础掉落率", draft, "consumable_drop_chance", 0, 1, true)
	consumable.max_value = 100
	consumable.allow_greater = false
	var crate := fields.number(_basics, "遗物箱基础掉落率", draft, "relic_drop_chance", 0, 1, true)
	crate.max_value = 100
	crate.allow_greater = false

func _build_equipment() -> void:
	fields.note(_equipment, "从装备库选择已保存的敌人装备。每个敌人装备一件；装备属性在 Equipment Editor 中修改。")
	_equipment_picker = _item_picker(_equipment, Store.EQUIPMENT_DIR, draft.equipment, true)
	_equipment_picker.name = "equipment_picker"
	_equipment_picker.item_selected.connect(_select_equipment)
	var actions := HFlowContainer.new()
	_equipment.add_child(actions)
	fields.button(actions, "打开装备编辑器", func(): _open_item_editor("Equipment Editor", draft.equipment))
	fields.button(actions, "刷新物品列表", _refresh_items)
	if draft.equipment == null:
		fields.note(_equipment, "尚未选择装备，保存敌人前需要选择一件。")
		return
	if not store.is_saved_item(draft.equipment, Store.EQUIPMENT_DIR):
		fields.note(_equipment, "当前为旧内嵌配置。请先将其保存为独立装备，再保存敌人。")
		fields.button(actions, "将旧配置存入装备库", func(): _export_old_item(draft.equipment, true))
	fields.note(_equipment, "%s [%s]\n%s\n%s" % [draft.equipment.display_name, draft.equipment.id, draft.equipment.description, draft.equipment.resource_path])
	for attack in draft.equipment.attacks:
		if attack == null:
			fields.note(_equipment, "攻击配置为空。")
		elif attack.kind == AttackProfileData.Kind.SPELL and attack.effect == AttackProfileData.Effect.HEAL:
			fields.note(_equipment, "施法·治疗：每秒 %.1f，最多 %d 目标，范围 %.1f" % [attack.healing_per_second, attack.target_count, attack.attack_range])
		elif attack.kind == AttackProfileData.Kind.RANGED:
			fields.note(_equipment, "远程：每弹 %.1f，%d 弹，发动范围 %.1f，间隔 %.2f 秒" % [attack.damage, attack.projectile_count, attack.attack_range, attack.attack_interval])
		else:
			fields.note(_equipment, "%s：伤害 %.1f，最多 %d 目标，范围 %.1f，间隔 %.2f 秒" % ["施法" if attack.kind == AttackProfileData.Kind.SPELL else "近战", attack.damage, attack.target_count, attack.attack_range, attack.attack_interval])

func _build_relic() -> void:
	fields.note(_relic, "从遗物库选择已保存的敌人遗物；也可选择不携带。遗物属性在 Relic Editor 中修改。")
	_relic_picker = _item_picker(_relic, Store.RELIC_DIR, draft.relic, false)
	_relic_picker.name = "relic_picker"
	_relic_picker.item_selected.connect(_select_relic)
	var actions := HFlowContainer.new()
	_relic.add_child(actions)
	fields.button(actions, "打开遗物编辑器", func(): _open_item_editor("Relic Editor", draft.relic))
	fields.button(actions, "刷新物品列表", _refresh_items)
	if draft.relic == null:
		fields.note(_relic, "不携带遗物。")
		return
	if not store.is_saved_item(draft.relic, Store.RELIC_DIR):
		fields.note(_relic, "当前为旧内嵌配置。请先将其保存为独立遗物，再保存敌人。")
		fields.button(actions, "将旧配置存入遗物库", func(): _export_old_item(draft.relic, false))
	fields.note(_relic, "%s [%s]\n%s\n%s" % [draft.relic.display_name, draft.relic.id, draft.relic.description, draft.relic.resource_path])
	fields.note(_relic, "每秒回血 %.1f；近战攻速 %+.1f%%；移速 %+.1f%%；伤害 %+.1f%%" % [draft.relic.regeneration, draft.relic.melee_attack_speed_bonus * 100.0, draft.relic.movement_bonus * 100.0, draft.relic.damage_bonus * 100.0])

func _build_skill() -> void:
	fields.note(_skill, "从技能库选择已保存的主动技能；也可选择不携带。敌人进入射程且冷却完毕时会自动蓄力/释放该技能。")
	_skill_picker = OptionButton.new()
	_skill_picker.name = "skill_picker"
	_skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_picker.add_item("不携带技能")
	_skill_picker.set_item_metadata(0, "")
	var current_path := draft.skill.resource_path if draft.skill != null else ""
	var selected := 0
	for path in store.resource_paths(Store.SKILL_DIR):
		if Engine.is_editor_hint() and not store.dependencies_ready(path, {}): continue
		var item := load(path) as SkillData
		if item == null: continue
		_skill_picker.add_item("%s [%s] · %s" % [item.display_name, item.id, SkillData.kind_label(item.kind)])
		var index := _skill_picker.item_count - 1
		_skill_picker.set_item_metadata(index, path)
		_skill_picker.set_item_tooltip(index, path)
		if path == current_path: selected = index
	_skill_picker.select(selected)
	_skill_picker.item_selected.connect(_select_skill)
	_skill.add_child(_skill_picker)
	var actions := HFlowContainer.new()
	_skill.add_child(actions)
	fields.button(actions, "打开技能编辑器", func(): _open_item_editor("Skill Editor", draft.skill))
	fields.button(actions, "刷新技能列表", _refresh_items)
	if draft.skill == null:
		fields.note(_skill, "不携带主动技能。")
		return
	fields.note(_skill, "%s\n%s\n%s" % [draft.skill.summary_text(), draft.skill.description, draft.skill.resource_path])

func _select_skill(index: int) -> void:
	var path := str(_skill_picker.get_item_metadata(index))
	if draft.skill != null and not path.is_empty() and path == draft.skill.resource_path: return
	draft.skill = load(path) as SkillData if not path.is_empty() else null
	_changed()
	_rebuild_skill.call_deferred()

func _item_picker(parent: Node, directory: String, current: ItemDefinition, equipment: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("请选择已保存的敌人装备" if equipment else "不携带遗物")
	picker.set_item_metadata(0, "")
	var current_path := current.resource_path if current != null else ""
	var selected := 0
	for path in store.resource_paths(directory):
		if Engine.is_editor_hint() and not store.dependencies_ready(path, {}): continue
		var item := load(path) as ItemDefinition
		if item == null or item.recipient != ItemDefinition.Recipient.ENEMY: continue
		if equipment and not item is EnemyEquipmentData: continue
		if not equipment and not item is RelicData: continue
		picker.add_item("%s [%s]" % [item.display_name, item.id])
		var index := picker.item_count - 1
		picker.set_item_metadata(index, path)
		picker.set_item_tooltip(index, path)
		if path == current_path: selected = index
	if current != null and selected == 0:
		picker.add_item("旧配置：%s（需保存为独立资源）" % current.display_name)
		selected = picker.item_count - 1
		picker.set_item_metadata(selected, current_path)
	picker.select(selected)
	parent.add_child(picker)
	return picker

func _select_equipment(index: int) -> void:
	var path := str(_equipment_picker.get_item_metadata(index))
	if draft.equipment != null and not path.is_empty() and path == draft.equipment.resource_path: return
	draft.equipment = load(path) as EnemyEquipmentData if not path.is_empty() else null
	_changed()
	_rebuild_equipment.call_deferred()

func _select_relic(index: int) -> void:
	var path := str(_relic_picker.get_item_metadata(index))
	if draft.relic != null and not path.is_empty() and path == draft.relic.resource_path: return
	draft.relic = load(path) as RelicData if not path.is_empty() else null
	_changed()
	_rebuild_relic.call_deferred()

func _open_item_editor(editor_name: String, item: Resource) -> void:
	if not Engine.is_editor_hint(): return
	if item != null and not item.resource_path.contains("::"):
		EditorInterface.edit_resource(item)
	EditorInterface.set_main_screen_editor(editor_name)

func _export_old_item(item: ItemDefinition, equipment: bool) -> void:
	var library := ItemStore.new()
	library.kind = "equipment" if equipment else "relic"
	var saved_item := store.copy_definition(item) as ItemDefinition
	saved_item.recipient = ItemDefinition.Recipient.ENEMY
	saved_item.id = library.unique_id("imported_equipment" if equipment else "imported_relic", saved_item.recipient)
	var result := library.save_item(saved_item, "")
	if not result.ok:
		_notify("保存独立物品失败：\n" + str(result.message))
		return
	if equipment:
		draft.equipment = load(str(result.path)) as EnemyEquipmentData
	else:
		draft.relic = load(str(result.path)) as RelicData
	_changed()
	_refresh_items()
	_scan_editor()
	_notify("已保存到物品库：\n" + str(result.path) + "\n请继续保存敌人以建立引用。")

func _refresh_items_deferred() -> void:
	_refresh_items.call_deferred()

func _refresh_items() -> void:
	if draft == null: return
	_rebuild_equipment()
	_rebuild_relic()
	_rebuild_skill()
	_update_status()
func _rebuild_equipment() -> void:
	_clear(_equipment)
	_build_equipment()

func _rebuild_relic() -> void:
	_clear(_relic)
	_build_relic()

func _rebuild_skill() -> void:
	_clear(_skill)
	_build_skill()

func _refresh_list() -> void:
	_list.clear()
	for path in store.resource_paths(Store.ENEMY_DIR):
		var enemy := load(path) as EnemyData
		if enemy == null: continue
		var label := "%s\n[%s] · %s" % [enemy.display_name, enemy.id, ["普通", "精英", "BOSS"][clampi(enemy.category, 0, 2)]]
		if _filter.selected > 0 and enemy.category != _filter.selected - 1: continue
		if not _search.text.is_empty() and not label.to_lower().contains(_search.text.to_lower()): continue
		_list.add_item(label)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, path)
		if path == selected_path: _list.select(index)

func request_open(path: String) -> void:
	if path == selected_path: return
	_guard(func(): _open(path))

func _open(path: String) -> void:
	var enemy := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EnemyData
	if enemy == null:
		_notify("无法载入敌人：" + path)
		return
	draft = store.copy_enemy(enemy)
	selected_path = path
	_fingerprint = store.fingerprint(path)
	_dirty = false
	_refresh_list()
	_rebuild_forms()

func _new_enemy() -> void:
	draft = store.new_enemy()
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild_forms()

func _duplicate_enemy() -> void:
	if draft == null:
		_notify("请先选择敌人。")
		return
	draft = store.copy_enemy(draft)
	draft.id = store.unique_id(draft.id + "_copy")
	draft.display_name += "（副本）"
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild_forms()

func _reload_current() -> void:
	if selected_path.is_empty():
		draft = null
		_dirty = false
		_rebuild_forms()
	else:
		ResourceLoader.load(selected_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		_open(selected_path)

func _refresh_library() -> void:
	_reload_current()
	_refresh_list()
	_scan_editor()

func is_dirty() -> bool:
	return _dirty

func _changed() -> void:
	_dirty = true
	_update_status()

func _update_status() -> void:
	if draft == null: return
	_status.text = ("新敌人（尚未保存）" if selected_path.is_empty() else selected_path) + ("  ● 有未保存修改" if _dirty else "  ✓ 已保存")
	var errors := store.validate(draft, selected_path)
	_validation.text = "配置有效。保存已有资源时文件路径不随 ID 改变。" if errors.is_empty() else "配置问题（%d）：\n• %s" % [errors.size(), "\n• ".join(errors)]
	_validation.modulate = Color("#aadbb6") if errors.is_empty() else Color("#f5bd8a")
	if is_instance_valid(_preview):
		_preview.texture = draft.texture
		_preview.modulate = Color("#efc78c") if draft.category == EnemyData.Category.ELITE else Color.WHITE
	if is_instance_valid(_statistics):
		var bonus := draft.relic.movement_bonus if draft.relic != null else 0.0
		_statistics.text = "实际移速 %.1f 像素/秒（固定 %.1f × 自身遗物倍率，不随玩家变化）；外观倍率 %.2f；出生边距至少 %.0f 像素。" % [draft.movement_speed * (1 + bonus), draft.movement_speed, 1.5 if draft.category == EnemyData.Category.BOSS else 1.15 if draft.category == EnemyData.Category.ELITE else 1.0, draft.required_spawn_margin()]

func save_current(show_result: bool = true) -> bool:
	if draft == null: return false
	var result := store.save_enemy(draft, selected_path, _fingerprint)
	if not result.ok:
		_notify("保存失败：\n" + str(result.message))
		return false
	_open(str(result.path))
	_scan_editor()
	if show_result: _notify("敌人已保存，并引用所选装备和遗物资源。")
	return true

func _guard(action: Callable) -> void:
	if _dirty:
		_pending_action = action
		_discard_dialog.popup_centered()
	else:
		action.call()

func _show_references() -> void:
	if selected_path.is_empty():
		_notify("新敌人尚未保存，没有引用。")
		return
	var users := store.references(selected_path)
	_notify("尚未被资源引用。" if users.is_empty() else "以下资源直接或间接引用此敌人：\n" + "\n".join(users))

func _request_delete() -> void:
	if selected_path.is_empty():
		_notify("请先选择已保存的敌人。")
		return
	var users := store.references(selected_path)
	if not users.is_empty():
		_notify("此敌人仍被引用，不能删除：\n" + "\n".join(users))
		return
	_pending_delete = selected_path
	_delete_dialog.dialog_text = "永久删除以下敌人资源？\n%s%s" % [selected_path, "\n当前未保存的修改也会被放弃。" if _dirty else ""]
	_delete_dialog.popup_centered()

func _delete_confirmed() -> void:
	var result := store.delete_enemy(_pending_delete)
	if result.ok:
		draft = null
		selected_path = ""
		_dirty = false
		_rebuild_forms()
		_refresh_list()
		_scan_editor()
	_pending_delete = ""
	_notify(str(result.message))

func _scan_editor() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

func _choose_texture(target: Resource, property: String, label: LineEdit) -> void:
	_texture_target = target
	_texture_property = property
	_texture_label = label
	_file_dialog.popup_centered_ratio(0.75)

func _texture_selected(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		_notify("请选择有效的 Texture2D 图片资源。")
		return
	_texture_target.set(_texture_property, texture)
	if is_instance_valid(_texture_label): _texture_label.text = path
	_changed()

func _notify(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered(Vector2i(650, 220))
