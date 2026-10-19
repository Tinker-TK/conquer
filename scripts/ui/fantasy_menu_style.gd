# 主菜单独立的纹章配色与衬线字体；不改变战斗和设置页的共用主题。
extends RefCounted

const INK := Color("3f493a")
const PAPER := Color("fff1d3")
const RED := Color("a65c47")
const GOLD := Color("a17a3d")
const MUTED := Color("777d64")
const BRONZE := Color("b39760")
const ARCANE := Color("6c9b93")
static var _chinese: SystemFont
static var _display: SystemFont


static func chinese() -> SystemFont:
	if _chinese == null:
		_chinese = SystemFont.new()
		_chinese.font_names = PackedStringArray(["Noto Serif CJK SC", "Source Han Serif SC", "SimSun", "Songti SC", "Microsoft YaHei"])
		_chinese.font_weight = 700
	return _chinese


static func display() -> SystemFont:
	if _display == null:
		_display = SystemFont.new()
		_display.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Noto Serif", "DejaVu Serif"])
		_display.font_weight = 700
	return _display


static func label(value: String, point: Vector2, font_size: int, color: Color = PAPER, latin: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.position = point
	result.add_theme_font_override("font", display() if latin else chinese())
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0.62, 0.49, 0.29, 0.12))
	result.add_theme_constant_override("shadow_offset_y", 1)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
