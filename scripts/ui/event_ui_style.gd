# 事件页独立的浅色叙事样式，不修改卡牌、商店和战斗的共用像素主题。
@tool
extends RefCounted

const FONT = preload("res://scripts/ui/fantasy_menu_style.gd")
const INK := Color("465044")
const MUTED := Color("858674")
const GOLD := Color("97743d")
const TEAL := Color("32746e")
const PAPER := Color("fff4dc")
static var _body_font: SystemFont


static func body_font() -> SystemFont:
	if _body_font == null:
		_body_font = SystemFont.new()
		_body_font.font_names = PackedStringArray(["Noto Serif CJK SC", "Source Han Serif SC", "SimSun", "Songti SC", "Microsoft YaHei"])
		_body_font.font_weight = 400
	return _body_font


static func button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT.chinese())
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_constant_override("outline_size", 0)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("55756e")
		if state in ["hover", "hover_pressed"]:
			box.bg_color = Color("6b8a7b")
		elif state == "pressed":
			box.bg_color = Color("45645f")
		elif state == "disabled":
			box.bg_color = Color("a5ad9b")
		box.border_color = Color("a2b19a")
		box.set_border_width_all(1)
		box.corner_radius_top_left = 9
		box.corner_radius_bottom_right = 9
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = Color("b69250")
			box.set_border_width_all(3)
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func highlight(text: String) -> String:
	var keywords := RegEx.new()
	keywords.compile("宝匣|圣匣|宝箱|遗物|药水|炼金师|新兵|战术|休憩整备|训练|强化|物资")
	var result := ""
	var offset := 0
	for found in keywords.search_all(text):
		result += escape(text.substr(offset, found.get_start() - offset))
		result += "[color=#32746e]" + escape(found.get_string()) + "[/color]"
		offset = found.get_end()
	return result + escape(text.substr(offset))
