# 战旗与地刺是固定于世界位置的战术设施，不参与单位导航或征召牌绑定。
extends Node2D

var is_banner := true
var radius := 200.0


func _draw() -> void:
	if is_banner:
		draw_circle(Vector2.ZERO, radius, Color(0.95, 0.72, 0.3, 0.06))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.95, 0.72, 0.3, 0.35), 2.0)
		draw_rect(Rect2(-4, -70, 5, 74), Color("3b2930"))
		draw_rect(Rect2(-3, -70, 3, 74), Color("d6b16a"))
		draw_colored_polygon(PackedVector2Array([Vector2(1, -66), Vector2(38, -61), Vector2(30, -47), Vector2(38, -32), Vector2(1, -36)]), Color("a7444a"))
		draw_rect(Rect2(8, -57, 17, 4), Color("f0d597"))
		draw_rect(Rect2(14, -63, 5, 21), Color("f0d597"))
		draw_rect(Rect2(-11, -1, 19, 7), Color("615964"))
	else:
		draw_circle(Vector2.ZERO, radius, Color(0.46, 0.31, 0.2, 0.16))
		draw_rect(Rect2(-23, -9, 46, 18), Color("5a4235"))
		for x in [-17, -6, 5, 16]:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 5), Vector2(x, -13), Vector2(x + 4, 5)]), Color("c4c6b8"))
