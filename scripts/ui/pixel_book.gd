class_name PixelBook
extends Control
## 透明、独立的像素书本。页纹理按左/右顺序排列，每两张为一个跨页。
## 每张活动页以分段网格弯曲，正反面共用几何，内容和阴影跟随纸面。

signal spread_changed(index: int)
signal turn_started(direction: int)
signal turn_finished(committed: bool)
signal progress_changed(value: float)

const CANVAS := Vector2(480, 340)
const OVERSCAN := Vector2(96, 112)
const SPINE := Vector2(240, 66)
const PAGE := Vector2(180, 230)
const SEGMENTS := 24
const MOTION_PIVOT := Vector2(240, 196)
const MOTION_PHASES := [0.0, 0.14, 0.46, 0.72, 0.87, 1.0]
# 分别为挤压、横移、缩放和纵向位移；统一采样翻页进度，支持暂停与拖动回退。
const MOTION_KEYS := [Vector4.ZERO, Vector4(-0.30, -0.18, -0.25, 2.0), Vector4(1.0, 1.0, 1.0, 6.0), Vector4(-0.18, -0.20, -1.0, -1.0), Vector4(0.08, 0.06, 0.10, 1.0), Vector4.ZERO]

@export var page_textures: Array[Texture2D] = []
@export_range(0.2, 3.0, 0.05) var turn_duration := 0.85
@export_range(0.0, 1.5, 0.05) var curl_strength := 0.8
@export_range(1, 5, 1) var leaf_count := 3
@export var cover_color := Color("671b91")
@export var paper_color := Color("fff4db")
@export var shadows_enabled := true
@export var interactive := true
@export var show_bookmark := true
@export_group("页面显示")
## 默认保留像素实验的画布；图鉴可按书皮范围铺满空间，并提高文字绘制分辨率。
@export var fitting_rect := Rect2(Vector2.ZERO, CANVAS)
@export var layout_stretch := Vector2.ONE
@export_range(1.0, 4.0, 0.5) var render_scale := 1.0
@export var constrain_motion_to_frame := false
@export_group("翻页整体运动")
@export var motion_enabled := true
@export_range(0.0, 0.45, 0.01) var squash_amount := 0.30
@export_range(0.0, 48.0, 1.0) var travel_distance := 32.0
@export_range(0.0, 0.30, 0.01) var zoom_amount := 0.18

var spread_index := 0
var turning := false
var dragging := false
var paused := false
var progress := 0.0
var direction := 1
var _view: SubViewport
var _surface: Node2D
var _image: TextureRect
var _settling := false
var _from := 0.0
var _target := 1.0
var _elapsed := 0.0
var _settle_duration := 0.85
var _press_position := Vector2.ZERO
var _drag_distance := 0.0
var _blank: ImageTexture


class BookSurface extends Node2D:

	var book: PixelBook

	func _draw() -> void:
		var raster := Transform2D.IDENTITY.scaled(book.layout_stretch * book.render_scale)
		raster.origin = OVERSCAN * book.layout_stretch * book.render_scale
		draw_set_transform_matrix(raster * book.get_motion_transform())
		book._draw_book(self)


func _ready() -> void:
	clip_contents = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var blank := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	blank.fill(paper_color)
	_blank = ImageTexture.create_from_image(blank)
	_view = SubViewport.new()
	_view.name = "BookCanvas"
	_view.size = Vector2i((CANVAS + OVERSCAN * 2.0) * layout_stretch * render_scale)
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.gui_disable_input = true
	add_child(_view)
	var surface := BookSurface.new()
	surface.book = self
	_surface = surface
	_view.add_child(surface)
	_image = TextureRect.new()
	_image.name = "BookImage"
	_image.texture = _view.get_texture()
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if render_scale > 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	resized.connect(_layout_image)
	_layout_image()
	gui_input.connect(_on_gui_input)


func get_spread_count() -> int:
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	return maxi(1, page_textures.size() / 2)


func _layout_image() -> void:
	var fit := get_layout_transform()
	_image.position = fit * -OVERSCAN
	_image.size = (CANVAS + OVERSCAN * 2.0) * Vector2(fit.x.x, fit.y.y)


func get_layout_transform() -> Transform2D:
	var extent := fitting_rect.size * layout_stretch
	var zoom := minf(size.x / extent.x, size.y / extent.y)
	var stretch := layout_stretch * zoom
	return Transform2D(Vector2(stretch.x, 0), Vector2(0, stretch.y), (size - fitting_rect.size * stretch) * 0.5 - fitting_rect.position * stretch)


