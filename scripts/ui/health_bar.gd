# 显示单位生命和左对齐的小状态；满血时只隐藏血条，已有状态仍然显示。
# 血条和图标留在同一单位下，沿用脚底 Y 排序；图标内容由战斗运行时推送。
extends Control

const STATUS_DISPLAY := preload("res://scripts/ui/unit_status_display.gd")
@onready var hp_bar: TextureProgressBar = $PanelContainer/MarginContainer/HpBar
@onready var panel: PanelContainer = $PanelContainer
var status_display: Control
var pending_statuses: Array[Dictionary] = []
var hp_revealed := false


func _ready() -> void:
	_ignore_mouse(self)
	panel.hide()
	status_display = STATUS_DISPLAY.new()
	status_display.name = "StatusDisplay"
	# 血条原有 0.2 倍缩放；抵消它，让图标保持 10 个世界像素，相比单位足够小。
	status_display.scale = Vector2.ONE / scale
	add_child(status_display)
	panel.resized.connect(_position_statuses)
	_position_statuses()
	set_statuses(pending_statuses)


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)


func _position_statuses() -> void:
	status_display.position = Vector2(panel.position.x, panel.position.y + panel.size.y + 2.0 / scale.y)


func setup(max_health: int) -> void:
	hp_bar.max_value = max_health
	hp_bar.value = max_health


func update_hp_bar(current_health: int) -> void:
	hp_bar.value = current_health


# 支持入树前预置状态；已 ready 时立即更新显示。
func set_statuses(entries: Array) -> void:
	pending_statuses.assign(entries.duplicate(true))
	if status_display != null:
		status_display.set_statuses(pending_statuses)
	visible = hp_revealed or not pending_statuses.is_empty()


func _on_hp_bar_value_changed(_value: float) -> void:
	if hp_bar.value < hp_bar.max_value:
		hp_revealed = true
	panel.visible = hp_revealed
	visible = hp_revealed or not pending_statuses.is_empty()
