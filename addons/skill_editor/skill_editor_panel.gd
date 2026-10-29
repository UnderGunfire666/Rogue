@tool
extends VBoxContainer

const Store = preload("res://addons/skill_editor/skill_editor_store.gd")
const Fields = preload("res://addons/enemy_editor/enemy_form_fields.gd")
var store := Store.new()
var fields := Fields.new()
var draft: SkillData
var selected_path := ""
var _fingerprint := ""
var _dirty := false
var _pending: Callable
var _delete_path := ""
var _list: ItemList
var _search: LineEdit
var _kind_filter: OptionButton
var _status: Label
var _validation: RichTextLabel
var _tabs: TabContainer
var _basics: VBoxContainer
var _parameters: VBoxContainer
var _preview: TextureRect
var _message: AcceptDialog
var _discard: ConfirmationDialog
var _delete: ConfirmationDialog
var _files: FileDialog
var _texture_target: Resource
var _texture_property: String
var _texture_label: LineEdit

func _ready() -> void:
	fields.changed = _changed
	fields.choose_texture = _choose_texture
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(func(): _refresh_list.call_deferred())
			fs.resources_reimported.connect(func(_paths: PackedStringArray): _refresh_list.call_deferred())
	_refresh_list()
	if selected_path.is_empty() and _list.item_count > 0:
		_open(str(_list.get_item_metadata(0)))
	else:
		_rebuild()

func ensure_loaded() -> void:
	_refresh_list()
	if draft == null and _list.item_count > 0:
		_open(str(_list.get_item_metadata(0)))

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "技能编辑器  /  SKILL EDITOR"
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)
	var toolbar := HFlowContainer.new()
	layout.add_child(toolbar)
	fields.button(toolbar, "新建技能", func(): _guard(_new_skill))
	fields.button(toolbar, "复制为新技能", func(): _guard(_duplicate_current))
	fields.button(toolbar, "保存当前技能", func(): save_current(true))
	fields.button(toolbar, "放弃修改", func(): _guard(_reload_current))
	fields.button(toolbar, "查看引用", _show_references)
	fields.button(toolbar, "删除技能", _request_delete)
	fields.button(toolbar, "刷新技能库", func(): _guard(_refresh_all))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 270
	layout.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	split.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索技能名称、ID…"
	_search.text_changed.connect(func(_text: String): _refresh_list())
	left.add_child(_search)
	_kind_filter = OptionButton.new()
	_kind_filter.add_item("全部类型")
	for label in SkillData.kind_labels():
		_kind_filter.add_item(label)
	_kind_filter.item_selected.connect(func(_index: int): _refresh_list())
	left.add_child(_kind_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int): request_open(str(_list.get_item_metadata(index))))
	left.add_child(_list)
	fields.note(left, "保存后的技能可在「角色编辑器」、「敌人编辑器」、「装备编辑器」和「遗物编辑器」中直接选用。")
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_tabs)
	_basics = _tab("基础与释放")
	_parameters = _tab("效果与进阶参数")
	_validation = RichTextLabel.new()
	_validation.custom_minimum_size.y = 85
	right.add_child(_validation)
	_message = AcceptDialog.new()
	_message.title = "技能编辑器"
	add_child(_message)
	_discard = ConfirmationDialog.new()
	_discard.title = "放弃未保存修改？"
	_discard.dialog_text = "当前草稿有未保存修改，确定放弃吗？"
	_discard.confirmed.connect(func():
		var action := _pending
		_pending = Callable()
		if action.is_valid(): action.call())
	_discard.canceled.connect(_refresh_list)
	add_child(_discard)
	_delete = ConfirmationDialog.new()
	_delete.title = "删除技能资源"
	_delete.confirmed.connect(_confirm_delete)
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
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box

func is_dirty() -> bool:
	return _dirty

func request_open(path: String) -> void:
	if path == selected_path and draft != null:
		return
	_guard(func(): _open(path))

func _guard(action: Callable) -> void:
	if _dirty:
		_pending = action
		_discard.popup_centered()
	else:
		action.call()

func _open(path: String) -> void:
	var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as SkillData
	if item == null:
		_notify("无法打开技能资源：" + path)
		return
	draft = store.io.copy_definition(item) as SkillData
	selected_path = path
	_fingerprint = store.io.fingerprint(path)
	_dirty = false
	_refresh_list()
	_rebuild()

func _new_skill() -> void:
	draft = store.new_skill()
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild()

func _duplicate_current() -> void:
	if draft == null:
		_notify("请先选择一个要复制的技能。")
		return
	draft = store.io.copy_definition(draft) as SkillData
	draft.id = store.unique_id(draft.id + "_copy")
	draft.display_name += " 副本"
	selected_path = ""
	_fingerprint = ""
	_dirty = true
	_refresh_list()
	_rebuild()

func _reload_current() -> void:
	if not selected_path.is_empty():
		_open(selected_path)
	else:
		draft = null
		_dirty = false
		_rebuild()

func _refresh_all() -> void:
	_refresh_list()
	if not selected_path.is_empty():
		_open(selected_path)
	elif _list.item_count > 0:
		_open(str(_list.get_item_metadata(0)))
	else:
		_reload_current()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

