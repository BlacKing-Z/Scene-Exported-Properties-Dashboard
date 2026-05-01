## SnapshotDialog — 创建快照对话框
##
## 弹出一个输入框让用户输入快照名称（如 "v1平衡"），
## 确认后通过 confirmed_with_name 信号将名称传递给 DashboardPanel。
@tool
extends AcceptDialog

## 确认信号：携带用户输入的快照名称
signal confirmed_with_name(snap_name: String)

## 快照名称输入框
@onready var _name_edit: LineEdit = $VBox/NameEdit

func _ready() -> void:
	_name_edit.placeholder_text = "输入快照名称"
	# 连接 AcceptDialog 的 confirmed 信号
	confirmed.connect(_on_confirmed)

## 对话框确认回调：发射带快照名称的信号（去除首尾空白）
func _on_confirmed() -> void:
	confirmed_with_name.emit(_name_edit.text.strip_edges())
