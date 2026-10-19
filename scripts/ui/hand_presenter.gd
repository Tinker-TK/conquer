# 这玩意儿是干嘛的（核心逻辑）：像摊开一把扑克牌一样排列手牌，播放抽入、弃置、出牌和悬停动画。
# 数据是咋流动的（数据流向）：牌堆移动说明 → 原牌编号对应的卡面 → 圆弧目标位置与 Tween；不改变真实牌堆。
# 为啥这么写（选型决策）：保存原卡面而不是整手重建，动画层承接离场卡；规则立即结算，连续操作也不会吞牌。
# 性能咋样（复杂度）：每次手牌变化只处理手中卡，每帧悬停只检查这些小矩形；通常十几张牌，动画由引擎驱动。
extends Control

const CARD_SCENE = preload("res://scenes/cards/unit_card.tscn")
const SOUL_RIBBON_SCENE = preload("res://scenes/effects/pixel_soul_ribbon.tscn")
@export_group("圆弧手牌")
## 手牌未悬停时的卡面缩放倍率，1 为原始卡面尺寸；越小则常规手牌越紧凑。悬停尺寸单独由 Hover Scale 控制。
@export_range(0.4, 1.0, 0.01) var hand_scale := 0.74
## 手牌相邻卡面中心的期望水平间距，单位为界面像素；手牌过多或可用宽度不足时会自动压缩，不影响真实牌堆。
@export var card_spacing := 158.0
## 整排手牌中心分布的最大宽度，单位为界面像素；还会受当前窗口可用空间限制，越小则牌越集中。
@export var max_hand_width := 1180.0
## 手牌排列圆弧的基础半径，单位为界面像素；越大则弧线越平、两端旋转越小。为了满足最大扇形角度，实际半径可能自动增大。
@export var arc_radius := 1550.0
## 左右最外侧卡牌允许的最大旋转角度，单位为度；越大则扇形更展开，越小则排列更平。
@export_range(5.0, 30.0, 1.0) var max_fan_angle := 18.0
## 手牌基准中心距容器底部的距离，单位为界面像素；越大则整排手牌更靠上。卡面本身围绕中心绘制。
@export var bottom_inset := 137.0
@export_group("悬停")
## 鼠标悬停卡牌时使用的绝对缩放倍率，1 为原始卡面大小；与 Hand Scale 分别控制悬停和常规尺寸。
@export var hover_scale := 1.04
## 悬停卡牌向上抬起的距离，单位为界面像素；越大则更容易看清卡面，实际位置还受边界保护限制。
@export var hover_lift := 132.0
## 悬停时相邻卡牌向左右让出的基础距离，单位为界面像素；距离悬停牌越远则让开越少，0 表示不额外展开。
@export var neighbor_spread := 48.0
@export_group("动效节奏（秒）")
## 手牌位置、旋转和缩放调整的补间时长，单位为秒；越小越快，控制排列变化和悬停切换的过渡。
@export var layout_duration := 0.2
## 单张卡从抽牌堆飞入手牌的动画时长，单位为秒；只控制表现，不延迟真实抽牌规则。
@export var draw_duration := 0.42
## 同批抽牌中相邻两张开始飞入的时间间隔，单位为秒；0 同时飞入，越大则分张节奏越明显。
@export var draw_stagger := 0.085
## 单张卡飞向弃牌堆的动画时长，单位为秒；只控制视觉表现，不延迟真实弃置和回合清场。
@export var discard_duration := 0.34
## 同批弃牌中相邻两张开始飞出的时间间隔，单位为秒；0 同时飞出，越大则分张弃置更明显。
@export var discard_stagger := 0.045
## 成功出牌后卡面飞向施放位置的动画时长，单位为秒；扣费和效果即时结算，动画不影响规则生效时间。
@export var play_duration := 0.2
@export_group("单位施放光带")
## 从卡面飞出、绕目标半圈再进入单位的时间；只控制表现，卡牌效果仍即时结算。
@export_range(0.5, 2.0, 0.05) var unit_ribbon_duration := 0.5
## 光带前端抵达后，尾迹继续被单位吸收的时间。
@export_range(0.1, 0.8, 0.05) var unit_ribbon_trail := 0.15
## 目标外围环绕的半径，单位为界面像素，不受相机缩放影响。
@export_range(40.0, 140.0, 1.0) var unit_ribbon_radius := 72.0

