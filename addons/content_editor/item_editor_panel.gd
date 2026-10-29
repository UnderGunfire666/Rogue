@tool
extends VBoxContainer

const Store = preload("res://addons/content_editor/item_editor_store.gd")
const Fields = preload("res://addons/enemy_editor/enemy_form_fields.gd")
const AttackForm = preload("res://addons/content_editor/attack_form.gd")
var kind := "equipment"
var store := Store.new()
var fields := Fields.new()
var draft: ItemDefinition
var selected_path := ""
var _fingerprint := ""
var _dirty := false
var _pending: Callable
var _delete_path := ""
var _list: ItemList
var _search: LineEdit
var _recipient: OptionButton
var _type_filter: OptionButton
var _status: Label
var _validation: RichTextLabel
var _tabs: TabContainer
var _identity: VBoxContainer
var _details: VBoxContainer
var _preview: TextureRect
var _message: AcceptDialog
var _discard: ConfirmationDialog
var _delete: ConfirmationDialog
var _files: FileDialog
var _texture_target: Resource
var _texture_property: String
var _texture_label: LineEdit

func _ready() -> void:
	store.kind = kind
	fields.changed = _changed
	fields.choose_texture = _choose_texture
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		filesystem.filesystem_changed.connect(func(): _refresh_list.call_deferred())
		filesystem.resources_reimported.connect(func(_paths: PackedStringArray): _refresh_list.call_deferred())
	_refresh_list()
	_rebuild()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "装备编辑器  /  EQUIPMENT EDITOR" if kind == "equipment" else "遗物编辑器  /  RELIC EDITOR"
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)
	var toolbar := HFlowContainer.new()
	layout.add_child(toolbar)
	fields.button(toolbar, "新建玩家物品", func(): _guard(func(): _new_item(0)))
	fields.button(toolbar, "新建敌人物品", func(): _guard(func(): _new_item(1)))
	fields.button(toolbar, "复制为新物品", _duplicate)
	fields.button(toolbar, "保存", func(): save_current())
	fields.button(toolbar, "放弃修改 / 重新载入", func(): _guard(_reload))
	fields.button(toolbar, "查看引用", _references)
	fields.button(toolbar, "删除", _request_delete)
	fields.button(toolbar, "刷新物品库", func(): _guard(_refresh))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var split := HSplitContainer.new()
	split.split_offset = 250
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 200
	split.add_child(library)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称、ID…"
	_search.text_changed.connect(func(_value: String): _refresh_list())
	library.add_child(_search)
	_recipient = OptionButton.new()
	for label in ["全部使用者", "玩家", "敌人"]: _recipient.add_item(label)
	_recipient.item_selected.connect(func(_index: int): _refresh_list())
	library.add_child(_recipient)
	if kind == "equipment":
		_type_filter = OptionButton.new()
		for label in ["全部类型", "近战", "远程", "施法", "复合装备"]: _type_filter.add_item(label)
		_type_filter.item_selected.connect(func(_index: int): _refresh_list())
		library.add_child(_type_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int): request_open(str(_list.get_item_metadata(index))))
	library.add_child(_list)
	fields.note(library, "玩家物品保存后会进入开局/商店列表。敌人物品可被敌人编辑器直接引用；修改共享物品会影响引用它的敌人。")
	var editor := VBoxContainer.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editor)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_child(_tabs)
	_identity = _tab("基础与外观")
	_details = _tab("攻击配置" if kind == "equipment" else "被动效果")
	_validation = RichTextLabel.new()
	_validation.custom_minimum_size.y = 100
	editor.add_child(_validation)
	_message = AcceptDialog.new()
	add_child(_message)
	_discard = ConfirmationDialog.new()
	_discard.title = "放弃未保存修改？"
	_discard.dialog_text = "当前草稿有未保存修改，继续将放弃这些修改。"
	_discard.confirmed.connect(func():
		var action := _pending
		_pending = Callable()
		if action.is_valid(): action.call())
	_discard.canceled.connect(_refresh_list)
	add_child(_discard)
	_delete = ConfirmationDialog.new()
	_delete.title = "删除物品资源"
	_delete.confirmed.connect(_delete_confirmed)
	add_child(_delete)
	_files = FileDialog.new()
	_files.access = FileDialog.ACCESS_RESOURCES
	_files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_files.filters = PackedStringArray(["*.png,*.webp,*.svg,*.jpg,*.tres,*.res ; Texture2D"])
	_files.file_selected.connect(_texture_selected)
	add_child(_files)

