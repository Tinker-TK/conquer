extends Node2D
## 共用落地扩散，闪电保留每一跳的连接；无伤害逻辑。
var tint := Color.CYAN
var radius := 85.0
var link := PackedVector2Array()
var elapsed := 0.0

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.55:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / 0.55, 0, 1)
	var color := Color(tint, 1.0 - progress)
	if not link.is_empty():
		var points := PackedVector2Array()
		for point in link:
			points.append(to_local(point))
		draw_polyline(points, color, 4.0, true)
		return
	draw_circle(Vector2.ZERO, radius * progress, Color(tint, (1 - progress) * 0.18))
	draw_arc(Vector2.ZERO, maxf(3, radius * progress), 0, TAU, 48, color, 3, true)
	for index in 8:
		var at := Vector2.from_angle(index * TAU / 8.0) * radius * progress
		draw_circle(at, 3.0 * (1 - progress), color)
