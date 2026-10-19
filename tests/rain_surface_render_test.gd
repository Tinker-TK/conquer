# 用真实 GPU 图像验证固定水洼、活动内边、局部折射与图块显示遮罩。
# 命令：godot --path . res://tests/rain_surface_render_test.tscn （需要图形模式）。
extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("RAIN_EDGE_CHECK: " + label)

func _capture(weather: RainWeather, time: float) -> Image:
	weather._elapsed = time
	weather._sky_scroll_offset = weather._sky_velocity() * time
	for pass_data in weather._floor_passes.values():
		pass_data.material.set_shader_parameter("clock_time", time)
		pass_data.material.set_shader_parameter("sky_scroll_offset", weather._sky_scroll_offset)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RAIN_SURFACE_RENDER_TEST: requires a graphical renderer")
		get_tree().quit(0)
		return
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.transparent_bg = true
	root.size = Vector2i(640, 360)
	var cloud_fixture := Node2D.new()
	cloud_fixture.name = "CloudFixture"
	cloud_fixture.position = Vector2(-2000, -2000)
	add_child(cloud_fixture)
	for path in ["res://assets/tilemap/Clouds/Clouds_01.png", "res://assets/tilemap/Clouds/Clouds_06.png"]:
		var source := Sprite2D.new()
		source.name = "Clouds%d" % cloud_fixture.get_child_count()
		source.texture = load(path)
		cloud_fixture.add_child(source)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(16, 16), Vector2(624, 16), Vector2(624, 344), Vector2(16, 344)])
	ground.color = Color(0.5, 0.5, 0.5)
	ground.z_index = -20
	add_child(ground)
	var weather := RainWeather.new()
	weather.cloud_source_path = NodePath("../CloudFixture")
	weather.use_terrain_mask = false
	weather.ground_rect = Rect2(16, 16, 608, 328)
	var settings := RainWeatherSettings.new()
	settings.intensity = 0.0
	settings.splash_rate = 0.0
	settings.reflections_enabled = false
	settings.wetness = 1.0
	settings.depth_opacity = 0.0
	settings.sky_strength = 1.0
	settings.sky_cloud_strength = 0.0
	settings.sky_follow_wind = false
	settings.sky_scroll_speed = Vector2.ZERO
	settings.water_tint = Color.BLACK
	settings.distortion = 0.0
	settings.puddle_coverage = 0.55
	settings.edge_softness = 0.008
	settings.edge_color = Color.WHITE
	weather.configure(settings)
	add_child(weather)
	weather.set_process(false)
	_check(weather._sky_cloud_image != null, "GPU cloud test must use actual Clouds sprite images")
	weather._sky_cloud_image.save_png("res://.maintenance/rain-scene-cloud-atlas.png")
	var visible_cloud_pixels := 0
	var dark_cloud_pixels := 0
	for y in range(0, weather._sky_cloud_image.get_height(), 2):
		for x in range(0, weather._sky_cloud_image.get_width(), 2):
			var color := weather._sky_cloud_image.get_pixel(x, y)
			if color.a > 0.0:
				visible_cloud_pixels += 1
				dark_cloud_pixels += int(maxf(color.r, maxf(color.g, color.b)) < 0.4)
	_check(visible_cloud_pixels > 1000 and dark_cloud_pixels == 0, "the rendered cloud atlas must contain cloud bodies without the original dark shadow strips")
	var zero := await _capture(weather, 0.0)
	zero.save_png("res://.maintenance/rain-edge-mask-00.png")
	var later := await _capture(weather, 3.0)
	later.save_png("res://.maintenance/rain-edge-mask-03.png")
	var moved := 0
	var stable_core := 0
	var core_pixels := 0
	var wrong_wet := 0
	var sampled_points := 0
	for y in range(20, 341, 2):
		for x in range(20, 621, 2):
			var a := zero.get_pixel(x, y).r < 0.2
			var b := later.get_pixel(x, y).r < 0.2
			if a != b:
				moved += 1
			if a and b:
				stable_core += 1
			if a:
				core_pixels += 1
			# 明显的深色水面必须被 CPU 脚步采样识别为积水。
			if b:
				sampled_points += 1
				if not weather._is_wet(Vector2(x, y)):
					wrong_wet += 1
	_check(moved > 80, "moving noise must visibly change the inner shoreline highlights")
	_check(stable_core > core_pixels * 0.8, "large puddles must remain anchored")
	_check(wrong_wet < sampled_points * 0.01, "CPU wet points must agree with visible water")
	weather._water_material.set_shader_parameter("edge_width", 0.0)
	var no_rim := await _capture(weather, 0.0)
	var bright_rim := 0
	for y in range(20, 341, 2):
		for x in range(20, 621, 2):
			if zero.get_pixel(x, y).r > no_rim.get_pixel(x, y).r + 0.12:
				bright_rim += 1
	_check(bright_rim > 80, "the shoreline layer must create a visible thin rim")
	weather._water_material.set_shader_parameter("edge_width", settings.edge_width)
	# 从透明背景上的 alpha 检验轮廓，排除天空颜色随时间改变造成的亮度差。
	ground.hide()
	weather._back_buffer.hide()
	var frozen_a := await _capture(weather, 0.0)
	var frozen_b := await _capture(weather, 3.0)
	var frozen_moved := 0
	var dry_pixels := 0
	var wet_pixels := 0
	for y in range(20, 341, 2):
		for x in range(20, 621, 2):
			if frozen_a.get_pixel(x, y).a != frozen_b.get_pixel(x, y).a:
				frozen_moved += 1
			if frozen_a.get_pixel(x, y).a < 0.1:
				dry_pixels += 1
			elif frozen_a.get_pixel(x, y).a > 0.9:
				wet_pixels += 1
	_check(dry_pixels > 100 and wet_pixels > 100, "alpha verification must actually contain both water and transparent ground")
	_check(frozen_moved == 0, "water coverage must be exactly fixed even with moving shoreline noise")
	weather._water_material.set_shader_parameter("edge_width", 0.0)
	var body_a := await _capture(weather, 0.0)
	var body_b := await _capture(weather, 3.0)
	_check(body_a.get_data() == body_b.get_data(), "without shoreline or splash events the whole water image must stay still")
	weather._water_material.set_shader_parameter("water_tint", Color(0.3, 0.4, 0.5))
	weather.settings.sky_scroll_speed = Vector2(4, -1)
	var sky_a := await _capture(weather, 0.0)
	var sky_b := await _capture(weather, 12.0)
	var sky_changed := 0
	var sky_alpha_changed := 0
	for y in range(20, 341, 2):
		for x in range(20, 621, 2):
			var a := sky_a.get_pixel(x, y)
			var b := sky_b.get_pixel(x, y)
			sky_alpha_changed += int(a.a != b.a)
			if a.a > 0.5 and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.005:
				sky_changed += 1
	_check(sky_changed > 200 and sky_alpha_changed == 0, "clouds must visibly drift without changing puddle coverage or depth opacity")
	print("RAIN_SKY_METRICS: changed=", sky_changed, "; alpha_changed=", sky_alpha_changed)
	# 用实际 GPU 图像匹配位移，而不只检查脚本传入的速度值。
	weather.settings.sky_follow_wind = true
	weather._water_material.set_shader_parameter("sky_cloud_strength", 0.2)
	weather.settings.sky_wind_speed_scale = 0.02
	weather.settings.wind = 600.0
	weather.settings.fall_speed = 800.0
	var wind_a := await _capture(weather, 0.0)
	var wind_b := await _capture(weather, 10.0)
	var along := _cloud_shift_error(wind_a, wind_b, Vector2i(120, 0))
	var opposite := _cloud_shift_error(wind_a, wind_b, Vector2i(-120, 0))
	_check(along.samples > 1000 and along.error < 0.001 and opposite.error > along.error + 0.0001, "rendered water clouds must move horizontally right without vertical drift")
	weather.settings.wind = -600.0
	var reverse_b := await _capture(weather, 10.0)
	var reverse := _cloud_shift_error(wind_a, reverse_b, Vector2i(-120, 0))
	_check(reverse.samples > 1000 and reverse.error < 0.001, "negative wind must reverse the rendered cloud's horizontal drift")
	weather.settings.wind = 0.0
	var still_a := await _capture(weather, 0.0)
	var still_b := await _capture(weather, 10.0)
	_check(still_a.get_data() == still_b.get_data(), "water clouds must stop when the wind is zero")
	_check(wind_a.get_data().size() == wind_b.get_data().size(), "cloud flow must preserve the render size")
	print("RAIN_WIND_CLOUD_METRICS: along=", along, "; opposite=", opposite, "; reverse=", reverse)
	weather._water_material.set_shader_parameter("sky_cloud_strength", 0.0)
	var no_clouds := await _capture(weather, 0.0)
	weather._water_material.set_shader_parameter("sky_cloud_strength", 0.65)
	var solid_clouds := await _capture(weather, 0.0)
	var faint_effect := 0.0
	var solid_effect := 0.0
	var opacity_samples := 0
	var alpha_changes := 0
	for y in range(20, 341, 2):
		for x in range(20, 621, 2):
			var a := no_clouds.get_pixel(x, y)
			var b := wind_a.get_pixel(x, y)
			var c := solid_clouds.get_pixel(x, y)
			alpha_changes += int(a.a != c.a)
			if a.a > 0.99:
				faint_effect += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				solid_effect += absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b)
				opacity_samples += 1
	_check(opacity_samples > 1000 and solid_effect > faint_effect * 1.6, "0.65 cloud opacity must visibly strengthen the actual sprite silhouettes compared with 0.20")
	_check(alpha_changes == 0, "stronger sprite clouds must not change puddle coverage or depth")
	print("RAIN_SCENE_CLOUD_OPACITY: faint=", faint_effect, "; solid=", solid_effect, "; alpha_changes=", alpha_changes)
	weather.settings.sky_follow_wind = false
	weather.settings.sky_scroll_speed = Vector2.ZERO
	# 高频地面纹理能检验折射确实只发生在水波环附近。
	var pattern := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for x in range(0, 640, 4):
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		pattern.fill_rect(Rect2i(x, 0, 4, 360), Color(0.8 if (x / 4) % 2 == 0 else 0.2, 0.4, 0.4))
	var stripes := Sprite2D.new()
	stripes.texture = ImageTexture.create_from_image(pattern)
	stripes.centered = false
	stripes.z_index = -20
	add_child(stripes)
	weather._back_buffer.show()
	weather._water_material.set_shader_parameter("sky_strength", 0.0)
	weather._water_material.set_shader_parameter("distortion", 4.0)
	weather._water_material.set_shader_parameter("coverage", 1.0)
	var no_wave := await _capture(weather, 0.0)
	var center := Vector2(300, 180)
	weather._events.append({"point": center, "age": 0.3, "strength": 1.25, "wet": true})
	weather._ripple_canvas.queue_redraw()
	var with_wave := await _capture(weather, 0.0)
	var local_changes := 0
	var distant_changes := 0
	for y in range(20, 341):
		for x in range(20, 621):
			if with_wave.get_pixel(x, y) != no_wave.get_pixel(x, y):
				if Vector2(x, y).distance_to(center) < 40.0:
					local_changes += 1
				else:
					distant_changes += 1
	_check(local_changes > 20 and distant_changes == 0, "ripples must change nearby pixels without animating the whole puddle")
	var ripple_image := weather._ripple_view.get_texture().get_image()
	var red_pixels := 0
	var green_pixels := 0
	for y in ripple_image.get_height():
		for x in ripple_image.get_width():
			var color := ripple_image.get_pixel(x, y)
			red_pixels += int(color.r > 0.02)
			green_pixels += int(color.g > 0.02)
	_check(red_pixels > 10 and green_pixels > red_pixels, "the green disturbance field must be wider than the red visible ring")
	print("RAIN_RIPPLE_METRICS: local_changes=", local_changes, "; distant_changes=", distant_changes, "; red=", red_pixels, "; green=", green_pixels)
	print("RAIN_EDGE_METRICS: moved=", moved, "; stable_core=", stable_core, "; rim=", bright_rim, "; wet_errors=", wrong_wet, "; frozen_moved=", frozen_moved)
	weather.queue_free()
	ground.queue_free()
	stripes.queue_free()
	cloud_fixture.queue_free()
	await get_tree().process_frame
	await _check_tile_render_mask()
	root.get_node("RunManager").start_new_run()
	var battle := load("res://scenes/levels/battles/battle_001.tscn").instantiate() as Node2D
	var config := BattleLevelConfig.new()
	config.weather_settings = load("res://data/weather/rain_storm.tres")
	battle.configure_level(config)
	root.add_child(battle)
	await get_tree().process_frame
	weather = battle.get_node("RainWeather") as RainWeather
	weather.set_process(false)
	for child in battle.get_children():
		if child is CanvasLayer:
			child.visible = false
	for particles in weather._rain:
		particles.hide()
	weather._splash_canvas.hide()
	var best_point := Vector2(640, 440)
	var best_distance := INF
	var threshold := lerpf(0.72, 0.28, weather.settings.puddle_coverage)
	for y in range(180, 701, 12):
		for x in range(450, 1301, 12):
			var point := Vector2(x, y)
			if not weather.is_ground_point(point):
				continue
			var field := weather._sample_noise_repeat(weather._noise_image, point)
			var distance := absf(field - threshold)
			if distance < best_distance:
				best_distance = distance
				best_point = point
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.position = best_point
	camera.zoom = Vector2.ONE * 1.5
	camera.force_update_scroll()
	var soldier := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamA").add_child(soldier)
	var wet_point := best_point
	var best_field := -INF
	for y in range(-60, 61, 8):
		for x in range(-120, 121, 8):
			var point := best_point + Vector2(x, y)
			if not weather.is_ground_point(point):
				continue
			var field := weather._sample_noise_repeat(weather._noise_image, point)
			if field > best_field:
				best_field = field
				wet_point = point
	soldier.global_position = wet_point - Vector2(0, weather.settings.foot_offset)
	soldier.set_physics_process(false)
	weather._scan_reflectors()
	weather._sync_reflectors()
	get_tree().paused = true
	for frame in 16:
		weather._events.clear()
		weather._events.append({"point": wet_point + Vector2(16, 4), "age": fmod(float(frame) * 0.25, weather.settings.ripple_lifetime), "strength": 1.25, "wet": true})
		weather._ripple_canvas.queue_redraw()
		var image := await _capture(weather, float(frame) * 0.25)
		image.save_png("res://.maintenance/rain-edge-game-%02d.png" % frame)
	weather.configure(load("res://data/weather/rain_reference.tres"))
	weather._sync_reflectors()
	for particles in weather._rain:
		particles.hide()
	var reference_preview := await _capture(weather, 0.0)
	reference_preview.save_png("res://.maintenance/rain-reference-preset-preview.png")
	camera.position = Vector2(960, 480)
	camera.zoom = Vector2.ONE * 0.4
	camera.force_update_scroll()
	for frame in 24:
		var cloud_frame := await _capture(weather, float(frame) * 0.2)
		cloud_frame.save_png("res://.maintenance/rain-wind-cloud-%02d.png" % frame)
		if frame == 0:
			cloud_frame.save_png("res://.maintenance/rain-scene-cloud-game.png")
	print("RAIN_WIND_CLOUD_PREVIEW: world_velocity=", weather._sky_velocity())
	print("RAIN_SURFACE_RENDER_TEST: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _cloud_shift_error(before: Image, after: Image, shift: Vector2i) -> Dictionary:
	var error := 0.0
	var samples := 0
	for y in range(20, before.get_height() - 20, 2):
		for x in range(20, before.get_width() - 20, 2):
			var target := Vector2i(x, y) + shift
			if not Rect2i(Vector2i.ZERO, after.get_size()).has_point(target):
				continue
			var a := before.get_pixel(x, y)
			var b := after.get_pixelv(target)
			# 只匹配两帧都为深水的像素，积水裁切不参与云纹平移。
			if a.a < 0.999 or b.a < 0.999:
				continue
			error += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 1
	return {"samples": samples, "error": error / maxf(samples, 1)}


# 直接对比引擎画出的 TileMapLayer alpha，不以另一套坐标公式作为测试答案。
func _check_tile_render_mask() -> void:
	var atlas_image := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.TRANSPARENT)
	atlas_image.fill_rect(Rect2i(0, 0, 12, 10), Color.WHITE)
	atlas_image.fill_rect(Rect2i(0, 10, 6, 22), Color.WHITE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(atlas_image)
	atlas.texture_region_size = Vector2i(16, 32)
	atlas.create_tile(Vector2i.ZERO)
	var alternative := atlas.create_alternative_tile(Vector2i.ZERO, 1)
	var tile_data := atlas.get_tile_data(Vector2i.ZERO, alternative)
	tile_data.texture_origin = Vector2i(5, -3)
	tile_data.transpose = true
	tile_data.flip_h = true
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(16, 16)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "rain_ground")
	tile_set.set_custom_data_layer_type(0, TYPE_BOOL)
	tile_set.add_source(atlas, 0)
	tile_data.set_custom_data("rain_ground", true)
	var layer := TileMapLayer.new()
	layer.name = "GroundTiles"
	layer.tile_set = tile_set
	layer.position = Vector2(80, 80)
	layer.rotation = PI / 2.0
	layer.z_index = -20
	add_child(layer)
	for combination in 8:
		var flags := (TileSetAtlasSource.TRANSFORM_FLIP_H if combination & 1 else 0) | (TileSetAtlasSource.TRANSFORM_FLIP_V if combination & 2 else 0) | (TileSetAtlasSource.TRANSFORM_TRANSPOSE if combination & 4 else 0)
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		layer.set_cell(Vector2i((combination / 2) * 4, -(combination % 2) * 4), 0, Vector2i.ZERO, alternative | flags)
	var weather := RainWeather.new()
	weather.terrain_root_path = NodePath("../GroundTiles")
	weather.settings = RainWeatherSettings.new()
	weather.settings.intensity = 0.0
	weather.settings.splash_rate = 0.0
	add_child(weather)
	weather.set_enabled(false)
	var rendered := await _capture(weather, 0.0)
	var mismatches := 0
	var solid_pixels := 0
	for y in range(40, 321, 2):
		for x in range(40, 221, 2):
			var point := Vector2(x + 1, y + 1)
			var visible := rendered.get_pixel(x + 1, y + 1).a > 0.2
			solid_pixels += int(visible)
			if visible != weather.is_ground_point(point):
				mismatches += 1
	_check(solid_pixels > 100 and mismatches == 0, "ground mask must match rendered tile alpha through origin offsets, overhangs, flips, transpose and layer rotation")
	print("RAIN_TILE_MASK_METRICS: solid=", solid_pixels, "; mismatches=", mismatches)
	weather.queue_free()
	layer.queue_free()
	await get_tree().process_frame