func _tab(title: String) -> VBoxContainer:
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

func _rebuild() -> void:
	_clear(_identity)
	_clear(_details)
	_tabs.visible = draft != null
	if draft == null:
		_status.text = "选择左侧物品，或新建玩家 / 敌人物品。"
		_validation.text = "在独立草稿中编辑；保存后才会写入资源。"
		return
	fields.note(_identity, "使用者：" + ("玩家 Player" if draft.recipient == 0 else "敌人 Enemy") + "（创建后固定，玩家与敌人的具体物品不通用）")
	fields.item(_identity, draft)
	if draft is WeaponData:
		var tags := LineEdit.new()
		tags.name = "weapon_tags"
		tags.text = ", ".join(draft.weapon_tags)
		tags.text_changed.connect(func(value: String):
			var result := PackedStringArray()
			for entry in value.split(",", false):
				if not entry.strip_edges().is_empty(): result.append(entry.strip_edges())
			draft.weapon_tags = result
			fields.changed.call())
		fields.row(_identity, "武器类别标签（逗号分隔）", tags)
	if draft is RelicData:
		fields.number(_identity, "基础价格", draft, "base_price", 0, 1)
		fields.number(_identity, "持有上限（0 为无限）", draft, "copy_limit", 0, 1)
		var tags_field := LineEdit.new()
		tags_field.name = "tags"
		tags_field.text = ", ".join(draft.tags)
		tags_field.text_changed.connect(func(value: String):
			var tags := PackedStringArray()
			for tag in value.split(",", false):
				if not tag.strip_edges().is_empty(): tags.append(tag.strip_edges())
			draft.tags = tags
			fields.changed.call())
		fields.row(_identity, "标签（逗号分隔）", tags_field)
	_preview = TextureRect.new()
	_preview.custom_minimum_size.y = 100
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_identity.add_child(_preview)
	_rebuild_details()
	_update_status()

