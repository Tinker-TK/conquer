# 验证大地图完整渲染、负坐标、累计变换以及缩放平移后的刷怪坐标。
# --capture 使用实际渲染检查四角瓦片，并保存波次编辑器截图。
extends SceneTree

const PREVIEW = preload("res://addons/wave_editor/preview.gd")
const COLORS := [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
const MARKERS := [Vector2(-3035, -1226), Vector2(6485, -1226), Vector2(6485, 2806), Vector2(-3035, 2806)]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_own(child, scene_root)

func _large_map() -> PackedScene:
	var battle := Node2D.new()
	var level := Node2D.new()
	level.name = "Level"
	level.position = Vector2(100, -80)
	level.scale = Vector2(1.25, 0.75)
	battle.add_child(level)
	var ground := Polygon2D.new()
	ground.position = Vector2(20, 40)
	ground.polygon = PackedVector2Array([Vector2(-2560, -1600), Vector2(5120, -1600), Vector2(5120, 3840), Vector2(-2560, 3840)])
	ground.color = Color(0.1, 0.12, 0.15)
	level.add_child(ground)
	var image := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	for i in COLORS.size():
		image.fill_rect(Rect2i(i * 64, 0, 64, 64), COLORS[i])
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(64, 64)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_source(atlas, 0)
	var layer := TileMapLayer.new()
	layer.position = Vector2(20, 40)
	layer.tile_set = tiles
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	level.add_child(layer)
	var cells := [Vector2i(-40, -25), Vector2i(79, -25), Vector2i(79, 59), Vector2i(-40, 59)]
	for i in cells.size():
		atlas.create_tile(Vector2i(i, 0))
		layer.set_cell(cells[i], 0, Vector2i(i, 0))
	var hidden := Polygon2D.new()
	hidden.visible = false
	hidden.polygon = PackedVector2Array([Vector2.ZERO, Vector2(100000, 0), Vector2(100000, 100000)])
	level.add_child(hidden)
	var entities := Node2D.new()
	entities.name = "Entities"
	entities.position = Vector2(-60, 80)
	entities.scale = Vector2(1.2, 0.9)
	battle.add_child(entities)
	var team := Node2D.new()
	team.name = "TeamB"
	team.position = Vector2(2800, 750)
	team.rotation = 0.1
	entities.add_child(team)
	_own(battle, battle)
	var packed := PackedScene.new()
	check(packed.pack(battle) == OK, "建立独立大地图夹具")
	battle.free()
	return packed

func _check_fit(preview: Control) -> void:
	for point in [preview.map_bounds.position, preview.map_bounds.end,
		Vector2(preview.map_bounds.end.x, preview.map_bounds.position.y), Vector2(preview.map_bounds.position.x, preview.map_bounds.end.y)]:
		var screen: Vector2 = preview.viewport.canvas_transform * point
		check(Rect2(Vector2.ZERO, preview.size).has_point(screen), "全图边缘在预览窗口内：" + str(point))
	check((preview.viewport.canvas_transform * preview.map_bounds.get_center()).distance_to(preview.size / 2.0) < 0.01, "全图居中")
	check(preview.viewport.size == Vector2i(preview.size.ceil()), "纹理大小由窗口决定")

func _capture(preview: Control) -> Image:
	preview.update_view()
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	return preview.viewport.get_texture().get_image()

func _check_marker(image: Image, preview: Control, index: int) -> void:
	var pixel := Vector2i((preview.viewport.canvas_transform * MARKERS[index]).round())
	check(Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel), "大地图角落像素在渲染区域内")
	if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
		var actual := image.get_pixelv(pixel)
		check(absf(actual.r - COLORS[index].r) + absf(actual.g - COLORS[index].g) + absf(actual.b - COLORS[index].b) < 0.1, "实际渲染出旧画幅以外的角落：%d，颜色 %s" % [index, actual])