var views: Dictionary[int, UnitCard] = {}
var ordered_cards: Array[CardInstance] = []
var slots: Dictionary = {}
var pending_motions: Dictionary = {}
var layout_tweens: Dictionary = {}
var entering: Dictionary = {}
var entrance_tweens: Dictionary = {}
var hovered_card: UnitCard
var dragged_card: UnitCard
var animation_layer: Control
var battle: Node2D
var card_ui: CanvasLayer
var available_energy := 0
var _mouse_position := Vector2.ZERO
var _board_discard_index := 0


# 作用：Godot 在手牌入树时连接离场动画层并监听尺寸；没有参数，没有返回值。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui = get_parent() as CanvasLayer
	battle = card_ui.get_parent() as Node2D
	# 层级高于手牌，鼠标却可以穿透，飞向战场的卡面不会挡住下一次出牌。
	animation_layer = card_ui.get_node("CardAnimations") as Control
	resized.connect(_on_resized)
	_mouse_position = get_viewport().get_mouse_position()


# 作用：Godot 收到鼠标移动时先确定要放大的卡；event 是输入事件，没有返回值。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_position = event.position
		_update_hover()


# 作用：Godot 每帧在动画移动后检查悬停；_delta 是帧间隔，没有返回值。
func _process(_delta: float) -> void:
	_update_hover()


# 作用：Godot 暂停战斗时收起放大的牌，避免弹窗关闭后残留；what 是通知，没有返回值。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		set_hovered_card(null)


# 作用：记录真实牌堆发来的移动原因；card 是原牌，motion 是操作，world_position 是世界落点，没有返回值。
func queue_card_motion(card: CardInstance, motion: StringName, world_position: Vector2) -> void:
	if motion == &"board_discard":
		var ghost := CARD_SCENE.instantiate() as UnitCard
		ghost.is_playable = false
		animation_layer.add_child(ghost)
		ghost.setup(card)
		ghost.position = world_to_ui(world_position)
		ghost.scale = Vector2.ONE * hand_scale
		# 同一次清场逐张错开，复用普通弃牌的飞行、缩小和淡出。
		if _board_discard_index == 0:
			_reset_board_discard_index.call_deferred()
		_fly_to_pile(ghost, "DiscardButton", _board_discard_index * discard_stagger)
		_board_discard_index += 1
		return
	# 随机出牌从未进入手牌；只生成视觉副本，不伪造一次抽牌或改动遗物计数。
	if motion == &"random_play":
		var ghost := CARD_SCENE.instantiate() as UnitCard
		ghost.is_playable = false
		animation_layer.add_child(ghost)
		ghost.setup(card)
		ghost.position = pile_position("DrawButton")
		ghost.scale = Vector2.ONE * 0.3
		_play_departure(ghost, world_position)
		return
	pending_motions[card.id] = {"kind": motion, "point": world_position}


# 作用：记录单位效果牌的目标和施放前阵营，供卡面与环绕光带共同使用。
func queue_unit_card_motion(card: CardInstance, target: UnitBase, from_draw: bool) -> void:
	var motion := {"kind": &"unit_play", "target": weakref(target), "point": target.global_position,
		"palette": 1 if target.unit_data.unit_team == "team_a" else 2}
	if from_draw:
		var ghost := CARD_SCENE.instantiate() as UnitCard
		ghost.is_playable = false
		animation_layer.add_child(ghost)
		ghost.setup(card)
		ghost.position = pile_position("DrawButton")
		ghost.scale = Vector2.ONE * 0.3
		_fly_into_unit(ghost, motion)
	else:
		pending_motions[card.id] = motion


# 作用：结束本次清场的错开计数；没有参数，没有返回值。
func _reset_board_discard_index() -> void:
	_board_discard_index = 0


