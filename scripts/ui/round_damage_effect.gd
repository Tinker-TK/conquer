# 回合结算光弹：只负责表现，命中信号交给唯一回合管理器扣血。
# 使用屏幕坐标，镜头缩放不会改变 HUD 落点；最后一次命中和余辉结束才发完成信号。
extends Control

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
var _result_banner: StyleBoxTexture
var _banner_panel: PanelContainer
var _banner_title: Label
var _banner_detail: Label

signal damage_impacted(amount: int)
signal playback_finished(completed: bool)

## 回合结算光弹发射前的蓄力时长，单位为秒；越大则发射前停顿更长。实际扣血在光弹命中时触发。
@export_range(0.05, 1.0, 0.01) var windup_duration := 0.24
## 回合结算光弹飞向败方生命栏的基础时长，单位为秒；越大则飞行更慢。最后一颗光弹命中后才完成本轮扣血。
@export_range(0.15, 1.5, 0.01) var flight_duration := 0.62
## 光弹命中后保留余辉与结算表现的时长，单位为秒；播完后才通知回合管理器继续清场或显示胜负。
@export_range(0.7, 1.5, 0.01) var aftermath_duration := 0.72

var playing := false
var elapsed := 0.0
var duration := 0.0
var packets: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var target_control: Control
var target_position := Vector2.ZERO
var result: StringName = &"draw"
var total_damage := 0
var base_damage := 0
var unit_damage := 0
var applied_damage := 0
var fallback_player_hp := 0
var fallback_player_max_hp := 1
var _font: Font
var _color := Color("#69edff")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = get_theme_default_font()
	_banner_panel = PanelContainer.new()
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_banner_panel)
	_banner_panel.anchor_left = 0.5
	_banner_panel.anchor_right = 0.5
	_banner_panel.anchor_top = 0.72
	_banner_panel.anchor_bottom = 0.72
	_banner_panel.offset_left = -300
	_banner_panel.offset_right = 300
	_banner_panel.offset_top = -56
	_banner_panel.offset_bottom = 56
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 2)
	_banner_panel.add_child(lines)
	_banner_title = _banner_label(30)
	_banner_detail = _banner_label(20)
	lines.add_child(_banner_title)
	lines.add_child(_banner_detail)
	hide()
	set_process(false)


# sources 保存幸存单位的屏幕位置和独立结算伤害，单位可以在下一轮安全释放。
func play(winner: StringName, round_damage: int, sources: Array[Dictionary], target: Control) -> void:
	if playing:
		cancel()
	result = winner
	base_damage = round_damage if winner != &"draw" else 0
	unit_damage = 0
	total_damage = base_damage
	applied_damage = 0
	elapsed = 0.0
	packets.clear()
	impacts.clear()
	target_control = target
	fallback_player_hp = RunManager.hp
	fallback_player_max_hp = RunManager.max_hp
	_color = Color("#69edff") if winner == &"player" else Color("#ff596b")
	if winner == &"draw":
		_color = Color("#f9ce78")
		duration = 0.82
	else:
		var center := Vector2.ZERO
		# 最多半秒发完单位光弹，大军不会把结算拖成漫长等待。
		var stagger := minf(0.075, 0.48 / maxf(sources.size(), 1))
		for index in sources.size():
			var source := sources[index]
			var origin: Vector2 = source.position
			origin = origin.clamp(Vector2(24, 230), size - Vector2(24, 160))
			center += origin
			var damage: int = maxi(0, source.damage)
			unit_damage += damage
			if damage > 0:
				packets.append({"origin": origin, "damage": damage, "start": windup_duration + index * stagger,
					"flight": flight_duration, "main": false, "hit": false})
		center = center / sources.size() if not sources.is_empty() else size * Vector2(0.5, 0.52)
		var main_start := windup_duration + sources.size() * stagger + 0.12
		packets.append({"origin": center + Vector2(0, 36), "damage": base_damage, "start": main_start,
			"flight": flight_duration + 0.1, "main": true, "hit": false})
		total_damage += unit_damage
		duration = main_start + flight_duration + 0.1 + maxf(aftermath_duration, 0.7)
	_result_banner = UI.ribbon("blue" if winner == &"player" else "red" if winner == &"enemy" else "yellow")
	# 此处丝带高 112（原图 64），纵向留白也按比例放大，避开下方尾带与投影。
	_result_banner.content_margin_top = 4
	_result_banner.content_margin_bottom = 32
	_banner_panel.add_theme_stylebox_override("panel", _result_banner)
	_banner_title.text = "回合胜利" if result == &"player" else ("回合失利" if result == &"enemy" else "双方全灭 · 平局")
	_banner_detail.text = "双方不扣血" if result == &"draw" else "%s -%d HP  ·  回合 %d + 单位 %d" % [
		"敌方" if result == &"player" else "玩家", total_damage, base_damage, unit_damage]
	for label: Label in [_banner_title, _banner_detail]:
		label.add_theme_color_override("font_color", UI.INK if result == &"draw" else UI.PAPER)
		label.add_theme_constant_override("outline_size", 0 if result == &"draw" else 3)
	_update_target()
	playing = true
	show()
	set_process(true)
	queue_redraw()


func cancel() -> void:
	if playing:
		_finish(false)


func _exit_tree() -> void:
	cancel()


func _finish(completed: bool) -> void:
	playing = false
	set_process(false)
	hide()
	packets.clear()
	impacts.clear()
	playback_finished.emit(completed)


func _update_target() -> void:
	if is_instance_valid(target_control):
		target_position = target_control.get_global_transform_with_canvas() * (target_control.size * 0.5)
	else:
		# F6 单独战场没有常驻玩家 HUD，用临时生命牌提供可见落点。
		target_position = Vector2(220, 42) if result == &"enemy" else Vector2(size.x * 0.56, 167)


