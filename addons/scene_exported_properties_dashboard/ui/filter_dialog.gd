## FilterDialog — 分组显示/隐藏筛选对话框
@tool
extends AcceptDialog

signal confirmed_with_data(hidden: Dictionary)

var _groups: PackedStringArray = []
var _hidden: Dictionary = {}
var _checkboxes: Array = []

@onready var _container: VBoxContainer = $Scroll/VBox

func setup(groups: PackedStringArray, hidden: Dictionary) -> void:
	_groups = groups
	_hidden = hidden

func _ready() -> void:
	_build_checkboxes()
	confirmed.connect(_on_confirmed)

func _build_checkboxes() -> void:
	if not _container:
		return
	for child in _container.get_children():
		child.queue_free()
	_checkboxes.clear()
	for group in _groups:
		var cb: CheckBox = CheckBox.new()
		cb.text = group
		cb.button_pressed = not _hidden.has(group)
		_container.add_child(cb)
		_checkboxes.append(cb)

func _on_confirmed() -> void:
	var hidden: Dictionary = {}
	for i in _checkboxes.size():
		if not _checkboxes[i].button_pressed:
			hidden[_groups[i]] = true
	confirmed_with_data.emit(hidden)
