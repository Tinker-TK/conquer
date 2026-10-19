# 这玩意儿是干嘛的（核心逻辑）：绘制向上推进的路线，让策划点击、拖动节点和选中连线。
# 数据是咋流动的（数据流向）：鼠标位置 → 层级与比例坐标 → 文档事务 → 重画路线。
# 为啥这么写（选型决策）：原生 Control 绘图不需要浏览器，试玩仅显示可走路线，不启动战斗。
# 性能咋样（复杂度）：编辑时绘制所有节点和连线；鼠标按下才做命中检查，没有每帧扫描。
@tool
extends Control

signal picked(id: String)
signal placed(kind: int, floor: int, x: float)
signal edge_picked(from: String, to: String)
var doc = preload("res://addons/map_editor/document.gd").new()
var mode := 0
var add_kind := -1
var source := ""
var selected_edge: Array = []
var journey: Array[String] = []
var dragging := false
var drag_origin := Vector2.ZERO
var dragged := false
const COLORS := [Color("c9bda2"), Color("b6a5d1"), Color("8fc6ac"), Color("e6a176"), Color("e6c986"), Color("d5bc70"), Color("bf839b"), Color("b6a5d1")]
const SYMBOLS := ["战", "事", "休", "B", "宝", "商", "精", "?"]

# 作用：引擎创建画布后设置宽度与交互；没有参数，没有返回值。
func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 460
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	refresh()

# 作用：按地图层数调整滚动高度；没有参数，没有返回值。
func refresh() -> void:
	custom_minimum_size.y = maxf(660.0, float(doc.data.get("floors", 10)) * 110.0 + 30.0)
	queue_redraw()

# 作用：把节点转换为画布中心坐标；node 为配置，返回像素位置。
func point(node: Dictionary) -> Vector2:
	var total := int(doc.data.get("floors", 10))
	return Vector2(65.0 + float(node.map_pos.x) * (size.x - 130.0), size.y - 70.0 - float(node.floor - 1) * (size.y - 140.0) / (total - 1))

# 作用：把鼠标换算成吸附层和横向比例；position 为鼠标像素位置，返回坐标字典。
func coordinates(position: Vector2) -> Dictionary:
	var total := int(doc.data.floors)
	return {"x": clampf((position.x - 65.0) / (size.x - 130.0), 0.03, 0.97),
		"floor": clampi(roundi((size.y - 70.0 - position.y) / (size.y - 140.0) * (total - 1)) + 1, 1, total)}

# 作用：查询试玩能进入的节点；没有参数，返回起点或当前节点的后续编号。
func available() -> Array:
	if journey.is_empty():
		return doc.data.get("starting_ids", [])
	return doc.find(journey.back()).get("next", [])

# 作用：引擎请求重画时显示层线、路线、节点和状态；没有参数，没有返回值。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("182225"))
	if doc.data.is_empty():
		return
	var font := get_theme_default_font()
	var total := int(doc.data.floors)
	for floor in range(1, total + 1):
		var y := size.y - 70.0 - float(floor - 1) * (size.y - 140.0) / (total - 1)
		draw_line(Vector2(55, y), Vector2(size.x - 30, y), Color("344448"))
		draw_string(font, Vector2(15, y + 5), "%02d" % floor, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("91a6a5"))
	for node in doc.data.locations:
		for id in node.next:
			var target: Dictionary = doc.find(id)
			if target.is_empty():
				continue
			var from := point(node)
			var to := point(target)
			var direction := (to - from).normalized()
			var color := Color("e9bb72") if selected_edge == [node.id, id] else Color("718a82")
			draw_line(from + direction * 26, to - direction * 30, color, 3, true)
			var end := to - direction * 30
			draw_line(end, end - direction.rotated(0.5) * 12, color, 2, true)
			draw_line(end, end - direction.rotated(-0.5) * 12, color, 2, true)
	var allowed := available()
	for node in doc.data.locations:
		var pos := point(node)
		var color: Color = COLORS[int(node.type)]
		if mode == 2 and not allowed.has(node.id) and not journey.has(node.id):
			color.a = 0.3
		draw_circle(pos, 25, Color("28383b"))
		if journey.has(node.id) and mode == 2:
			draw_circle(pos, 25, Color("426753"))
		var highlight: bool = (mode == 2 and allowed.has(node.id)) or node.id == doc.selection or node.id == source
		draw_arc(pos, 25, 0, TAU, 48, Color("e9bb72") if highlight else color, 3 if highlight else 2, true)
		draw_string(font, pos + Vector2(-14, 7), SYMBOLS[int(node.type)], HORIZONTAL_ALIGNMENT_CENTER, 28, 20, color)
		draw_string(font, pos + Vector2(-65, 45), node.title, HORIZONTAL_ALIGNMENT_CENTER, 130, 13, color)
		if doc.data.starting_ids.has(node.id):
			draw_string(font, pos + Vector2(-45, 62), "出发点", HORIZONTAL_ALIGNMENT_CENTER, 90, 12, Color("e9bb72"))

# 作用：鼠标命中节点或连线并拖动；event 为引擎 GUI 输入，没有返回值。
func _gui_input(event: InputEvent) -> void:
	if doc.data.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			finish_drag()
			return
		grab_focus()
		var id := ""
		for node in doc.data.locations:
			if point(node).distance_to(event.position) <= 28:
				id = node.id
				break
		if not id.is_empty():
			if mode == 2:
				if available().has(id):
					journey.append(id)
					picked.emit(id)
					queue_redraw()
			else:
				picked.emit(id)
				if mode == 0 and add_kind == -1:
					dragging = true
					dragged = false
					drag_origin = event.position
					doc.begin()
		elif mode == 0 and add_kind >= 0:
			var coord := coordinates(event.position)
			placed.emit(add_kind, coord.floor, coord.x)
		elif mode == 0:
			for node in doc.data.locations:
				for target in node.next:
					var next: Dictionary = doc.find(target)
					if not next.is_empty() and Geometry2D.get_closest_point_to_segment(event.position, point(node), point(next)).distance_to(event.position) < 7:
						edge_picked.emit(node.id, target)
						return
			picked.emit("")
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_origin) > 4 or dragged:
			dragged = true
			var coord := coordinates(event.position)
			doc.node().floor = coord.floor
			doc.node().map_pos.x = coord.x
			doc.normalize()
			queue_redraw()
		accept_event()

# 作用：结束拖动并提交一次撤销记录；没有参数，没有返回值。
func finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	if dragged:
		doc.commit()
	else:
		doc.before = {}
	dragged = false
