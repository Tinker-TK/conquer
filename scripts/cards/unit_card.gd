# 这玩意儿是干嘛的（核心逻辑）：显示一张具体卡牌，负责卡面命中、可用发光、原生拖放和右键兵种详情。
# 数据是咋流动的（数据流向）：原牌费用与能量 → 发光开关；鼠标拖动 → 手牌动画管理器与战场接收区。
# 为啥这么写（选型决策）：保留既有中心式卡面和 Godot 拖放；装饰不接鼠标，避免旋转放大后点击失效。
# 性能咋样（复杂度）：卡面只在配置变化时刷新，发光由着色器绘制，每次拖牌只建立一张预览。
extends Control
class_name UnitCard

const CARD_RECT := Rect2(-126.0, -169.0, 252.0, 338.0)
const COST_RECT := Rect2(-157.0, -199.0, 100.0, 100.0)
const GLOW_SHADER = preload("res://shaders/card_playable_glow.gdshader")
const RARE_FRAME_SHADER = preload("res://shaders/card_rare_frame.gdshader")
const UNIT_DETAILS = preload("res://scripts/ui/card_unit_details.gd")
const UPGRADED_NAME_COLOR := Color("7fff00")
const UPGRADED_NAME_OUTLINE_COLOR := Color("245c16")
var rare_frame_material: ShaderMaterial
## 此卡面预览使用的单位征召配置，提供名称、费用、插图和说明。运行时 setup 会以具体 CardInstance 绑定的数据覆盖，不能用它修改牌堆中的实例进度。
@export var unit_data: UnitData
var is_playable: bool = true
var card_instance: CardInstance
var hand_presenter: Control
var energy_available := false
var dragging := false
var glow: ColorRect
var glow_material: ShaderMaterial
var _glow_tween: Tween


# 作用：绑定一张原牌；card 是牌堆里的具体实例，没有返回值。
func setup(card: CardInstance) -> void:
	card_instance = card
	unit_data = card.unit_data
	_refresh_card_view()


# 作用：Godot 在卡面入树时准备装饰和鼠标命中；没有参数，没有返回值。
func _ready() -> void:
	# 原卡面向中心两侧绘制，根节点保持零尺寸；命中范围由 _has_point 明确提供。
	mouse_filter = Control.MOUSE_FILTER_STOP if is_playable else Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		_ignore_preview_mouse(child)
	_create_glow()
	_refresh_card_view()


# 作用：Godot 判断鼠标是否位于卡面内；point 是转换后的局部位置，返回能否命中卡面。
func _has_point(point: Vector2) -> bool:
	# 费用徽章突出在卡面左上角，鼠标放在徽章上也应该能查看和拖动这张牌。
	return CARD_RECT.has_point(point) or COST_RECT.has_point(point)


# 只读选牌界面让左键继续传给外层选择按钮，右键由卡面自己处理。
func enable_unit_details() -> void:
	if card_instance != null and card_instance.is_unit_card():
		mouse_filter = Control.MOUSE_FILTER_STOP if is_playable else Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
		and event.pressed and card_instance != null and card_instance.is_unit_card() \
		and not dragging and not get_viewport().gui_is_dragging():
		accept_event()
		UNIT_DETAILS.show_for(card_instance, self)


# 作用：建立不挡鼠标的外围发光层；没有参数，没有返回值。
func _create_glow() -> void:
	glow = ColorRect.new()
	glow.name = "PlayableGlow"
	glow.position = Vector2(-153.0, -196.0)
	glow.size = Vector2(306.0, 392.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_material = ShaderMaterial.new()
	glow_material.shader = GLOW_SHADER
	glow.material = glow_material
	add_child(glow)
	move_child(glow, 0)
	glow.hide()


# 作用：能量或阶段变化时刷新光效；available 表示目前付得起费用且处于出牌阶段，没有返回值。
func set_energy_available(available: bool) -> void:
	var enabled := available and is_playable
	if energy_available == enabled:
		return
	energy_available = enabled
	if glow == null:
		return
	if _glow_tween != null and _glow_tween.is_running():
		_glow_tween.kill()
	# 不可用时立即熄灭，绝不保留一段让玩家误以为还能出牌的残光。
	if not enabled:
		glow.hide()
		glow_material.set_shader_parameter("strength", 0.0)
		return
	glow.show()
	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow_strength, 0.0, 1.0, 0.12)


