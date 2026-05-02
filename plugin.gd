## Scene Parameter Dashboard — EditorPlugin 入口
@tool
extends EditorPlugin

var _dock: EditorDock

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Dashboard"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	var panel: VBoxContainer = preload("ui/dashboard_panel.tscn").instantiate()
	panel.plugin = self
	_dock.add_child(panel)
	add_dock(_dock)
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)

func _exit_tree() -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null

func _handles(object: Object) -> bool:
	return object is PackedScene

func _edit(object: Object) -> void:
	var panel = _get_panel()
	if panel and panel.has_method("refresh"):
		panel.refresh()

func _on_filesystem_changed() -> void:
	var panel = _get_panel()
	if panel and panel.has_method("refresh"):
		panel.refresh()

func _process(delta: float) -> void:
	var panel = _get_panel()
	if panel and panel.is_visible_in_tree() and panel.has_method("check_scene_changed"):
		panel.check_scene_changed()

func _get_panel():
	if _dock:
		for child in _dock.get_children():
			if child is VBoxContainer:
				return child
	return null
