# 单位头顶独立的咏唱条；由技能管理器的物理时钟推进，暂停时保持当前进度。
extends Node2D

var progress := 0.0
const WIDTH := 54.0
const HEIGHT := 7.0


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var background := Rect2(-WIDTH * 0.5, -HEIGHT, WIDTH, HEIGHT)
	draw_rect(background.grow(1.0), Color("111e32"))
	draw_rect(background, Color("263f58"))
	draw_rect(Rect2(background.position, Vector2(WIDTH * progress, HEIGHT)), Color("79dff2"))
	draw_rect(background.grow(1.0), Color("d6ebf1"), false, 1.0)
