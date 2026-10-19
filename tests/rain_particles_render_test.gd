# 在真实 GPU 上测量雨滴宽/长/透明度，并输出当前正式关卡的动态预览。
extends Node

var failures: Array[String] = []
var weather: RainWeather
var camera: Camera2D

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("RAIN_PARTICLES_RENDER_TEST: " + label)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RAIN_PARTICLES_RENDER_TEST: requires a graphical renderer")
		get_tree().quit(0)
		return
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.transparent_bg = true
	camera = Camera2D.new()
	camera.position = Vector2(960, 540)
	add_child(camera)
	weather = RainWeather.new()
	weather.use_terrain_mask = false
	weather.settings = RainWeatherSettings.new()
	weather.settings.puddles_enabled = false
	weather.settings.intensity = 0.0
	weather.settings.splash_rate = 0.0
	weather.settings.wind = 0.0
	add_child(weather)
	weather.set_process(false)
	var base := await _measure(3, 32, 0.7, 1.0, Color.WHITE)
	var distant := await _measure(3, 32, 0.7, 0.75, Color.WHITE)
	var close := await _measure(3, 32, 0.7, 2.0, Color.WHITE)
	var wide := await _measure(6, 64, 0.7, 1.0, Color.WHITE)
	var faint := await _measure(3, 32, 0.35, 1.0, Color.WHITE)
	var dark := await _measure(3, 32, 0.7, 1.0, Color(0.2, 0.2, 0.2))
	_check(base.width == 3 and absf(base.height - 32) <= 2, "a 3x32 rain streak must render at the requested screen size in a small window")
	_check(distant.width == base.width and close.width == base.width and distant.height == base.height and close.height == base.height, "rain dimensions must stay readable across camera zoom")
	_check(wide.width >= base.width * 1.8 and wide.height >= base.height * 1.8, "width and length controls must visibly enlarge actual particles")
	_check(base.alpha > 0.6 and faint.alpha < base.alpha * 0.65, "rain opacity must directly change rendered opacity")
	_check(absf(dark.brightness - base.brightness) < 0.02, "overcast world tint must not dim rain streaks")
	print("RAIN_PARTICLE_METRICS: base=", base, "; zoom_out=", distant, "; zoom_in=", close, "; wide=", wide, "; faint=", faint, "; dark=", dark)
	var slow := await _measure_motion(600, 300, 1.0)
	var fast := await _measure_motion(1200, 600, 1.0)
	var zoom_out_motion := await _measure_motion(600, 300, 0.75)
	var zoom_in_motion := await _measure_motion(600, 300, 2.0)
	root.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var maximum := await _measure_motion(6000, 3000, 1.0)
	root.size = Vector2i(640, 360)
	await get_tree().process_frame
	for motion in [slow, fast, zoom_out_motion, zoom_in_motion, maximum]:
		_check(motion.alignment > 0.995, "a rain streak must move along its rendered long axis")
		_check(motion.straightness > 0.995, "successive GPU displacements must follow one straight line")
		_check(absf(motion.speed_y - motion.requested_speed) < motion.requested_speed * 0.03, "actual screen fall speed must match the setting")
	_check(fast.speed_y > slow.speed_y * 1.7, "doubling fall speed must actually make rendered rain faster")
	print("RAIN_MOTION_METRICS: slow=", slow, "; fast=", fast, "; zoom_out=", zoom_out_motion, "; zoom_in=", zoom_in_motion, "; maximum=", maximum)
	await _check_ground_splashes()
	weather.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	root.get_node("RunManager").start_new_run()
	var battle := load("res://scenes/levels/battles/battle_001.tscn").instantiate() as Node2D
	var config := load("res://data/levels/level_001.tres") as BattleLevelConfig
	battle.configure_level(config)
	root.add_child(battle)
	await get_tree().process_frame
	weather = battle.get_node("RainWeather") as RainWeather
	root.size = Vector2i(960, 540)
	# 隐藏 UI 仅用于看清实机天气，正式关卡仍显示正常界面。
	for child in battle.get_children():
		if child is CanvasLayer:
			child.visible = false
	for i in weather._rain.size():
		weather._rain[i].use_fixed_seed = true
		weather._rain[i].seed = 731 + i
		weather._rain[i].restart(true)
	await get_tree().create_timer(0.5).timeout
	var timing: Array[int] = []
	for frame in 48:
		await RenderingServer.frame_post_draw
		timing.append(roundi(weather._elapsed * 1000.0))
		root.get_texture().get_image().save_png("res://.maintenance/rain-visible-%02d.png" % frame)
		for step in 2:
			await get_tree().process_frame
	var closeup_camera := battle.get_node("Camera2D") as Camera2D
	closeup_camera.zoom = Vector2.ONE * 1.8
	closeup_camera.position = Vector2(500, 380)
	closeup_camera.force_update_scroll()
	await get_tree().create_timer(0.4).timeout
	var closeup_timing: Array[int] = []
	for frame in 48:
		await RenderingServer.frame_post_draw
		closeup_timing.append(roundi(weather._elapsed * 1000.0))
		root.get_texture().get_image().save_png("res://.maintenance/rain-contact-%02d.png" % frame)
		for step in 2:
			await get_tree().process_frame
	var timing_file := FileAccess.open("res://.maintenance/rain-visible-timing.json", FileAccess.WRITE)
	timing_file.store_string(JSON.stringify({"overview": timing, "closeup": closeup_timing}))
	print("RAIN_PARTICLES_RENDER_TEST: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _measure(width: int, length: int, opacity: float, zoom: float, tint: Color) -> Dictionary:
	weather.settings.streak_width = width
	weather.settings.streak_length = length
	weather.settings.rain_opacity = opacity
	weather.apply_settings()
	weather.set_process(false)
	weather._tint.color = tint
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	var particles := weather._rain[1]
	particles.amount = 1
	particles.amount_ratio = 1.0
	particles.preprocess = 0.0
	particles.lifetime = 10.0
	particles.global_position = Vector2.ZERO
	particles.visibility_rect = Rect2(0, 0, 1920, 1080)
	particles.show()
	particles.emitting = false
	var process := particles.process_material as ParticleProcessMaterial
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.angle_min = 0.0
	process.angle_max = 0.0
	particles.restart()
	particles.emitting = false
	await get_tree().process_frame
	particles.emit_particle(Transform2D(0, camera.global_position), Vector2.ZERO, Color.WHITE, Color(0, 0, 0, 1), GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_ROTATION_SCALE | GPUParticles2D.EMIT_FLAG_VELOCITY)
	for frame in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var start := Vector2i(image.get_size())
	var end := Vector2i(-1, -1)
	var alpha := 0.0
	var brightness := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.05:
				start = start.min(Vector2i(x, y))
				end = end.max(Vector2i(x, y))
				alpha = maxf(alpha, color.a)
				brightness = maxf(brightness, color.r + color.g + color.b)
	var size := (end - start + Vector2i.ONE).max(Vector2i.ZERO)
	return {"width": size.x, "height": size.y, "alpha": alpha, "brightness": brightness}


func _particle_pixels() -> Dictionary:
	var stamp := Time.get_ticks_usec()
	var image := get_tree().root.get_texture().get_image()
	var total := 0.0
	var sum := Vector2.ZERO
	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	var start := Vector2i(image.get_size())
	var end := Vector2i(-1, -1)
	var peak := 0.0
	var brightness := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			var a := color.a
			count += 1
			total += a
			sum += Vector2(x, y) * a
			xx += x * x * a
			yy += y * y * a
			xy += x * y * a
			start = start.min(Vector2i(x, y))
			end = end.max(Vector2i(x, y))
			peak = maxf(peak, a)
			brightness = maxf(brightness, color.r + color.g + color.b)
	var center := sum / maxf(total, 0.001)
	var theta := 0.5 * atan2(2.0 * (xy / maxf(total, 0.001) - center.x * center.y), xx / maxf(total, 0.001) - center.x * center.x - yy / maxf(total, 0.001) + center.y * center.y)
	var axis := Vector2(cos(theta), sin(theta))
	if axis.y < 0.0:
		axis = -axis
	return {"point": center, "axis": axis, "stamp": stamp, "count": count, "size": (end - start + Vector2i.ONE).max(Vector2i.ZERO), "end": end, "alpha": peak, "brightness": brightness}


func _measure_motion(speed: float, wind: float, zoom: float) -> Dictionary:
	weather.settings.fall_speed = speed
	weather.settings.wind = wind
	weather.settings.streak_width = 3
	weather.settings.streak_length = 32
	weather.apply_settings()
	weather.set_process(false)
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	weather._update_rain_emitters()
	var particles := weather._rain[1]
	particles.amount = 1
	particles.amount_ratio = 1.0
	particles.preprocess = 0.0
	particles.lifetime = 3.0
	particles.speed_scale = 0.0
	particles.global_position = Vector2.ZERO
	particles.visibility_rect = Rect2(-500, -500, 3000, 2000)
	particles.show()
	particles.emitting = false
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	particles.restart()
	particles.emitting = false
	await get_tree().process_frame
	var inverse := (get_viewport().get_stretch_transform() * get_viewport().get_canvas_transform()).affine_inverse()
	# 不覆盖速度或旋转，让真正的粒子处理材质决定运动和朝向。
	particles.emit_particle(Transform2D(0, inverse * Vector2(260, 35)), Vector2.ZERO, Color.WHITE, Color(0, 0, 0, 1), GPUParticles2D.EMIT_FLAG_POSITION)
	particles.request_particles_process(0.001)
	for frame in 2:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var first := _particle_pixels()
	# fixed_fps=0 时额外处理使用 1/30 秒步长；0.09 秒请求执行三步，0.025 执行一步。
	# 冻结自动步进，避免 GPU 读回/截图耗时改变测量间隔。
	var request_time := 0.09 if speed <= 1200.0 else 0.025
	var step_time := 0.1 if speed <= 1200.0 else 1.0 / 30.0
	particles.request_particles_process(request_time)
	for frame in 2:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var second := _particle_pixels()
	particles.request_particles_process(request_time)
	for frame in 2:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var third := _particle_pixels()
	_check(first.count > 0 and second.count > 0 and third.count > 0, "moving GPU rain must remain visible in all measurement frames")
	var travel: Vector2 = second.point - first.point
	var next_travel: Vector2 = third.point - second.point
	var measured_speed: float = travel.y / step_time
	return {"speed_y": measured_speed, "requested_speed": speed, "alignment": absf(travel.normalized().dot(first.axis)), "straightness": travel.normalized().dot(next_travel.normalized())}


func _splash_pixels(age: float, zoom: float) -> Dictionary:
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	weather._events[0].age = age
	weather._splash_canvas.queue_redraw()
	weather._ripple_canvas.queue_redraw()
	for frame in 2:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	return _particle_pixels()


func _check_ground_splashes() -> void:
	weather.settings.wind = 450.0
	weather.settings.fall_speed = 1800.0
	weather.settings.streak_length = 32.0
	weather.apply_settings()
	weather.set_process(false)
	weather._tint.color = Color(0.2, 0.2, 0.2)
	for particles in weather._rain:
		particles.hide()
	weather._add_splash(camera.position, 1.0, true)
	# 出生的雨滴尚在空中，不得提前产生水波。
	weather._events[0].wet = true
	var arrival := await _splash_pixels(-0.025, 1.0)
	var ripple_image := weather._ripple_view.get_texture().get_image()
	var premature_wave := false
	for y in range(0, ripple_image.get_height(), 3):
		for x in range(0, ripple_image.get_width(), 3):
			var color := ripple_image.get_pixel(x, y)
			premature_wave = premature_wave or color.r > 0.01 or color.g > 0.01
	_check(not premature_wave, "water rings must begin on contact, after the falling drop")
	_check(absf(arrival.end.y - 135.0) <= 2.0, "the falling drop tip must approach its exact ground point along the configured velocity")
	weather._events[0].wet = false
	var impact := await _splash_pixels(0.015, 1.0)
	var rising := await _splash_pixels(0.08, 1.0)
	var far := await _splash_pixels(0.08, 0.75)
	var close := await _splash_pixels(0.08, 2.0)
	_check(impact.count >= 10 and rising.count >= 6, "dry land must show a visible contact flash and rising droplets")
	_check(rising.size.y >= 5 and rising.size.x >= 6, "ground splash must visibly rise and spread from the contact point")
	_check(rising.size == far.size and rising.size == close.size, "ground splash must remain readable when the camera zooms")
	_check(rising.alpha > 0.7 and rising.brightness > 1.8, "overcast tint must not hide ground splash droplets")
	camera.position += Vector2(180, 60)
	var moved := await _splash_pixels(0.08, 1.0)
	_check(moved.point.distance_to(rising.point - Vector2(60, 20)) < 1.0, "a ground splash must stay anchored in the world when the camera moves")
	camera.position -= Vector2(180, 60)
	weather._splash_canvas.splash_opacity = 0.3
	var faint := await _splash_pixels(0.08, 1.0)
	_check(faint.alpha < rising.alpha * 0.45, "splash opacity must directly control the rendered water droplets")
	var ended := await _splash_pixels(0.4, 1.0)
	_check(ended.count == 0, "dry-land splash must disappear after its short lifetime")
	weather._process(0.01)
	_check(weather._events.is_empty(), "expired dry impacts must release their event slots")
	print("RAIN_CONTACT_METRICS: arrival=", arrival, "; impact=", impact, "; rising=", rising, "; zoom_out=", far, "; zoom_in=", close, "; faint=", faint)