func _run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 1000)
	var preview = PREVIEW.new()
	root.add_child(preview)
	preview.position = Vector2(20, 20)
	preview.size = Vector2(1050, 640)
	await process_frame
	preview.load_terrain(load("res://scenes/levels/battles/battle_005.tscn"))
	preview.fit()
	check(preview.map_bounds.position.x < 0 and preview.map_bounds.end.x > 1920 and preview.map_bounds.end.y > 1080, "正式大地图范围包含负坐标和旧画幅以外的地形")
	check(not preview.polygons.is_empty(), "大地图仍显示敌方导航建议区域")
	_check_fit(preview)
	preview.load_terrain(_large_map())
	preview.fit()
	check(preview.map_bounds.is_equal_approx(Rect2(-3075, -1250, 9600, 4080)), "累计变换后的完整地形边界，隐藏图层不扩大范围")
	_check_fit(preview)
	var unit := Node2D.new()
	unit.position = preview.team_transform.affine_inverse() * MARKERS[1]
	preview.units.append(unit)
	check(preview.local_point(preview.screen(unit.position)).distance_to(unit.position) < 0.01, "大地图负坐标和 TeamB 变换可逆")
	var anchor := Vector2(300, 220)
	var before: Vector2 = preview.local_point(anchor)
	preview.zoom_at(1.6, anchor)
	check(preview.local_point(anchor).distance_to(before) < 0.01, "滚轮围绕鼠标缩放")
	preview.pan += Vector2(125, -75)
	preview.update_view()
	check((preview.viewport.canvas_transform * MARKERS[1]).distance_to(preview.screen(unit.position)) < 0.01, "缩放平移后地形与怪物标记一致")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = preview.screen(unit.position)
	preview._gui_input(press)
	var target: Vector2 = unit.position + Vector2(-200, 80)
	var motion := InputEventMouseMotion.new()
	motion.position = preview.screen(target)
	preview._gui_input(motion)
	press.pressed = false
	press.position = motion.position
	preview._gui_input(press)
	check(unit.position.distance_to(target.round()) < 0.01, "缩放平移后的拖动仍保存正确刷怪坐标")
	preview.units.clear()
	unit.free()
	preview.fit()
	preview.size = Vector2(700, 800)
	preview.update_view()
	_check_fit(preview)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		preview.size = Vector2(1050, 640)
		preview.fit()
		var image := await _capture(preview)
		for i in MARKERS.size():
			_check_marker(image, preview, i)
		image.save_png("res://.maintenance/wave-preview-large-map.png")
		preview.zoom_at(4.0, preview.size / 2.0)
		preview.pan += preview.size / 2.0 - (preview.viewport.canvas_transform * MARKERS[1])
		image = await _capture(preview)
		_check_marker(image, preview, 1)
		image.save_png("res://.maintenance/wave-preview-large-map-zoom.png")
	preview.load_terrain(null)
	preview.fit()
	check(preview.map_bounds == PREVIEW.DEFAULT_BOUNDS and preview.polygons.is_empty(), "空地形恢复默认范围")
	preview.load_terrain(load("res://scenes/levels/battles/battle_001.tscn"))
	preview.fit()
	check(preview.map_bounds.size.x < 9600, "切换关卡重新计算范围")
	preview.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var editor = load("res://addons/wave_editor/editor.gd").new()
		editor.initial_path = "res://data/levels/level_107_1.tres"
		root.add_child(editor)
		editor.size = Vector2(1600, 1000)
		editor.doc.set_field("battle_scene", load("res://scenes/levels/battles/battle_005.tscn"))
		await _capture(editor.preview)
		# 等待文字换行的临时最小尺寸稳定后，模拟宿主容器重新分配主屏幕大小。
		editor.size = Vector2(root.size)
		await _capture(editor.preview)
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(editor.preview.get_global_rect()), "编辑器预览全部位于宿主窗口内")
		_check_fit(editor.preview)
		print("WAVE_PREVIEW_LAYOUT: window=", root.size, " editor=", editor.size, " minimum=", editor.get_combined_minimum_size(), " preview=", editor.preview.get_global_rect())
		root.get_texture().get_image().save_png("res://.maintenance/wave-preview-editor.png")
		editor.free()
	print("WAVE_PREVIEW_TEST: %d checks; %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)