func can_turn(value: int) -> bool:
	return not turning and spread_index + signi(value) >= 0 and spread_index + signi(value) < get_spread_count() and value != 0


func turn_next() -> bool:
	return _start(1, true)


func turn_previous() -> bool:
	return _start(-1, true)


func preview_turn(value: int = 1) -> bool:
	return _start(value, false)


func _start(value: int, animate: bool) -> bool:
	if not can_turn(value):
		return false
	direction = signi(value)
	turning = true
	progress = 0.0
	paused = false
	turn_started.emit(direction)
	if animate:
		finish_turn(true)
	return true


func seek_turn(value: float) -> void:
	if not turning:
		return
	_settling = false
	paused = true
	progress = clampf(value, 0.0, 1.0)
	progress_changed.emit(progress)


func finish_turn(commit: bool = true) -> void:
	if not turning:
		return
	dragging = false
	paused = false
	_from = progress
	_target = 1.0 if commit else 0.0
	_elapsed = 0.0
	_settle_duration = maxf(0.12, turn_duration * absf(_target - _from))
	_settling = true


func reset() -> void:
	jump_to_spread(0)


func jump_to_spread(index: int) -> void:
	turning = false
	dragging = false
	paused = false
	_settling = false
	progress = 0.0
	spread_index = clampi(index, 0, get_spread_count() - 1)
	spread_changed.emit(spread_index)
	progress_changed.emit(progress)


func _process(delta: float) -> void:
	if turning and _settling and not paused and not dragging:
		_elapsed += delta
		var t := clampf(_elapsed / _settle_duration, 0.0, 1.0)
		progress = lerpf(_from, _target, t * t * (3.0 - 2.0 * t))
		progress_changed.emit(progress)
		if t >= 1.0:
			var committed := _target > 0.5
			if committed:
				spread_index += direction
			turning = false
			_settling = false
			progress = 0.0
			spread_changed.emit(spread_index)
			turn_finished.emit(committed)
	_surface.queue_redraw()


func get_motion_transform() -> Transform2D:
	if not turning or not motion_enabled:
		return Transform2D.IDENTITY
	var value := Vector4.ZERO
	for i in MOTION_PHASES.size() - 1:
		if progress <= MOTION_PHASES[i + 1]:
			var t := inverse_lerp(MOTION_PHASES[i], MOTION_PHASES[i + 1], progress)
			value = MOTION_KEYS[i].lerp(MOTION_KEYS[i + 1], smoothstep(0.0, 1.0, t))
			break
	var zoom := 1.0 - zoom_amount * value.z
	var stretch := Vector2(1.0 - squash_amount * value.x, 1.0 + squash_amount * value.x * 0.10) * zoom
	var offset := Vector2(-direction * travel_distance * value.y, value.w * travel_distance / 32.0)
	var motion := Transform2D(Vector2(stretch.x, 0), Vector2(0, stretch.y), MOTION_PIVOT + offset - MOTION_PIVOT * stretch)
	return _frame_motion(motion) if constrain_motion_to_frame else motion


func _frame_motion(motion: Transform2D) -> Transform2D:
	# 满版图鉴仍给卷起的纸面留出空间，不能在放大回弹时遮住页头或裁掉书签。
	var bounds := fitting_rect
	for layer in leaf_count:
		var amount := clampf(progress * (1.0 + 0.14 * (leaf_count - 1)) - layer * 0.14, 0.0, 1.0)
		for point in _page_points(amount, layer): bounds = bounds.expand(point)
	bounds = motion * bounds
	var ratio := minf(1.0, minf(fitting_rect.size.x / bounds.size.x, fitting_rect.size.y / bounds.size.y))
	var correction := Transform2D.IDENTITY.scaled(Vector2.ONE * ratio)
	var scaled := correction * bounds
	for axis in 2:
		if scaled.position[axis] < fitting_rect.position[axis]:
			correction.origin[axis] = fitting_rect.position[axis] - scaled.position[axis]
		elif scaled.end[axis] > fitting_rect.end[axis]:
			correction.origin[axis] = fitting_rect.end[axis] - scaled.end[axis]
	return correction * motion


func _to_surface(point: Vector2) -> Vector2:
	return get_layout_transform().affine_inverse() * point


func _to_canvas(point: Vector2) -> Vector2:
	return get_motion_transform().affine_inverse() * _to_surface(point)


