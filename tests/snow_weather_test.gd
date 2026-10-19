# 实际战场验证积雪遮罩、雨雪切换、资源隔离、树冠、镜头、暂停和回收。
extends Node

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("SNOW_WEATHER_TEST: " + label)


func _run() -> void:
	get_tree().create_timer(55.0).timeout.connect(func(): get_tree().quit(2))
	var root := get_tree().root
	root.get_node("RunManager").start_new_run()
	var preset := load("res://data/weather/snow_default.tres") as SnowWeatherSettings
	var initial := preset.initial_coverage
	var detached := SnowWeather.new()
	detached.settings = preset
	detached.set_enabled(false)
	detached.set_snow_intensity(0.1)
	detached.set_snow_cover(0.2)
	_check(preset.enabled and preset.initial_coverage == initial and preset.intensity == 0.65, "pre-tree APIs must preserve shared presets")
	detached.free()
	var config := load("res://data/levels/level_001.tres").duplicate(true) as BattleLevelConfig
	config.snow_weather_settings = preset
	var direct_battle := config.battle_scene.instantiate() as Node2D
	_check(direct_battle.get_node("SnowWeather").settings.enabled, "F6 battle scene must explicitly enable snow")
	direct_battle.free()
	var battle := config.battle_scene.instantiate() as Node2D
	battle.configure_level(config)
	# 树冠演示仅在验证场景创建，正式关卡的地形与碰撞保持原样。
	var tree := load("res://scenes/world/tree01.tscn").instantiate() as Node2D
	tree.position = Vector2(620, 590)
	battle.get_node("Level").add_child(tree)
	root.add_child(battle)
	await get_tree().process_frame
	var snow := battle.get_node("SnowWeather") as SnowWeather
	var rain := battle.get_node("RainWeather") as RainWeather
	_check(snow.settings != preset and snow.settings.enabled, "level must use an isolated enabled snow preset")
	_check(not rain.settings.enabled and not rain._rain[0].emitting, "snow level must suppress rain")
	_check(snow._tint == rain._tint, "rain and snow must share one canvas tint")
	_check(snow.is_ground_point(Vector2(400, 440)), "land must accept ground snow")
	_check(not snow.is_ground_point(Vector2(960, 320)), "terrain hole must not receive snow")
	_check(not snow.is_ground_point(Vector2(400, 960)), "cliff must not receive ground snow")
	_check(not snow.is_ground_point(Vector2(-100, -100)), "off-map must not receive ground snow")
	var region := battle.get_node("Level/NavigationRegion2D") as NavigationRegion2D
	var nav := region.navigation_polygon
	var old_mask: PackedByteArray = snow._ground.image.get_data()
	region.navigation_polygon = null
	snow.apply_settings()
	_check(snow._ground.image.get_data() == old_mask, "snow mask must be independent of navigation bake")
	region.navigation_polygon = nav
	var source := tree.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_check(snow._scenery.has(source.get_instance_id()), "tree must receive a snow cover")
	var other_scenery := snow._scenery.size() - 1
	var cover: Sprite2D = snow._scenery[source.get_instance_id()].copy
	snow._sync_scenery()
	_check(cover.get_parent() == source and cover.texture == source.sprite_frames.get_frame_texture(source.animation, source.frame), "cover must follow the source without changing its material")
	source.hide()
	snow._sync_scenery()
	_check(not cover.visible, "hidden scenery must hide its snow")
	source.show()
	source.flip_h = true
	source.modulate.a = 0.4
	snow._sync_scenery()
	_check(cover.flip_h == source.flip_h and cover.modulate == Color.WHITE, "cover must inherit transparency once and follow flips")
	source.modulate.a = 1.0
	source.flip_h = false
	var count := snow._scenery.size()
	snow._scan_scenery()
	_check(snow._scenery.size() == count, "scanning must not recursively cover its own snow proxies")
	snow.settings.automatic_accumulation = true
	snow.set_snow_cover(0.4)
	snow.set_snow_intensity(1.0)
	snow._process(1.0)
	_check(snow._coverage > 0.4, "snowfall must accumulate cover")
	snow.set_snow_intensity(0.0)
	var before_melt := snow._coverage
	snow._process(1.0)
	_check(snow._coverage < before_melt and snow._surface.visible and not snow._flakes[0].emitting, "stopping flakes must leave existing snow to melt")
	snow.set_snow_cover(1.0, 0.12)
	await get_tree().create_timer(0.18).timeout
	_check(snow._coverage > 0.98, "manual cover transition must complete")
	var elapsed := snow._elapsed
	var coverage := snow._coverage
	get_tree().paused = true
	await get_tree().create_timer(0.05, true).timeout
	_check(snow._elapsed == elapsed and snow._coverage == coverage, "snowfall and accumulation must pause with battle")
	get_tree().paused = false
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.75
	camera.position = Vector2(800, 450)
	camera.force_update_scroll()
	snow._update_emitters()
	for flakes in snow._flakes:
		var process := flakes.process_material as ParticleProcessMaterial
		var view := snow._camera_rect()
		_check(process.emission_box_extents.x >= view.size.x * 0.5, "snow must cover a moved and zoomed camera")
		_check(flakes.lifetime > view.size.y / snow.settings.fall_speed, "slow flakes must survive across the screen")
	_check(preset.initial_coverage == initial and preset.intensity == 0.65, "runtime transitions must preserve preset")
	rain.configure(load("res://data/weather/rain_light.tres"))
	_check(rain.settings.enabled and not snow.settings.enabled and not cover.visible, "switching to rain must hide snow ground and scenery")
	snow.configure(preset)
	_check(not rain.settings.enabled and snow.settings.enabled, "switching back to snow must suppress rain")
	snow.set_enabled(false)
	_check(not snow.is_processing() and not snow._flakes[0].visible and not cover.visible, "disabled snow must stop all drawing and updates")
	_check(snow._tint.color == Color.WHITE, "clear sky must restore world colors")
	snow.configure(preset)
	if "--capture" in OS.get_cmdline_user_args():
		camera.zoom = Vector2.ONE
		camera.position = Vector2(960, 540)
		camera.force_update_scroll()
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/snow-weather-preview.png")
		snow.configure(load("res://data/weather/snow_blizzard.tres"))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/snow-weather-blizzard.png")
		snow.set_enabled(false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/snow-weather-clear.png")
	tree.queue_free()
	await get_tree().process_frame
	snow._scan_scenery()
	_check(snow._scenery.size() == other_scenery, "freed scenery must release its snow proxy")
	var weak_snow: WeakRef = weakref(snow)
	battle.queue_free()
	await get_tree().process_frame
	_check(weak_snow.get_ref() == null, "leaving battle must free the weather")
	# 已有雨天预设必须覆盖继承场景的雪天设置，兼容旧关卡。
	var rainy_battle := config.battle_scene.instantiate() as Node2D
	var rainy_config := BattleLevelConfig.new()
	rainy_config.weather_settings = load("res://data/weather/rain_default.tres")
	rainy_battle.configure_level(rainy_config)
	root.add_child(rainy_battle)
	_check(not rainy_battle.get_node("SnowWeather").settings.enabled and rainy_battle.get_node("RainWeather").settings.enabled, "legacy rain level must remain rain")
	rainy_battle.queue_free()
	print("SNOW_WEATHER_TEST: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
