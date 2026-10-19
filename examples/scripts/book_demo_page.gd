extends Node2D
## 演示用内容；实际使用时可替换为任意 UI 视口或页面图片。

const PAGE_SIZE := Vector2(180, 230)
const INK := Color("503b59")
const MUTED := Color("a28283")
const STYLE := preload("res://scripts/ui/comic_style.gd")
const TITLES := ["旅人手记", "原野行记", "兵种图鉴", "剑与誓言", "遗物档案", "星辉棱晶", "旅途地图", "未完的征途"]
const CAPTIONS := ["TRAVELER'S JOURNAL", "THE GREEN FIELDS", "THE COMPANY", "STEEL & OATH", "RELIC ARCHIVE", "AETHER CRYSTAL", "THE ROAD AHEAD", "TO BE CONTINUED"]
var page_index := 0
var _font: Font
var _pixel: Font


func _ready() -> void:
	_font = STYLE.chinese()
	_pixel = preload("res://assets/front/PixelOperator-Bold.ttf")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PAGE_SIZE), Color("fff4db"))
	for y in range(4, 230, 7):
		for x in range(5 + (y % 3) * 2, 180, 17):
			draw_rect(Rect2(x, y, 1, 1), Color(0.7, 0.45, 0.35, 0.08))
	# 外侧双线装饰、装订一侧留空。
	var outer := 9.0 if page_index % 2 == 0 else 171.0
	draw_line(Vector2(outer, 13), Vector2(outer, 210), Color("d9b599"), 1)
	draw_line(Vector2(outer + (3 if page_index % 2 == 0 else -3), 18), Vector2(outer + (3 if page_index % 2 == 0 else -3), 205), Color("edcfac"), 1)
	_text(CAPTIONS[page_index], Vector2(22, 25), 10, MUTED, true)
	_text(TITLES[page_index], Vector2(22, 49), 19)
	draw_line(Vector2(22, 59), Vector2(158, 59), Color("ba8b8c"), 1)
	match page_index:
		0:
			_mountains(Vector2(25, 72))
			_lines(["风从翠绿原野吹来。", "把沿途的故事记在这里，", "也记下每一次新的相遇。"], 154)
		1:
			_text("第一章", Vector2(23, 83), 13, Color("a65a72"))
			_lines(["穿过森林，越过古桥。", "远方的钟声仍在回响。", "", "今日记录", "  ·  扎营于溪流西岸", "  ·  发现一座废弃哨塔", "  ·  补给与队伍均已就绪"], 108)
		2:
			_lines(["先锋  /  守护  /  游侠", "每一种兵种都有自己的", "职责与战斗方式。"], 84)
			for i in 3:
				var r := Rect2(24 + i * 46, 133, 38, 48)
				draw_rect(r, Color("eedcc0"))
				_sword(r.position + Vector2(15, 6), float(i) * 0.12)
			_text("同行之人，皆有其名。", Vector2(23, 201), 11, MUTED)
		3:
			_sword(Vector2(80, 75), 0.2, 1.8)
			_lines(["持剑而立，守护同伴。", "", "生命  120     攻击  18", "防御    8     速度  12"], 155)
		4:
			for i in 3:
				var y := 76.0 + i * 43
				_crystal(Vector2(36, y + 8), 0.52)
				_text(["星辉棱晶", "旅人的护符", "古树的种子"][i], Vector2(59, y + 8), 12)
				_text(["微光中藏着旧日回声", "一段被珍藏的旅途", "在新的土地再度生长"][i], Vector2(59, y + 23), 8, MUTED)
		5:
			_crystal(Vector2(90, 111), 1.6)
			_lines(["一颗不会熄灭的星辰。", "据说，它能指引迷路的", "旅人走出最深的黑夜。"], 169)
		6:
			_map()
			_text("沿着星光，继续前行。", Vector2(25, 200), 11, MUTED)
		7:
			_mountains(Vector2(25, 72))
			_lines(["故事仍在路上。", "下一页，留给新的冒险。", "", "——  旅人手记  ——"], 157)
	_text("%02d" % (page_index + 1), Vector2(82, 221), 11, MUTED, true)


func _text(value: String, point: Vector2, font_size: int, color: Color = INK, latin := false) -> void:
	draw_string(_pixel if latin else _font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _lines(values: Array, y: float) -> void:
	for i in values.size():
		_text(values[i], Vector2(23, y + i * 16), 10)


func _mountains(origin: Vector2) -> void:
	draw_rect(Rect2(origin, Vector2(132, 67)), Color("edcbb4"))
	draw_circle(origin + Vector2(101, 16), 8, Color("f8e8b8"))
	draw_colored_polygon(PackedVector2Array([origin + Vector2(0, 57), origin + Vector2(28, 18), origin + Vector2(54, 50), origin + Vector2(86, 9), origin + Vector2(132, 65), origin + Vector2(0, 67)]), Color("ad8a99"))
	draw_colored_polygon(PackedVector2Array([origin + Vector2(0, 67), origin + Vector2(39, 37), origin + Vector2(68, 63), origin + Vector2(108, 35), origin + Vector2(132, 58), origin + Vector2(132, 67)]), Color("6b617d"))
	for x in [11, 20, 110, 122]:
		draw_rect(Rect2(origin + Vector2(x, 49), Vector2(2, 18)), Color("504661"))
		draw_colored_polygon(PackedVector2Array([origin + Vector2(x - 5, 60), origin + Vector2(x + 1, 43), origin + Vector2(x + 7, 60)]), Color("504661"))


func _sword(origin: Vector2, tilt: float, zoom := 1.0) -> void:
	draw_set_transform(origin, tilt, Vector2.ONE * zoom)
	draw_colored_polygon(PackedVector2Array([Vector2(4, 0), Vector2(8, 5), Vector2(8, 25), Vector2(0, 25), Vector2(0, 5)]), Color("80788f"))
	draw_rect(Rect2(1, 5, 3, 21), Color("d8d4d6"))
	draw_rect(Rect2(-5, 25, 18, 4), Color("cda06c"))
	draw_rect(Rect2(2, 29, 4, 9), Color("8b536a"))
	draw_rect(Rect2(0, 38, 8, 3), Color("cda06c"))
	draw_set_transform(Vector2.ZERO)


func _crystal(origin: Vector2, zoom: float) -> void:
	draw_set_transform(origin, 0, Vector2.ONE * zoom)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -23), Vector2(14, -8), Vector2(9, 17), Vector2(0, 25), Vector2(-12, 9), Vector2(-14, -8)]), Color("8864a9"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -23), Vector2(2, -4), Vector2(0, 25), Vector2(-12, 9), Vector2(-14, -8)]), Color("b296cc"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -23), Vector2(14, -8), Vector2(2, -4)]), Color("e4cce9"))
	draw_line(Vector2(2, -4), Vector2(9, 17), Color("d5b4e1"), 1)
	draw_set_transform(Vector2.ZERO)


func _map() -> void:
	var points := PackedVector2Array([Vector2(42, 172), Vector2(76, 141), Vector2(48, 112), Vector2(104, 93), Vector2(133, 129), Vector2(119, 174)])
	draw_polyline(points, Color("bd9294"), 2)
	for p in points:
		draw_circle(p, 5, Color("7a5a80"))
		draw_circle(p, 2, Color("fff4db"))
	_text("N", Vector2(145, 80), 12, MUTED, true)
	draw_line(Vector2(148, 86), Vector2(148, 104), MUTED, 1)