func _on_gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point := _to_canvas(event.position)
			if not Rect2(46, 48, 388, 266).has_point(point):
				return
			var value := 1 if point.x >= SPINE.x else -1
			if not _start(value, false):
				return
			dragging = true
			_press_position = _to_surface(event.position)
			_drag_distance = 0.0
			accept_event()
		elif dragging:
			finish_turn(_drag_distance < 6.0 or progress >= 0.22)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		# 拖动距离使用稳定的预览坐标，避免书本自身平移/缩放反过来推动进度。
		var distance := (_press_position.x - _to_surface(event.position).x) * direction
		_drag_distance = maxf(_drag_distance, absf(distance))
		progress = clampf(distance / (PAGE.x * 1.6), 0.0, 1.0)
		progress_changed.emit(progress)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging:
		finish_turn(false)


func _texture(index: int) -> Texture2D:
	if index >= 0 and index < page_textures.size() and page_textures[index] != null:
		return page_textures[index]
	return _blank


func _flat(canvas: Node2D, left: bool, index: int) -> void:
	var pos := SPINE - Vector2(PAGE.x if left else 0.0, 0.0)
	canvas.draw_texture_rect(_texture(index), Rect2(pos, PAGE), false)
	canvas.draw_line(pos, pos + Vector2(PAGE.x, 0), Color("86636e"), 1)
	canvas.draw_line(pos + Vector2(0, PAGE.y), pos + PAGE, Color("d89e86"), 2)
	var edge := pos.x if left else pos.x + PAGE.x
	canvas.draw_line(Vector2(edge, pos.y), Vector2(edge, pos.y + PAGE.y), Color("f6d1af"), 1)


func _page_points(amount: float, layer: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var envelope := sin(amount * PI)
	var x := 0.0
	var z := 0.0
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		if i > 0:
			var midpoint := (float(i) - 0.5) / SEGMENTS
			var angle := amount * PI + envelope * curl_strength * sin(midpoint * TAU - 0.7)
			x += cos(angle) * PAGE.x / SEGMENTS
			z += sin(angle) * PAGE.x / SEGMENTS
		var px := SPINE.x + direction * (x + z * 0.10)
		var lift := z * 0.34
		var flutter := envelope * sin(u * PI) * (3.0 + layer * 1.1)
		points.append(Vector2(px, SPINE.y - lift - flutter))
		points.append(Vector2(px, SPINE.y + PAGE.y - lift * 0.56 + flutter))
	return points


func _draw_leaf(canvas: Node2D, amount: float, layer: int, points: Array[Vector2]) -> void:
	var envelope := sin(amount * PI)
	var strips: Array[Dictionary] = []
	for i in SEGMENTS:
		strips.append({"index": i, "depth": SPINE.y * 2.0 - points[i * 2].y - points[(i + 1) * 2].y})
	strips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.depth < b.depth)
	for strip in strips:
		var i: int = strip.index
		# 逐段判断朝向，卷边可同时露出正反面，穿过中线时不会整页跳图。
		var back := (points[(i + 1) * 2].x - points[i * 2].x) * direction < 0.0
		# 只在起始外页正面和最终落页背面显示内容，夹在中间的纸面留白。
		var texture: Texture2D = _blank
		if not back and layer == 0:
			texture = _texture(spread_index * 2 + (1 if direction > 0 else 0))
		elif back and layer == leaf_count - 1:
			texture = _texture((spread_index + direction) * 2 + (0 if direction > 0 else 1))
		var mirror := (back and direction > 0) or (not back and direction < 0)
		var u0 := float(i) / SEGMENTS
		var u1 := float(i + 1) / SEGMENTS
		var quad := PackedVector2Array([points[i * 2], points[(i + 1) * 2], points[(i + 1) * 2 + 1], points[i * 2 + 1]])
		var uv := PackedVector2Array([Vector2(1.0 - u0 if mirror else u0, 0), Vector2(1.0 - u1 if mirror else u1, 0), Vector2(1.0 - u1 if mirror else u1, 1), Vector2(1.0 - u0 if mirror else u0, 1)])
		var shade := 1.0 - envelope * (0.10 + 0.18 * sin(u0 * PI)) - layer * 0.018 * envelope
		_quad(canvas, quad, Color(shade, shade, shade), uv, texture)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in SEGMENTS + 1:
		top.append(points[i * 2])
		bottom.append(points[i * 2 + 1])
	canvas.draw_polyline(top, Color("86636e"), 1.0)
	canvas.draw_polyline(bottom, Color("d89e86"), 2.0)
	canvas.draw_line(top[-1], bottom[-1], Color("f6d1af"), 1.0)


