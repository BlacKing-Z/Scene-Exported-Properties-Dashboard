## SnapshotManager — 命名快照的创建、存储、加载、恢复与删除
##
## 职责：
##   1. 将当前场景所有 export 变量值序列化为 JSON 快照文件
##   2. 列出当前场景的所有快照（按时间倒序）
##   3. 从快照恢复变量值到节点
##   4. 删除快照文件
##   5. 管理快照存储目录（默认 snapshots/，可通过 ProjectSettings 自定义）
##
## 快照 JSON 格式：
##   {
##     "scene": "res://scenes/main.tscn",
##     "timestamp": "2026-04-30T12:00:00",
##     "name": "v1平衡",
##     "data": { "Player": { "max_hp": 100 }, "Enemy/Goblin": { "attack": 15 } }
##   }
##
## 复合类型（Color/Vector2/Vector3/Rect2）序列化为带 _type 标记的字典，
## 反序列化时根据 _type 还原为对应 Godot 类型。
extends RefCounted

var _editor_interface: EditorInterface

## 快照保存目录（相对于 res://），如 "snapshots" 或自定义路径
var _snapshot_dir: String

func _init(p_editor_interface: EditorInterface) -> void:
	_editor_interface = p_editor_interface
	_snapshot_dir = _get_snapshot_dir()

## 读取快照目录设置，优先从 ProjectSettings 读取自定义路径，否则使用默认 "snapshots"
func _get_snapshot_dir() -> String:
	if ProjectSettings.has_setting("plugin/scene_param_dashboard/snapshot_dir"):
		var custom: String = ProjectSettings.get_setting("plugin/scene_param_dashboard/snapshot_dir")
		if custom != "":
			return custom
	return "snapshots"

## 设置自定义快照目录并持久化到 ProjectSettings
func set_snapshot_dir(p_dir: String) -> void:
	_snapshot_dir = p_dir
	ProjectSettings.set_setting("plugin/scene_param_dashboard/snapshot_dir", p_dir)
	ProjectSettings.save()

## 创建快照
## [param snapshot_name] 用户指定的快照名称（如 "v1平衡"）
## [param scene_path] 当前场景资源路径（如 "res://scenes/main.tscn"）
## [param data] PropertyCollector 收集的数据字典
## 返回 true 表示保存成功
func take_snapshot(snapshot_name: String, scene_path: String, data: Dictionary) -> bool:
	# 确保快照目录存在
	var dir: DirAccess = DirAccess.open("res://")
	var full_dir: String = "res://" + _snapshot_dir
	if not dir.dir_exists(full_dir):
		dir.make_dir_recursive(full_dir)

	# 构造文件名：场景名_快照名.json（特殊字符替换为下划线）
	var scene_name: String = scene_path.get_file().replace(".tscn", "").replace(".scn", "")
	var safe_name: String = _sanitize(snapshot_name)
	var file_name: String = scene_name + "_" + safe_name + ".json"
	var file_path: String = full_dir + "/" + file_name

	# 构造快照数据并写入 JSON
	var snapshot: Dictionary = {
		"scene": scene_path,
		"timestamp": Time.get_datetime_string_from_system(),
		"name": snapshot_name,
		"data": _serialize_data(data)
	}
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	return true

## 从文件加载快照数据，返回解析后的字典（失败返回空字典）
func load_snapshot(file_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	return json.data as Dictionary

## 列出当前场景的所有快照，按时间戳倒序排列
## 每个快照字典额外包含 "_file_path" 字段用于删除操作
func list_snapshots(scene_path: String) -> Array:
	var results: Array = []
	var full_dir: String = "res://" + _snapshot_dir
	var dir: DirAccess = DirAccess.open(full_dir)
	if not dir:
		print("[SPD] list_snapshots: cannot open dir ", full_dir)
		# 尝试用 res:// 根目录打开再检查
		var root_dir: DirAccess = DirAccess.open("res://")
		if root_dir and root_dir.dir_exists(full_dir):
			dir = root_dir
		else:
			return results
	print("[SPD] list_snapshots: opened dir ", full_dir)
	var scene_name: String = scene_path.get_file().replace(".tscn", "").replace(".scn", "")
	print("[SPD] list_snapshots: scene_name=", scene_name, " scene_path=", scene_path)
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(scene_name + "_") and file_name.ends_with(".json"):
			var snap: Dictionary = load_snapshot(full_dir + "/" + file_name)
			if snap.size() > 0:
				snap["_file_path"] = full_dir + "/" + file_name
				results.append(snap)
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(func(a, b): return a["timestamp"] > b["timestamp"])
	print("[SPD] list_snapshots: found ", results.size(), " snapshots")
	return results

## 删除指定路径的快照文件，返回是否成功
func delete_snapshot(file_path: String) -> bool:
	var dir: DirAccess = DirAccess.open("res://")
	return dir.remove(file_path) == OK

## 将快照数据恢复到节点
## [param snapshot] 快照字典（需包含 "data" 字段）
## [param node_map] 节点路径 → 节点实例的映射
func apply_snapshot(snapshot: Dictionary, node_map: Dictionary) -> void:
	if not snapshot.has("data"):
		return
	var data: Dictionary = snapshot["data"]
	for node_path in data:
		if not node_map.has(node_path):
			continue
		var node: Node = node_map[node_path]
		var props: Dictionary = data[node_path]
		for prop_name in props:
			if prop_name in node:
				node.set(prop_name, _deserialize_value(props[prop_name]))

## 序列化收集的数据为快照 "data" 字段格式
## 输出：{ 节点路径: { 属性名: 序列化值, ... }, ... }
func _serialize_data(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node_path in data:
		var entry = data[node_path]
		var node: Node = entry["node"]
		var props: Array = entry["properties"]
		var prop_dict: Dictionary = {}
		for prop in props:
			var pname: String = prop["name"]
			var value: Variant = node.get(pname)
			prop_dict[pname] = _serialize_value(value)
		result[node_path] = prop_dict
	return result

## 将 Godot 值序列化为 JSON 可存储格式
## 复合类型（Color/Vector2/Vector3/Rect2）转为带 _type 标记的字典
## Resource 存 resource_path，Node 存场景树路径
func _serialize_value(value: Variant) -> Variant:
	if value is Resource:
		return value.resource_path
	if value is Node:
		return str(value.get_path())
	if value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "_type": "Color"}
	if value is Vector2:
		return {"x": value.x, "y": value.y, "_type": "Vector2"}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z, "_type": "Vector3"}
	if value is Rect2:
		return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y, "_type": "Rect2"}
	return value

## 将 JSON 值反序列化为 Godot 类型
## 识别带 _type 标记的字典，还原为 Color/Vector2/Vector3/Rect2
func _deserialize_value(value: Variant) -> Variant:
	if value is Dictionary and value.has("_type"):
		match value["_type"]:
			"Color":
				return Color(value["r"], value["g"], value["b"], value["a"])
			"Vector2":
				return Vector2(value["x"], value["y"])
			"Vector3":
				return Vector3(value["x"], value["y"], value["z"])
			"Rect2":
				return Rect2(value["x"], value["y"], value["w"], value["h"])
	return value

## 将快照名中的非法文件名字符替换为下划线
func _sanitize(name: String) -> String:
	var result: String = ""
	for c in name:
		if c.is_valid_filename() or c == " ":
			result += c
		else:
			result += "_"
	return result
