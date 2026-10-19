# 详情面板的方形图标；冷却由真实 Timer 驱动，灰黑遮罩从十二点方向顺时针退去。
extends Control

var _frame: StyleBoxFlat
var texture: Texture2D
var symbol := ""
var tint := Color.WHITE
var cooldown_fraction := 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if not is_equal_approx(next, cooldown_fraction):
			cooldown_fraction = next
			queue_redraw()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	# 技能和状态是只读图标，使用无凸起、无投影的平面边框。
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color("364a48")
	_frame.border_color = Color("8d8967")
	_frame.set_border_width_all(1)


# 与方形图标边缘相交，而非画圆盘；图标的四个角也会被冷却遮住。
func cooldown_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if cooldown_fraction <= 0.0:
		return polygon
	var center := size * 0.5
	var start := TAU * (1.0 - cooldown_fraction)
	polygon.append(center)
	polygon.append(_edge_point(start))
	for corner in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		if corner > start:
			polygon.append(_edge_point(corner))
	polygon.append(_edge_point(TAU))
	return polygon


func _edge_point(angle: float) -> Vector2:
	var direction := Vector2(sin(angle), -cos(angle))
	var half := size * 0.5
	var reach := minf(half.x / maxf(absf(direction.x), 0.00001), half.y / maxf(absf(direction.y), 0.00001))
	return half + direction * reach


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_frame, rect)
	var surface_center := size * 0.5
	if texture != null:
		var available := (size - Vector2.ONE * 16).max(Vector2.ONE)
		var factor := minf(available.x / texture.get_width(), available.y / texture.get_height())
		var image_size := texture.get_size() * factor
		draw_texture_rect(texture, Rect2(surface_center - image_size * 0.5, image_size), false, tint)
	else:
		# 缺少贴图的毒、爆炸与灼烧仍使用与战场一致的符号语言。
		draw_set_transform(Vector2(8, 8), 0.0, (size - Vector2.ONE * 16) / 10.0)
		match symbol:
			"poison", "poison_on_hit":
				_shape([Vector2(5, 0), Vector2(9, 6), Vector2(8, 9), Vector2(5, 10), Vector2(2, 9), Vector2(1, 6)], Color("86d75b"))
				draw_circle(Vector2(4, 6), 1, Color("d7f3b6"))
				if symbol == "poison_on_hit":
					draw_line(Vector2(1, 9), Vector2(9, 1), Color("eeeac5"), 1.5)
			"explosion":
				_shape([Vector2(5, 0), Vector2(6, 3), Vector2(10, 2), Vector2(8, 5), Vector2(10, 8), Vector2(6, 7), Vector2(5, 10), Vector2(3, 7), Vector2(0, 8), Vector2(2, 5), Vector2(0, 2), Vector2(4, 3)], Color("f0a454"))
				draw_circle(Vector2(5, 5), 1.5, Color("ffebae"))
			"burn":
				_shape([Vector2(1, 7), Vector2(2, 3), Vector2(4, 5), Vector2(6, 0), Vector2(9, 5), Vector2(9, 8), Vector2(5, 10), Vector2(2, 9)], Color("ed874a"))
				_shape([Vector2(4, 8), Vector2(6, 4), Vector2(7, 8), Vector2(5, 9)], Color("ffe48e"))
			_:
				preload("res://scripts/ui/tactical_status_symbols.gd").draw_icon(self, symbol)
		draw_set_transform(Vector2.ZERO)
	if cooldown_fraction > 0.0:
		draw_colored_polygon(cooldown_polygon(), Color(0, 0, 0, 0.72))
		if cooldown_fraction < 1.0:
			draw_line(size * 0.5, _edge_point(TAU * (1.0 - cooldown_fraction)), Color("b6c1cc70"), 1.0)


func _shape(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
