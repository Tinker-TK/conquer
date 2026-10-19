# 真实关卡验证显示遮罩独立于导航、固定干湿、动画倒影、暂停与生命周期。
extends Node

var failures: Array[String] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("RAIN_WEATHER_TEST: " + label)


func _run() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	root.get_node("RunManager").start_new_run()
	var preset := load("res://data/weather/rain_default.tres") as RainWeatherSettings
	var original_intensity := preset.intensity
	var original_enabled := preset.enabled
	var detached := load("res://scenes/effects/rain_weather.tscn").instantiate() as RainWeather
	detached.set_enabled(false)
	detached.set_rain_intensity(0.2)
	_check(preset.enabled == original_enabled and is_equal_approx(preset.intensity, original_intensity), "pre-tree weather APIs must not mutate the shared preset")
	detached.free()
	var battle := load("res://scenes/levels/battles/battle_001.tscn").instantiate() as Node2D
	var config := BattleLevelConfig.new()
	config.weather_settings = load("res://data/weather/rain_default.tres")
	battle.configure_level(config)
	root.add_child(battle)
	await get_tree().process_frame
	var weather := battle.get_node("RainWeather") as RainWeather
	var background_cloud := battle.get_node("Level/decrition/Clouds20") as Sprite2D
	var cloud_transform := background_cloud.transform
	var cloud_texture := background_cloud.texture
	var cloud_color := background_cloud.modulate
	_check(not weather._reflectors.has(background_cloud.get_instance_id()), "background cloud sprites must not enter ground-object reflections")
	_check(weather._sky_cloud_source_ids.has(background_cloud.get_instance_id()), "the original Clouds sprite must be recognized as a read-only cloud source")
	var tree_sprite := battle.get_node("Level/NavigationRegion2D/Collision/Tree/AnimatedSprite2D")
	_check(weather._reflectors.has(tree_sprite.get_instance_id()), "excluding background clouds must preserve tree reflections")
	_check(weather._sky_cloud_image != null and weather._sky_cloud_choices.size() == weather.settings.sky_cloud_count, "water clouds must be randomly assembled from actual scene sprites")
	for cloud_path in weather._sky_cloud_choices:
		_check(cloud_path.begins_with("res://assets/tilemap/Clouds/"), "water-cloud shapes must come from the scene's Clouds textures")
	var original_cloud_atlas := weather._sky_cloud_image.get_data()
	_check_cloud_mirror(weather, background_cloud)
	_check(weather.settings != config.weather_settings, "runtime settings must be isolated")
	_check(weather._reflection_view.world_2d != root.world_2d, "reflection viewport must isolate gameplay canvas")
	_check(weather._reflection_view.gui_disable_input, "reflection viewport must not consume UI input")
	_check(not weather._ground_tiles.is_empty(), "visual mask must use ground terrain textures")
	_check(weather.is_ground_point(Vector2(400, 440)), "actual land must receive splashes")
	_check(weather.is_ground_point(Vector2(960, 250)), "visible grass bordering a hole must survive the navigation agent margin")
	_check(not weather.is_ground_point(Vector2(960, 320)), "transparent terrain inside stale navigation must remain dry")
	_check(not weather.is_ground_point(Vector2(-100, -100)), "off-map must remain dry")
	_check(not weather.is_ground_point(Vector2(400, 960)), "opaque cliff tiles must remain dry")
	_check(weather.is_ground_point(Vector2(770, 440)), "visible connecting grass must not be cut by navigation margins")
	var region := battle.get_node("Level/NavigationRegion2D") as NavigationRegion2D
	var navigation := region.navigation_polygon
	var mask_before := weather._ground_mask_image.get_data()
	var bounds_before := weather._bounds
	region.navigation_polygon = null
	weather._build_ground()
	_check(weather._bounds == bounds_before and weather._ground_mask_image.get_data() == mask_before, "rebaking or removing navigation must not change visible puddle ground")
	region.navigation_polygon = navigation
	var scenery_reflections := weather._reflectors.size()
	for y in range(200, 800, 24):
		for x in range(200, 1720, 24):
			var point := Vector2(x, y)
			weather._elapsed = 0.0
			var wet := weather._is_wet(point)
			weather._elapsed = 3.0
			_check(weather._is_wet(point) == wet, "animated shoreline must never change footstep wet/dry classification")
	weather._elapsed = 0.0
	var soldier := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	soldier.position = Vector2(430, 430)
	battle.get_node("Entities/TeamA").add_child(soldier)
	soldier.global_position = Vector2(530, 460)
	soldier.set_physics_process(false)
	var orc := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	orc.position = Vector2(-250, 50)
	battle.get_node("Entities/TeamB").add_child(orc)
	orc.global_position = Vector2(1410, 550)
	orc.set_physics_process(false)
	await get_tree().process_frame
	weather._scan_reflectors()
	weather._sync_reflectors()
	var source := soldier.animated_sprite_2d
	var record: Dictionary = weather._reflectors[source.get_instance_id()]
	var reflected: Sprite2D = record.copy
	_check(reflected.texture == source.sprite_frames.get_frame_texture(source.animation, source.frame), "reflection must show current animation frame")
	_check(reflected.transform.determinant() * source.global_transform.determinant() < 0.0, "reflection must flip around feet")
	_check(weather._reflectors.size() == scenery_reflections + 2, "only the two added units may add reflections alongside existing scenery")
	source.flip_h = not source.flip_h
	weather._sync_reflectors()
	_check(reflected.flip_h == source.flip_h, "reflection must follow facing direction")
	source.hide()
	weather._sync_reflectors()
	_check(not reflected.visible, "hidden units must have hidden reflections")
	source.show()
	weather._events.clear()
	# 实际移动积水中的单位，验证脚步事件经同步路径产生，而不是直接调用绘制接口。
	weather.settings.puddle_coverage = 1.0
	weather.apply_settings()
	_check(weather._sky_cloud_image.get_data() == original_cloud_atlas, "reapplying the same seed must preserve the chosen cloud forms and layout")
	var original_seed := weather.settings.random_seed
	weather.settings.random_seed += 1
	weather.apply_settings()
	_check(weather._sky_cloud_image.get_data() != original_cloud_atlas, "a different seed must produce another random cloud layout")
	weather.settings.random_seed = original_seed
	weather.apply_settings()
	_check(weather._sky_cloud_image.get_data() == original_cloud_atlas, "restoring the seed must reproduce the original cloud layout")
	for x in range(400, 481, 4):
		var point := Vector2(x, 440)
		if weather.is_ground_point(point) and weather._is_wet(point):
			soldier.global_position = point - Vector2(0, weather.settings.foot_offset)
			weather._sync_reflectors()
			break
	_check(not weather._events.is_empty(), "moving a unit through a puddle must create a footstep ripple")
	weather._events.clear()
	for i in weather.settings.max_ripples + 12:
		weather._add_splash(Vector2(400, 440), 1.0)
	_check(weather._events.size() == weather.settings.max_ripples, "water event count must be bounded")
	weather._add_splash(Vector2(-100, -100), 1.0)
	_check(weather._events.size() == weather.settings.max_ripples, "invalid ground must never emit")
	weather._events.clear()
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.5
	camera.position = Vector2(850, 500)
	camera.force_update_scroll()
	weather._update_rain_emitters()
	_check_sky_wind(weather)
	for particles in weather._rain:
		var material := particles.process_material as ParticleProcessMaterial
		var view := weather._camera_rect()
		_check(particles.global_position.y + material.emission_box_extents.y < view.position.y, "rain must spawn above the zoomed and moved camera")
		var lowest_slow_drop := particles.global_position.y - material.emission_box_extents.y + material.direction.y * material.initial_velocity_min * particles.lifetime
		_check(lowest_slow_drop > view.end.y, "even slow rain must survive until it crosses the viewport bottom")
	var previous_elapsed := weather._elapsed
	var previous_sky_offset := weather._sky_scroll_offset
	get_tree().paused = true
	await get_tree().create_timer(0.05, true).timeout
	_check(is_equal_approx(previous_elapsed, weather._elapsed), "water clock must pause with battle")
	_check(weather._sky_scroll_offset == previous_sky_offset, "reflected clouds must pause with battle")
	get_tree().paused = false
	_check(background_cloud.transform == cloud_transform and background_cloud.texture == cloud_texture and background_cloud.modulate == cloud_color and background_cloud.visible, "water-cloud flow must not alter original scene clouds")
	weather.set_rain_intensity(0.2)
	_check(is_equal_approx(config.weather_settings.intensity, original_intensity), "changing rain must not mutate shared preset")
	weather.set_enabled(false)
	_check(not weather.is_processing() and not weather._rain[0].emitting, "disabled weather must stop updates and emission")
	_check(weather._reflection_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "disabled weather must stop offscreen render")
	_check(weather._tint.color == Color.WHITE, "clear weather must restore world colors")
	weather.configure(load("res://data/weather/rain_storm.tres"))
	_check(weather.settings.enabled and weather.is_processing(), "runtime preset changes must enable rain")
	weather.configure(load("res://data/weather/rain_default.tres"))
	camera.zoom = Vector2.ONE
	camera.position = Vector2(960, 540)
	camera.force_update_scroll()
	if "--capture" in OS.get_cmdline_user_args():
		# 正式第 1 关的实际天气资源，用真实参数验收倒影。
		weather.configure(load("res://data/levels/level_001.tres").weather_settings)
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/rain-weather-preview.png")
		weather._reflection_view.get_texture().get_image().save_png("res://.maintenance/rain-reflection-pass.png")
		weather._water_material.get_shader_parameter("ground_mask").get_image().save_png("res://.maintenance/rain-ground-mask.png")
		weather._noise_image.save_png("res://.maintenance/rain-noise.png")
		await _check_rendered_water(weather, soldier, orc)
		weather.set_enabled(false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/rain-weather-clear.png")
		weather.set_enabled(true)
		weather.settings.puddle_coverage = 0.52
		weather.apply_settings()
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/rain-weather-default.png")
	soldier.queue_free()
	await get_tree().process_frame
	weather._scan_reflectors()
	_check(weather._reflectors.size() == scenery_reflections + 1, "freed unit must release reflection proxy")
	var clear_battle := load("res://scenes/battle/battle_scene.tscn").instantiate() as Node2D
	var clear_config := BattleLevelConfig.new()
	clear_config.weather_settings = load("res://data/weather/weather_clear.tres")
	clear_battle.configure_level(clear_config)
	root.add_child(clear_battle)
	_check(not clear_battle.get_node("RainWeather").settings.enabled, "level override must apply before first frame")
	clear_battle.queue_free()
	var default_battle := load("res://scenes/battle/battle_scene.tscn").instantiate() as Node2D
	default_battle.configure_level(BattleLevelConfig.new())
	root.add_child(default_battle)
	_check(not default_battle.get_node("RainWeather").settings.enabled, "unconfigured base battle must default to clear weather")
	_check(not default_battle.get_node("SnowWeather").settings.enabled, "unconfigured base battle must not enable snow")
	default_battle.queue_free()
	var weak_weather: WeakRef = weakref(weather)
	battle.queue_free()
	await get_tree().process_frame
	_check(weak_weather.get_ref() == null, "weather must be released on leaving battle")
	print("RAIN_WEATHER_TEST: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_cloud_mirror(weather: RainWeather, source: Sprite2D) -> void:
	var original := source.texture.get_image()
	if original.is_compressed():
		original.decompress()
	var original_data := original.get_data()
	var reflected := weather._cloud_reflection_image(source)
	var body_pixels := 0
	var shadow_pixels := 0
	var mismatches := 0
	for y in original.get_height():
		for x in original.get_width():
			var color := original.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			var target := Vector2i(original.get_width() - 1 - x if source.flip_h else x, y if source.flip_v else original.get_height() - 1 - y)
			var actual := reflected.get_pixelv(target)
			if maxf(color.r, maxf(color.g, color.b)) < 0.4:
				shadow_pixels += 1
				mismatches += int(actual.a > 0.0)
			else:
				body_pixels += 1
				mismatches += int(not actual.is_equal_approx(color))
	_check(body_pixels > 1000 and shadow_pixels > 1000 and mismatches == 0, "water clouds must vertically mirror the real cloud body and mask its dark underside")
	var unchanged := source.texture.get_image()
	if unchanged.is_compressed():
		unchanged.decompress()
	_check(unchanged.get_data() == original_data, "mirroring and masking must preserve the original cloud texture pixels")
	print("RAIN_CLOUD_MIRROR: body=", body_pixels, "; removed_shadow=", shadow_pixels, "; mismatches=", mismatches)


func _check_sky_wind(weather: RainWeather) -> void:
	var saved: Dictionary = {}
	for key in ["wind", "fall_speed", "sky_follow_wind", "sky_wind_speed_scale", "sky_scroll_speed"]:
		saved[key] = weather.settings.get(key)
	weather.settings.sky_follow_wind = true
	weather.settings.sky_wind_speed_scale = 0.02
	weather.settings.wind = 600.0
	weather.settings.fall_speed = 800.0
	var velocity := weather._sky_velocity()
	_check(is_equal_approx(velocity.length(), 12.0), "water-cloud speed must scale with wind magnitude")
	var to_screen := get_viewport().get_stretch_transform() * get_viewport().get_canvas_transform()
	var cloud_direction := (to_screen * velocity - to_screen.origin).normalized()
	_check(cloud_direction.is_equal_approx(Vector2.RIGHT), "positive wind must move water clouds horizontally right after camera zoom")
	weather.settings.fall_speed = 3200.0
	_check(weather._sky_velocity().is_equal_approx(velocity), "rain fall speed must not affect water-cloud motion")
	weather.settings.wind = 1200.0
	_check(is_equal_approx(weather._sky_velocity().length(), 24.0), "doubling wind must double cloud-flow speed")
	weather.settings.wind = -600.0
	var reverse_velocity := weather._sky_velocity()
	var phase := weather._sky_scroll_offset
	weather._advance_sky(0.1)
	_check(weather._sky_scroll_offset.is_equal_approx(phase + reverse_velocity * 0.1), "changing wind must continue cloud motion without a phase jump")
	var reverse_screen := to_screen * reverse_velocity - to_screen.origin
	_check(reverse_screen.x < 0 and is_zero_approx(reverse_screen.y), "negative wind must move reflected clouds horizontally left without vertical drift")
	for pass_data in weather._floor_passes.values():
		_check(pass_data.material.get_shader_parameter("sky_scroll_offset") == weather._sky_scroll_offset, "all floor water passes must share the accumulated cloud phase")
	weather.settings.wind = 0.0
	_check(weather._sky_velocity() == Vector2.ZERO, "no wind must stop wind-driven water clouds")
	weather.settings.sky_follow_wind = false
	weather.settings.sky_scroll_speed = Vector2(-7, 3)
	_check(weather._sky_velocity() == Vector2(-7, 3), "custom cloud speed must remain available with wind-follow disabled")
	for key in saved:
		weather.settings.set(key, saved[key])


func _check_rendered_water(weather: RainWeather, soldier: UnitBase, orc: UnitBase) -> void:
	var wet_image := root.get_texture().get_image()
	var mask: Image = weather._water_material.get_shader_parameter("ground_mask").get_image()
	var hole_uv := (Vector2(960, 320) - weather._bounds.position) / weather._bounds.size
	_check(mask.get_pixelv(Vector2i(hole_uv * Vector2(mask.get_size()))).r < 0.1, "rendered mask must exclude transparent terrain")
	var reflection_image := weather._reflection_view.get_texture().get_image()
	var reflected_pixels := 0
	for y in range(0, reflection_image.get_height(), 2):
		for x in range(0, reflection_image.get_width(), 2):
			if reflection_image.get_pixel(x, y).a > 0.05:
				reflected_pixels += 1
	_check(reflected_pixels > 10, "GPU must render visible reflection pixels")
	weather._surface.hide()
	weather._back_buffer.hide()
	weather._splash_canvas.hide()
	for particles in weather._rain:
		particles.hide()
	for i in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var dry_image := root.get_texture().get_image()
	var changed := 0
	for y in range(300, 730, 20):
		for x in range(220, 1680, 20):
			var point := Vector2(x, y)
			if not weather.is_ground_point(point) or point.distance_to(soldier.global_position) < 100.0 or point.distance_to(orc.global_position) < 100.0:
				continue
			var pixel := Vector2i(root.get_canvas_transform() * point)
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= wet_image.get_width() or pixel.y >= wet_image.get_height():
				continue
			var difference := wet_image.get_pixelv(pixel) - dry_image.get_pixelv(pixel)
			if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.04:
				changed += 1
	_check(changed > 60, "water shader must visibly change actual ground pixels")
	print("RAIN_GPU_RENDER: visible_reflection_pixels=", reflected_pixels, "; water_samples=", changed)
	weather._surface.show()
	weather._back_buffer.show()
	weather._splash_canvas.show()
	for particles in weather._rain:
		particles.show()
