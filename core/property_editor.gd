## PropertyEditor — 属性值读写与修改追踪
##
## 职责：
##   1. 设置节点属性值，并追踪"修改前旧值"用于回写
##   2. 记录哪些变量在运行时被修改过（key = "节点路径/属性名", value = 修改前的旧值）
##   3. 提供"应用回场景文件"功能：将修改持久化到 .tscn
##
## 修改追踪逻辑：
##   - 首次修改：记录旧值
##   - 再次修改回旧值：自动从 _modified 中移除（视为未修改）
##   - 这样"应用回场景文件"只保存真正有变化的变量
extends RefCounted

var _editor_interface: EditorInterface

## 修改追踪字典。key = "节点路径/属性名"，value = 修改前的原始值
var _modified: Dictionary = {}

func _init(p_editor_interface: EditorInterface) -> void:
	_editor_interface = p_editor_interface

## 设置节点属性值并追踪修改
## [param node_path] 节点路径（如 "Enemy/Goblin"）
## [param node] 目标节点实例
## [param prop_name] 属性名
## [param new_value] 新值
func set_property_value(node_path: String, node: Node, prop_name: String, new_value: Variant) -> void:
	var old_value: Variant = node.get(prop_name)
	node.set(prop_name, new_value)
	var key: String = node_path + "/" + prop_name
	if _modified.has(key):
		# 如果改回原始值，视为"未修改"，从追踪中移除
		if _modified[key] == new_value:
			_modified.erase(key)
			return
	else:
		# 首次修改，记录原始值
		_modified[key] = old_value

## 返回当前已修改变量数量
func get_modified_count() -> int:
	return _modified.size()

## 返回修改追踪字典的副本
func get_modified() -> Dictionary:
	return _modified.duplicate()

## 清空修改追踪（通常在保存后调用）
func clear_modified() -> void:
	_modified.clear()

## 将运行时修改应用回场景文件
## 遍历 _modified 中的所有已修改变量，确保节点上的值已设置，
## 然后调用 EditorInterface.save_scene() 保存当前场景
## [param node_map] 节点路径 → 节点实例的映射
func apply_to_scene_file(node_map: Dictionary) -> void:
	for key in _modified:
		var parts: PackedStringArray = key.split("/")
		var prop_name: String = parts[-1]
		var node_path: String = key.substr(0, key.length() - prop_name.length() - 1)
		if not node_map.has(node_path):
			continue
		var node: Node = node_map[node_path]
		# 节点上已经是新值，此处 set 确保编辑器实例也同步
		node.set(prop_name, node.get(prop_name))
	_editor_interface.save_scene()
	clear_modified()
