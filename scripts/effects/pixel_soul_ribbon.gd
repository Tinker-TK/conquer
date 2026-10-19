@tool
class_name PixelSoulRibbon
extends Node2D
## 独立灵魂光带：贝塞尔或环绕路径、加速前端、延迟尾迹、圆头、像素化与吸收。
## 路径坐标均相对本节点；不访问单位、战场或自动加载节点。

signal arrived
signal finished

const PALETTES: Array = [
	[Color("33565e"), Color("79b6b7"), Color("e0dfd1")],
	[Color("745234"), Color("dbb969"), Color("fff0c2")],
	[Color("514469"), Color("b496cf"), Color("ede2ff")],
]
const ORBIT_APPROACH_END := 0.28
const ORBIT_CIRCLE_END := 0.84
const ORBIT_SWEEP := PI

class RibbonCanvas extends Node2D:
	var source: Node2D

	func _draw() -> void:
		if is_instance_valid(source):
			source._draw_ribbon(self)

@export_group("路径 / 本地坐标")
@export var start_point := Vector2.ZERO:
	set(value):
		start_point = value
		_sync_layout()
@export var control_point := Vector2(20, -300):
	set(value):
		control_point = value
		_sync_layout()
@export var end_point := Vector2(760, -40):
	set(value):
		end_point = value
		_sync_layout()
@export var show_path := false:
	set(value):
		show_path = value
		queue_redraw()

@export_group("飞行与吸收")
@export_range(0.1, 4.0, 0.05) var flight_duration := 1.35:
	set(value):
		flight_duration = maxf(value, 0.1)
		_refresh()
## 尾端追随前端的时间差；到达后仍继续推进，直到整条光带被吸收。
@export_range(0.05, 2.0, 0.05) var trail_delay := 0.65:
	set(value):
		trail_delay = maxf(value, 0.05)
		_refresh()
@export_range(1.0, 4.0, 0.1) var acceleration := 2.3:
	set(value):
		acceleration = maxf(value, 1.0)
		_refresh()
@export var autoplay := true
@export var looping := false
@export_range(0.0, 2.0, 0.05) var loop_delay := 0.45
@export var playing := true

@export_group("带状轮廓")
@export_range(2.0, 60.0, 1.0) var head_width := 20.0:
	set(value):
		head_width = maxf(value, 2.0)
		_sync_layout()
@export_range(0.4, 3.0, 0.1) var taper := 1.2:
	set(value):
		taper = maxf(value, 0.1)
		_refresh()
@export_range(1.0, 8.0, 1.0) var pixel_size := 3.0:
	set(value):
		pixel_size = maxf(value, 1.0)
		_sync_layout()
@export_range(12, 128, 4) var curve_samples := 64:
	set(value):
		curve_samples = clampi(value, 12, 128)
		_refresh()
@export var glow_enabled := false:
	set(value):
		glow_enabled = value
		_refresh()

@export_group("三段配色")
@export_enum("青色灵魂", "金色能量", "紫色奥术") var palette_preset: int = 0:
	set(value):
		palette_preset = clampi(value, 0, 2)
		_refresh()
@export var use_custom_palette := false:
	set(value):
		use_custom_palette = value
		_refresh()
@export var custom_palette := PackedColorArray([Color("33565e"), Color("79b6b7"), Color("e0dfd1")]):
	set(value):
		custom_palette = value
		_refresh()

var _elapsed := 0.0
var _bounds := Rect2()
var _canvas: RibbonCanvas
var _arrival_emitted := false
var _finished_emitted := false
var _batch_path_update := false
var _orbiting := false
var _orbit_radius := 72.0
var _orbit_angle := 0.0
var _orbit_direction := 1.0


func _ready() -> void:
	var view := $LowResolution as SubViewport
	view.world_2d = World2D.new()
	_canvas = RibbonCanvas.new()
	_canvas.name = "RibbonCanvas"
	_canvas.source = self
	view.add_child(_canvas)
	($Display as Sprite2D).texture = view.get_texture()
	playing = autoplay
	_sync_layout()


func _process(delta: float) -> void:
	if not playing:
		return
	seek(_elapsed + delta)
	if not Engine.is_editor_hint():
		if not _arrival_emitted and _elapsed >= flight_duration:
			_arrival_emitted = true
			arrived.emit()
		if not _finished_emitted and _elapsed >= get_duration():
			_finished_emitted = true
			finished.emit()
	if looping or Engine.is_editor_hint():
		if _elapsed >= get_duration() + maxf(loop_delay, 0.0):
			seek(fmod(_elapsed, get_duration() + maxf(loop_delay, 0.0)))
			_arrival_emitted = false
			_finished_emitted = false
	elif _elapsed >= get_duration():
		playing = false


