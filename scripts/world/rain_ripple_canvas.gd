# 共用有上限的事件；离屏 R 画细环，G 画柔和高度场，主画布只画落地水滴。
extends Node2D

var events: Array[Dictionary] = []
var floor_id := 1
var distortion_pass := false
var lifetime := 0.7
var radius := 14.0
var splash_size := 1.0
var splash_opacity := 0.9
var splash_lifetime := 0.22
var rain_color := Color(0.84, 0.92, 1.0, 0.6)
var streak_width := 3.0
var streak_length := 22.0


func _draw() -> void:
	# 局部笔画用屏幕像素绘制，但中心跟随世界落点，不会随镜头贴屏滑动。
	var pixel_basis := (get_viewport().get_stretch_transform() * get_global_transform_with_canvas()).affine_inverse()
	for event in events:
		if int(event.get("floor_id", 1)) != floor_id:
			continue
		var age: float = event.age
		var center: Vector2 = event.point
		if not distortion_pass:
			draw_set_transform_matrix(Transform2D(pixel_basis.x, pixel_basis.y, center))
			_draw_ground_splash(event)
			continue
		# 雨滴尚未碰到地面时不产生水面扰动；水面环单独保留较长寿命。
		if age < 0.0 or age >= lifetime or not bool(event.wet):
			continue
		var t: float = clampf(event.age / lifetime, 0.0, 1.0)
		var alpha: float = (1.0 - t) * float(event.strength)
		var points := PackedVector2Array()
		var r: float = lerpf(2.0, radius, t) * float(event.strength)
		for i in 25:
			var a := TAU * float(i) / 24.0
			points.append(center + Vector2(cos(a) * r, sin(a) * r * 0.4))
		# 加法混合下叠三层宽度，G 的平滑梯度只在环附近产生扰动。
		for band in [Vector2(6.0, 0.08), Vector2(4.0, 0.16), Vector2(2.0, 0.3)]:
			draw_polyline(points, Color(0.0, alpha * band.y, 0.0, 1.0), band.x, true)
		draw_polyline(points, Color(alpha * 0.65, 0.0, 0.0, 1.0), 1.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_ground_splash(event: Dictionary) -> void:
	var age: float = event.age
	if age < 0.0:
		var velocity: Vector2 = event.get("velocity", Vector2(0, 1800))
		var tip := velocity * age
		var streak_color := rain_color
		streak_color.a *= clampf((age + 0.05) / 0.015, 0.0, 1.0)
		draw_line(tip - velocity.normalized() * streak_length, tip, streak_color, streak_width)
		return
	if age >= splash_lifetime:
		return
	var t := age / splash_lifetime
	var size := splash_size * float(event.strength)
	var alpha := splash_opacity * (1.0 - t * t)
	var color := Color(0.82, 0.93, 1.0, alpha)
	# 先出现贴地的扁亮点，然后三粒水珠升起并落回原地附近。
	if t < 0.45:
		var points := PackedVector2Array()
		var r := (2.0 + t * 8.0) * size
		for i in 13:
			var a := TAU * float(i) / 12.0
			points.append(Vector2(cos(a) * r, sin(a) * r * 0.3))
		var impact_color := color
		impact_color.a *= (1.0 - t / 0.45) * 0.75
		draw_polyline(points, impact_color, maxf(1.0, size))
		if t < 0.18:
			draw_rect(Rect2(Vector2(-size, -size * 0.5), Vector2(2.0, 1.0) * size), color)
	for side in [-1.0, 0.0, 1.0]:
		var height := 4.0 * t * (1.0 - t) * (6.0 if side != 0.0 else 8.0) * size
		var point := Vector2(side * (1.0 + t * 6.0) * size, -height).round()
		var droplet_size := maxf(1.0, roundf(size))
		draw_line(point, point + Vector2(side, -1.5) * droplet_size, color, droplet_size)
