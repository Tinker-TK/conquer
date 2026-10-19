extends Control
## 原生分辨率纸面，每页三个独立词条；完整属性与技能在条目内阅读。

const SIZE := Vector2i(840, 740)
const INK := Color("302b32")
const MUTED := Color("786459")
const ACCENT := Color("854250")
var entries: Array = []
var category := "遗物"
var right := false
var navigation_enabled := false
var readers: Array[RichTextLabel] = []
static var _body_font: SystemFont
static var _title_font: SystemFont


static func body_font() -> Font:
	if _body_font == null:
		_body_font = SystemFont.new()
		_body_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC"])
		_body_font.font_weight = 500
	return _body_font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = body_font().duplicate()
		_title_font.font_weight = 700
	return _title_font


func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for i in entries.size(): _entry(entries[i], i)
	if entries.is_empty():
		_label("本类条目已全部收录" if right else "未找到条目", Vector2(56, 280), Vector2(730, 50), 28, MUTED)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("fff5df"))
	for y in range(12, SIZE.y, 24):
		for x in range(15 + y % 7, SIZE.x, 67):
			draw_rect(Rect2(x, y, 2, 2), Color(0.6, 0.39, 0.27, 0.045))
	var edge := 819.0 if right else 21.0
	draw_line(Vector2(edge, 24), Vector2(edge, 710), Color("dbb898"), 2)
	draw_string(title_font(), Vector2(32, 29), category, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
	for i in range(1, entries.size()):
		draw_line(Vector2(32, 41 + i * 214), Vector2(805, 41 + i * 214), Color("d3b796"), 1.5)
	draw_string(title_font(), Vector2(603 if right else 32, 716), "下一页 →" if right else "← 上一页", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, ACCENT if navigation_enabled else Color("c1ab92"))


func _entry(entry: Dictionary, index: int) -> void:
	var top := 48.0 + index * 214
	var picture := TextureRect.new()
	picture.position = Vector2(32, top + 37)
	picture.size = Vector2(124, 132)
	picture.texture = entry.get("icon")
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	if picture.texture == null:
		_label(entry.title.left(1), Vector2(65, top + 75), Vector2(70, 60), 42, ACCENT)
	_label(entry.title, Vector2(174, top - 2), Vector2(625, 34), 26, INK, true)
	var facts := _label("  ·  ".join(entry.facts), Vector2(174, top + 35), Vector2(625, 46), 17, MUTED)
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reader := RichTextLabel.new()
	reader.name = "EntryText_" + str(index)
	reader.position = Vector2(174, top + 83)
	reader.size = Vector2(626, 122)
	reader.mouse_filter = Control.MOUSE_FILTER_STOP
	reader.focus_mode = Control.FOCUS_NONE
	reader.scroll_active = true
	reader.add_theme_font_override("normal_font", body_font())
	reader.add_theme_font_override("bold_font", title_font())
	reader.add_theme_font_size_override("normal_font_size", 20)
	reader.add_theme_font_size_override("bold_font_size", 20)
	reader.add_theme_color_override("default_color", INK)
	reader.add_theme_constant_override("line_separation", 3)
	add_child(reader)
	for i in entry.sections.size():
		var section: Dictionary = entry.sections[i]
		if i > 0: reader.add_text("\n")
		reader.push_font(title_font())
		reader.push_color(ACCENT)
		reader.add_text(str(section.title) + "  ")
		reader.pop()
		reader.pop()
		reader.add_text(str(section.text).strip_edges())
	if entry.sections.is_empty(): reader.add_text("暂无额外说明。")
	readers.append(reader)


func _label(value: String, point: Vector2, extent: Vector2, font_size: int, color: Color, bold: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.position = point
	result.size = extent
	result.add_theme_font_override("font", title_font() if bold else body_font())
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result