## 指定路径并从起点播放一次；由调用方选择本节点的位置与坐标系。
func play(from: Vector2, bend: Vector2, to: Vector2) -> void:
	set_path(from, bend, to)
	restart()


func set_path(from: Vector2, bend: Vector2, to: Vector2) -> void:
	# Batch the three assignments so resizing the viewport happens only once.
	_batch_path_update = true
	_orbiting = false
	start_point = from
	control_point = bend
	end_point = to
	_batch_path_update = false
	_sync_layout()


## 从发射点切入目标外围，环绕半圈，再向内收束；仍使用本地坐标。
func set_orbit_path(from: Vector2, to: Vector2, radius: float = 72.0, clockwise: bool = true) -> void:
	_batch_path_update = true
	_orbiting = true
	_orbit_radius = maxf(radius, head_width * 2.0)
	_orbit_direction = 1.0 if clockwise else -1.0
	_orbit_angle = (from - to).angle() - _orbit_direction * PI * 0.55
	start_point = from
	end_point = to
	_update_orbit_control()
	_batch_path_update = false
	_sync_layout()


## 追踪移动中的吸收点，保持发射点、环绕方向和播放时钟稳定。
func move_orbit_target(to: Vector2) -> void:
	if not _orbiting or end_point.is_equal_approx(to):
		return
	_batch_path_update = true
	end_point = to
	_update_orbit_control()
	_batch_path_update = false
	_sync_layout()


func _update_orbit_control() -> void:
	var radial := Vector2.from_angle(_orbit_angle)
	var entry := end_point + radial * _orbit_radius
	var tangent := radial.rotated(_orbit_direction * PI * 0.5)
	control_point = entry - tangent * _orbit_radius * 1.2


func restart() -> void:
	_arrival_emitted = false
	_finished_emitted = false
	playing = true
	seek(0.0)


## seek 只改变画面，不发 arrived/finished，便于暂停、倒退和可重复采样。
func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	_refresh()


func get_duration() -> float:
	return flight_duration + trail_delay


func get_head_progress() -> float:
	return pow(clampf(_elapsed / flight_duration, 0.0, 1.0), acceleration)


func get_tail_progress() -> float:
	return pow(clampf((_elapsed - trail_delay) / flight_duration, 0.0, 1.0), acceleration)


func point_at(progress: float) -> Vector2:
	var u := clampf(progress, 0.0, 1.0)
	if _orbiting:
		var radial := Vector2.from_angle(_orbit_angle)
		if u < ORBIT_APPROACH_END:
			var approach := u / ORBIT_APPROACH_END
			var entry := end_point + radial * _orbit_radius
			return start_point * pow(1.0 - approach, 2.0) + control_point * 2.0 * (1.0 - approach) * approach + entry * approach * approach
		if u < ORBIT_CIRCLE_END:
			var orbit := (u - ORBIT_APPROACH_END) / (ORBIT_CIRCLE_END - ORBIT_APPROACH_END)
			return end_point + radial.rotated(_orbit_direction * ORBIT_SWEEP * orbit) * _orbit_radius
		var absorb := (u - ORBIT_CIRCLE_END) / (1.0 - ORBIT_CIRCLE_END)
		var absorb_angle := ORBIT_SWEEP + PI * 0.5 * absorb
		return end_point + radial.rotated(_orbit_direction * absorb_angle) * _orbit_radius * (1.0 - smoothstep(0.0, 1.0, absorb))
	return start_point * (1.0 - u) * (1.0 - u) + control_point * 2.0 * (1.0 - u) * u + end_point * u * u


func tangent_at(progress: float) -> Vector2:
	var u := clampf(progress, 0.0, 1.0)
	if _orbiting:
		var direction := point_at(u + 0.0002) - point_at(u - 0.0002)
		return direction.normalized() if direction.length_squared() > 0.0000001 else Vector2.RIGHT
	var tangent := (control_point - start_point) * (2.0 * (1.0 - u)) + (end_point - control_point) * (2.0 * u)
	if tangent.length_squared() < 0.001:
		tangent = end_point - start_point
	return tangent.normalized() if tangent.length_squared() > 0.001 else Vector2.RIGHT


func get_palette() -> PackedColorArray:
	if use_custom_palette and custom_palette.size() == 3:
		return custom_palette
	return PackedColorArray(PALETTES[palette_preset])


