## PropertyCollector — 遍历场景树，收集所有 @export 变量
## 直接从脚本源码解析 @export 变量名，不依赖 usage 标记
extends RefCounted

var _editor_interface: EditorInterface

func _init(p_editor_interface: EditorInterface) -> void:
	_editor_interface = p_editor_interface

func collect_exported_properties() -> Dictionary:
	var root: Node = _editor_interface.get_edited_scene_root()
	if not root:
		return {}
	var result: Dictionary = {}
	_collect_recursive(root, root, result)
	return result

func _collect_recursive(node: Node, root: Node, result: Dictionary) -> void:
	var path: String = _get_node_path_relative(node, root)
	var props: Array = _get_exported_props(node)
	if props.size() > 0:
		result[path] = {
			"node": node,
			"properties": props
		}
	for child in node.get_children():
		_collect_recursive(child, root, result)

func _get_node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return str(node.name)
	var root_path: String = str(root.get_path())
	var node_path: String = str(node.get_path())
	if not node_path.begins_with(root_path + "/"):
		return str(node.name)
	# 去掉根节点前缀，只保留子路径
	return node_path.substr(root_path.length() + 1)

## 从脚本源码解析所有 @export 变量，同时提取 group/subgroup 信息
func _get_exported_props(node: Node) -> Array:
	var script: Script = node.get_script() as Script
	if not script:
		return []
	var source: String = script.source_code
	if source == "":
		return []

	var result: Array = []
	var current_group: String = ""
	var current_subgroup: String = ""
	var lines: PackedStringArray = source.split("\n")

	# 预编译正则
	var group_re: RegEx = RegEx.create_from_string("@export_group\\([\"'](.+?)[\"']\\s*(?:,\\s*[\"'](.+?)[\"'])?\\)")
	var subgroup_re: RegEx = RegEx.create_from_string("@export_subgroup\\([\"'](.+?)[\"']\\s*(?:,\\s*[\"'](.+?)[\"'])?\\)")
	# 匹配所有 @export 变体（@export, @export_range, @export_enum 等）
	var export_re: RegEx = RegEx.create_from_string("@export")
	# 匹配 var 声明：var 变量名
	var var_re: RegEx = RegEx.create_from_string("var\\s+(\\w+)")

	var pending_export: bool = false

	for line in lines:
		var stripped: String = line.strip_edges(true, true)

		# 检测 @export_group
		var gm: RegExMatch = group_re.search(stripped)
		if gm:
			current_group = gm.get_string(1)
			current_subgroup = ""
			pending_export = false
			continue

		# 检测 @export_subgroup
		var sgm: RegExMatch = subgroup_re.search(stripped)
		if sgm:
			current_subgroup = sgm.get_string(1)
			pending_export = false
			continue

		# 检测 @export 注解
		var is_export_line: bool = export_re.search(stripped) != null

		# 情况1：@export 和 var 在同一行，如 @export var speed: float = 300.0
		if is_export_line:
			var vm: RegExMatch = var_re.search(stripped)
			if vm:
				_add_export_var(result, node, vm.get_string(1), current_group, current_subgroup)
				pending_export = false
			else:
				# @export 独占一行，下一行的 var 才是目标
				pending_export = true
			continue

		# 情况2：上一行有 @export，本行是 var 声明
		if pending_export:
			var vm2: RegExMatch = var_re.search(stripped)
			if vm2:
				_add_export_var(result, node, vm2.get_string(1), current_group, current_subgroup)
			pending_export = false

	return result

## 添加一个 export 变量到结果列表
func _add_export_var(result: Array, node: Node, var_name: String, group: String, subgroup: String) -> void:
	if not var_name in node:
		return
	result.append({
		"name": var_name,
		"value": node.get(var_name),
		"group": group,
		"subgroup": subgroup,
	})
