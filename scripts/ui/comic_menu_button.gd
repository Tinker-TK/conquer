# 这玩意儿是干嘛的（核心逻辑）：把普通 Button 画成带编号和箭头的斜切漫画菜单。
# 数据是咋流动的（数据流向）：鼠标悬停或键盘焦点 → 选中信号 → 位移补间 → 重画纸片与文字。
# 为啥这么写（选型决策）：仍然使用真实 Button 的点击和焦点，键盘、手柄和鼠标共用一套操作。
# 性能咋样（复杂度）：只有选中变化时做短补间；稳定后停止重画，不逐帧建立节点。
extends Button

const Style = preload("res://scripts/ui/comic_style.gd")
signal selection_requested(button: Button)
## 漫画菜单按钮旁显示的编号文字，如 01；只控制装饰编号，不决定菜单执行顺序。
@export var number := "01"
## 漫画菜单按钮显示的英文副标题，如 PLAY；实际点击动作仍由按钮连接的信号决定。
@export var english := "PLAY"
var selected := false
var highlight := 0.0
var motion: Tween


# 作用：引擎在按钮入树时连接焦点与悬停；没有参数，没有返回值。
func _ready() -> void:
	# 原生 Button 处理输入，自定义绘制负责可见文字，避免同时出现两份标题。
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_request_selection)
	focus_entered.connect(_request_selection)
	queue_redraw()


# 作用：告诉菜单玩家正在看这个选项；没有参数，没有返回值，不会直接执行按钮。
func _request_selection() -> void:
	selection_requested.emit(self)


# 作用：切换高亮纸片；value 表示是否选中，instant 表示跳过位移动画，没有返回值。
func set_selected(value: bool, instant: bool = false) -> void:
	selected = value
	if motion != null:
		motion.kill()
	if instant:
		_set_highlight(1.0 if value else 0.0)
		return
	# 补间只修改一个浮点数，箭头、文字和底板因此始终一起移动。
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_method(_set_highlight, highlight, 1.0 if value else 0.0, 0.16)


# 作用：补间传入新的高亮程度；value 从 0 到 1，没有返回值。
func _set_highlight(value: float) -> void:
	highlight = value
	queue_redraw()


# 作用：引擎在需要重画时绘制菜单；没有参数，没有返回值，坐标基于按钮实际大小。
func _draw() -> void:
	var x := 24.0 * highlight
	var w := size.x - 38.0
	var h := size.y - 12.0
	var points := PackedVector2Array([Vector2(x + 28, 0), Vector2(x + w, 0), Vector2(x + w - 28, h), Vector2(x, h)])
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(6, 8))
	draw_colored_polygon(shadow, Style.RED.lerp(Style.INK, 1.0 - highlight))
	draw_colored_polygon(points, Color("26252d").lerp(Style.PAPER, highlight))
	# 轻网点保留纸张质感；只画按钮上的几十个点，不铺满全屏。
	for column in range(15):
		for row in range(5):
			draw_circle(Vector2(x + 294 + column * 17, 10 + row * 17), 1.2, Color(0.1, 0.1, 0.12, 0.08))
	draw_colored_polygon(PackedVector2Array([Vector2(x + 32, 8), Vector2(x + 116, 8), Vector2(x + 94, h - 8), Vector2(x + 10, h - 8)]), Color("34313a").lerp(Style.RED, highlight))
	var ink := Style.PAPER.lerp(Style.INK, highlight)
	draw_string(Style.display(), Vector2(x + 38, 65), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 43, Style.PAPER)
	draw_string(Style.chinese(), Vector2(x + 145, 69), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, ink)
	draw_string(Style.display(), Vector2(x + 365, 64), english, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Style.MUTED.lerp(Style.RED, highlight))
	# 尾部的双斜杠和左侧箭头加强选中反馈；颜色以高亮程度淡入。
	for stripe in range(2):
		var sx := x + w - 48.0 + stripe * 19.0
		draw_colored_polygon(PackedVector2Array([Vector2(sx, 0), Vector2(sx + 10, 0), Vector2(sx - 18, h), Vector2(sx - 28, h)]), Style.RED)
	if highlight > 0.01:
		draw_polyline(PackedVector2Array([Vector2(x - 38, 30), Vector2(x - 20, 48), Vector2(x - 38, 66)]), Color(Style.GOLD, highlight), 9, true)