func _refresh_list() -> void:
	if not is_instance_valid(_list):
		return
	_list.clear()
	var query := _search.text.strip_edges().to_lower() if is_instance_valid(_search) else ""
	var filter_idx := _kind_filter.selected if is_instance_valid(_kind_filter) else 0
	for path in store.paths():
		var item := load(path) as SkillData
		if item == null:
			continue
		if filter_idx > 0 and item.kind != filter_idx - 1:
			continue
		var label := "%s [%s]\n%s · CD %.1fs" % [item.display_name, item.id, SkillData.kind_label(item.kind), item.cooldown]
		if not query.is_empty() and not label.to_lower().contains(query) and not item.description.to_lower().contains(query):
			continue
		_list.add_item(label)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, path)
		if path == selected_path:
			_list.select(index)

func _rebuild() -> void:
	_clear(_basics)
	_clear(_parameters)
	_tabs.visible = draft != null
	if draft == null:
		_status.text = "选择左侧技能，或新建一个主动技能。"
		_validation.text = "所有编辑均在草稿中进行，保存前不会改动磁盘文件。"
		return
	fields.text(_basics, "技能 ID", draft, "id")
	fields.text(_basics, "显示名称", draft, "display_name")
	fields.text(_basics, "效果说明", draft, "description", true)
	var kind_picker := fields.choice(_basics, "技能机制类型", draft, "kind", SkillData.kind_labels())
	kind_picker.item_selected.connect(func(_idx: int): _rebuild_parameters.call_deferred())
	fields.texture(_basics, "技能图标", draft, "icon")
	_preview = TextureRect.new()
	_preview.custom_minimum_size.y = 84
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_basics.add_child(_preview)
	fields.number(_basics, "基础伤害 / 治疗值", draft, "damage", 0.0, 1.0)
	fields.number(_basics, "元素属性加成系数", draft, "elemental_scaling", 0.0, 0.1)
	fields.number(_basics, "施放射程（像素）", draft, "cast_range", 1.0, 5.0)
	fields.number(_basics, "作用半径（像素）", draft, "radius", 1.0, 2.0)
	fields.number(_basics, "冷却时间（秒）", draft, "cooldown", 0.1, 0.1)
	_rebuild_parameters()
	_update_status()

func _rebuild_parameters() -> void:
	_clear(_parameters)
	if draft == null:
		return
	fields.note(_parameters, "当前类型：" + SkillData.kind_label(draft.kind))
	fields.number(_parameters, "持续时间（秒）", draft, "duration", 0.0, 0.1)
	fields.number(_parameters, "投射物 / 召唤 / 弹跳数", draft, "projectile_count", 1, 1)
	fields.number(_parameters, "散射 / 横扫角度（度）", draft, "spread_angle", 0.0, 1.0)
	fields.number(_parameters, "冲刺速度（像素/秒）", draft, "dash_speed", 10.0, 10.0)
	fields.number(_parameters, "光环移速加成", draft, "buff_move_speed_bonus", 0.0, 1.0, true)
	fields.number(_parameters, "光环攻速加成", draft, "buff_attack_speed_bonus", 0.0, 1.0, true)
	fields.text(_parameters, "召唤敌人 ID（用于虫巢召唤）", draft, "summon_enemy_id")

func _changed() -> void:
	_dirty = true
	_update_status()

func _update_status() -> void:
	if draft == null:
		return
	if is_instance_valid(_preview):
		_preview.texture = draft.icon
	var target := selected_path if not selected_path.is_empty() else Store.SKILL_DIR.path_join(draft.id + ".tres")
	_status.text = "%s：%s  ->  %s" % ["未保存草稿 *" if _dirty else "已同步", draft.display_name, target]
	var errors := store.validate(draft, selected_path)
	_validation.text = "校验通过：可以保存。\n" + draft.summary_text() if errors.is_empty() else "无法保存，请修正：\n• " + "\n• ".join(errors)

func save_current(show_feedback: bool) -> void:
	if draft == null:
		return
	var result := store.save_skill(draft, selected_path, _fingerprint)
	if not result.ok:
		_update_status()
		if show_feedback:
			_notify("保存失败：\n" + str(result.message))
		return
	selected_path = str(result.path)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_open(selected_path)
	if show_feedback:
		_notify("已保存：" + selected_path)

func _show_references() -> void:
	if selected_path.is_empty():
		_notify("当前草稿尚未保存，没有引用记录。")
		return
	var users := store.io.references(selected_path)
	_notify("没有发现其他资源引用此技能。" if users.is_empty() else "以下文件引用了此技能：\n" + "\n".join(users))

func _request_delete() -> void:
	if selected_path.is_empty():
		_reload_current()
		return
	var users := store.io.references(selected_path)
	if not users.is_empty():
		_notify("技能仍被引用，不能删除：\n" + "\n".join(users))
		return
	_delete_path = selected_path
	_delete.dialog_text = "确定删除技能资源？\n" + selected_path
	_delete.popup_centered()

func _confirm_delete() -> void:
	var result := store.delete_skill(_delete_path)
	if not result.ok:
		_notify(str(result.message))
		return
	selected_path = ""
	draft = null
	_dirty = false
	_refresh_all()

func _choose_texture(target: Resource, property: String, label: LineEdit) -> void:
	_texture_target = target
	_texture_property = property
	_texture_label = label
	_files.popup_centered_ratio(0.65)

func _texture_selected(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		_notify("所选文件不是有效的 Texture2D。")
		return
	_texture_target.set(_texture_property, texture)
	_texture_label.text = path
	_changed()

func _notify(text: String) -> void:
	_message.dialog_text = text
	_message.popup_centered()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

