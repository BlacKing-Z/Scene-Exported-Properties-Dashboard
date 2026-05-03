## DashboardPanel — 主面板 UI 与逻辑
@tool
extends VBoxContainer

var plugin: EditorPlugin

const _CollectorScript = preload("res://addons/scene_exported_properties_dashboard/core/property_collector.gd")
const _EditorScript = preload("res://addons/scene_exported_properties_dashboard/core/property_editor.gd")
const _SnapshotScript = preload("res://addons/scene_exported_properties_dashboard/core/snapshot_manager.gd")

var _collector
var _prop_editor
var _snapshot_mgr

var _collected: Dictionary = {}
var _node_map: Dictionary = {}
var _favorites: Dictionary = {}
var _hidden_groups: Dictionary = {}
var _search_text: String = ""
var _last_scene_root_id: int = -1
var _sync_timer: float = 0.0

@onready var _search_bar: LineEdit = $ToolBar/SearchBar
@onready var _btn_filter: Button = $ToolBar/BtnFilter
@onready var _btn_snapshot: Button = $ToolBar/BtnSnapshot
@onready var _btn_snapshot_list: Button = $ToolBar/BtnSnapshotList
@onready var _btn_apply: Button = $ToolBar/BtnApply
@onready var _tree: Tree = $Tree

func _ready() -> void:
	_search_bar.placeholder_text = "搜索"
	_search_bar.right_icon = get_theme_icon("Search", "EditorIcons")
	_search_bar.text_changed.connect(_on_search_changed)

	_btn_filter.icon = get_theme_icon("AnimationFilter", "EditorIcons")
	_btn_filter.tooltip_text = "筛选分组"
	_btn_filter.pressed.connect(_on_filter_pressed)

	_btn_snapshot.icon = get_theme_icon("Save", "EditorIcons")
	_btn_snapshot.tooltip_text = "创建快照"
	_btn_snapshot.pressed.connect(_on_snapshot_pressed)

	_btn_snapshot_list.icon = get_theme_icon("FileList", "EditorIcons")
	_btn_snapshot_list.tooltip_text = "快照管理"
	_btn_snapshot_list.pressed.connect(_on_snapshot_list_pressed)

	_btn_apply.text = "应用回场景文件"
	_btn_apply.tooltip_text = "将运行时修改写回 .tscn"
	_btn_apply.pressed.connect(_on_apply_pressed)
	_btn_apply.visible = false

	_tree.columns = 3
	_tree.set_column_title(0, "变量")
	_tree.set_column_title(1, "值")
	_tree.set_column_title(2, "★")
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 36)
	_tree.item_edited.connect(_on_tree_item_edited)
	_tree.cell_selected.connect(_on_tree_cell_selected)

	call_deferred("refresh")

## 检测场景切换，由 plugin.gd _process 调用
func check_scene_changed() -> void:
	if not plugin:
		return
	var root: Node = plugin.get_editor_interface().get_edited_scene_root()
	var current_id: int = root.get_instance_id() if root else -1
	if current_id != _last_scene_root_id:
		refresh()
		return
	# 定期同步 Inspector 中的值变化（每0.5秒）
	_sync_timer += get_process_delta_time() if get_process_delta_time() > 0 else 0.016
	if _sync_timer >= 0.5:
		_sync_timer = 0.0
		_sync_values_from_nodes()

## 从节点重新读取值，更新 Tree 中显示的值（不重建 Tree）
func _sync_values_from_nodes() -> void:
	if _collected.is_empty():
		return
	var root_item: TreeItem = _tree.get_root()
	if not root_item:
		return
	_iterate_tree_items(root_item)

func _iterate_tree_items(item: TreeItem) -> void:
	var meta = item.get_metadata(0)
	if meta and meta.has("key"):
		var key: String = meta["key"]
		var parsed: Dictionary = _parse_key(key)
		var node_path: String = parsed["node_path"]
		var prop_name: String = parsed["prop_name"]
		if _node_map.has(node_path):
			var node: Node = _node_map[node_path]
			var current_val = node.get(prop_name)
			var display_val: String = str(current_val)
			if item.get_text(1) != display_val:
				item.set_text(1, display_val)
				# 同步更新 _collected 缓存
				if _collected.has(node_path):
					for p in _collected[node_path]["properties"]:
						if p["name"] == prop_name:
							p["value"] = current_val
							break
	var child: TreeItem = item.get_first_child()
	while child:
		_iterate_tree_items(child)
		child = child.get_next()

func _init_managers() -> void:
	if not _collector:
		_collector = _CollectorScript.new(plugin.get_editor_interface())
		_prop_editor = _EditorScript.new(plugin.get_editor_interface())
		_snapshot_mgr = _SnapshotScript.new(plugin.get_editor_interface())