# 作用：同步当前手牌并复用已有卡面；cards 是真实手牌快照，没有返回值。
func sync_hand(cards: Array[CardInstance]) -> void:
	var active_ids: Dictionary = {}
	for card in cards:
		active_ids[card.id] = true
	# 离场卡先从可交互集合移走，再播放动画；期间新抽到同一原牌也能安全建立新卡面。
	var discard_index := 0
	for id: int in views.keys():
		if active_ids.has(id):
			continue
		var view := views[id]
		var motion: Dictionary = pending_motions.get(id, {"kind": &"discard", "point": Vector2.ZERO})
		_remove_view(view, motion, discard_index * discard_stagger)
		discard_index += 1
		views.erase(id)
		pending_motions.erase(id)
	ordered_cards.assign(cards)
	_compute_slots()
	var draw_index := 0
	for card in ordered_cards:
		if views.has(card.id):
			views[card.id].setup(card)
			continue
		var view := CARD_SCENE.instantiate() as UnitCard
		view.hand_presenter = self
		add_child(view)
		view.setup(card)
		views[card.id] = view
		var motion: Dictionary = pending_motions.get(card.id, {"kind": &"draw", "point": Vector2.ZERO})
		var start := world_to_ui(motion.point) if motion.kind == &"return" else pile_position("DrawButton")
		_start_entrance(view, start, draw_index * draw_stagger)
		draw_index += 1
		pending_motions.erase(card.id)
	_layout_hand()
	refresh_availability()


# 作用：计算每张卡的圆弧位置；没有参数，没有返回值。
func _compute_slots() -> void:
	slots.clear()
	var count := ordered_cards.size()
	# 手牌越多间距越小；限制扇形角度，避免两边的牌掉进牌堆按钮区域。
	var width := minf(max_hand_width, maxf(200.0, size.x - 560.0))
	var spacing := minf(card_spacing, width / maxf(1.0, count - 1.0))
	var half_span := spacing * maxf(0.0, count - 1.0) * 0.5
	var radius := maxf(arc_radius, half_span / sin(deg_to_rad(max_fan_angle)))
	for i in count:
		var x := (i - (count - 1.0) * 0.5) * spacing
		var angle := asin(clampf(x / radius, -1.0, 1.0))
		var position_on_arc := Vector2(size.x * 0.5 + x, size.y - bottom_inset + radius * (1.0 - cos(angle)))
		slots[ordered_cards[i].id] = {"position": position_on_arc, "rotation": angle, "index": i}


# 作用：让卡面平滑移动到当前手牌位置；没有参数，没有返回值。
func _layout_hand() -> void:
	var hover_index := -1
	if is_instance_valid(hovered_card) and slots.has(hovered_card.card_instance.id):
		hover_index = int(slots[hovered_card.card_instance.id].index)
	for card in ordered_cards:
		var view := views[card.id]
		var slot: Dictionary = slots[card.id]
		view.z_index = int(slot.index) + 10
		if view == dragged_card or entering.has(card.id):
			continue
		var target: Vector2 = slot.position
		var target_rotation: float = slot.rotation
		var target_scale := hand_scale
		if view == hovered_card:
			# 放大牌抬高、扶正并放到最上层，让文字完整露出来。
			target.y = minf(target.y - hover_lift, size.y - 190.0)
			target.x = clampf(target.x, 160.0, size.x - 160.0)
			target_rotation = 0.0
			target_scale = hover_scale
			view.z_index = 80
		elif hover_index >= 0:
			var distance := int(slot.index) - hover_index
			target.x += signf(float(distance)) * neighbor_spread / maxf(1.0, absf(float(distance)))
		_tween_layout(view, target, target_rotation, target_scale)
	# Godot 的鼠标命中按子节点顺序处理；同时调整顺序，才能让置顶卡真正在最上层接收拖动。
	for card in ordered_cards:
		move_child(views[card.id], -1)
	if is_instance_valid(hovered_card) and hovered_card.get_parent() == self:
		move_child(hovered_card, -1)


# 作用：替换卡面的旧布局动画；view 是卡面，target/angle/zoom 是位置、角度、大小，没有返回值。
func _tween_layout(view: UnitCard, target: Vector2, angle: float, zoom: float) -> void:
	_stop_layout(view.card_instance.id)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	layout_tweens[view.card_instance.id] = tween
	tween.tween_property(view, "position", target, layout_duration)
	tween.tween_property(view, "rotation", angle, layout_duration)
	tween.tween_property(view, "scale", Vector2.ONE * zoom, layout_duration)


# 作用：取消一张牌的旧布局动画；id 是原牌编号，没有返回值。
func _stop_layout(id: int) -> void:
	var tween: Tween = layout_tweens.get(id)
	if tween != null and tween.is_running():
		tween.kill()
	layout_tweens.erase(id)