func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	_update_target()
	for packet in packets:
		if not packet.hit and elapsed >= packet.start + packet.flight:
			packet.hit = true
			applied_damage += packet.damage
			impacts.append({"time": elapsed, "damage": packet.damage, "main": packet.main, "index": impacts.size()})
			damage_impacted.emit(packet.damage)
			# 回调可能强制结束战斗并取消特效，此时不能再继续处理旧光弹。
			if not playing:
				return
	if elapsed >= duration:
		_finish(true)
	else:
		queue_redraw()


func _point(packet: Dictionary, progress: float) -> Vector2:
	var origin: Vector2 = packet.origin
	var end := target_position
	var bend := Vector2(0, -minf(150, origin.distance_to(end) * 0.2))
	var first := origin.lerp(end, 0.32) + bend
	var second := origin.lerp(end, 0.72) + bend
	var t := clampf(progress, 0, 1)
	var inv := 1.0 - t
	return inv * inv * inv * origin + 3 * inv * inv * t * first + 3 * inv * t * t * second + t * t * t * end


func _draw() -> void:
	if not playing or _font == null:
		return
	var fade := minf(elapsed / 0.16, 1.0) * clampf((duration - elapsed) / 0.3, 0, 1)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.06, 0.12 * fade))
	if result == &"enemy" and not is_instance_valid(target_control):
		draw_style_box(_fallback_style(), Rect2(112, 12, 220, 60))
		_text("生命 %d / %d" % [RunManager.hp, fallback_player_max_hp], Vector2(222, 53), 26, Color("#ff909d"), 1.0)
	for packet in packets:
		if packet.hit:
			continue
		var progress: float = (elapsed - packet.start) / packet.flight
		if progress < 0:
			var charge := clampf((elapsed - packet.start + windup_duration) / windup_duration, 0, 1)
			if charge > 0:
				draw_arc(packet.origin, 12 + 12 * (1 - charge), 0, TAU, 24, Color(_color, charge * 0.7), 2, true)
			continue
		var point := _point(packet, progress)
		var radius := 11.0 if packet.main else 6.0
		for segment in 12:
			var behind := maxf(0, progress - float(segment + 1) * 0.015)
			var previous := _point(packet, maxf(0, behind - 0.015))
			var trail_color := Color(_color, (1 - float(segment) / 12) * 0.7)
			draw_line(previous, _point(packet, behind), trail_color, radius * (1 - float(segment) / 14), true)
		draw_circle(point, radius * 2.6, Color(_color, 0.08))
		draw_circle(point, radius * 1.8, Color(_color, 0.19))
		draw_circle(point, radius, _color)
		draw_circle(point, radius * 0.48, Color("#fff9e5"))
		var diamond := PackedVector2Array([point + Vector2(0, -radius * 1.6), point + Vector2(radius, 0),
			point + Vector2(0, radius * 1.6), point - Vector2(radius, 0)])
		draw_colored_polygon(diamond, Color("#fff5cc") if packet.main else Color("#e5ffff"))
		if packet.main:
			_text("回合 +%d" % base_damage, point + Vector2(0, 35), 21, Color("#ffdf8d"), 1.0)
	for impact in impacts:
		_draw_impact(impact)
	_draw_banner(fade)


func _draw_banner(alpha: float) -> void:
	# 文字由原生容器按丝带的内容边距居中，避免把字体基线当成视觉中心。
	_banner_panel.modulate.a = alpha


func _banner_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UI.FONT.chinese())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", UI.INK)
	return label


func _draw_impact(impact: Dictionary) -> void:
	var age: float = elapsed - impact.time
	var life := 0.66 if impact.main else 0.5
	if age > life:
		return
	var fade := clampf(1 - age / life, 0, 1)
	var strength := 1.0 if impact.main else 0.6
	var wobble := Vector2(sin(age * 85) * 5 * fade * strength, 0)
	var point := target_position + wobble
	draw_circle(point, (16 + age * 70) * strength, Color(_color, fade * 0.14))
	draw_arc(point, (22 + age * 110) * strength, 0, TAU, 40, Color(_color, fade * 0.85), 3 * strength, true)
	for ray in 14:
		var direction := Vector2.from_angle(float(ray) * TAU / 14 + impact.index * 0.41)
		var start := point + direction * (16 + age * 75) * strength
		draw_line(start, start + direction * (8 + 14 * fade), Color(_color, fade), 2, true)
	var hit_rect := Rect2(point - Vector2(108 if result == &"enemy" else 202, 25),
		Vector2(216 if result == &"enemy" else 404, 50))
	draw_rect(hit_rect, Color(_color, fade * 0.14))
	draw_rect(hit_rect, Color(_color, fade * 0.8), false, 2)
	var number_point := point + Vector2((impact.index % 3 - 1) * 38, 69 + (impact.index % 2) * 25 - age * 32)
	_text("-%d" % impact.damage, number_point, 32 if impact.main else 26, Color("#ffe9a2"), fade)
	if impact.main:
		_text("-%d HP" % total_damage, point + Vector2(0, 138 - age * 24), 44, Color("#ffdf8d"), fade)


func _text(value: String, baseline: Vector2, font_size: int, tint: Color, alpha: float) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var start := baseline - Vector2(width * 0.5, 0)
	draw_string_outline(_font, start, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, Color(0.015, 0.025, 0.045, alpha))
	draw_string(_font, start, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(tint, alpha))


func _fallback_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#18242d")
	style.border_color = Color("#ff596b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style