# 作用：逐渐点亮卡面外围；value 是亮度，没有返回值。
func _set_glow_strength(value: float) -> void:
	glow_material.set_shader_parameter("strength", value)


# 作用：把配方与实例当前费用填入卡面；没有参数，没有返回值。
func _refresh_card_view() -> void:
	var data: Resource
	if card_instance != null:
		data = card_instance.definition
	else:
		data = unit_data
	if data == null:
		return
	# 显示退场后增加的实际费用，发光判断也读取同一个 get_cost()。
	$CostIcon/CostLabel.text = str(card_instance.get_cost() if card_instance != null else data.card_cost)
	$CardName.text = data.card_name
	if card_instance != null and card_instance.upgrade_count > 0:
		$CardName.text += "+"
		$CardName.add_theme_color_override("font_color", UPGRADED_NAME_COLOR)
		$CardName.add_theme_color_override("font_outline_color", UPGRADED_NAME_OUTLINE_COLOR)
	else:
		# 同一个卡面会复用，临时进化结束后还原场景中的普通文字样式。
		$CardName.remove_theme_color_override("font_color")
		$CardName.remove_theme_color_override("font_outline_color")
	$CardImage.texture = data.card_image
	$CardImage2.texture = data.card_image_2
	var description: String = card_instance.get_description() if card_instance != null else CardInstance.new(data).get_description()
	$CardDiscription.text = description
	# 以实际换行后的高度缩小长说明；卡面必须完整显示，不能靠滚动才能读完。
	$CardDiscription.scroll_active = false
	for font_size in [16, 14, 12, 11, 10]:
		$CardDiscription.add_theme_font_size_override("normal_font_size", font_size)
		if $CardDiscription.get_content_height() <= $CardDiscription.size.y:
			break
	var rare := card_instance != null and card_instance.definition.rarity == CardDefinition.Rarity.RARE
	if rare and rare_frame_material == null:
		rare_frame_material = ShaderMaterial.new()
		rare_frame_material.shader = RARE_FRAME_SHADER
	$FrameLayer.material = rare_frame_material if rare else null
	if card_instance != null and card_instance.definition != null:
		tooltip_text = ["征召", "强化", "能力"][card_instance.definition.category]
		tooltip_text += " · 稀有" if rare else " · 普通"
		if card_instance.definition.after_use == CardDefinition.AfterUse.PERSIST:
			tooltip_text += "\n常驻至战斗结束"
		tooltip_text += "\n" + description
		tooltip_text += "\n" + card_instance.upgrade_summary()
		if card_instance.is_unit_card():
			tooltip_text += "\n右键查看单位详情"


# 作用：Godot 请求拖放数据时建立随鼠标的卡面；_at_position 是点击局部位置，返回原牌数据或空。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_playable or card_instance == null or get_tree().paused or not Global.is_card_play_phase():
		return null
	# 独立预览避免复制手牌管理器引用和动画；原卡面仍留着，失败后可以飞回原位。
	var preview_root := Control.new()
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
	preview.is_playable = false
	preview_root.add_child(preview)
	preview.setup(card_instance)
	preview.position = Vector2(0.0, -28.0)
	preview.scale = Vector2.ONE * 0.9
	preview.modulate.a = 0.94
	_ignore_preview_mouse(preview)
	set_drag_preview(preview_root)
	dragging = true
	if is_instance_valid(hand_presenter):
		hand_presenter.begin_drag(self)
	return {"kind": &"unit_card", "card_instance": card_instance, "source_card": self}


# 作用：Godot 在拖放结束时恢复仍在手里的牌；what 是引擎通知，没有返回值。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and dragging:
		dragging = false
		if is_instance_valid(hand_presenter):
			hand_presenter.end_drag(self)


# 作用：装饰和预览卡面不截走鼠标；node 是需要穿透的节点，没有返回值。
func _ignore_preview_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_preview_mouse(child)
