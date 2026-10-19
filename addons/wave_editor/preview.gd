# 这玩意儿是干嘛的（核心逻辑）：显示地形、建议区域和重叠提示，支持框选、组拖动与视图导航。
# 数据是咋流动的（数据流向）：导航右半边 → 建议区域 → 鼠标换算局部坐标 → 整组提交撤销。
# 为啥这么写（选型决策）：只画立绘不启动 AI；碰撞外接圆给出保守的重叠提示。
# 性能咋样（复杂度）：操作时重画，几十个单位两两比较，不做持续物理模拟。
@tool
extends Control

signal selection_changed(indices: PackedInt32Array)
signal drag_started
signal drag_finished(changed: bool)
var units: Array[Node] = []
var selection := PackedInt32Array()
var team_transform := Transform2D.IDENTITY
var origin := Vector2.ZERO
var viewport: SubViewport
var backdrop: TextureRect
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)
const FIT_PADDING := 16.0
var map_bounds := DEFAULT_BOUNDS
var _bounds_points := PackedVector2Array()
var polygons: Array[PackedVector2Array] = []
var view_scale := 1.0
var pan := Vector2.ZERO
var snapping := false
var grid := 32.0
var show_area := true
var dragging := false
var panning := false
var boxing := false
var anchor := Vector2.ZERO
var box_end := Vector2.ZERO
var old_positions: Dictionary = {}
var box_selection := PackedInt32Array()

