@tool
class_name PixelLightning
extends Node2D
## 独立像素落雷，原点是主干落点。每次击发生成固定折线，播放中不抖动。
## 不读取全局状态、不造成伤害、不移动镜头；可以在编辑器或独立场景中查看。

signal struck
signal finished

@export_group("形状")
@export_enum("单雷", "树状落雷") var lightning_type: int = 1:
	set(value):
		lightning_type = clampi(value, 0, 1)
		_rebuild()
@export_range(32.0, 320.0, 1.0) var bolt_height := 136.0:
	set(value):
		bolt_height = maxf(value, 32.0)
		_rebuild()
@export_range(3, 14, 1) var segment_count := 7:
	set(value):
		segment_count = clampi(value, 3, 14)
		_rebuild()
@export_range(0.0, 40.0, 1.0) var lateral_spread := 11.0:
	set(value):
		lateral_spread = maxf(value, 0.0)
		_rebuild()
@export_range(1.0, 4.0, 1.0) var pixel_size := 1.0:
	set(value):
		pixel_size = maxf(value, 1.0)
		_rebuild()
@export_range(1, 3, 1) var core_width := 1:
	set(value):
		core_width = clampi(value, 1, 3)
		queue_redraw()
@export_range(1, 5, 1) var branch_count := 3:
	set(value):
		branch_count = clampi(value, 1, 5)
		_rebuild()
@export_range(8.0, 80.0, 1.0) var branch_spread := 38.0:
	set(value):
		branch_spread = maxf(value, 8.0)
		_rebuild()
@export var secondary_branches := true:
	set(value):
		secondary_branches = value
		_rebuild()
## 固定种子使 seek() 可精确复现。每次 trigger() 增加击发编号，生成新的形状。
@export var random_seed: int = 17:
	set(value):
		random_seed = value
		_rebuild()

@export_group("节奏")
@export_range(0.02, 0.3, 0.005) var strike_duration := 0.055:
	set(value):
		strike_duration = maxf(value, 0.02)
		queue_redraw()
@export_range(0.02, 0.2, 0.005) var flash_duration := 0.045:
	set(value):
		flash_duration = maxf(value, 0.02)
		queue_redraw()
@export_range(0.05, 0.6, 0.01) var afterglow_duration := 0.24:
	set(value):
		afterglow_duration = maxf(value, 0.05)
		queue_redraw()
@export_range(0.0, 3.0, 0.05) var playback_speed := 1.0
@export var playing := true
@export var auto_start := true
@export var loop := false
@export_range(0.1, 5.0, 0.05) var loop_delay := 1.25
@export var restrike_enabled := false:
	set(value):
		restrike_enabled = value
		queue_redraw()

@export_group("细节")
@export var glints_enabled := true:
	set(value):
		glints_enabled = value
		queue_redraw()
@export var sparks_enabled := true:
	set(value):
		sparks_enabled = value
		queue_redraw()
@export_range(0.04, 0.25, 0.005) var spark_duration := 0.095:
	set(value):
		spark_duration = maxf(value, 0.04)
		queue_redraw()
@export_range(4.0, 40.0, 1.0) var spark_spread := 17.0:
	set(value):
		spark_spread = maxf(value, 4.0)
		_rebuild()

@export_group("颜色")
@export var core_color := Color("e5e5d5"):
	set(value):
		core_color = value
		queue_redraw()
@export var branch_color := Color("87c6cb"):
	set(value):
		branch_color = value
		queue_redraw()
@export var dim_color := Color("385e69"):
	set(value):
		dim_color = value
		queue_redraw()

@export_group("分层查看")
@export_enum("完整效果", "折线与折点", "只看主干", "只看分支", "只看亮片", "只看火花") var debug_view: int = 0:
	set(value):
		debug_view = clampi(value, 0, 5)
		queue_redraw()

var _paths: Array[Dictionary] = []
var _elapsed := 0.0
var _strike_id := 0
var _active := false
var _has_preview := false
var _impact_emitted := false
var _finished_emitted := false


func _ready() -> void:
	_rebuild()
	if auto_start:
		restart()


func _process(delta: float) -> void:
	if not playing or not _active or playback_speed <= 0.0:
		return
	var previous := _elapsed
	seek(_elapsed + delta * playback_speed)
	if not _impact_emitted and previous < strike_duration and _elapsed >= strike_duration:
		_impact_emitted = true
		if not Engine.is_editor_hint():
			struck.emit()
	if not _finished_emitted and _elapsed >= get_duration():
		_finished_emitted = true
		if not Engine.is_editor_hint():
			finished.emit()
	if loop and _elapsed >= get_duration() + loop_delay:
		trigger()
	elif not loop and _finished_emitted:
		_active = false