func _rebuild_details() -> void:
	_clear(_details)
	if draft.recipient == ItemDefinition.Recipient.PLAYER and (draft is WeaponData or draft is RelicData):
		fields.note(_details, "绑定主动技能（从技能库选择已保存的技能资源，战斗中按 Q 键瞄准并释放）：")
		var skill_picker := OptionButton.new()
		skill_picker.name = "skill_picker"
		skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_picker.add_item("不绑定主动技能")
		skill_picker.set_item_metadata(0, "")
		var current_skill_path := draft.skill.resource_path if draft.skill != null else ""
		var selected_skill := 0
		for skill_path in store.io.resource_paths( store.io.SKILL_DIR ):
			if Engine.is_editor_hint() and not store.io.dependencies_ready(skill_path, {}): continue
			var sk := load(skill_path) as SkillData
			if sk == null: continue
			skill_picker.add_item("%s [%s] · %s" % [sk.display_name, sk.id, SkillData.kind_label(sk.kind)])
			var s_idx := skill_picker.item_count - 1
			skill_picker.set_item_metadata(s_idx, skill_path)
			skill_picker.set_item_tooltip(s_idx, skill_path)
			if skill_path == current_skill_path: selected_skill = s_idx
		if draft.skill != null and selected_skill == 0:
			skill_picker.add_item("内嵌技能：%s（建议保存为独立技能）" % draft.skill.display_name)
			selected_skill = skill_picker.item_count - 1
			skill_picker.set_item_metadata(selected_skill, current_skill_path)
		skill_picker.select(selected_skill)
		skill_picker.item_selected.connect(func(idx: int):
			var s_path := str(skill_picker.get_item_metadata(idx))
			draft.skill = load(s_path) as SkillData if not s_path.is_empty() else null
			_changed()
			_rebuild_details.call_deferred())
		fields.row(_details, "主动技能", skill_picker)
		var skill_bar := HFlowContainer.new()
		_details.add_child(skill_bar)
		fields.button(skill_bar, "打开技能编辑器", func():
			if not Engine.is_editor_hint(): return
			if draft.skill != null and not draft.skill.resource_path.contains("::"):
				EditorInterface.edit_resource(draft.skill)
			EditorInterface.set_main_screen_editor("Skill Editor"))
		if draft.skill != null:
			fields.note(_details, "%s\n%s\n%s" % [draft.skill.summary_text(), draft.skill.description, draft.skill.resource_path])
		_details.add_child(HSeparator.new())
	if draft is WeaponData:
		fields.note(_details, "玩家武器均自动寻敌；远程攻击范围是发动门槛，不是子弹飞行距离。")
		AttackForm.build(fields, _details, draft, _rebuild_details)
	elif draft is EnemyEquipmentData:
		fields.note(_details, "一件敌人装备可含多个攻击配置，各自独立冷却；保持距离行为采用第一个远程配置的射程。")
		var bar := HFlowContainer.new()
		_details.add_child(bar)
		for attack_kind in 3:
			fields.button(bar, "+ " + ["近战", "远程", "施法"][attack_kind], _add_attack.bind(attack_kind))
		for index in draft.attacks.size(): _attack_card(index)
	elif draft is RelicData:
		fields.number(_details, "每秒回复生命", draft, "regeneration", 0, 0.1)
		fields.number(_details, "近战攻击速度加成", draft, "melee_attack_speed_bonus", -99.9, 1, true)
		fields.number(_details, "移动速度加成", draft, "movement_bonus", -99.9, 1, true)
		fields.number(_details, "伤害加成", draft, "damage_bonus", -99.9, 1, true)
		fields.note(_details, "一件遗物可同时提供多种被动效果。百分比以 0% 为基准；近战攻速 +50% 即攻击间隔 ÷ 1.5，移速 +5% 即基础移速 × 1.05。")
		if draft.recipient == ItemDefinition.Recipient.PLAYER:
			if draft.primary_stats == null: draft.primary_stats = PrimaryStatsData.new()
			_details.add_child(HSeparator.new())
			fields.note(_details, "玩家主属性加成：百分比以百分点输入；生命再生使用属性点，旧的每秒回血效果保留。")
			for id in PlayerPrimaryStats.IDS:
				var stat_field := fields.number(_details, PlayerPrimaryStats.label(id), draft.primary_stats, id, -100000, 1)
				if PlayerPrimaryStats.PERCENT_IDS.has(id): stat_field.suffix = "%"

func _attack_card(index: int) -> void:
	var frame := PanelContainer.new()
	_details.add_child(frame)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	frame.add_child(content)
	var bar := HFlowContainer.new()
	content.add_child(bar)
	var title := fields.note(bar, "攻击配置 %d" % (index + 1))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size.x = 120
	if index > 0: fields.button(bar, "上移", func(): _move_attack(index, -1))
	if index + 1 < draft.attacks.size(): fields.button(bar, "下移", func(): _move_attack(index, 1))
	fields.button(bar, "移除", func():
		draft.attacks.remove_at(index)
		_changed()
		_rebuild_details())
	if draft.attacks[index] == null:
		fields.note(content, "配置为空，请移除并重新添加。")
	else:
		AttackForm.build(fields, content, draft.attacks[index], _rebuild_details)

func _add_attack(attack_kind: int) -> void:
	var profile := AttackProfileData.new()
	profile.kind = attack_kind
	profile.attack_range = 60 if attack_kind == 0 else 220
	draft.attacks.append(profile)
	_changed()
	_rebuild_details()

func _move_attack(index: int, offset: int) -> void:
	var other: AttackProfileData = draft.attacks[index + offset]
	draft.attacks[index + offset] = draft.attacks[index]
	draft.attacks[index] = other
	_changed()
	_rebuild_details()

func _classification(item: ItemDefinition) -> int:
	if item is WeaponData: return item.kind
	if item is EnemyEquipmentData:
		var kinds: Dictionary = {}
		for attack in item.attacks:
			if attack != null: kinds[attack.kind] = true
		return int(kinds.keys()[0]) if kinds.size() == 1 else 3
	return 0

