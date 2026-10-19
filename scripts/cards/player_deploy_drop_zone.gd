# 这玩意儿是干嘛的（核心逻辑）：接收战场上的拖牌，交给统一入口判断征召、单位效果或全局能力。
# 数据是咋流动的（数据流向）：拖动时只预览目标，松开时才交给战场检查费用并执行。
# 为啥这么写（选型决策）：接收区覆盖视口，征召范围由实际导航左半边决定，不被旧矩形截断。
# 性能咋样（复杂度）：仅拖牌经过接收区时查找本场目标，平时不扫描单位。
extends Control

## 相对本拖放接收区的战场节点路径，目标需提供 try_play_unit_card 接口。用于把屏幕拖放落点转换成世界位置并交给战场验证和施放。
@export var battle_scene_path: NodePath = NodePath("../..")
@onready var battle_scene: Node2D = get_node_or_null(battle_scene_path)
var preview_local_position := Vector2.ZERO
var has_preview_position := false


# 作用：记录鼠标在接收区的局部位置；event 为引擎输入事件，没有返回值。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		preview_local_position = get_global_transform_with_canvas().affine_inverse() * event.position
		has_preview_position = true


# 作用：Godot 开始或结束拖放时清除旧落点；what 为通知编号，没有返回值。
func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_BEGIN, NOTIFICATION_DRAG_END]:
		has_preview_position = false


# 作用：将接收区局部落点转成战场世界坐标；point 是局部坐标，返回世界坐标。
func _world_drop_position(point: Vector2) -> Vector2:
	# 使用 Godot 拖放给出的坐标，预览与松开都走这里，并正确处理 Camera2D。
	return battle_scene.get_canvas_transform().affine_inverse() * (get_global_transform_with_canvas() * point)


# 作用：Godot 每帧读取当前拖牌与鼠标覆盖区域；_delta 为帧间隔，没有返回值。
func _process(_delta: float) -> void:
	if not is_instance_valid(battle_scene) or not is_instance_valid(battle_scene.card_runtime):
		return
	var runtime = battle_scene.card_runtime
	var viewport := get_viewport()
	if not is_visible_in_tree() or not viewport.gui_is_dragging() or not has_preview_position:
		runtime.clear_cast_preview()
		return
	# 鼠标覆盖手牌、按钮或弹窗时不预览背后的单位。
	var hovered := viewport.gui_get_hovered_control()
	if hovered != self and (hovered == null or not is_ancestor_of(hovered)):
		runtime.clear_cast_preview()
		return
	var data: Variant = viewport.gui_get_drag_data()
	if not data is Dictionary or data.get("kind") != &"unit_card":
		runtime.clear_cast_preview()
		return
	var source = data.get("source_card")
	if not is_instance_valid(source) or source.is_queued_for_deletion():
		runtime.clear_cast_preview()
		return
	runtime.update_cast_preview(data.get("card_instance") as CardInstance, _world_drop_position(preview_local_position))

# 作用：初始化部署区，并监听游戏阶段变化。
# 参数：没有参数，由 Godot 在节点进入场景树后调用。
# 返回值：没有返回值。
func _ready() -> void:
	# 只负责接收落点；后绘制的手牌与按钮仍优先接收鼠标。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SignalBus.phase_change.connect(_on_phase_changed)
	_on_phase_changed(Global.game_phase)


# 作用：判断当前拖过来的东西是不是可以召唤的单位牌。
# 参数 at_position：鼠标在部署区内的位置，本次只利用区域本身进行限制。
# 参数 data：UnitCard 提供的拖放数据。
# 返回值：true 代表松开鼠标可以召唤，false 代表卡牌会回到手牌。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not Global.is_card_play_phase():
		return false

	if battle_scene == null or not battle_scene.has_method("try_play_unit_card"):
		return false

	if not data is Dictionary:
		return false

	if data.get("kind") != &"unit_card":
		return false

	var card_instance := data.get("card_instance") as CardInstance
	var source_card := data.get("source_card") as Control

	return card_instance != null and is_instance_valid(source_card)


# 作用：玩家在有效区域松开鼠标后，请求 BattleScene 执行卡牌。
# 参数 at_position：接收区局部落点，转换成世界坐标后施放。
# 参数 data：包含单位数据和来源卡牌。
# 返回值：没有返回值。
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return

	var card_instance := data.get("card_instance") as CardInstance

	# 和预览使用同一套坐标转换，避免相机移动后高亮和施放位置不一致。
	var spawn_position: Vector2 = _world_drop_position(at_position)
	battle_scene.try_play_unit_card(
		card_instance,
		spawn_position
	)

# 作用：准备与交锋都允许拖牌，同时放行战场所需的鼠标事件。
# 参数 phase：Global 刚刚切换到的游戏阶段。
# 返回值：没有返回值。
func _on_phase_changed(phase: Global.GamePhase) -> void:
	if phase in [Global.GamePhase.CARD_PLAY, Global.GamePhase.AUTO_BATTLE]:
		mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		# 结算和胜负阶段不再接收拖牌。
		mouse_filter = Control.MOUSE_FILTER_IGNORE