## 触发新形状；暂停状态下也可生成，时间由外部 seek() 控制。
func trigger() -> void:
	_strike_id += 1
	_rebuild()
	restart()


## 重播当前形状，保留种子与折点。
func restart() -> void:
	_active = true
	_impact_emitted = false
	_finished_emitted = false
	seek(0.0)


## 只设置画面时间，不发送击中/结束信号，也不重新随机化。
func seek(seconds: float) -> void:
	_elapsed = maxf(seconds, 0.0)
	_has_preview = true
	queue_redraw()


func get_elapsed() -> float:
	return _elapsed


func get_duration() -> float:
	var duration := strike_duration + maxf(flash_duration + afterglow_duration, spark_duration)
	if restrike_enabled:
		duration += strike_duration * 0.2 + flash_duration + 0.065
	return duration


func is_active() -> bool:
	return _active


## 恢复种子序列的第一道落雷，便于对照默认效果。
func reset_sequence() -> void:
	_strike_id = 0
	_rebuild()
	restart()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + _strike_id * 104729
	_paths.clear()
	var points := PackedVector2Array([_snap(Vector2(0, -bolt_height))])
	# 固定端点；中间折点沿竖向等分后左右交替，避免一帧一帧随机抖动。
	var initial_side := 1.0 if rng.randf() > 0.5 else -1.0
	for i in range(1, segment_count):
		var side := initial_side * (1.0 if i % 2 == 0 else -1.0)
		points.append(_snap(Vector2(side * rng.randf_range(0.25, 1.0) * lateral_spread,
			-bolt_height * (1.0 - float(i) / segment_count))))
	points.append(Vector2.ZERO)
	_add_path(points, 0, true, rng)
	if lightning_type == 1:
		for i in branch_count:
			var start_index := clampi(2 + int(float(i) * (segment_count - 3) / branch_count), 1, segment_count - 2)
			var start := points[start_index]
			var direction := -1.0 if i % 2 == 0 else 1.0
			var grounded := i % 2 == 0
			var endpoint := _snap(Vector2(start.x + direction * branch_spread * rng.randf_range(0.65, 1.1),
				0.0 if grounded else lerpf(start.y, 0.0, rng.randf_range(0.60, 0.85))))
			var branch := _branch_points(start, endpoint, 4, rng)
			_add_path(branch, 1, grounded, rng)
			if secondary_branches:
				var child_start := branch[rng.randi_range(1, 2)]
				var child_end := _snap(Vector2(child_start.x + direction * branch_spread * rng.randf_range(0.25, 0.5),
					lerpf(child_start.y, endpoint.y, 0.8)))
				_add_path(_branch_points(child_start, child_end, 3, rng), 2, false, rng)
	queue_redraw()