func _refresh_list() -> void:
	_list.clear()
	for path in store.paths():
		var item := load(path) as ItemDefinition
		if _recipient.selected > 0 and item.recipient != _recipient.selected - 1: continue
		var classification := _classification(item)
		if kind == "equipment" and _type_filter.selected > 0 and classification != _type_filter.selected - 1: continue
		var label := "%s [%s] · %s" % [item.display_name, item.id, "玩家" if item.recipient == 0 else "敌人"]
		if kind == "equipment": label += " · " + ["近战", "远程", "施法", "复合"][clampi(classification, 0, 3)]
		if not _search.text.is_empty() and not label.to_lower().contains(_search.text.to_lower()): continue
		_list.add_item(label)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, label + "\n" + path)
		if path == selected_path: _list.select(index)

func request_open(path: String) -> void:
	if path == selected_path: return
	_guard(func(): _open(path))

func _open(path: String) -> void:
	var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemDefinition
	if item == null or not store.accepts(item):
		_notify("无法载入此物品：" + path)
		return
	draft = store.io.copy_definition(item) as ItemDefinition
	selected_path = path
	_fingerprint = store.io.fingerprint(path)
	_dirty = false
	_refresh_list()
	_rebuild()

func _new_item(recipient: int) -> void:
	draft = store.new_item(recipient)
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild()

func _duplicate() -> void:
	if draft == null: return
	draft = store.io.copy_definition(draft) as ItemDefinition
	draft.id = store.unique_id(draft.id + "_copy", draft.recipient)
	draft.display_name += "（副本）"
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild()

func _reload() -> void:
	if selected_path.is_empty():
		draft = null
		_dirty = false
		_rebuild()
	else:
		_open(selected_path)

func _refresh() -> void:
	_reload()
	_refresh_list()
	_scan()

func _changed() -> void:
	_dirty = true
	_update_status()

func is_dirty() -> bool:
	return _dirty

func _update_status() -> void:
	if draft == null: return
	_status.text = ("新物品（尚未保存）" if selected_path.is_empty() else selected_path) + ("  ● 有未保存修改" if _dirty else "  ✓ 已保存")
	var errors := store.validate(draft, selected_path)
	_validation.text = "配置有效。修改 ID 保留原文件路径；保存后会影响引用此物品的资源。" if errors.is_empty() else "配置问题（%d）：\n• %s" % [errors.size(), "\n• ".join(errors)]
	_validation.modulate = Color("#aadbb6") if errors.is_empty() else Color("#f5bd8a")
	if is_instance_valid(_preview): _preview.texture = draft.icon

func save_current(show_result: bool = true) -> bool:
	if draft == null: return false
	var result := store.save_item(draft, selected_path, _fingerprint)
	if not result.ok:
		_notify("保存失败：\n" + str(result.message))
		return false
	_open(str(result.path))
	_scan()
	if show_result: _notify("物品已保存。")
	return true

func _guard(action: Callable) -> void:
	if _dirty:
		_pending = action
		_discard.popup_centered()
	else: action.call()

func _references() -> void:
	var users := store.io.references(selected_path) if not selected_path.is_empty() else PackedStringArray()
	_notify("没有已保存资源引用此物品。" if users.is_empty() else "直接或间接引用：\n" + "\n".join(users))

func _request_delete() -> void:
	if selected_path.is_empty():
		_notify("请先选择已保存的物品。")
		return
	var users := store.io.references(selected_path)
	if not users.is_empty():
		_notify("物品仍被引用，不能删除：\n" + "\n".join(users))
		return
	_delete_path = selected_path
	_delete.dialog_text = "永久删除此物品？\n" + selected_path + ("\n当前草稿也将被放弃。" if _dirty else "")
	_delete.popup_centered()

func _delete_confirmed() -> void:
	var result := store.delete_item(_delete_path)
	if result.ok:
		draft = null
		selected_path = ""
		_dirty = false
		_rebuild()
		_refresh_list()
		_scan()
	_notify(str(result.message))

func _choose_texture(target: Resource, property: String, label: LineEdit) -> void:
	_texture_target = target
	_texture_property = property
	_texture_label = label
	_files.popup_centered_ratio(0.75)

func _texture_selected(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		_notify("请选择 Texture2D 图片资源。")
		return
	_texture_target.set(_texture_property, texture)
	if is_instance_valid(_texture_label): _texture_label.text = path
	_changed()

func _scan() -> void:
	if Engine.is_editor_hint(): EditorInterface.get_resource_filesystem().scan()

func _notify(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered(Vector2i(650, 220))
