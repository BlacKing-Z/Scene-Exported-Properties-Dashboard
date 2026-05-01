## SnapshotList — 快照管理对话框
@tool
extends AcceptDialog

signal snapshot_selected(snapshot: Dictionary)

var _snapshot_mgr
var _snapshots: Array = []

@onready var _list: ItemList = $VBox/List
@onready var _btn_restore: Button = $VBox/HBox/BtnRestore
@onready var _btn_delete: Button = $VBox/HBox/BtnDelete

func setup(snapshots: Array, mgr) -> void:
	_snapshots = snapshots
	_snapshot_mgr = mgr

func _ready() -> void:
	_btn_restore.text = "恢复"
	_btn_delete.text = "删除"
	_btn_restore.pressed.connect(_on_restore)
	_btn_delete.pressed.connect(_on_delete)
	_list.item_selected.connect(_on_item_selected)
	_refresh_list()

func _refresh_list() -> void:
	if not _list:
		return
	_list.clear()
	for snap in _snapshots:
		var label: String = snap.get("name", "?") + "  (" + snap.get("timestamp", "?") + ")"
		_list.add_item(label)

func _on_item_selected(idx: int) -> void:
	_btn_restore.disabled = false
	_btn_delete.disabled = false

func _on_restore() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	var idx: int = selected[0] if selected.size() > 0 else -1
	if idx < 0 or idx >= _snapshots.size():
		return
	snapshot_selected.emit(_snapshots[idx])
	hide()

func _on_delete() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	var idx: int = selected[0] if selected.size() > 0 else -1
	if idx < 0 or idx >= _snapshots.size():
		return
	var snap: Dictionary = _snapshots[idx]
	if snap.has("_file_path"):
		_snapshot_mgr.delete_snapshot(snap["_file_path"])
	_snapshots.remove_at(idx)
	_refresh_list()
