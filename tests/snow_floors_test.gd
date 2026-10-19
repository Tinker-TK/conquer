# 四层真实瓦片：积雪覆盖、单位/悬崖遮挡、堆积/融化、雨雪切换和正式关卡。
# headless 验证逻辑，图形模式额外检查 GPU 像素并导出前后对比。
extends Node2D

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
var failures: Array[String] = []
var checks := 0
var snow: SnowWeather
var regions: Array[Rect2] = []


func _ready() -> void:
	_run.call_deferred()


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error("SNOW_FLOORS_TEST: " + label)


func _capture() -> Image:
	for frame in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()


func _check_coverage(label: String) -> void:
	for pass_data in snow._floor_passes.values():
		_check(is_equal_approx(float(pass_data.material.get_shader_parameter("coverage")), snow._coverage), label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.maintenance/snow-floors")
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("RunManager").start_new_run()
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	var terrain := FLOORS.new()
	terrain.name = "NavigationRegion2D"
	terrain.floor_z_stride = 80
	terrain.floor_agent_radius = 2.0
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.15, 0.35, 0.1))
	image.fill_rect(Rect2i(32, 0, 32, 32), Color(0.2, 0.4, 0.8))
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(32, 32)
	atlas.create_tile(Vector2i.ZERO)
	atlas.create_tile(Vector2i(1, 0))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(32, 32)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "snow_ground")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	tiles.add_source(atlas, 0)
	atlas.get_tile_data(Vector2i.ZERO, 0).set_custom_data("snow_ground", true)
	for floor_id in range(1, 5):
		var layer := TileMapLayer.new()
		layer.name = "Layer%02d" % floor_id
		layer.tile_set = tiles
		layer.position = Vector2(16 + (floor_id - 1) * 224, 16)
		regions.append(Rect2(layer.position, Vector2(192, 128)))
		for x in 6:
			for y in 4:
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		for x in range(320, 448, 32):
			for y in range(224, 352, 32):
				var cell := Vector2i((Vector2(x + 16, y + 16) - layer.position) / 32.0)
				layer.set_cell(cell, 0, Vector2i(1, 0) if floor_id == 4 else Vector2i.ZERO)
		if floor_id == 2:
			var child := TileMapLayer.new()
			child.name = "ExtraGround"
			child.tile_set = tiles
			child.position = Vector2(0, 160)
			child.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
			layer.add_child(child)
		terrain.add_child(layer)
	var stairs := TileMapLayer.new()
	stairs.name = "stair03"
	stairs.tile_set = tiles
	stairs.position = Vector2(480, 192)
	stairs.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	terrain.add_child(stairs)
	level.add_child(terrain)
	var rain := RainWeather.new()
	rain.name = "RainWeather"
	rain.settings = RainWeatherSettings.new()
	rain.settings.enabled = false
	add_child(rain)
	snow = SnowWeather.new()
	snow.name = "SnowWeather"
	var settings := SnowWeatherSettings.new()
	settings.intensity = 0.0
	settings.automatic_accumulation = false
	settings.initial_coverage = 1.0
	settings.ground_detail = 0.0
	settings.atmosphere_tint = Color.WHITE
	settings.snow_tint = Color.WHITE
	settings.snow_shadow = Color.WHITE
	settings.scenery_snow_enabled = false
	snow.configure(settings)
	add_child(snow)
	snow.set_process(false)
	_check(snow._floor_passes.size() == 4, "all four occupied floors must have snow passes")
	for floor_id in range(1, 5):
		var pass_data: Dictionary = snow._floor_passes[floor_id]
		_check(snow.is_ground_point(regions[floor_id - 1].get_center(), floor_id), "floor %d must have its own snow mask" % floor_id)
		_check(not snow.is_ground_point(regions[floor_id - 1].get_center(), floor_id % 4 + 1), "floor %d must not borrow another floor mask" % floor_id)
		_check(pass_data.surface.z_index > terrain.floor_layers[floor_id - 1].z_index and pass_data.surface.z_index < terrain.get_floor_z_index(floor_id), "floor %d snow must draw between terrain and units" % floor_id)
		var marker := Polygon2D.new()
		var center := regions[floor_id - 1].get_center()
		marker.polygon = PackedVector2Array([center + Vector2(-8, -8), center + Vector2(8, -8), center + Vector2(8, 8), center + Vector2(-8, 8)])
		marker.color = Color.RED
		marker.z_index = terrain.get_floor_z_index(floor_id)
		level.add_child(marker)
	_check(snow.is_ground_point(Vector2(256, 192), 2), "child terrain must share floor 2 snow")
	_check(snow.is_ground_point(Vector2(496, 208), 3), "stairs must share floor 3 snow")
	_check(not snow.is_ground_point(Vector2(384, 288), 4), "upper cliff must stay outside its floor mask")
	_check(snow.is_ground_point(Vector2(384, 288), 1), "bridge underside must retain its lower snow mask")
	if DisplayServer.get_name() != "headless":
		var covered := await _capture()
		covered.save_png("res://.maintenance/snow-floors/four-floors-covered.png")
		snow.set_snow_cover(0.0)
		var clear := await _capture()
		for floor_id in range(1, 5):
			var changed := 0
			var rect := regions[floor_id - 1].grow(-12)
			for y in range(int(rect.position.y), int(rect.end.y), 4):
				for x in range(int(rect.position.x), int(rect.end.x), 4):
					if covered.get_pixel(x, y).r - clear.get_pixel(x, y).r > 0.5:
						changed += 1
			_check(changed > 800, "GPU snow must visibly cover floor %d" % floor_id)
			_check(covered.get_pixelv(Vector2i(regions[floor_id - 1].get_center())).is_equal_approx(Color.RED), "floor %d unit must remain above snow" % floor_id)
		_check(covered.get_pixel(384, 288).is_equal_approx(clear.get_pixel(384, 288)), "upper cliff must hide lower snow")
		_check(covered.get_pixel(280, 280).is_equal_approx(clear.get_pixel(280, 280)), "off-ground pixels must remain unchanged")
	else:
		print("SNOW_FLOORS_GPU: skipped (headless)")
	snow.set_snow_cover(0.4)
	_check_coverage("manual coverage must reach every floor")
	snow.settings.automatic_accumulation = true
	snow.set_snow_intensity(1.0)
	snow._process(1.0)
	_check(snow._coverage > 0.4, "snowfall must accumulate")
	_check_coverage("accumulation must reach every floor")
	snow.set_snow_intensity(0.0)
	var before_melt := snow._coverage
	snow._process(1.0)
	_check(snow._coverage < before_melt, "stopped snowfall must melt")
	_check_coverage("melting must reach every floor")
	snow.settings.ground_snow_enabled = false
	snow.apply_settings()
	for pass_data in snow._floor_passes.values():
		_check(not pass_data.surface.visible and not pass_data.back_buffer.visible, "ground snow switch must hide all floor passes")
	snow.settings.ground_snow_enabled = true
	snow.apply_settings()
	rain.set_enabled(true)
	for pass_data in snow._floor_passes.values():
		_check(not pass_data.surface.visible, "switching to rain must hide snow on every floor")
	snow.configure(load("res://data/weather/snow_blizzard.tres"))
	_check(not rain.settings.enabled, "switching to snow must suppress rain")
	for pass_data in snow._floor_passes.values():
		_check(pass_data.surface.visible and pass_data.material.get_shader_parameter("snow_tint") == snow.settings.snow_tint, "snow preset must update every floor")
	# 去掉某层后刷新不应留下悬空积雪；重新启用也不应重复创建绘制节点。
	terrain.floor_layers[3].enabled = false
	snow.apply_settings()
	_check(not snow._floor_passes[4].surface.visible and not snow.is_ground_point(regions[3].get_center(), 4), "removed floor must not retain snow")
	terrain.floor_layers[3].enabled = true
	snow.apply_settings()
	_check(snow._floor_passes.size() == 4 and snow._floor_passes[4].surface.visible, "restored floor must reuse its snow pass")
	var weak_runtime: WeakRef = weakref(snow._runtime)
	snow.queue_free()
	rain.queue_free()
	level.queue_free()
	await get_tree().process_frame
	_check(weak_runtime.get_ref() == null, "leaving scene must release all floor snow passes")
	await _check_stage()
	print("SNOW_FLOORS_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_stage() -> void:
	var battle := load("res://scenes/levels/battles/battle_005.tscn").instantiate() as Node2D
	var config := BattleLevelConfig.new()
	config.snow_weather_settings = load("res://data/weather/snow_default.tres")
	battle.configure_level(config)
	add_child(battle)
	await get_tree().process_frame
	var stage_snow := battle.get_node("SnowWeather") as SnowWeather
	_check(stage_snow._floor_passes.has(2), "real battle_005 must have upper floor snow")
	if DisplayServer.get_name() != "headless":
		var root := get_tree().root
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i(1920, 1080)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		var camera := battle.get_node("Camera2D") as Camera2D
		camera.position = Vector2(960, 540)
		camera.force_update_scroll()
		stage_snow.set_process(false)
		for particles in stage_snow._flakes:
			particles.hide()
		for child in battle.get_children():
			if child is CanvasLayer or child is Control:
				child.hide()
		var covered := await _capture()
		covered.save_png("res://.maintenance/snow-floors/battle-005-fixed.png")
		var upper: Dictionary = stage_snow._floor_passes[2]
		upper.surface.hide()
		upper.back_buffer.hide()
		var clear := await _capture()
		clear.save_png("res://.maintenance/snow-floors/battle-005-before.png")
		var changed := 0
		for y in range(0, covered.get_height(), 4):
			for x in range(0, covered.get_width(), 4):
				if covered.get_pixel(x, y).r - clear.get_pixel(x, y).r > 0.1:
					changed += 1
		_check(changed > 500, "real upper terrain must visibly receive snow")
		print("SNOW_FLOORS_STAGE_GPU: upper_snow_samples=", changed)
	battle.queue_free()
	await get_tree().process_frame
