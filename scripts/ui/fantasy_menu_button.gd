# 保留真实按钮和焦点行为，绘制两列对齐的中世纪菜单。
extends Button

const Style = preload("res://scripts/ui/fantasy_menu_style.gd")
signal selection_requested(button: Button)
@export var english := "PLAY"
var selected := false
var highlight := 0.0
var motion: Tween


func _ready() -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_request_selection)
	focus_entered.connect(_request_selection)
	queue_redraw()


func _request_selection() -> void:
	selection_requested.emit(self)


func set_selected(value: bool, instant: bool = false) -> void:
	selected = value
	if motion != null:
		motion.kill()
	if instant:
		_set_highlight(1.0 if value else 0.0)
		return
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_method(_set_highlight, highlight, 1.0 if value else 0.0, 0.16)


func _set_highlight(value: float) -> void:
	highlight = value
	queue_redraw()


func _draw() -> void:
	var x := 12.0 * highlight
	var w := size.x - 38.0
	var h := size.y - 12.0
	var rim := Style.BRONZE.lerp(Color("e5c58b"), highlight)
	var ink := Style.INK.lerp(Style.PAPER, highlight)
	if disabled:
		rim = Color("b7ad8e")
		ink = Color("a19d85")
	var points := PackedVector2Array([Vector2(x + 28, 0), Vector2(x + w, 0), Vector2(x + w - 28, h), Vector2(x, h)])
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(3, 5))
	draw_colored_polygon(shadow, Color(0.41, 0.34, 0.20, 0.18))
	draw_colored_polygon(points, Color("f5ebd0").lerp(Color("99533f"), highlight))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, rim, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(x + 34, 7), Vector2(x + w - 10, 7), Vector2(x + w - 34, h - 7), Vector2(x + 10, h - 7), Vector2(x + 34, 7)]), Color(rim, 0.32), 1.0, true)
	# 中文左齐、英文右齐；用字体基线居中，避免删掉图标后留下多余缩进。
	var chinese_font := Style.chinese()
	var english_font := Style.display()
	var chinese_baseline := (h + chinese_font.get_ascent(40) - chinese_font.get_descent(40)) * 0.5
	var english_baseline := (h + english_font.get_ascent(18) - english_font.get_descent(18)) * 0.5
	var english_width := english_font.get_string_size(english, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(chinese_font, Vector2(x + 64, chinese_baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, ink)
	draw_string(english_font, Vector2(x + w - 52 - english_width, english_baseline), english, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Style.MUTED.lerp(Color("f3d5a2"), highlight) if not disabled else ink)
	for tip in [Vector2(x + w - 33, 18), Vector2(x + w - 50, h - 18)]:
		draw_polyline(PackedVector2Array([tip + Vector2(-15, 0), tip, tip + Vector2(-4, 13)]), rim, 1.0, true)
	if highlight > 0.01:
		var center := Vector2(x - 24, h * 0.5)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -12), center + Vector2(7, 0), center + Vector2(0, 12), center + Vector2(-7, 0)]), Color(Style.RED, highlight))
		draw_line(center + Vector2(-17, 0), center + Vector2(-10, 0), Color(Style.RED, highlight), 1.0, true)
		draw_line(center + Vector2(10, 0), center + Vector2(17, 0), Color(Style.RED, highlight), 1.0, true)
