# 这玩意儿是干嘛的（核心逻辑）：画四条错开的斜向幕布，让切场像漫画分镜合拢与展开。
# 数据是咋流动的（数据流向）：SceneTransition 写入幕布程度、真实进度、提示和目的地色系，本控件把它们画到最上层。
# 为啥这么写（选型决策）：用多边形绘制幕布，不依赖大视频，也能随窗口等比例缩放。
# 性能咋样（复杂度）：只在切场期间重画四个面板、少量线条与文字，隐藏后停止处理。
extends Control

const Style = preload("res://scripts/ui/comic_style.gd")
var coverage := 0.0
var progress := 0.0
var heading := "展开征途"
var status := "正在准备战场"
var elapsed := 0.0
var ink := Style.INK
var paper := Style.PAPER
var accent := Style.RED
var highlight := Style.GOLD
var muted := Style.MUTED
var track := Color("3b3640")


# 作用：按目的地切换加载色系；palette 为 grassland 时使用第一幕草原绿，否则恢复通用红黑色，没有返回值。
func set_palette(palette: String) -> void:
	var grassland := palette == "grassland"
	# 深绿底配浅色文字，让幕布停留期间的标题与提示仍然容易阅读。
	ink = Color("14271e") if grassland else Style.INK
	paper = Color("f0f4e6") if grassland else Style.PAPER
	accent = Color("469756") if grassland else Style.RED
	# 进度和运动短条一起换色，每次切场都重新设置，防止绿色残留到返回主菜单的动画。
	highlight = Color("cbea7b") if grassland else Style.GOLD
	muted = Color("a2bba3") if grassland else Style.MUTED
	track = Color("294536") if grassland else Color("3b3640")
	queue_redraw()


# 作用：引擎在加载层入树时设置标准画布；没有参数，没有返回值。
func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


# 作用：加载期间推进装饰条纹；delta 是这帧秒数，没有返回值，父管理器控制何时开始或停止。
func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


# 作用：接收幕布补间；value 是覆盖程度，没有返回值，0 为露出场景、1 为完全遮盖。
func set_coverage(value: float) -> void:
	coverage = value
	queue_redraw()


# 作用：引擎在加载期间画分镜和进度；没有参数，没有返回值。
func _draw() -> void:
	for index in range(4):
		# 后两条略晚一点到达，最终仍严密覆盖屏幕，不让新旧场景从缝隙里闪过。
		var amount := clampf(coverage * 1.30 - index * 0.08, 0.0, 1.0)
		var offset_x := (1.0 - amount) * 2260.0 * (-1.0 if index % 2 == 0 else 1.0)
		var y := index * 270.0
		var polygon := PackedVector2Array([Vector2(-200 + offset_x, y - 2), Vector2(2120 + offset_x, y - 2), Vector2(2040 + offset_x, y + 274), Vector2(-280 + offset_x, y + 274)])
		draw_colored_polygon(polygon, accent if index == 1 else ink)
		if index == 1:
			for stripe in range(18):
				var sx := stripe * 140.0 + offset_x
				draw_line(Vector2(sx, y), Vector2(sx - 80, y + 270), Color(ink, 0.20), 40)
	# 文字只在幕布接近合拢时出现，避免飘在仍然可见的旧场景上。
	if coverage < 0.85:
		return
	var opacity := clampf((coverage - 0.85) / 0.15, 0, 1)
	draw_string(Style.display(), Vector2(560, 480), "NEXT STAGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 106, Color(paper, opacity))
	draw_string(Style.chinese(), Vector2(568, 608), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(paper, opacity))
	draw_string(Style.display(), Vector2(568, 680), "LOADING /", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color(highlight, opacity))
	draw_string(Style.display(), Vector2(1226, 680), "%03d%%" % roundi(progress * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 35, Color(highlight, opacity))
	# 分段填充来自资源加载状态；移动短条只说明程序仍在工作，不代表虚构进度。
	for segment in range(32):
		var filled := float(segment) / 32.0 < progress
		draw_rect(Rect2(568 + segment * 24, 711, 19, 10), Color(highlight if filled else track, opacity))
	draw_string(Style.chinese(), Vector2(568, 772), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color(muted, opacity))
	var runner := fmod(elapsed * 160, 768.0)
	draw_rect(Rect2(568 + runner, 802, 42, 3), Color(accent, opacity))
	draw_string(Style.chinese(), Vector2(568, 924), "部署前看清路线，让每一张牌都有价值。", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color(paper, opacity * 0.75))
	draw_string(Style.display(), Vector2(72, 1020), "CONQUER!   /   TACTICAL CARD BATTLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color(muted, opacity))
