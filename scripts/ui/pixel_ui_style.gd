# 新增 UI 素材的统一入口；九宫格保留像素边角，所有装饰不接管输入。
@tool
extends RefCounted

const INK := Color("282d3b")
const PAPER := Color("fff1cd")
const FONT = preload("res://scripts/ui/comic_style.gd")
const CARVED = preload("res://assets/ui/Banners/Carved_9Slides.png")
const CARVED_STRIP = preload("res://assets/ui/Banners/Carved_3Slides.png")
const BLUE = preload("res://assets/ui/Buttons/Button_Blue_9Slides.png")
const BLUE_DOWN = preload("res://assets/ui/Buttons/Button_Blue_9Slides_Pressed.png")
const RED = preload("res://assets/ui/Buttons/Button_Red_9Slides.png")
const RED_DOWN = preload("res://assets/ui/Buttons/Button_Red_9Slides_Pressed.png")
const HOVER = preload("res://assets/ui/Buttons/Button_Hover_9Slides.png")
const DISABLED = preload("res://assets/ui/Buttons/Button_Disable_9Slides.png")
const BLUE_STRIP = preload("res://assets/ui/Buttons/Button_Blue_3Slides.png")
const BLUE_STRIP_DOWN = preload("res://assets/ui/Buttons/Button_Blue_3Slides_Pressed.png")
const RED_STRIP = preload("res://assets/ui/Buttons/Button_Red_3Slides.png")
const RED_STRIP_DOWN = preload("res://assets/ui/Buttons/Button_Red_3Slides_Pressed.png")
const HOVER_STRIP = preload("res://assets/ui/Buttons/Button_Hover_3Slides.png")
const DISABLED_STRIP = preload("res://assets/ui/Buttons/Button_Disable_3Slides.png")
const BLUE_SMALL = preload("res://assets/ui/Buttons/Button_Blue.png")
const BLUE_SMALL_DOWN = preload("res://assets/ui/Buttons/Button_Blue_Pressed.png")
const RED_SMALL = preload("res://assets/ui/Buttons/Button_Red.png")
const RED_SMALL_DOWN = preload("res://assets/ui/Buttons/Button_Red_Pressed.png")
const HOVER_SMALL = preload("res://assets/ui/Buttons/Button_Hover.png")
const DISABLED_SMALL = preload("res://assets/ui/Buttons/Button_Disable.png")
const BLUE_RIBBON = preload("res://assets/ui/Ribbons/Ribbon_Blue_3Slides.png")
const RED_RIBBON = preload("res://assets/ui/Ribbons/Ribbon_Red_3Slides.png")
const YELLOW_RIBBON = preload("res://assets/ui/Ribbons/Ribbon_Yellow_3Slides.png")


static func texture_box(texture: Texture2D, edge: Vector2, padding: Vector2) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		box.set_texture_margin(side, edge.x)
		box.set_content_margin(side, padding.x)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		box.set_texture_margin(side, edge.y)
		box.set_content_margin(side, padding.y)
	return box


static func panel(padding: Vector2 = Vector2(28, 24)) -> StyleBoxTexture:
	var box := texture_box(CARVED, Vector2(20, 20), padding)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return box


static func strip(padding: Vector2 = Vector2(20, 8)) -> StyleBoxTexture:
	return texture_box(CARVED_STRIP, Vector2(24, 12), padding)


static func ribbon(color: String = "blue") -> StyleBoxTexture:
	var texture: Texture2D = RED_RIBBON if color == "red" else YELLOW_RIBBON if color == "yellow" else BLUE_RIBBON
	var box := texture_box(texture, Vector2(62, 0), Vector2(64, 10))
	box.content_margin_top = 2
	box.content_margin_bottom = 18
	return box


static func button_box(state: String = "normal", important: bool = false, selected: bool = false, tall: bool = false, compact: bool = false) -> StyleBoxTexture:
	var normal: Texture2D = (RED if important else BLUE) if tall else (RED_STRIP if important else BLUE_STRIP)
	var pressed: Texture2D = (RED_DOWN if important else BLUE_DOWN) if tall else (RED_STRIP_DOWN if important else BLUE_STRIP_DOWN)
	var hover: Texture2D = HOVER if tall else HOVER_STRIP
	if compact:
		normal = RED_SMALL if important else BLUE_SMALL
		pressed = RED_SMALL_DOWN if important else BLUE_SMALL_DOWN
		hover = HOVER_SMALL
	var texture: Texture2D = normal
	match state:
		"hover", "hover_pressed", "focus": texture = hover
		"pressed": texture = pressed
		"disabled": texture = DISABLED_SMALL if compact else DISABLED if tall else DISABLED_STRIP
		_: texture = hover if selected else normal
	var box := texture_box(texture, Vector2(20, 20) if tall else Vector2(24, 12), Vector2(24, 12))
	if compact:
		box = texture_box(texture, Vector2(14, 14), Vector2(6, 6))
	# 原图末尾 8 像素是透明留白，底板下方另有投影；文字按可见表面居中。
	box.region_rect = Rect2(0, 0, texture.get_width(), texture.get_height() - 8)
	if not tall:
		var lowered := state in ["pressed", "disabled"]
		box.content_margin_top = (6 if lowered else 2) if compact else (10 if lowered else 6)
		box.content_margin_bottom = (6 if lowered else 10) if compact else (14 if lowered else 18)
	if state == "focus":
		box.draw_center = false
	return box


static func button(control: Button, font_size: int = 24, important: bool = false, compact: bool = false) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.add_theme_font_override("font", FONT.chinese())
	control.add_theme_font_size_override("font_size", font_size)
	var width := maxf(control.size.x, control.custom_minimum_size.x)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := button_box(state, important, false, maxf(control.size.y, control.custom_minimum_size.y) > 110, compact or (width > 0 and width <= 90))
		control.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, INK)
	control.add_theme_color_override("font_disabled_color", Color("525662"))
	control.add_theme_constant_override("outline_size", 0)


static func select(control: Button, selected: bool) -> void:
	control.add_theme_stylebox_override("normal", button_box("normal", false, selected, maxf(control.size.y, control.custom_minimum_size.y) > 110))


static func caption(control: Label, color: String = "blue", font_size: int = 24) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_theme_stylebox_override("normal", ribbon(color))
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", INK if color == "yellow" else PAPER)
	control.add_theme_color_override("font_outline_color", Color("253548"))
	control.add_theme_constant_override("outline_size", 0 if color == "yellow" else 2)
	control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