func _branch_points(start: Vector2, endpoint: Vector2, segments: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	for i in range(1, segments):
		var point := start.lerp(endpoint, float(i) / segments)
		point.x += rng.randf_range(-1.0, 1.0) * lateral_spread * 0.55
		points.append(_snap(point))
	points.append(endpoint)
	return points


func _add_path(points: PackedVector2Array, depth: int, grounded: bool, rng: RandomNumberGenerator) -> void:
	var cells := PackedVector2Array()
	for i in range(points.size() - 1):
		var segment := _rasterize(points[i], points[i + 1])
		if i > 0:
			segment.remove_at(0)
		cells.append_array(segment)
	var glints := PackedVector2Array()
	if depth < 2:
		for i in range(1, points.size() - 1):
			if rng.randf() < (0.48 if depth == 0 else 0.28):
				glints.append(points[i])
	var sparks := PackedVector2Array()
	for direction in [Vector2(-1, -0.2), Vector2(-0.48, -0.9), Vector2(0.48, -0.9), Vector2(1, -0.2)]:
		sparks.append(_snap(direction * spark_spread * rng.randf_range(0.8, 1.2) * (1.0 if depth == 0 else 0.65)))
	_paths.append({"points": points, "cells": cells, "depth": depth, "grounded": grounded,
		"glints": glints, "sparks": sparks})


func _snap(point: Vector2) -> Vector2:
	return (point / pixel_size).round() * pixel_size


## Bresenham 栅格化保证所有线段都由整数像素块组成，不依赖抗锯齿或屏幕着色器。
func _rasterize(start: Vector2, endpoint: Vector2) -> PackedVector2Array:
	var a := Vector2i((start / pixel_size).round())
	var b := Vector2i((endpoint / pixel_size).round())
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var error := dx + dy
	var cells := PackedVector2Array()
	while true:
		cells.append(Vector2(a) * pixel_size)
		if a == b:
			break
		var twice := error * 2
		if twice >= dy:
			error += dy
			a.x += sx
		if twice <= dx:
			error += dx
			a.y += sy
	return cells


func _draw() -> void:
	if _paths.is_empty():
		return
	if debug_view == 1:
		_draw_structure()
		return
	if not _has_preview:
		return
	var t := _elapsed
	if restrike_enabled:
		var repeat_at := strike_duration + flash_duration + 0.065
		if t >= repeat_at:
			t -= repeat_at
			# 二次闪击重用已生成的通道，迅速贯通。
			t += strike_duration * 0.8
	if t >= strike_duration + maxf(flash_duration + afterglow_duration, spark_duration):
		return
	var head_y := lerpf(-bolt_height - pixel_size, pixel_size, clampf(t / strike_duration, 0.0, 1.0))
	var impact_time := maxf(t - strike_duration, 0.0)
	for path in _paths:
		var depth: int = path.depth
		var fade_duration: float = afterglow_duration * [1.0, 0.62, 0.40][depth]
		var fade := clampf((impact_time - flash_duration) / fade_duration, 0.0, 1.0)
		var color := core_color if depth == 0 else (branch_color if depth == 1 else dim_color.lerp(branch_color, 0.28))
		if t >= strike_duration + flash_duration * 0.45:
			color = branch_color if depth == 0 else dim_color.lerp(branch_color, 0.45 if depth == 1 else 0.10)
		color = color.lerp(dim_color, fade)
		color.a *= 1.0 - fade
		if color.a > 0.01 and debug_view in [0, 2, 3]:
			if (debug_view != 2 or depth == 0) and (debug_view != 3 or depth > 0):
				var width := core_width if depth == 0 else 1
				for cell in path.cells:
					if cell.y <= head_y:
						_pixel(cell, Vector2(width, width), color)
		if glints_enabled and debug_view in [0, 4] and impact_time < flash_duration and t >= strike_duration:
			var glint_color := core_color if depth == 0 else branch_color
			for point in path.glints:
				_pixel(point - Vector2(pixel_size, 0), Vector2(3, 1), glint_color)
				_pixel(point - Vector2(0, pixel_size * 2), Vector2(1, 4), glint_color)
		if sparks_enabled and path.grounded and debug_view in [0, 5] and t >= strike_duration and impact_time < spark_duration:
			_draw_sparks(path, impact_time)


func _draw_sparks(path: Dictionary, time: float) -> void:
	var life := clampf(time / spark_duration, 0.0, 1.0)
	var origin: Vector2 = path.points[-1]
	var color := branch_color if path.depth == 0 else dim_color.lerp(branch_color, 0.55)
	color = color.lerp(dim_color, maxf((life - 0.35) / 0.65, 0.0))
	# 火花提前到达目标；后半段上方两粒先消失，左右两粒随后消失。
	if life < 0.7:
		_pixel(origin - Vector2(pixel_size, pixel_size * 2), Vector2(3, 4) if life < 0.35 else Vector2(2, 2), color)
	for i in path.sparks.size():
		if life > (0.68 if i in [1, 2] else 0.88):
			continue
		var location := _snap(origin + path.sparks[i] * (1.0 - pow(1.0 - life, 3.0)))
		_pixel(location, Vector2(2, 1) if i in [0, 3] else Vector2.ONE, color)


func _pixel(point: Vector2, dimensions: Vector2, color: Color) -> void:
	draw_rect(Rect2(point, dimensions * pixel_size), color)


func _draw_structure() -> void:
	for path in _paths:
		var points: PackedVector2Array = path.points
		var color := core_color if path.depth == 0 else branch_color.darkened(path.depth * 0.2)
		for cell in path.cells:
			_pixel(cell, Vector2.ONE, Color(color, 0.55))
		for i in points.size():
			var point := points[i]
			draw_rect(Rect2(point - Vector2.ONE * pixel_size * 2, Vector2.ONE * pixel_size * 5), Color("d9ad66"), false, pixel_size)
			if path.depth == 0:
				draw_string(ThemeDB.fallback_font, point + Vector2(5, -3), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("d9ad66"))