# 作用：逐张安排卡面从牌堆或单位位置飞入；view 是新卡，start 是起点，delay 是错开时间，没有返回值。
func _start_entrance(view: UnitCard, start: Vector2, delay: float) -> void:
	var id := view.card_instance.id
	entering[id] = true
	view.position = start
	view.scale = Vector2.ONE * 0.24
	view.rotation = -0.55
	view.modulate.a = 0.0
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	entrance_tweens[id] = tween
	if delay > 0.0:
		tween.tween_interval(delay)
	# 飞行中动态读取槽位，连锁抽牌或改窗口大小也不会落到过期的位置。
	tween.tween_callback(_draw_sound.bind(weakref(view)))
	tween.tween_method(_entrance_step.bind(view, start), 0.0, 1.0, draw_duration)
	tween.tween_callback(_finish_entrance.bind(view))


func _draw_sound(reference: WeakRef) -> void:
	var view := reference.get_ref() as UnitCard
	if is_instance_valid(view) and views.get(view.card_instance.id) == view:
		UIAudio.play(&"card_draw")


# 作用：沿弧线更新飞入卡；progress 是进度，view 是卡面，start 是起点，没有返回值。
func _entrance_step(progress: float, view: UnitCard, start: Vector2) -> void:
	if not slots.has(view.card_instance.id):
		return
	var slot: Dictionary = slots[view.card_instance.id]
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	view.position = start.lerp(slot.position, eased) + Vector2(0.0, -sin(progress * PI) * 95.0)
	view.rotation = lerpf(-0.55, slot.rotation, eased)
	view.scale = Vector2.ONE * lerpf(0.24, hand_scale, eased)
	view.modulate.a = minf(1.0, progress * 5.0)


# 作用：飞入完成后恢复卡面交互；view 是到位卡，没有返回值。
func _finish_entrance(view: UnitCard) -> void:
	entering.erase(view.card_instance.id)
	entrance_tweens.erase(view.card_instance.id)
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_hand()


# 作用：找出鼠标下应该放大的手牌；没有参数，没有返回值。
func _update_hover() -> void:
	if dragged_card != null or get_viewport().gui_is_dragging():
		return
	if get_tree().paused or not Global.is_card_play_phase():
		set_hovered_card(null)
		return
	var point := get_global_transform_with_canvas().affine_inverse() * _mouse_position
	var candidate: UnitCard
	# 使用稳定的原槽位选牌；否则放大牌把邻牌遮住后，鼠标会反复进出产生抖动。
	for i in range(ordered_cards.size() - 1, -1, -1):
		var id := ordered_cards[i].id
		if entering.has(id):
			continue
		var slot: Dictionary = slots[id]
		var local := (point - Vector2(slot.position)).rotated(-float(slot.rotation)) / hand_scale
		if views[id]._has_point(local):
			candidate = views[id]
			break
	# 鼠标移到被抬高的卡面上继续阅读时，也保持悬停，不要求留在原来的小槽位里。
	if candidate == null and is_instance_valid(hovered_card):
		var local := hovered_card.get_global_transform_with_canvas().affine_inverse() * _mouse_position
		if hovered_card._has_point(local):
			candidate = hovered_card
	set_hovered_card(candidate)


# 作用：切换当前放大的牌；view 是目标卡面或空，没有返回值。
func set_hovered_card(view: UnitCard) -> void:
	if hovered_card == view:
		return
	hovered_card = view
	if is_instance_valid(view):
		UIAudio.play(&"hover")
	_layout_hand()


# 作用：开始拖放时收起手里的原卡面；view 是拖动来源，没有返回值。
func begin_drag(view: UnitCard) -> void:
	dragged_card = view
	hovered_card = null
	_stop_layout(view.card_instance.id)
	view.modulate.a = 0.0
	# 透明仍然会接收 GUI 命中；拖起后放行原卡面下的单位，回弹时恢复交互。
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_hand()


