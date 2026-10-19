# 暂停菜单与设置页使用同一套青色面板、金色选中状态。
extends RefCounted
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const FontStyle = preload("res://scripts/ui/comic_style.gd")
const PAPER := Color("f5ecd5")
const GOLD := Color("f3c84c")
const TEAL := Color("477e86")

static func box(fill: Color, border: Color = Color("30535c"), radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style

static func button(control: Button, font_size: int = 30) -> void:
	UI.button(control, font_size)

static func icon(svg: String) -> Texture2D:
	var picture := Image.new()
	picture.load_svg_from_string(svg)
	return ImageTexture.create_from_image(picture)

static func checkbox(control: CheckBox) -> void:
	button(control)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	control.add_theme_icon_override("unchecked", icon('<svg xmlns="http://www.w3.org/2000/svg" width="46" height="46"><rect x="5" y="5" width="36" height="36" rx="8" fill="#29414e" stroke="#f5ecd5" stroke-width="4"/></svg>'))
	control.add_theme_icon_override("checked", icon('<svg xmlns="http://www.w3.org/2000/svg" width="46" height="46"><rect x="5" y="5" width="36" height="36" rx="8" fill="#29414e" stroke="#f5ecd5" stroke-width="4"/><path d="M10 22 L21 33 L38 13" fill="none" stroke="#f3c84c" stroke-width="7" stroke-linejoin="round"/></svg>'))

static func slider(control: HSlider) -> void:
	var track := box(Color("597277"), Color("597277"), 3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	control.add_theme_stylebox_override("slider", track)
	control.add_theme_stylebox_override("grabber_area", track)
	control.add_theme_stylebox_override("grabber_area_highlight", track)
	var handle := icon('<svg xmlns="http://www.w3.org/2000/svg" width="30" height="48"><path d="M15 3 L27 15 L27 33 L15 45 L3 33 L3 15 Z" fill="#eab345" stroke="#7c5523" stroke-width="3"/><path d="M15 8 L22 17 L22 31 L15 40 L8 31 L8 17 Z" fill="#f3c84c" stroke="#f8da82"/></svg>')
	control.add_theme_icon_override("grabber", handle)
	control.add_theme_icon_override("grabber_highlight", handle)
	control.add_theme_icon_override("grabber_disabled", handle)
