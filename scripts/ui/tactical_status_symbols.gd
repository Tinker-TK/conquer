# 战场与详情共用的战术状态符号，按 10×10 像素坐标绘制。
extends RefCounted


static func draw_icon(canvas: CanvasItem, kind: String) -> void:
	var gold := Color("efc16a")
	var red := Color("e66b70")
	var blue := Color("669edb")
	match kind:
		"seventh_strike":
			canvas.draw_polyline(PackedVector2Array([Vector2(1, 1), Vector2(9, 1), Vector2(4, 10)]), gold, 2)
		"taunt":
			canvas.draw_circle(Vector2(5, 5), 4, red, false, 1.5)
			canvas.draw_line(Vector2(5, 1), Vector2(5, 6), gold, 2)
			canvas.draw_circle(Vector2(5, 8), 1, gold)
		"taunt_guard":
			draw_icon(canvas, "shield")
		"armor_break":
			draw_icon(canvas, "defence_down")
		"soldier_growth":
			canvas.draw_line(Vector2(2, 8), Vector2(8, 2), gold, 2)
			canvas.draw_polyline(PackedVector2Array([Vector2(3, 2), Vector2(8, 2), Vector2(8, 7)]), gold, 1.5)
		"missile_mark":
			canvas.draw_circle(Vector2(5, 5), 4.0, red, false, 1.5)
			canvas.draw_line(Vector2(0, 0), Vector2(10, 10), red, 1.5)
			canvas.draw_line(Vector2(10, 0), Vector2(0, 10), red, 1.5)
		"shield":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(9, 1), Vector2(8, 7), Vector2(5, 10), Vector2(2, 7)]), blue)
			canvas.draw_line(Vector2(5, 2), Vector2(5, 7), gold, 1.5)
		"slow":
			for angle in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
				var offset := Vector2.from_angle(angle) * 4.5
				canvas.draw_line(Vector2(5, 5) - offset, Vector2(5, 5) + offset, blue, 1.5)
		"bleed":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(9, 6), Vector2(8, 9), Vector2(5, 10), Vector2(2, 9), Vector2(1, 6)]), red)
		"confusion":
			canvas.draw_arc(Vector2(5, 4), 3.5, -PI, PI * 0.65, 12, Color("cc92d8"), 1.5)
			canvas.draw_circle(Vector2(5, 9), 1, gold)
		"mortal_wounds":
			canvas.draw_line(Vector2(5, 1), Vector2(5, 9), blue, 3)
			canvas.draw_line(Vector2(1, 5), Vector2(9, 5), blue, 3)
			canvas.draw_line(Vector2(0, 10), Vector2(10, 0), red, 2)
		"sleep":
			canvas.draw_polyline(PackedVector2Array([Vector2(1, 1), Vector2(9, 1), Vector2(1, 9), Vector2(9, 9)]), blue, 1.5)
		"stealth":
			canvas.draw_arc(Vector2(5, 5), 4, 0.2, PI - 0.2, 10, blue, 1.5)
			canvas.draw_arc(Vector2(5, 5), 4, PI + 0.2, TAU - 0.2, 10, blue, 1.5)
			canvas.draw_line(Vector2(1, 9), Vector2(9, 1), gold, 1.5)
		"consecutive_attack":
			canvas.draw_line(Vector2(2, 9), Vector2(8, 1), gold, 2)
			canvas.draw_line(Vector2(1, 6), Vector2(5, 9), gold, 1.5)
			canvas.draw_polyline(PackedVector2Array([Vector2(6, 5), Vector2(9, 2), Vector2(9, 5)]), red, 1.5)
		"protection":
			canvas.draw_circle(Vector2(5, 5), 4.5, gold, false, 1)
			canvas.draw_polyline(PackedVector2Array([Vector2(2, 2), Vector2(8, 2), Vector2(7, 7), Vector2(5, 9), Vector2(3, 7), Vector2(2, 2)]), blue, 1.5)
		"sword_arrow":
			canvas.draw_line(Vector2(0, 9), Vector2(9, 0), gold, 2)
			canvas.draw_polyline(PackedVector2Array([Vector2(4, 0), Vector2(9, 0), Vector2(9, 5)]), gold, 1.5)
			canvas.draw_line(Vector2(1, 5), Vector2(5, 9), blue, 1.5)
		"weakness":
			canvas.draw_line(Vector2(5, 0), Vector2(5, 8), red, 2)
			canvas.draw_polyline(PackedVector2Array([Vector2(1, 5), Vector2(5, 9), Vector2(9, 5)]), red, 2)
		"defence_down":
			canvas.draw_polyline(PackedVector2Array([Vector2(1, 1), Vector2(9, 1), Vector2(8, 6), Vector2(5, 10), Vector2(2, 6), Vector2(1, 1)]), blue, 1.5)
			canvas.draw_polyline(PackedVector2Array([Vector2(6, 0), Vector2(4, 4), Vector2(7, 5), Vector2(4, 10)]), red, 1.5)
		"vulnerability":
			canvas.draw_circle(Vector2(5, 5), 4, red, false, 1.5)
			canvas.draw_circle(Vector2(5, 5), 1.5, gold)
		"paralysis":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(1, 6), Vector2(5, 6), Vector2(4, 10), Vector2(9, 3), Vector2(5, 3)]), gold)
		"stun":
			canvas.draw_circle(Vector2(2, 2), 1.5, gold)
			canvas.draw_circle(Vector2(8, 2), 1.5, gold)
			canvas.draw_line(Vector2(3, 6), Vector2(7, 9), gold, 2)
		"frenzy":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(1, 8), Vector2(3, 1), Vector2(5, 5), Vector2(7, 0), Vector2(9, 8), Vector2(5, 10)]), red)
		"lifesteal":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 3), Vector2(2, 1), Vector2(5, 3), Vector2(8, 1), Vector2(10, 3), Vector2(5, 9)]), red)
		"composition":
			for x in [1, 5, 9]:
				canvas.draw_circle(Vector2(x, 2), 1.4, gold)
				canvas.draw_line(Vector2(x, 4), Vector2(x, 9), gold, 1.5)
		"distance":
			canvas.draw_line(Vector2(0, 5), Vector2(10, 5), blue, 1.5)
			canvas.draw_polyline(PackedVector2Array([Vector2(3, 2), Vector2(0, 5), Vector2(3, 8)]), blue, 1.5)
			canvas.draw_polyline(PackedVector2Array([Vector2(7, 2), Vector2(10, 5), Vector2(7, 8)]), blue, 1.5)
		"judger":
			canvas.draw_rect(Rect2(2, 0, 7, 3), gold)
			canvas.draw_line(Vector2(5, 2), Vector2(3, 8), gold, 2)
			canvas.draw_line(Vector2(1, 10), Vector2(9, 10), gold, 2)
		"converted":
			canvas.draw_line(Vector2(2, 0), Vector2(2, 10), blue, 1.5)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(3, 0), Vector2(10, 2), Vector2(3, 5)]), gold)