# 作用：拖放失败或取消时让卡飞回手牌；view 是拖动来源，没有返回值。
func end_drag(view: UnitCard) -> void:
	if dragged_card == view:
		dragged_card = null
	# 成功出牌已从 views 移走并交给离场层，绝不能再把它拉回手里。
	if views.get(view.card_instance.id) != view:
		return
	view.position = get_global_transform_with_canvas().affine_inverse() * _mouse_position + Vector2(0.0, -28.0)
	view.scale = Vector2.ONE * 0.9
	view.rotation = 0.0
	view.modulate.a = 1.0
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_hand()


# 作用：把离场卡交给动画层；view 是旧卡面，motion 是原因与落点，delay 是弃牌错开时间，没有返回值。
func _remove_view(view: UnitCard, motion: Dictionary, delay: float) -> void:
	var id := view.card_instance.id
	_stop_layout(id)
	var entrance: Tween = entrance_tweens.get(id)
	if entrance != null and entrance.is_running():
		entrance.kill()
	entrance_tweens.erase(id)
	entering.erase(id)
	if hovered_card == view:
		hovered_card = null
	var was_dragged := dragged_card == view
	if was_dragged:
		dragged_card = null
	# 本层和动画层都使用屏幕坐标；相机移动不会影响牌堆的固定位置。
	view.reparent(animation_layer)
	view.hand_presenter = null
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_energy_available(false)
	view.modulate.a = 1.0
	if motion.kind in [&"play", &"unit_play"]:
		if was_dragged:
			view.position = _mouse_position + Vector2(0.0, -28.0)
			view.rotation = 0.0
			view.scale = Vector2.ONE * 0.9
		if motion.kind == &"unit_play":
			_fly_into_unit(view, motion)
		else:
			_play_departure(view, motion.point)
	else:
		_fly_to_pile(view, "ExhaustButton" if motion.kind == &"exhaust" else "DiscardButton", delay)


# 作用：单位牌效果沿弃牌弧线缩入目标，抵达后直接消失；view 是卡面，motion 保存弱引用和最后位置，没有返回值。
func _fly_into_unit(view: UnitCard, motion: Dictionary) -> void:
	_play_unit_ribbon(view.position, motion)
	var tween := view.create_tween()
	tween.tween_method(_unit_flight_step.bind(view, view.position, view.scale.x, view.rotation, motion), 0.0, 1.0, discard_duration)
	tween.tween_callback(view.queue_free)


# 作用：飞行中跟随单位和相机，目标退场后使用最后位置；progress 是进度，其余参数为卡面和起始姿态，没有返回值。
func _unit_flight_step(progress: float, view: UnitCard, start: Vector2, zoom: float, angle: float, motion: Dictionary) -> void:
	_card_flight_step(progress, view, start, zoom, angle, _unit_motion_destination(motion))


# 作用：从实际卡面中心发射示例同款光带，己方金色、敌方紫色；尾迹吸收后自行清理。
func _play_unit_ribbon(start: Vector2, motion: Dictionary) -> void:
	var ribbon := SOUL_RIBBON_SCENE.instantiate() as PixelSoulRibbon
	ribbon.autoplay = false
	ribbon.palette_preset = int(motion.palette)
	ribbon.flight_duration = unit_ribbon_duration
	ribbon.trail_delay = unit_ribbon_trail
	ribbon.acceleration = 1.15
	ribbon.head_width = 18.0
	ribbon.curve_samples = 128
	ribbon.glow_enabled = true
	ribbon.z_index = 90
	ribbon.set_orbit_path(start, _unit_motion_destination(motion), unit_ribbon_radius)
	animation_layer.add_child(ribbon)
	ribbon.finished.connect(ribbon.queue_free)
	ribbon.restart()
	# Tween 与特效同属动画层，暂停和战场退出时自动停下；不依赖已消失的卡面。
	var tween := ribbon.create_tween()
	tween.tween_method(_unit_ribbon_step.bind(ribbon, motion), 0.0, 1.0, ribbon.get_duration())


func _unit_ribbon_step(_progress: float, ribbon: PixelSoulRibbon, motion: Dictionary) -> void:
	ribbon.move_orbit_target(_unit_motion_destination(motion))


# 作用：飞行中跟随单位和相机，目标退场后继续吸收至最后的世界位置。
func _unit_motion_destination(motion: Dictionary) -> Vector2:
	var target := (motion.target as WeakRef).get_ref() as UnitBase
	if is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion():
		motion.point = target.global_position
	return world_to_ui(motion.point)