# 作用：引擎入树时建立隔离视口；没有参数，没有返回值。
func _ready() -> void:
	custom_minimum_size = Vector2(550, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.texture = viewport.get_texture()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	add_child(backdrop)
	resized.connect(update_view)
	update_view()

# 作用：获取世界缩放；没有参数，返回像素倍率。
func zoom() -> float:
	var available := (size - Vector2.ONE * FIT_PADDING * 2.0).max(Vector2.ONE)
	return maxf(0.0001, minf(available.x / map_bounds.size.x, available.y / map_bounds.size.y) * view_scale)

# 作用：获取地形起点；没有参数，返回屏幕坐标。
func offset() -> Vector2:
	return size / 2.0 - map_bounds.get_center() * zoom() + pan

# 作用：局部刷怪坐标转屏幕；point 为 TeamB 坐标，返回屏幕位置。
func screen(point: Vector2) -> Vector2:
	return offset() + (team_transform * point) * zoom()

# 作用：鼠标位置转局部刷怪坐标；point 为屏幕位置，返回 TeamB 坐标。
func local_point(point: Vector2) -> Vector2:
	return team_transform.affine_inverse() * ((point - offset()) / zoom())

# 作用：刷新地形与标记；没有参数，没有返回值。
func update_view() -> void:
	if viewport != null and backdrop != null:
		# 按窗口分辨率渲染当前视野，地图再大也不分配整张地图大小的纹理。
		viewport.size = Vector2i(maxi(2, ceili(size.x)), maxi(2, ceili(size.y)))
		viewport.canvas_transform = Transform2D(Vector2(zoom(), 0), Vector2(0, zoom()), offset())
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		backdrop.position = Vector2.ZERO
		backdrop.size = Vector2(viewport.size)
	queue_redraw()

# 作用：恢复全景；没有参数，没有返回值。
func fit() -> void:
	view_scale = 1.0
	pan = Vector2.ZERO
	update_view()

# 作用：绕鼠标缩放；factor 为倍率，point 为锚点，没有返回值。
func zoom_at(factor: float, point: Vector2) -> void:
	var world := (point - offset()) / zoom()
	view_scale = clampf(view_scale * factor, 0.35, 8.0)
	pan += point - (offset() + world * zoom())
	update_view()

# 作用：读取树外节点累计变换；node 为目标节点，返回世界变换。
func world_transform(node: Node) -> Transform2D:
	var result := Transform2D.IDENTITY
	while node != null:
		if node is Node2D:
			result = node.transform * result
		node = node.get_parent()
	return result

# 作用：加载地形和导航；scene 是关卡场景，没有返回值。
func load_terrain(scene: PackedScene) -> void:
	for child in viewport.get_children():
		child.free()
	polygons.clear()
	_bounds_points.clear()
	map_bounds = DEFAULT_BOUNDS
	team_transform = Transform2D.IDENTITY
	origin = Vector2.ZERO
	if scene != null:
		var battle := scene.instantiate()
		var team := battle.get_node_or_null("Entities/TeamB")
		if team != null:
			team_transform = world_transform(team)
			origin = team_transform.origin
		_read_polygons(battle.get_node_or_null("Level/NavigationRegion2D"))
		var terrain := battle.get_node_or_null("Level")
		if terrain != null:
			_read_terrain_bounds(terrain)
			var transform := world_transform(terrain)
			terrain.owner = null
			battle.remove_child(terrain)
			_sanitize(terrain)
			if terrain is Node2D:
				terrain.transform = transform
			viewport.add_child(terrain)
		battle.free()
	if not _bounds_points.is_empty():
		map_bounds = Rect2(_bounds_points[0], Vector2.ZERO)
		for point in _bounds_points:
			map_bounds = map_bounds.expand(point)
		map_bounds.size = map_bounds.size.max(Vector2.ONE)
	update_view()

# 作用：收集地形实际边界；node 为树外地形节点，没有返回值。
func _read_terrain_bounds(node: Node) -> void:
	# 循环背景不定义地图大小，隐藏的图层也不扩大全景范围。
	if node is Parallax2D or (node is CanvasItem and not node.visible):
		return
	var transform := world_transform(node)
	if node is TileMapLayer and node.enabled and node.tile_set != null:
		var used: Rect2i = node.get_used_rect()
		if used.has_area():
			var last := used.end - Vector2i.ONE
			var half_tile := Vector2(node.tile_set.tile_size) / 2.0
			for cell in [used.position, Vector2i(last.x, used.position.y), last, Vector2i(used.position.x, last.y)]:
				_append_bounds_rect(Rect2(node.map_to_local(cell) - half_tile, half_tile * 2.0), transform)
	elif node is Sprite2D and node.texture != null:
		_append_bounds_rect(node.get_rect(), transform)
	elif node is Polygon2D:
		for point in node.polygon:
			_bounds_points.append(transform * (point + node.offset))
	for child in node.get_children():
		_read_terrain_bounds(child)

# 作用：把局部矩形四角纳入世界边界；rect 为局部范围，transform 为累计变换。
func _append_bounds_rect(rect: Rect2, transform: Transform2D) -> void:
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		_bounds_points.append(transform * point)

# 作用：提取烘焙导航右半边；region 是导航节点，没有返回值。
func _read_polygons(region: Node) -> void:
	if not region is NavigationRegion2D or region.navigation_polygon == null or not region.enabled:
		return
	var nav: NavigationPolygon = region.navigation_polygon
	var vertices := nav.get_vertices()
	if vertices.is_empty():
		return
	var transform := world_transform(region)
	var bounds := Rect2(transform * vertices[0], Vector2.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(transform * vertex)
		_bounds_points.append(transform * vertex)
	var middle := bounds.get_center().x
	var right := PackedVector2Array([Vector2(middle, bounds.position.y), Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(middle, bounds.end.y)])
	for i in nav.get_polygon_count():
		var polygon := PackedVector2Array()
		for index in nav.get_polygon(i):
			polygon.append(transform * vertices[index])
		polygons.append_array(Geometry2D.intersect_polygons(polygon, right))

# 作用：剥离预览地形行为；node 是节点，没有返回值。
func _sanitize(node: Node) -> void:
	node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is NavigationRegion2D:
		node.enabled = false
	if node is TileMapLayer:
		node.navigation_enabled = false
		node.collision_enabled = false
	if node is Parallax2D:
		node.autoscroll = Vector2.ZERO
		node.follow_viewport = false
	for child in node.get_children():
		_sanitize(child)

# 作用：检查脚底是否在建议区域；point 是世界位置，返回是否在区域内。
func allowed(point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

# 作用：获取保守碰撞范围；unit 是怪物，返回世界中心与半径。
func footprint(unit: Node2D) -> Vector3:
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var center: Vector2 = team_transform * unit.position
	var radius := 20.0
	if shape != null and shape.shape != null and not shape.disabled:
		var transform := team_transform * unit.transform * shape.transform
		center = transform.origin
		radius = shape.shape.get_rect().size.length() * 0.5 * maxf(transform.x.length(), transform.y.length())
		if shape.shape is CircleShape2D:
			radius = shape.shape.radius * maxf(transform.x.length(), transform.y.length())
	return Vector3(center.x, center.y, radius)

# 作用：检查越界和重叠；没有参数，返回每个怪物的提示。
func analyze() -> Array[String]:
	var result: Array[String] = []
	for unit in units:
		result.append("导航未知" if polygons.is_empty() else ("" if allowed(team_transform * unit.position) else "超出建议区域"))
	for i in units.size():
		var a := footprint(units[i])
		for j in range(i + 1, units.size()):
			var b := footprint(units[j])
			if Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) < a.z + b.z:
				result[i] += " 重叠#%d" % (j + 1)
				result[j] += " 重叠#%d" % (i + 1)
	return result

# 作用：引擎重画时显示辅助和怪物；没有参数，没有返回值。
func _draw() -> void:
	if show_area:
		for polygon in polygons:
			var points := PackedVector2Array()
			for point in polygon:
				points.append(offset() + point * zoom())
			draw_colored_polygon(points, Color(0.15, 0.8, 0.5, 0.18))
	if snapping:
		# 只画屏幕可见的世界网格；整组吸附时以第一个怪物对齐，保留组内相对站位。
		var start := (Vector2.ZERO - offset()) / zoom()
		var end := (size - offset()) / zoom()
		for x in range(int(floor(start.x / grid)), int(ceil(end.x / grid)) + 1):
			draw_line(offset() + Vector2(x * grid, start.y) * zoom(), offset() + Vector2(x * grid, end.y) * zoom(), Color(1, 1, 1, 0.16))
		for y in range(int(floor(start.y / grid)), int(ceil(end.y / grid)) + 1):
			draw_line(offset() + Vector2(start.x, y * grid) * zoom(), offset() + Vector2(end.x, y * grid) * zoom(), Color(1, 1, 1, 0.16))
	var warnings := analyze()
	for i in units.size():
		var unit := units[i] as Node2D
		var point := screen(unit.position)
		var color := Color(0.2, 0.8, 0.5, 0.65) if warnings[i].is_empty() else Color(1, 0.35, 0.1, 0.8)
		var circle := footprint(unit)
		draw_circle(offset() + Vector2(circle.x, circle.y) * zoom(), maxf(10, circle.z * zoom()), color)
		_draw_sprite(unit, point)
		if selection.has(i):
			draw_arc(point, maxf(22, circle.z * zoom() + 4), 0, TAU, 32, Color.YELLOW, 2)
		draw_string(ThemeDB.fallback_font, point + Vector2(18, 0), str(i + 1) + (" !" if not warnings[i].is_empty() else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if boxing:
		draw_rect(Rect2(anchor, box_end - anchor).abs(), Color(0.4, 0.7, 1, 0.25))
		draw_rect(Rect2(anchor, box_end - anchor).abs(), Color.SKY_BLUE, false)

# 作用：绘制立绘；unit 是怪物，point 是屏幕脚底坐标，没有返回值。
func _draw_sprite(unit: Node2D, point: Vector2) -> void:
	var sprite := unit.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	if texture == null:
		return
	var extent := texture.get_size() * unit.scale * sprite.scale * zoom()
	var center := point + sprite.position * unit.scale * zoom()
	draw_set_transform(center, 0, Vector2(-1 if sprite.flip_h else 1, -1 if sprite.flip_v else 1))
	draw_texture_rect(texture, Rect2(-extent / 2, extent), false)
	draw_set_transform(Vector2.ZERO)

# 作用：结束组拖动；没有参数，没有返回值。
func finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	var modified := false
	for index in old_positions:
		modified = modified or units[index].position != old_positions[index]
	drag_finished.emit(modified)
	old_positions.clear()

# 作用：输入驱动选择、拖动和视图操作；event 为鼠标事件，没有返回值。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				anchor = event.position
				var hit := -1
				for i in range(units.size() - 1, -1, -1):
					if event.position.distance_to(screen(units[i].position)) <= 24:
						hit = i
						break
				var multiple: bool = event.ctrl_pressed or event.shift_pressed
				if hit >= 0:
					if multiple and selection.has(hit):
						selection.remove_at(selection.find(hit))
					else:
						if not multiple and not selection.has(hit):
							selection.clear()
						if not selection.has(hit):
							selection.append(hit)
					selection_changed.emit(selection)
					dragging = selection.has(hit)
					old_positions.clear()
					if dragging:
						for index in selection:
							old_positions[index] = units[index].position
						drag_started.emit()
				else:
					boxing = true
					box_end = anchor
					box_selection = selection.duplicate() if multiple else PackedInt32Array()
			else:
				finish_drag()
				if boxing:
					boxing = false
					selection = box_selection.duplicate()
					var rect := Rect2(anchor, event.position - anchor).abs()
					for i in units.size():
						if rect.has_point(screen(units[i].position)) and not selection.has(i):
							selection.append(i)
					selection_changed.emit(selection)
		accept_event()
	if event is InputEventMouseMotion:
		if panning:
			pan += event.relative
			update_view()
		elif dragging:
			var delta := local_point(event.position) - local_point(anchor)
			if snapping and not selection.is_empty():
				var first: Vector2 = team_transform * (old_positions[selection[0]] + delta)
				delta = team_transform.affine_inverse() * first.snapped(Vector2.ONE * grid) - old_positions[selection[0]]
			for index in selection:
				units[index].position = (old_positions[index] + delta).round()
		elif boxing:
			box_end = event.position
	queue_redraw()