func refresh() -> void:
	if not plugin:
		return
	_init_managers()
	_collected = _collector.collect_exported_properties()
	var root: Node = plugin.get_editor_interface().get_edited_scene_root()
	_last_scene_root_id = root.get_instance_id() if root else -1
	_node_map.clear()
	for path in _collected:
		_node_map[path] = _collected[path]["node"]
	_hidden_groups.clear()
	_rebuild_tree()

## 从 key 解析出节点路径和属性名
## 匹配最长的节点路径以正确处理嵌套节点（如 A/B/C/prop）
func _parse_key(key: String) -> Dictionary:
	var best_path: String = ""
	for node_path in _collected:
		if key.begins_with(node_path + "/") and node_path.length() > best_path.length():
			best_path = node_path
	if best_path != "":
		return {"node_path": best_path, "prop_name": key.substr(best_path.length() + 1)}
	var last_slash: int = key.rfind("/")
	if last_slash >= 0:
		return {"node_path": key.substr(0, last_slash), "prop_name": key.substr(last_slash + 1)}
	return {"node_path": "", "prop_name": key}

func _rebuild_tree() -> void:
	_tree.clear()
	var root_item: TreeItem = _tree.create_item()

	if _search_text == "" and _favorites.size() > 0:
		var fav_root: TreeItem = _tree.create_item(root_item)
		fav_root.set_text(0, "★ 收藏")
		fav_root.set_expand_right(0, true)
		fav_root.set_selectable(0, false)
		fav_root.set_selectable(1, false)
		fav_root.set_selectable(2, false)
		fav_root.set_editable(1, false)
		for fav_key in _favorites:
			_add_property_row(fav_root, fav_key)

	var groups: Dictionary = _get_grouped_properties()
	for group_path in groups:
		if _is_group_hidden(group_path):
			continue
		var group_item: TreeItem = _tree.create_item(root_item)
		group_item.set_text(0, group_path)
		group_item.set_expand_right(0, true)
		group_item.set_selectable(0, false)
		group_item.set_selectable(1, false)
		group_item.set_selectable(2, false)
		group_item.set_editable(1, false)
		var subgroups: Dictionary = groups[group_path]
		for sg_name in subgroups:
			var props: Array = subgroups[sg_name]
			if not _matches_search(props):
				continue
			var parent: TreeItem = group_item
			if sg_name != "":
				parent = _tree.create_item(group_item)
				parent.set_text(0, sg_name)
				parent.set_expand_right(0, true)
				parent.set_selectable(0, false)
				parent.set_selectable(1, false)
				parent.set_selectable(2, false)
				parent.set_editable(1, false)
			for prop in props:
				if not _matches_search_prop(prop):
					continue
				_add_property_row(parent, group_path + "/" + prop["name"], prop)

	_update_apply_button()

func _get_grouped_properties() -> Dictionary:
	var result: Dictionary = {}
	for node_path in _collected:
		var entry = _collected[node_path]
		var props: Array = entry["properties"]
		if not result.has(node_path):
			result[node_path] = {}
		for prop in props:
			var group: String = prop["group"]
			var subgroup: String = prop["subgroup"]
			var key: String = group
			if subgroup != "":
				key = group + "/" + subgroup if group != "" else subgroup
			if not result[node_path].has(key):
				result[node_path][key] = []
			result[node_path][key].append(prop)
	return result

func _add_property_row(parent: TreeItem, key: String, prop: Dictionary = {}) -> void:
	if prop.is_empty():
		var parsed: Dictionary = _parse_key(key)
		var node_path: String = parsed["node_path"]
		var prop_name: String = parsed["prop_name"]
		if _collected.has(node_path):
			for p in _collected[node_path]["properties"]:
				if p["name"] == prop_name:
					prop = p
					break
	if prop.is_empty():
		return
	var item: TreeItem = _tree.create_item(parent)
	item.set_text(0, prop["name"])
	item.set_metadata(0, {"key": key})
	item.set_text(1, str(prop["value"]))
	item.set_editable(1, true)
	item.set_selectable(2, true)
	if _favorites.has(key):
		item.set_text(2, "★")
	else:
		item.set_text(2, "☆")

## Tree 单元格编辑完成：将修改应用到节点
func _on_tree_item_edited() -> void:
	var item: TreeItem = _tree.get_edited()
	if not item:
		return
	var column: int = _tree.get_edited_column()
	if column != 1:
		return
	var meta = item.get_metadata(0)
	if not meta or not meta.has("key"):
		return
	var key: String = meta["key"]
	var parsed: Dictionary = _parse_key(key)
	var node_path: String = parsed["node_path"]
	var prop_name: String = parsed["prop_name"]
	if not _node_map.has(node_path):
		return
	var node: Node = _node_map[node_path]
	var new_text: String = item.get_text(1)
	var current_value = node.get(prop_name)
	var converted = _convert_value(new_text, current_value)
	# 使用 UndoRedo 系统，确保修改可撤销且被 Godot 标记为场景已修改
	var ur: EditorUndoRedoManager = plugin.get_editor_interface().get_editor_undo_redo()
	ur.create_action("Set %s" % prop_name)
	ur.add_do_property(node, prop_name, converted)
	ur.add_undo_property(node, prop_name, current_value)
	ur.commit_action()
	# 同步更新 _collected 缓存
	if _collected.has(node_path):
		for p in _collected[node_path]["properties"]:
			if p["name"] == prop_name:
				p["value"] = converted
				break

