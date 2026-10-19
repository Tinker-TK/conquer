# 四层真实瓦片与单位：积水/倒影/水花归属，以及 GPU 地形、单位、桥下遮挡。
# 图形模式运行同一场景可验收像素；headless 只验证逻辑。
extends Node2D

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
var failures: Array[String] = []
var checks := 0
var weather: RainWeather
var terrain: NavigationRegion2D
var regions: Array[Rect2] = []


func _ready() -> void:
	_run.call_deferred()


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error("RAIN_FLOORS_TEST: " + label)


func _capture() -> Image:
	for frame in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.maintenance/rain-floors")
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("RunManager").start_new_run()
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	terrain = FLOORS.new()
	terrain.name = "NavigationRegion2D"
	terrain.floor_z_stride = 80 # 验证跟随实际楼层配置，而非写死 64。
	terrain.floor_agent_radius = 2.0
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.55, 0.65, 0.35))
	image.fill_rect(Rect2i(32, 0, 32, 32), Color(0.2, 0.4, 0.8))
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(32, 32)
	atlas.create_tile(Vector2i.ZERO)
	atlas.create_tile(Vector2i(1, 0))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(32, 32)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "rain_ground")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	tiles.add_source(atlas, 0)
	atlas.get_tile_data(Vector2i.ZERO, 0).set_custom_data("rain_ground", true)
	for floor_id in range(1, 5):
		var layer := TileMapLayer.new()
		layer.name = "Layer%02d" % floor_id
		layer.tile_set = tiles
		layer.position = Vector2(16 + (floor_id - 1) * 224, 16)
		regions.append(Rect2(layer.position, Vector2(192, 128)))
		for x in 6:
			for y in 4:
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		# 所有楼层在这个矩形内重叠；最高层立面不可被下层积水覆盖。
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
	level.add_child(terrain)
	var entities := Node2D.new()
	entities.name = "Entities"
	var team := Node2D.new()
	team.name = "TeamA"
	entities.add_child(team)
	add_child(entities)
	weather = RainWeather.new()
	weather.name = "RainWeather"
	var settings := RainWeatherSettings.new()
	settings.intensity = 0.0
	settings.splash_rate = 0.0
	settings.wetness = 1.0
	settings.depth_opacity = 0.0
	settings.sky_strength = 1.0
	settings.sky_cloud_strength = 0.0
	settings.water_tint = Color.BLACK
	settings.edge_width = 0.0
	settings.distortion = 0.0
	settings.puddle_coverage = 1.0
	settings.sky_follow_wind = false
	settings.sky_scroll_speed = Vector2.ZERO
	weather.configure(settings)
	add_child(weather)
	weather.set_process(false)
	# 固定为全湿，避免测试依赖某个随机噪声恰好落在高层。
	weather._noise_image.fill(Color.WHITE)
	weather._water_material.set_shader_parameter("noise_map", ImageTexture.create_from_image(weather._noise_image))
	weather._sync_floor_materials()
	_check(weather._floor_passes.size() == 4, "all four occupied floors must have water passes")
	weather.settings.sky_follow_wind = true
	weather.settings.wind = 600.0
	weather.settings.fall_speed = 800.0
	weather._advance_sky(0.1)
	for pass_data in weather._floor_passes.values():
		_check(pass_data.material.get_shader_parameter("sky_scroll_offset") == weather._sky_scroll_offset, "wind-driven cloud phase must reach every floor water material")
	weather.settings.sky_follow_wind = false
	for floor_id in range(1, 5):
		var pass_data: Dictionary = weather._floor_passes[floor_id]
		_check(weather.is_ground_point(regions[floor_id - 1].get_center(), floor_id), "floor %d must have its own mask" % floor_id)
		_check(not weather.is_ground_point(regions[floor_id - 1].get_center(), floor_id % 4 + 1), "floor %d must not borrow another floor mask" % floor_id)
		_check(pass_data.surface.z_index > terrain.floor_layers[floor_id - 1].z_index and pass_data.surface.z_index < terrain.get_floor_z_index(floor_id), "floor %d water must draw between terrain and units" % floor_id)
		var marker := Polygon2D.new()
		var center := regions[floor_id - 1].get_center()
		marker.polygon = PackedVector2Array([center + Vector2(-8, -8), center + Vector2(8, -8), center + Vector2(8, 8), center + Vector2(-8, 8)])
		marker.color = Color.RED
		marker.z_index = terrain.get_floor_z_index(floor_id)
		level.add_child(marker)
	_check(weather.is_ground_point(Vector2(256, 192), 2), "child terrain must share floor 2 weather")
	_check(not weather.is_ground_point(Vector2(384, 288), 4), "upper cliff must stay outside its floor mask")
	_check(weather.is_ground_point(Vector2(384, 288), 1), "bridge underside must retain lower ground")
	weather._add_splash(Vector2(384, 288), 1.0, false, 1)
	weather._add_splash(regions[3].get_center(), 1.0)
	_check(weather._events.size() == 2 and weather._events[0].floor_id == 1 and weather._events[1].floor_id == 4, "footsteps retain their floor and random rain targets the top surface")
	weather._events.clear()
	if DisplayServer.get_name() != "headless":
		var wet := await _capture()
		wet.save_png("res://.maintenance/rain-floors/four-floors-wet.png")
		for pass_data in weather._floor_passes.values():
			pass_data.surface.hide()
			pass_data.back_buffer.hide()
		var dry := await _capture()
		for floor_id in range(1, 5):
			var changed := 0
			var rect := regions[floor_id - 1].grow(-12)
			for y in range(int(rect.position.y), int(rect.end.y), 4):
				for x in range(int(rect.position.x), int(rect.end.x), 4):
					if dry.get_pixel(x, y).g - wet.get_pixel(x, y).g > 0.3:
						changed += 1
			_check(changed > 800, "GPU puddles must visibly cover floor %d" % floor_id)
			var center := Vector2i(regions[floor_id - 1].get_center())
			_check(wet.get_pixelv(center).is_equal_approx(Color.RED), "floor %d unit must remain above puddles" % floor_id)
		_check(wet.get_pixel(384, 288).is_equal_approx(dry.get_pixel(384, 288)), "upper cliff must hide lower puddles")
		_check(wet.get_pixel(280, 280).is_equal_approx(dry.get_pixel(280, 280)), "off-ground pixels must remain unchanged")
		for pass_data in weather._floor_passes.values():
			pass_data.surface.show()
			pass_data.back_buffer.show()
	else:
		print("RAIN_FLOORS_GPU: skipped (headless)")
	var soldier := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	team.add_child(soldier)
	soldier.set_physics_process(false)
	weather._scan_reflectors()
	var record: Dictionary = weather._reflectors[soldier.animated_sprite_2d.get_instance_id()]
	for floor_id in range(1, 5):
		soldier.floor_id = floor_id
		soldier.global_position = regions[floor_id - 1].position + Vector2(64, 48)
		weather._sync_reflectors()
		_check(record.copy.get_parent() == weather._floor_passes[floor_id].reflection_view, "moving to floor %d must move reflection to that viewport" % floor_id)
		weather._events.clear()
		soldier.global_position.x += weather.settings.step_distance + 1.0
		weather._sync_reflectors()
		_check(weather._events.size() == 1 and weather._events[0].floor_id == floor_id, "floor %d movement must produce its own footstep" % floor_id)
		if DisplayServer.get_name() != "headless":
			await _capture()
			for other_floor in range(1, 5):
				var reflected: Image = weather._floor_passes[other_floor].reflection_view.get_texture().get_image()
				_check(reflected.is_invisible() == (other_floor != floor_id), "floor %d reflection must not leak into floor %d" % [floor_id, other_floor])
	weather.set_enabled(false)
	for pass_data in weather._floor_passes.values():
		_check(not pass_data.surface.visible and pass_data.reflection_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "disabled weather must stop every floor")
	weather.configure(load("res://data/weather/rain_storm.tres"))
	for pass_data in weather._floor_passes.values():
		_check(pass_data.surface.visible and is_equal_approx(float(pass_data.material.get_shader_parameter("coverage")), weather.settings.puddle_coverage), "preset changes must update every floor")
	# 河流只裁掉底层积水；相同世界位置的桥面仍可积水并产生脚步。
	var river := DynamicRiver.new()
	river.polygon = PackedVector2Array([Vector2(32, 32), Vector2(160, 32), Vector2(160, 112), Vector2(32, 112)])
	river.weather_path = NodePath("../RainWeather")
	add_child(river)
	await get_tree().process_frame
	_check(not weather.is_ground_point(Vector2(80, 64), 1), "riverbed must exclude floor 1 puddles")
	river.position = Vector2(224, 0)
	river.apply_settings()
	await get_tree().process_frame
	_check(weather.is_ground_point(Vector2(304, 64), 2), "river underneath must not remove upper floor puddles")
	_check(weather._floor_passes[1].material.get_shader_parameter("reflection_map") == weather.get_shared_water_maps().reflection, "river must keep sharing the first floor reflection map")
	river.set_enabled(false)
	await get_tree().process_frame
	_check(weather.is_ground_point(Vector2(80, 64), 1), "disabling river must restore lower ground")
	river.queue_free()
	weather.queue_free()
	entities.queue_free()
	level.queue_free()
	await get_tree().process_frame
	await _check_stage()
	print("RAIN_FLOORS_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_stage() -> void:
	var battle := load("res://scenes/levels/battles/battle_005.tscn").instantiate() as Node2D
	var config := BattleLevelConfig.new()
	config.weather_settings = load("res://data/weather/rain_reference.tres")
	battle.configure_level(config)
	add_child(battle)
	await get_tree().process_frame
	var stage_weather := battle.get_node("RainWeather") as RainWeather
	_check(stage_weather._floor_passes.has(2), "real battle_005 must have upper floor puddles")
	if DisplayServer.get_name() != "headless":
		var root := get_tree().root
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i(1920, 1080)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		var camera := battle.get_node("Camera2D") as Camera2D
		camera.position = Vector2(960, 540)
		camera.force_update_scroll()
		stage_weather.set_process(false)
		stage_weather._splash_canvas.hide()
		for particles in stage_weather._rain:
			particles.hide()
		for child in battle.get_children():
			if child is CanvasLayer or child is Control:
				child.hide()
		var wet := await _capture()
		wet.save_png("res://.maintenance/rain-floors/battle-005-fixed.png")
		var upper: Dictionary = stage_weather._floor_passes[2]
		upper.surface.hide()
		upper.back_buffer.hide()
		var dry := await _capture()
		dry.save_png("res://.maintenance/rain-floors/battle-005-before.png")
		var changed := 0
		for y in range(0, wet.get_height(), 4):
			for x in range(0, wet.get_width(), 4):
				var difference := wet.get_pixel(x, y) - dry.get_pixel(x, y)
				if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.04:
					changed += 1
		_check(changed > 500, "real upper terrain must visibly receive puddles")
		print("RAIN_FLOORS_STAGE_GPU: upper_water_samples=", changed)
	battle.queue_free()
	await get_tree().process_frame
