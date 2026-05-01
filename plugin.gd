## Scene Parameter Dashboard — EditorPlugin 入口
@tool
extends EditorPlugin

var _dashboard: VBoxContainer

func _enter_tree() -> void:
	_dashboard = preload("ui/dashboard_panel.tscn").instantiate()
	_dashboard.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dashboard)
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)

func _exit_tree() -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	if _dashboard:
		remove_control_from_docks(_dashboard)
		_dashboard.queue_free()

func _handles(object: Object) -> bool:
	return object is PackedScene

func _edit(object: Object) -> void:
	if _dashboard and _dashboard.has_method("refresh"):
		_dashboard.refresh()

func _on_filesystem_changed() -> void:
	if _dashboard and _dashboard.has_method("refresh"):
		_dashboard.refresh()

func _process(delta: float) -> void:
	if _dashboard and _dashboard.is_visible_in_tree() and _dashboard.has_method("check_scene_changed"):
		_dashboard.check_scene_changed()
