# GPU 验证真实雪斑、遮罩、融化、镜头坐标和像素雪花；headless 不替代渲染验收。
extends Node

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("SNOW_SURFACE_RENDER_TEST: " + label)


func _capture() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()


func _covered(image: Image) -> int:
	var count := 0
	for y in range(24, 336, 3):
		for x in range(24, 616, 3):
			if image.get_pixel(x, y).r > 0.55:
				count += 1
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SNOW_SURFACE_RENDER_TEST: requires a graphical renderer")
		get_tree().quit(0)
		return
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640, 360)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)])
	ground.color = Color(0.12, 0.3, 0.1)
	ground.z_index = -20
	add_child(ground)
	var snow := SnowWeather.new()
	snow.use_terrain_mask = false
	snow.ground_rect = Rect2(16, 16, 608, 328)
	var settings := SnowWeatherSettings.new()
	settings.intensity = 0.0
	settings.initial_coverage = 0.0
	settings.automatic_accumulation = false
	settings.atmosphere_tint = Color.WHITE
	settings.scenery_snow_enabled = false
	snow.configure(settings)
	add_child(snow)
	snow.set_process(false)
	var clear := await _capture()
	snow.set_snow_cover(0.5)
	var half := await _capture()
	snow.set_snow_cover(1.0)
	var full := await _capture()
	_check(_covered(clear) == 0, "coverage zero must show original grass")
	_check(_covered(half) > 100 and _covered(half) < _covered(full) - 100, "intermediate cover must show snow and grass patches")
	_check(_covered(full) > 19000, "full cover must visibly whiten the entire ground")
	snow.set_snow_cover(0.2)
	var melting := await _capture()
	_check(_covered(melting) < _covered(half), "melting must shrink existing snow patches")
	snow.set_snow_cover(0.5)
	snow._elapsed = 100.0
	var later := await _capture()
	_check(later.get_data() == half.get_data(), "snow patches must stay still when coverage is unchanged")
	# 将中心设为真实透明洞，并按最终 GPU 像素检查裁切。
	var mask: Image = snow._ground.image.duplicate()
	mask.fill_rect(Rect2i(284, 134, 40, 40), Color.BLACK)
	snow._material.set_shader_parameter("ground_mask", ImageTexture.create_from_image(mask))
	snow.set_snow_cover(1.0)
	var clipped := await _capture()
	_check(clipped.get_pixel(320, 170).r < 0.3 and clipped.get_pixel(250, 170).r > 0.55, "snow must respect holes inside its ground mask")
	_check(clipped.get_pixel(8, 180).r < 0.3, "snow must stay within the ground bounds")
	snow._material.set_shader_parameter("ground_mask", ImageTexture.create_from_image(snow._ground.image))
	snow.set_snow_cover(0.5)
	var camera := Camera2D.new()
	camera.position = Vector2(320, 180)
	add_child(camera)
	camera.force_update_scroll()
	var centered := await _capture()
	camera.position.x += 24.0
	camera.force_update_scroll()
	var moved := await _capture()
	var mismatches := 0
	for y in range(32, 328, 4):
		for x in range(40, 580, 4):
			if centered.get_pixel(x + 24, y).r != moved.get_pixel(x, y).r:
				mismatches += 1
	_check(mismatches < 10, "camera movement must preserve world anchored snow patches")
	camera.position = Vector2(320, 180)
	camera.force_update_scroll()
	snow.set_snow_cover(0.0)
	snow.set_snow_intensity(1.0)
	snow._update_emitters()
	snow.set_process(true)
	await get_tree().create_timer(1.0).timeout
	var flakes_a := await _capture()
	await get_tree().create_timer(0.2).timeout
	var flakes_b := await _capture()
	var bright := 0
	var changed := 0
	for y in range(0, 360):
		for x in range(0, 640):
			if flakes_a.get_pixel(x, y).r > 0.5:
				bright += 1
			if absf(flakes_a.get_pixel(x, y).r - flakes_b.get_pixel(x, y).r) > 0.2:
				changed += 1
	_check(bright > 80 and changed > 80, "random atlas snowflakes must visibly fall and move")
	full.save_png("res://.maintenance/snow-surface-full.png")
	half.save_png("res://.maintenance/snow-surface-patches.png")
	flakes_a.save_png("res://.maintenance/snow-flakes-render.png")
	print("SNOW_SURFACE_RENDER_TEST: failures=", failures, "; flake_pixels=", bright, "; moving_pixels=", changed)
	get_tree().quit(0 if failures.is_empty() else 1)