func _sync_layout() -> void:
	if _canvas == null or not is_inside_tree() or _batch_path_update:
		return
	# Include the complete orbit as well as the Bezier control hull.
	var padding := head_width * 1.8 + pixel_size * 2.0
	var box := Rect2(start_point, Vector2.ZERO).expand(control_point).expand(end_point)
	if _orbiting:
		box = box.merge(Rect2(end_point - Vector2.ONE * _orbit_radius, Vector2.ONE * _orbit_radius * 2.0))
	box = box.grow(padding)
	var grid_origin := (box.position / pixel_size).floor() * pixel_size
	var grid_size := ((box.end - grid_origin) / pixel_size).ceil().max(Vector2.ONE)
	_bounds = Rect2(grid_origin, grid_size * pixel_size)
	var view := $LowResolution as SubViewport
	view.size = Vector2i(grid_size)
	_canvas.scale = Vector2.ONE / pixel_size
	_canvas.position = -grid_origin / pixel_size
	var display := $Display as Sprite2D
	display.position = grid_origin
	display.scale = Vector2.ONE * pixel_size
	_refresh()


func _refresh() -> void:
	queue_redraw()
	if _canvas != null:
		_canvas.queue_redraw()
		($LowResolution as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _width_scale() -> float:
	var absorb := clampf((_elapsed - flight_duration) / trail_delay, 0.0, 1.0)
	return 1.0 - smoothstep(0.0, 1.0, absorb)


func _band_polygon(begin: float, end: float, multiplier: float = 1.0) -> PackedVector2Array:
	var head := get_head_progress()
	var tail := get_tail_progress()
	var steps := maxi(3, ceili(curve_samples * (end - begin)))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in steps + 1:
		var fraction := lerpf(begin, end, float(i) / steps)
		var u := lerpf(tail, head, fraction)
		var center := point_at(u)
		var tangent := tangent_at(u)
		var normal := Vector2(-tangent.y, tangent.x)
		var width := head_width * 0.5 * pow(fraction, taper) * _width_scale() * multiplier
		left.append(center + normal * width)
		right.append(center - normal * width)
	right.reverse()
	left.append_array(right)
	return left


func _draw_ribbon(canvas: Node2D) -> void:
	if get_head_progress() - get_tail_progress() < 0.00001 or _elapsed >= get_duration():
		return
	if start_point.distance_to(control_point) + control_point.distance_to(end_point) < 0.01:
		return
	var colors := get_palette()
	if glow_enabled:
		_draw_band(canvas, 0.0, 1.0, Color(colors[1], 0.08), 2.4)
		_draw_band(canvas, 0.0, 1.0, Color(colors[1], 0.10), 1.6)
	# Three separate polygons keep the palette transitions hard and avoid per-segment draw calls.
	_draw_band(canvas, 0.0, 0.30, colors[0])
	_draw_band(canvas, 0.30, 0.77, colors[1])
	_draw_band(canvas, 0.77, 1.0, colors[2])
	var head_position := point_at(get_head_progress())
	canvas.draw_circle(head_position, head_width * 0.5 * _width_scale(), colors[2], true, -1.0, false)


func _draw_band(canvas: Node2D, begin: float, end: float, color: Color, multiplier: float = 1.0) -> void:
	var polygon := _band_polygon(begin, end, multiplier)
	if not Geometry2D.triangulate_polygon(polygon).is_empty():
		canvas.draw_colored_polygon(polygon, color)
		return
	# Very short strips or a curve that doubles back can have duplicate/self-intersecting
	# vertices. Fall back to non-degenerate triangles rather than submitting invalid polygons.
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	var count := polygon.size() / 2
	for i in count - 1:
		var a := polygon[i]
		var b := polygon[i + 1]
		var c := polygon[polygon.size() - 2 - i]
		var d := polygon[polygon.size() - 1 - i]
		for triangle in [PackedVector2Array([a, b, c]), PackedVector2Array([a, c, d])]:
			if not Geometry2D.triangulate_polygon(triangle).is_empty():
				canvas.draw_colored_polygon(triangle, color)


func _draw() -> void:
	if not show_path:
		return
	var path := PackedVector2Array()
	for i in 65:
		path.append(point_at(float(i) / 64.0))
	draw_polyline(path, Color(0.42, 0.63, 0.67, 0.23), 1.0, true)
	draw_line(start_point, control_point, Color(0.42, 0.63, 0.67, 0.15), 1.0, true)
	draw_line(control_point, end_point, Color(0.42, 0.63, 0.67, 0.15), 1.0, true)
	for point in [start_point, control_point, end_point]:
		draw_circle(point, 5.0, Color("79b6b7"), false, 1.0, true)