func _draw_book(canvas: Node2D) -> void:
	# 所有书本内容在低分辨率透明视口中栅格化，缩放时保持像素边缘。
	if shadows_enabled:
		for i in range(7, 0, -1):
			canvas.draw_style_box(_box(Color(0.02, 0.01, 0.04, 0.025), 12), Rect2(44 - i * 2, 80 + i * 2, 392 + i * 4, 236))
	canvas.draw_style_box(_box(Color("281538"), 8), Rect2(43, 59, 394, 254))
	canvas.draw_style_box(_box(cover_color.darkened(0.35), 7), Rect2(46, 57, 388, 252))
	canvas.draw_style_box(_box(cover_color, 7), Rect2(46, 55, 388, 249))
	canvas.draw_style_box(_box(cover_color.lightened(0.18), 5), Rect2(50, 59, 380, 240))
	# 封面金属角与多层书口。
	for x in [51.0, 415.0]:
		for y in [60.0, 287.0]:
			canvas.draw_rect(Rect2(x, y, 14, 3), Color("e1a26e"))
			canvas.draw_rect(Rect2(x, y, 3, 12), Color("e1a26e"))
	for i in range(5, 0, -1):
		canvas.draw_rect(Rect2(58, 65 + i * 1.7, 364, 232), Color("bf8e83") if i % 2 else Color("f0c7a5"))
	var left_index := spread_index * 2
	var right_index := left_index + 1
	if turning:
		if direction > 0:
			right_index += 2
		else:
			left_index -= 2
	_flat(canvas, true, left_index)
	_flat(canvas, false, right_index)
	if turning:
		var leaves: Array[Dictionary] = []
		for i in leaf_count:
			var amount := clampf(progress * (1.0 + 0.14 * (leaf_count - 1)) - i * 0.14, 0.0, 1.0)
			leaves.append({"amount": amount, "layer": i, "depth": sin(amount * PI), "points": _page_points(amount, i)})
		leaves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a.depth, b.depth):
				return a.depth < b.depth
			# 同处起点时首张在上；同处终点时末张在上，避免空白页盖住内容。
			return a.layer > b.layer if a.amount < 0.5 else a.layer < b.layer)
		if shadows_enabled:
			for leaf in leaves:
				var depth: float = leaf.depth
				if depth < 0.02:
					continue
				var points: Array[Vector2] = leaf.points
				var offset := Vector2(direction * depth * 7, depth * 18)
				# 卷曲投影可能折回自身；显式三角形避免凹多边形三角化失败。
				for i in SEGMENTS:
					var quad := PackedVector2Array([points[i * 2] + offset, points[(i + 1) * 2] + offset, points[(i + 1) * 2 + 1] + offset, points[i * 2 + 1] + offset])
					_quad(canvas, quad, Color(0.15, 0.06, 0.18, depth * 0.11))
		for leaf in leaves:
			_draw_leaf(canvas, leaf.amount, leaf.layer, leaf.points)
	# 装订阴影放在纸面上方，落页前后使用相同的明暗与描边。
	if shadows_enabled:
		for i in 13:
			canvas.draw_line(Vector2(SPINE.x - 6 + i, SPINE.y), Vector2(SPINE.x - 6 + i, SPINE.y + PAGE.y), Color(0.23, 0.08, 0.25, 0.17 * (1.0 - absf(i - 6) / 7.0)))
	canvas.draw_line(Vector2(240, 66), Vector2(240, 298), Color("b77786"), 1)
	# 书签垂在书口之外。
	if show_bookmark:
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(385, 297), Vector2(397, 297), Vector2(397, 324), Vector2(391, 319), Vector2(385, 324)]), Color("b55869"))


func _quad(canvas: Node2D, points: PackedVector2Array, color: Color, uv := PackedVector2Array(), texture: Texture2D = null) -> void:
	for indices in [[0, 1, 2], [0, 2, 3]]:
		var triangle := PackedVector2Array()
		var coordinates := PackedVector2Array()
		for index in indices:
			triangle.append(points[index])
			if not uv.is_empty():
				coordinates.append(uv[index])
		canvas.draw_primitive(triangle, PackedColorArray([color]), coordinates, texture)


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.corner_detail = 1
	return result