# 作用：成功出牌时让牌冲向世界落点，再按去向收走；view 是卡面，point 是世界落点，没有返回值。
func _play_departure(view: UnitCard, point: Vector2) -> void:
	var target := world_to_ui(point)
	var tween := view.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", target, play_duration)
	tween.tween_property(view, "rotation", 0.0, play_duration)
	tween.tween_property(view, "scale", Vector2.ONE * 0.64, play_duration)
	# 轻微提亮只属于这次释放动画，不代表剩余手牌可用能量增加。
	tween.tween_property(view, "modulate", Color(1.35, 1.35, 1.15, 1.0), play_duration)
	tween.chain().tween_callback(_finish_play.bind(view))


# 作用：根据原牌的结算去向完成离场；view 是已抵达落点的卡，没有返回值。
func _finish_play(view: UnitCard) -> void:
	var definition := view.card_instance.definition
	if definition.category == CardDefinition.Category.RECRUIT:
		# 征召原牌绑定到单位，不进弃牌堆；卡面缩散消失在召唤位置。
		var tween := view.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "scale", Vector2.ONE * 0.9, 0.15)
		tween.tween_property(view, "modulate:a", 0.0, 0.15)
		tween.chain().tween_callback(view.queue_free)
	else:
		var pile := "ExhaustButton" if definition.after_use == CardDefinition.AfterUse.EXHAUST else "DiscardButton"
		_fly_to_pile(view, pile, 0.06)


# 作用：把弃置或用完的牌沿弧线缩进目标牌堆；view 是卡，pile 是按钮名，delay 是延迟，没有返回值。
func _fly_to_pile(view: UnitCard, pile: String, delay: float) -> void:
	var tween := view.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(_pile_flight_step.bind(view, view.position, view.scale.x, view.rotation, pile), 0.0, 1.0, discard_duration)
	tween.tween_callback(view.queue_free)


# 作用：推进一次牌堆飞行动画；progress 是进度，view/start/zoom/angle 是卡和起始姿态，pile 是目标，没有返回值。
func _pile_flight_step(progress: float, view: UnitCard, start: Vector2, zoom: float, angle: float, pile: String) -> void:
	_card_flight_step(progress, view, start, zoom, angle, pile_position(pile))


# 作用：共用弧线、缩小、旋转和淡出，让单位吸收与弃牌的手感一致；target 是当前 UI 落点，没有返回值。
func _card_flight_step(progress: float, view: UnitCard, start: Vector2, zoom: float, angle: float, target: Vector2) -> void:
	var eased := progress * progress
	view.position = start.lerp(target, eased) + Vector2(0.0, -sin(progress * PI) * 80.0)
	view.scale = Vector2.ONE * lerpf(zoom, 0.12, progress)
	view.rotation = lerpf(angle, 0.65, progress)
	view.modulate.a = 1.0 - smoothstep(0.65, 1.0, progress)


# 作用：取得牌堆按钮的屏幕中心；button_name 是现有节点名，返回 UI 坐标。
func pile_position(button_name: String) -> Vector2:
	var button := card_ui.get_node("CardButtons/" + button_name) as Control
	return button.get_global_transform_with_canvas() * (button.size * 0.5)


# 作用：把世界位置映射到 UI，兼容相机移动与缩放；point 是世界坐标，返回 UI 坐标。
func world_to_ui(point: Vector2) -> Vector2:
	return card_ui.get_final_transform().affine_inverse() * (battle.get_canvas_transform() * point)


# 作用：更新当前能量并刷新所有手牌发光；energy 是剩余能量，没有返回值。
func set_available_energy(energy: int) -> void:
	available_energy = energy
	refresh_availability()


# 作用：阶段或能量变化时判断手牌是否应发光；没有参数，没有返回值。
func refresh_availability() -> void:
	var can_play: bool = battle.battle_round_manager.can_play_cards()
	for view: UnitCard in views.values():
		var cost := view.card_instance.get_cost()
		view.set_energy_available(can_play and cost >= 0 and cost <= available_energy)
	if not can_play:
		set_hovered_card(null)


# 作用：Godot 在窗口尺寸变化时重新计算手牌圆弧；没有参数，没有返回值。
func _on_resized() -> void:
	_compute_slots()
	_layout_hand()
