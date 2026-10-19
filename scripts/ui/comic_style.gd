# 这玩意儿是干嘛的（核心逻辑）：集中保管漫画界面的配色、字体和小控件样式。
# 数据是咋流动的（数据流向）：菜单和加载层传入文字、大小和颜色，得到可以直接摆放的控件。
# 为啥这么写（选型决策）：共用一个样式入口，调整红色或字体时不用在每个按钮里寻找。
# 性能咋样（复杂度）：字体只建立一次，控件只在打开界面时建立，没有每帧字体创建。
extends RefCounted

const INK := Color("15151b")
const PAPER := Color("f4f0e6")
const RED := Color("ff3854")
const GOLD := Color("f8d84e")
const MUTED := Color("99969e")
static var _chinese: SystemFont
static var _display: SystemFont


# 作用：取得可显示中文的粗体；没有参数，返回菜单共用字体，缺少某款字体时由后备字体接替。
static func chinese() -> SystemFont:
	if _chinese == null:
		_chinese = SystemFont.new()
		_chinese.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC"])
		_chinese.font_weight = 800
	return _chinese


# 作用：取得紧凑的海报英文字体；没有参数，返回标题和编号使用的字体。
static func display() -> SystemFont:
	if _display == null:
		_display = SystemFont.new()
		_display.font_names = PackedStringArray(["Impact", "Bahnschrift", "DejaVu Sans"])
		_display.font_weight = 800
	return _display


# 作用：生成一行海报文字；value 是内容，point 是左上角，font_size 是字号，color 是颜色，latin 决定字体，返回标签。
static func label(value: String, point: Vector2, font_size: int, color: Color = PAPER, latin: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.position = point
	result.add_theme_font_override("font", display() if latin else chinese())
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	# 装饰文字不能吃掉鼠标，否则按钮的悬停会被文字区域打断。
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


# 作用：给普通面板按钮套上漫画配色；button 是待处理按钮，没有返回值。
static func style_small_button(button: Button) -> void:
	button.add_theme_font_override("font", chinese())
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = RED if state == "normal" else GOLD
		box.content_margin_left = 24.0
		box.content_margin_right = 24.0
		box.content_margin_top = 12.0
		box.content_margin_bottom = 12.0
		button.add_theme_stylebox_override(state, box)


# 作用：生成清晰的设置开关图标；enabled 是开关状态，返回面板共用的原生矢量纹理。
static func switch_icon(enabled: bool) -> Texture2D:
	var image := Image.new()
	var fill := "#f8d84e" if enabled else "#423d49"
	var cx := 69 if enabled else 23
	# 图标是简单几何形状；圆点位置比单靠颜色更容易分辨状态。纹理跟面板一同释放。
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="92" height="46"><rect x="1" y="1" width="90" height="44" rx="22" fill="%s"/><circle cx="%d" cy="23" r="17" fill="#f4f0e6"/></svg>' % [fill, cx])
	return ImageTexture.create_from_image(image)