## Tree 单元格选中回调：检测收藏列点击
func _on_tree_cell_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if not item:
		return
	var column: int = _tree.get_selected_column()
	if column != 2:
		return
	var meta = item.get_metadata(0)
	if not meta or not meta.has("key"):
		return
	var key: String = meta["key"]
	if _favorites.has(key):
		_favorites.erase(key)
	else:
		_favorites[key] = true
	# Tree 处于 blocked 状态时不能直接 rebuild，需延迟
	call_deferred("_rebuild_tree")

func _convert_value(text: String, reference) -> Variant:
	match typeof(reference):
		TYPE_INT:
			return int(text)
		TYPE_FLOAT:
			return float(text)
		TYPE_BOOL:
			return text.to_lower() == "true" or text == "1"
		TYPE_STRING:
			return text
		TYPE_VECTOR2:
			var v = str_to_var("Vector2" + text)
			return v if v != null else reference
		TYPE_COLOR:
			var c = str_to_var("Color" + text)
			return c if c != null else reference
		_:
			var parsed = str_to_var(text)
			return parsed if parsed != null else text

func _is_group_hidden(group_path: String) -> bool:
	return _hidden_groups.has(group_path)

func _matches_search(props: Array) -> bool:
	if _search_text == "":
		return true
	for prop in props:
		if _matches_search_prop(prop):
			return true
	return false

func _matches_search_prop(prop: Dictionary) -> bool:
	if _search_text == "":
		return true
	var q: String = _search_text.to_lower()
	if prop["name"].to_lower().contains(q):
		return true
	if str(prop["group"]).to_lower().contains(q):
		return true
	if str(prop["subgroup"]).to_lower().contains(q):
		return true
	return false

func _update_apply_button() -> void:
	if not _prop_editor:
		return
	var is_running: bool = not Engine.is_editor_hint()
	_btn_apply.visible = is_running and _prop_editor.get_modified_count() > 0

func _on_search_changed(text: String) -> void:
	_search_text = text
	_rebuild_tree()

func _on_filter_pressed() -> void:
	var dialog = load("res://addons/scene_exported_properties_dashboard/ui/filter_dialog.tscn").instantiate()
	dialog.setup(_get_all_groups(), _hidden_groups)
	add_child(dialog)
	dialog.confirmed_with_data.connect(_on_filter_confirmed)
	dialog.popup_centered(Vector2i(300, 400))

func _on_filter_confirmed(hidden: Dictionary) -> void:
	_hidden_groups = hidden
	_rebuild_tree()

func _on_snapshot_pressed() -> void:
	var dialog = load("res://addons/scene_exported_properties_dashboard/ui/snapshot_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.confirmed_with_name.connect(_on_snapshot_confirmed)
	dialog.popup_centered(Vector2i(300, 120))

func _on_snapshot_confirmed(snap_name: String) -> void:
	if snap_name == "":
		return
	var scene_path: String = _get_edited_scene_path()
	_snapshot_mgr.take_snapshot(snap_name, scene_path, _collected)

func _on_snapshot_list_pressed() -> void:
	var dialog = load("res://addons/scene_exported_properties_dashboard/ui/snapshot_list.tscn").instantiate()
	var scene_path: String = _get_edited_scene_path()
	dialog.setup(_snapshot_mgr.list_snapshots(scene_path), _snapshot_mgr)
	add_child(dialog)
	dialog.snapshot_selected.connect(_on_snapshot_selected)
	dialog.popup_centered(Vector2i(400, 500))

func _on_snapshot_selected(snapshot: Dictionary) -> void:
	_snapshot_mgr.apply_snapshot(snapshot, _node_map)
	refresh()

func _on_apply_pressed() -> void:
	_prop_editor.apply_to_scene_file(_node_map)
	_update_apply_button()

## 获取当前编辑场景的资源路径
func _get_edited_scene_path() -> String:
	var root: Node = plugin.get_editor_interface().get_edited_scene_root()
	if root:
		var owner: Node = root.owner if root.owner else root
		var scene_path: String = owner.scene_file_path
		if scene_path != "":
			return scene_path
	# 兜底
	return plugin.get_editor_interface().get_current_path()

func _get_all_groups() -> PackedStringArray:
	var groups: PackedStringArray = []
	for node_path in _collected:
		if not node_path in groups:
			groups.append(node_path)
		var entry = _collected[node_path]
		for prop in entry["properties"]:
			var g: String = prop["group"]
			if g != "" and not g in groups:
				groups.append(g)
	return groups
