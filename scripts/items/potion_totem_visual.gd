extends Node2D
## 诱饵仍是完整战斗单位；这个挂件只绘制木桩与宝石，生命、嘲讽和期限由正式运行器处理。
func _draw() -> void:
	draw_ellipse_shadow()
	draw_rect(Rect2(-8, -54, 16, 54), Color("322d35"))
	draw_rect(Rect2(-6, -52, 12, 50), Color("ab7849"))
	draw_rect(Rect2(-15, -49, 30, 24), Color("41313a"))
	draw_rect(Rect2(-13, -47, 26, 20), Color("cb9958"))
	draw_line(Vector2(-8, -41), Vector2(-3, -37), Color("292c3d"), 3)
	draw_line(Vector2(8, -41), Vector2(3, -37), Color("292c3d"), 3)
	draw_line(Vector2(-4, -30), Vector2(4, -30), Color("fff1b9"), 3)
	draw_line(Vector2(-17, -34), Vector2(-26, -45), Color("f0d698"), 4)
	draw_line(Vector2(17, -34), Vector2(26, -45), Color("f0d698"), 4)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -68), Vector2(7, -59), Vector2(0, -50), Vector2(-7, -59)]), Color("8bedcd"))
	draw_line(Vector2(-3, -19), Vector2(3, -10), Color("e4b777"), 2)

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.4))
	draw_circle(Vector2.ZERO, 21, Color(0.04, 0.07, 0.08, 0.3))
	draw_set_transform(Vector2.ZERO)
