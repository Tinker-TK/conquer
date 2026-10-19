# 选牌共用透明点击区；整排底板保持静止，悬停只缩放卡面，选中用卡面外的金框标记。
@tool
extends Button

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const CARD_SCENE = preload("res://scenes/cards/unit_card.tscn")
const HOVER_FACTOR := 1.35
var view: Control
var selection_frame: Panel
var base_scale := 0.7
var _hovered := false
var _selected := false
var _motion: Tween


static func row_background() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CardRowBackground"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style := UI.button_box("normal", false, false, true)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(_queue_hover_update)
	mouse_exited.connect(_queue_hover_update)
	resized.connect(_reset_pose)
	visibility_changed.connect(_visibility_changed)


func setup(card: CardInstance, card_scale: float = 0.7) -> void:
	base_scale = card_scale
	tooltip_text = card.definition.card_name + "\n" + card.get_description()
	if Engine.is_editor_hint():
		var label := Label.new()
		label.text = card.definition.card_name
		label.add_theme_font_override("font", UI.FONT.chinese())
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", UI.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var card_view := CARD_SCENE.instantiate() as UnitCard
	card_view.is_playable = false
	add_child(card_view)
	view = card_view
	card_view.setup(card)
	_ignore_mouse(card_view)
	card_view.enable_unit_details()
	card_view.mouse_entered.connect(_queue_hover_update)
	card_view.mouse_exited.connect(_queue_hover_update)
	selection_frame = Panel.new()
	selection_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_frame.position = UnitCard.CARD_RECT.position - Vector2(5, 5)
	selection_frame.size = UnitCard.CARD_RECT.size + Vector2(10, 10)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color("ffe17a")
	frame.set_border_width_all(4)
	selection_frame.add_theme_stylebox_override("panel", frame)
	card_view.add_child(selection_frame)
	card_view.move_child(selection_frame, 0)
	selection_frame.visible = _selected
	_reset_pose()


func set_selected(value: bool) -> void:
	_selected = value
	if is_instance_valid(selection_frame):
		selection_frame.visible = value


func _has_point(point: Vector2) -> bool:
	if not is_instance_valid(view):
		return Rect2(Vector2.ZERO, size).has_point(point)
	# 底板上的空隙不触发悬停；同时保留原卡面与放大卡面的命中范围，避免动画抖动。
	var resting := (point - _rest_position()) / base_scale
	var current := (point - view.position) / view.scale
	return UnitCard.CARD_RECT.has_point(resting) or UnitCard.COST_RECT.has_point(resting) \
		or UnitCard.CARD_RECT.has_point(current) or UnitCard.COST_RECT.has_point(current)


func _rest_position() -> Vector2:
	# 费用徽章向左上突出，稍向右下偏移，让整张卡面在点击区中居中。
	return size * 0.5 + Vector2(8, 8)


func _queue_hover_update() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		_sync_hover.call_deferred()


func _sync_hover() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(view):
		return
	var target := get_viewport().gui_get_hovered_control()
	var hovered := is_visible_in_tree() and not disabled and target != null \
		and (target == self or is_ancestor_of(target))
	if hovered == _hovered:
		return
	_hovered = hovered
	if _motion != null:
		_motion.kill()
		_motion = null
	z_index = 10 if hovered else 0
	_motion = create_tween().set_parallel(true)
	_motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_property(view, "scale", Vector2.ONE * base_scale * (HOVER_FACTOR if hovered else 1.0), 0.14)
	_motion.tween_property(view, "position", _rest_position() - Vector2(0, 6 if hovered else 0), 0.14)


func _reset_pose() -> void:
	if not is_instance_valid(view):
		return
	if _motion != null:
		_motion.kill()
		_motion = null
	_hovered = false
	z_index = 0
	view.scale = Vector2.ONE * base_scale
	view.position = _rest_position()
	if is_visible_in_tree():
		_queue_hover_update()


func _visibility_changed() -> void:
	_reset_pose()


func _exit_tree() -> void:
	if _motion != null:
		_motion.kill()
		_motion = null


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
