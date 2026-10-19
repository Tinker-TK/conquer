# 单位血条下方的状态图标：左对齐、增减益混排，按首次生效顺序每行显示五个。
# 同类状态更新数值时保留位置，完全解除后重新施加则排到末尾；不拦截战场输入。
extends Control

const ICON_SIZE := 10.0
const CELL_WIDTH := 14.0
const ROW_HEIGHT := 14.0
const ICONS_PER_ROW := 5
var statuses: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = not statuses.is_empty()


func set_statuses(entries: Array[Dictionary]) -> void:
	var incoming := {}
	for entry: Dictionary in entries:
		incoming[String(entry.icon)] = entry
	var ordered: Array[Dictionary] = []
	# 保留仍在生效的图标顺序，叠层或提示更新不会移动它们。
	for previous: Dictionary in statuses:
		var key := String(previous.icon)
		if incoming.has(key):
			ordered.append(incoming[key].duplicate(true))
			incoming.erase(key)
	# 新出现的状态按输入的施加顺序追加，已消失的状态不再占位。
	for entry: Dictionary in entries:
		var key := String(entry.icon)
		if incoming.has(key):
			ordered.append(entry.duplicate(true))
			incoming.erase(key)
	if statuses == ordered:
		return
	statuses = ordered
	var columns := mini(statuses.size(), ICONS_PER_ROW)
	var rows := ceili(float(statuses.size()) / ICONS_PER_ROW)
	size = Vector2(columns * CELL_WIDTH, rows * ROW_HEIGHT)
	visible = not statuses.is_empty()
	queue_redraw()


# 与绘制使用同一矩形，通过完整画布变换命中，兼容相机缩放与 HUD 拖牌接收区。
func status_at(screen_position: Vector2) -> Dictionary:
	if not is_visible_in_tree():
		return {}
	var point := get_global_transform_with_canvas().affine_inverse() * screen_position
	for index in statuses.size():
		if icon_rect(index).grow(1.0).has_point(point):
			return statuses[index]
	return {}


func icon_rect(index: int) -> Rect2:
	return Rect2(Vector2((index % ICONS_PER_ROW) * CELL_WIDTH, floori(float(index) / ICONS_PER_ROW) * ROW_HEIGHT),
		Vector2.ONE * ICON_SIZE)


func _draw() -> void:
	for index in statuses.size():
		var entry: Dictionary = statuses[index]
		draw_set_transform(icon_rect(index).position)
		_draw_symbol(String(entry.icon))
		var count := int(entry.get("count", 0))
		if count > 0:
			var font := ThemeDB.fallback_font
			var text := str(count)
			var origin := Vector2(ICON_SIZE - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 2, 12)
			draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 2, Color("14201e"))
			draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("e9efce"))
	draw_set_transform(Vector2.ZERO)


func _shape(points: Array, tint: Color) -> void:
	var polygon := PackedVector2Array()
	for point: Vector2 in points:
		polygon.append(point)
	draw_colored_polygon(polygon, tint)
	polygon.append(polygon[0])
	draw_polyline(polygon, Color("18232add"), 1.0, true)


func _draw_symbol(kind: String) -> void:
	match kind:
		"attack":
			_shape([Vector2(4, 6), Vector2(4, 2), Vector2(5, 0), Vector2(6, 2), Vector2(6, 6)], Color("e66b70"))
			draw_line(Vector2(2, 6), Vector2(8, 6), Color("b84350"), 2)
			draw_line(Vector2(5, 7), Vector2(5, 10), Color("b84350"), 2)
		"max_hp":
			_shape([Vector2(1, 1), Vector2(3, 0), Vector2(5, 2), Vector2(7, 0), Vector2(9, 1), Vector2(10, 4), Vector2(5, 10), Vector2(0, 4)], Color("de777e"))
		"defence", "overflow_shield", "steadfast", "armor_shred":
			_shape([Vector2(1, 1), Vector2(5, 0), Vector2(9, 1), Vector2(8, 6), Vector2(5, 10), Vector2(2, 6)], Color("669edb"))
			draw_line(Vector2(5, 2), Vector2(5, 7), Color("bddcf0"), 1)
			if kind == "armor_shred":
				draw_line(Vector2(2, 1), Vector2(8, 8), Color("dc6672"), 2)
			elif kind == "overflow_shield":
				draw_line(Vector2(2, 4), Vector2(8, 4), Color("eddf9a"), 2)
		"haste":
			draw_polyline(PackedVector2Array([Vector2(1, 2), Vector2(6, 5), Vector2(1, 8)]), Color("8ddbc7"), 2)
			draw_polyline(PackedVector2Array([Vector2(5, 2), Vector2(10, 5), Vector2(5, 8)]), Color("8ddbc7"), 2)
		"banner":
			draw_line(Vector2(1, 0), Vector2(1, 10), Color("ecd29a"), 2)
			_shape([Vector2(2, 1), Vector2(9, 1), Vector2(7, 4), Vector2(9, 6), Vector2(2, 6)], Color("ce6b6c"))
		"mud":
			_shape([Vector2(3, 0), Vector2(6, 0), Vector2(6, 5), Vector2(9, 6), Vector2(9, 8), Vector2(2, 8)], Color("b7986a"))
			draw_line(Vector2(0, 10), Vector2(10, 10), Color("826d4e"), 1)
		"burn":
			_shape([Vector2(1, 7), Vector2(2, 3), Vector2(4, 5), Vector2(6, 0), Vector2(9, 5), Vector2(9, 8), Vector2(5, 10), Vector2(2, 9)], Color("dc8a51"))
			_shape([Vector2(4, 8), Vector2(6, 4), Vector2(7, 8), Vector2(5, 9)], Color("efc16a"))
		"poison", "poison_on_hit":
			_shape([Vector2(5, 0), Vector2(9, 6), Vector2(8, 9), Vector2(5, 10), Vector2(2, 9), Vector2(1, 6)], Color("a7bd68") if kind == "poison_on_hit" else Color("8aaa67"))
			draw_circle(Vector2(4, 6), 1, Color("daebbb"))
		"explosion":
			_shape([Vector2(5, 0), Vector2(6, 3), Vector2(10, 2), Vector2(8, 5), Vector2(10, 8), Vector2(6, 7), Vector2(5, 10), Vector2(3, 7), Vector2(0, 8), Vector2(2, 5), Vector2(0, 2), Vector2(4, 3)], Color("b39acb"))
		_:
			preload("res://scripts/ui/tactical_status_symbols.gd").draw_icon(self, kind)
