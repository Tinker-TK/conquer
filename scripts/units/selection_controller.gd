# 这玩意儿是干嘛的（核心逻辑）：准备阶段点击或框选己方单位，相机移动后框选位置仍对应战场。
# 数据是咋流动的（数据流向）：鼠标转换到世界坐标选择单位；世界选框再投影到 UI 显示。
# 为啥这么写（选型决策）：选框在 CanvasLayer 中，不能直接把世界坐标当成屏幕坐标。
# 性能咋样（复杂度）：拖选时每帧更新一个矩形，松开才遍历己方单位。
extends Node2D

const ControlledUnit := preload("res://scripts/units/team_a_base.gd")
const ClickIndicator := preload("res://scripts/effects/move_click_indicator.gd")

var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_cursor_screen: Vector2 = Vector2.ZERO

@onready var control: Control = $CanvasLayer/Control
@onready var selection_frame: NinePatchRect = $CanvasLayer/Control/SelectionFrame
var selected_units: Array = []
var click_indicator: Node2D


func _ready() -> void:
	SignalBus.phase_change.connect(_on_phase_changed)
	get_window().focus_exited.connect(_cancel_drag)
	get_window().mouse_exited.connect(_cancel_drag)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and is_node_ready():
		_cancel_drag()


# 从战场开始的框选也可能在 UI 上松开；先结束选择，避免选框残留并拦截后续点击。
func _input(event: InputEvent) -> void:
	if not is_dragging:
		return
	if not is_visible_in_tree() or get_tree().paused or Global.game_phase != Global.GamePhase.CARD_PLAY:
		_cancel_drag()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_selected(drag_start, get_canvas_transform().affine_inverse() * event.position)
		_cancel_drag()
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_cancel_drag()
		else:
			drag_cursor_screen = event.position
			_update_selection_rectangle()

# 作用：Godot 处理未被 UI 消费的选择输入；event 为鼠标事件，没有返回值。
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_tree().paused:
		return
	if event is InputEventMouseButton and Global.game_phase == Global.GamePhase.CARD_PLAY:
		if event.is_action_pressed("move"):
			var floor_step := 1 if event.alt_pressed else (-1 if event.ctrl_pressed else 0)
			_show_move_indicator(get_canvas_transform().affine_inverse() * event.position, floor_step)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_cursor_screen = event.position
				drag_start = get_canvas_transform().affine_inverse() * event.position
				_update_selection_rectangle()
			else:
				if is_dragging:
					_finish_selected(drag_start, get_canvas_transform().affine_inverse() * event.position)
				_cancel_drag()


# 作用：拖选期间相机移动也刷新选框；delta 为帧间隔，没有返回值。
func _process(_delta: float) -> void:
	if is_dragging:
		if not is_visible_in_tree() or Global.game_phase != Global.GamePhase.CARD_PLAY:
			_cancel_drag()
		else:
			_update_selection_rectangle()


# 作用：把世界中的选框转换成固定 UI 层坐标；没有参数，没有返回值。
func _update_selection_rectangle() -> void:
	var world_to_screen := get_canvas_transform()
	var screen_to_ui := control.get_canvas_transform().affine_inverse()
	var start: Vector2 = screen_to_ui * (world_to_screen * drag_start)
	var finish: Vector2 = screen_to_ui * drag_cursor_screen
	var rectangle := Rect2(start, finish - start).abs()
	control.global_position = rectangle.position
	control.size = rectangle.size
	# 原图四角各占24像素；极短或窄拖框居中显示最小48像素，实际选中范围仍使用鼠标矩形。
	selection_frame.size = rectangle.size.max(Vector2(48, 48))
	selection_frame.position = (rectangle.size - selection_frame.size) * 0.5
	control.visible = rectangle.size.length() > 5.0


func _cancel_drag() -> void:
	is_dragging = false
	control.hide()


func _on_phase_changed(phase: int) -> void:
	if phase != Global.GamePhase.CARD_PLAY:
		_cancel_drag()
		if is_instance_valid(click_indicator):
			click_indicator.queue_free()


# 单位继续使用原有移动接口；这里只显示一次整队指令的实际导航落点。
func _show_move_indicator(world_point: Vector2, floor_step: int = 0) -> void:
	for unit in selected_units:
		if not _can_select(unit) or unit.is_stunned:
			continue
		var resolved: Dictionary = unit.resolve_move_destination(world_point, floor_step)
		if resolved.is_empty():
			continue
		var destination: Vector2 = resolved.position
		var destination_floor: int = resolved.floor
		if is_instance_valid(click_indicator):
			click_indicator.free()
		click_indicator = ClickIndicator.new()
		add_child(click_indicator)
		if is_instance_valid(unit.floor_map):
			click_indicator.z_index += (destination_floor - 1) * unit.floor_map.floor_z_stride
		click_indicator.global_position = destination
		return

# 作用：松开时选择单击或框选；start_pos、end_pos 是世界坐标，没有返回值。
func _finish_selected(start_pos: Vector2, end_pos: Vector2):
	if start_pos.distance_to(end_pos) <= 5.0:
		_click_selected(start_pos)
	else:
		_box_selected(Rect2(min(start_pos.x,end_pos.x),min(start_pos.y,end_pos.y),abs(start_pos.x-end_pos.x),abs(start_pos.y-end_pos.y)))

# 作用：选择点击附近单位；start_pos 是世界坐标，没有返回值。
func _click_selected(start_pos:Vector2):
	clear_selection()
	for unit in get_tree().get_nodes_in_group('team_a'):
		if not _can_select(unit):
			continue
		if unit.global_position.distance_to(start_pos) <= 40.0:
			_add_seleted(unit)
			print(selected_units)
			break


# 作用：选中矩形内的己方单位；box 为世界坐标矩形，没有返回值。
func _box_selected(box: Rect2):
	clear_selection()
	for unit in get_tree().get_nodes_in_group('team_a'):
		if not _can_select(unit):
			continue
		if box.has_point(unit.global_position):
			_add_seleted(unit)
	print(selected_units)
	
# 作用：取消旧选择并跳过已死亡对象；没有参数，没有返回值。
func clear_selection():
	for unit in selected_units:
		if is_instance_valid(unit) and unit is ControlledUnit:
			unit.is_selected = false
	selected_units.clear()


# 己方分组还包含策反兵和其它自动单位；只有原己方操控脚本提供选中与部署接口。
func _can_select(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is ControlledUnit and unit.is_inside_tree() \
		and not unit.is_queued_for_deletion() and unit.unit_data.unit_team == "team_a" \
		and not unit.is_in_group("converted_enemy") and not unit.is_in_group("player_base") \
		and unit.current_state != UnitBase.State.DEATH and unit.current_health > 0

# 作用：记录选中对象并变色；unit 为己方单位，没有返回值。
func _add_seleted(unit):
	if not _can_select(unit) or selected_units.has(unit):
		return
	selected_units.append(unit)
	unit.is_selected = true
