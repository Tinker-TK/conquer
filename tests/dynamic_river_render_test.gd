extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("DYNAMIC_RIVER_RENDER: " + label)

func _capture(river: DynamicRiver, time: float) -> Image:
	river._water_material.set_shader_parameter("clock_time", time)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()

func _changed(a: Image, b: Image) -> int:
	var count := 0
	for y in range(20, 340, 2):
		for x in range(20, 620, 2):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("DYNAMIC_RIVER_RENDER: requires graphical rendering")
		get_tree().quit(2)
		return
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640, 360)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var river := DynamicRiver.new()
	river.polygon = PackedVector2Array([Vector2(20, 20), Vector2(620, 20), Vector2(620, 340), Vector2(20, 340)])
	river.weather_path = NodePath()
	river.settings = RiverSettings.new()
	river.settings.bank_slope = 130.0
	river.settings.height_resolution = 512
	var island := Polygon2D.new()
	island.name = "Island"
	island.polygon = PackedVector2Array([Vector2(260, 150), Vector2(320, 130), Vector2(360, 180), Vector2(310, 210)])
	river.add_child(island)
	river.dry_islands = [NodePath("Island")]
	add_child(river)
	river.set_process(false)
	river.set_water_level(0.0)
	var dry_a := await _capture(river, 0.0)
	var dry_b := await _capture(river, 3.0)
	_check(_changed(dry_a, dry_b) == 0, "dry bed must remain completely still")
	dry_a.save_png("res://.maintenance/river-render-dry.png")
	river.set_water_level(0.65)
	var wet_a := await _capture(river, 0.0)
	var wet_b := await _capture(river, 3.0)
	var movement := _changed(wet_a, wet_b)
	_check(movement > 1000, "flow, caustics and refraction must visibly move")
	var dry_errors := 0
	for y in range(24, 338, 4):
		for x in range(24, 618, 4):
			if not river.is_water_point(Vector2(x, y)) and wet_a.get_pixel(x, y) != wet_b.get_pixel(x, y):
				dry_errors += 1
	_check(dry_errors == 0, "flow animation must not affect exposed bed or islands")
	_check(wet_a.get_pixel(310, 172).r < 0.01, "dry-island mask must actually clip GPU pixels")
	# 完全相同的静态外观必须能冻结；不依赖 Godot 内置 TIME。
	river.settings.flow_velocity = Vector2.ZERO
	river.apply_settings()
	var stopped_a := await _capture(river, 0.0)
	var stopped_b := await _capture(river, 4.0)
	_check(_changed(stopped_a, stopped_b) == 0, "zero flow must stop shader animation")
	# 让水/干床颜色完全分离，以像素判断验证 GPU 与 CPU 的高度阈值相同。
	river._water_material.set_shader_parameter("bed_color", Color.BLACK)
	river._water_material.set_shader_parameter("bank_color", Color.BLACK)
	river._water_material.set_shader_parameter("shallow_color", Color(0, 1, 1))
	river._water_material.set_shader_parameter("deep_color", Color(0, 1, 1))
	river._water_material.set_shader_parameter("shallow_opacity", 1.0)
	river._water_material.set_shader_parameter("deep_opacity", 1.0)
	river._water_material.set_shader_parameter("caustics_strength", 0.0)
	river._water_material.set_shader_parameter("foam_width", 0.0)
	var counts: Array[int] = []
	for level in [0.0, 0.3, 0.7, 1.0]:
		river.set_water_level(level)
		var frame := await _capture(river, 0.0)
		var count := 0
		var mismatch := 0
		for y in range(24, 338, 4):
			for x in range(24, 618, 4):
				var wet := frame.get_pixel(x, y).g > 0.9
				if wet:
					count += 1
				if wet != river.is_water_point(Vector2(x, y)):
					mismatch += 1
		counts.append(count)
		_check(mismatch == 0, "GPU/CPU water coverage must agree at level %.2f (errors %d)" % [level, mismatch])
	_check(counts[0] == 0 and counts[1] < counts[2] and counts[2] < counts[3], "GPU flooded area must increase with level")
	river.queue_free()
	await get_tree().process_frame
	# 可交互演示的真实画面；自动导出 16 帧，包含一个涨退水周期。
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	var demo := preload("res://scenes/testing/river_demo.tscn").instantiate()
	add_child(demo)
	await get_tree().process_frame
	demo.river.set_process(false)
	demo.weather.set_process(false)
	for i in 16:
		demo.river.set_water_level(0.58 + sin(float(i) * TAU / 16.0) * 0.32)
		var frame := await _capture(demo.river, float(i) * 0.3)
		frame.save_png("res://.maintenance/river-demo-%02d.png" % i)
	demo.river.set_water_level(0.66)
	var preview := await _capture(demo.river, 0.0)
	preview.save_png("res://.maintenance/river-demo-preview.png")
	demo.weather.settings.reflections_enabled = false
	demo.weather._update_active()
	demo.river._update_weather_maps()
	var no_reflection := await _capture(demo.river, 0.0)
	var reflected_pixels := 0
	for y in range(285, 485, 2):
		for x in range(48, 1230, 2):
			if preview.get_pixel(x, y) != no_reflection.get_pixel(x, y):
				reflected_pixels += 1
	_check(reflected_pixels > 50, "shared weather texture must visibly reflect trees in the river")
	# 正式第一关的地形、UI、单位和天气共享纹理实际渲染。
	demo.queue_free()
	await get_tree().process_frame
	root.content_scale_size = Vector2i(1920, 1080)
	RunManager.start_new_run()
	var config := preload("res://data/levels/level_001.tres")
	var battle := config.battle_scene.instantiate()
	battle.configure_level(config)
	add_child(battle)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.maintenance/river-battle-preview.png")
	print("DYNAMIC_RIVER_RENDER_METRICS: moving=", movement, "; dry_errors=", dry_errors, "; wet_area=", counts, "; reflection_pixels=", reflected_pixels)
	print("DYNAMIC_RIVER_RENDER_PASS: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
