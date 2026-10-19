# 纯显示落点反馈：四道带暗色描边的金色线段下降、收束，再淡出，不参与寻路或战斗结算。
extends Node2D

const DURATION := 0.42
const DIRECTIONS := [Vector2(-1, -0.55), Vector2(1, -0.55), Vector2(1, 0.55), Vector2(-1, 0.55)]
var elapsed := 0.0


func _ready() -> void:
	z_index = 100
	_update_scale()
	queue_redraw()


func _process(delta: float) -> void:
	# 提示时长按真实时间，倍速不会改变鼠标反馈的可读性。
	elapsed += delta / maxf(Engine.time_scale, 0.001)
	if elapsed >= DURATION:
		queue_free()
		return
	_update_scale()
	queue_redraw()


func _update_scale() -> void:
	# 锚点保留世界坐标，线宽与尺寸保持屏幕可读；平移和滚轮缩放不会让提示飘离落点。
	var zoom := get_canvas_transform().get_scale().abs()
	scale = Vector2(1.0 / maxf(zoom.x, 0.001), 1.0 / maxf(zoom.y, 0.001))


func _draw() -> void:
	var progress := clampf(elapsed / DURATION, 0.0, 1.0)
	var remaining := (1.0 - progress) * (1.0 - progress)
	var radius := lerpf(3.0, 26.0, remaining)
	var length := lerpf(5.0, 15.0, remaining)
	var fall := Vector2(0, -22.0 * remaining)
	var opacity := 1.0 - smoothstep(0.58, 1.0, progress)
	for direction: Vector2 in DIRECTIONS:
		var inner := direction * radius + fall
		var outer := direction * (radius + length) + fall
		draw_line(outer, inner, Color(0.08, 0.12, 0.19, opacity), 7.0, false)
		draw_line(outer, inner, Color(0.83, 0.66, 0.37, opacity), 4.0, false)
		draw_line(outer, inner, Color(1.0, 0.93, 0.77, opacity), 2.0, false)
