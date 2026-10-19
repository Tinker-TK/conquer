extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("DYNAMIC_RIVER_TEST: " + label)

func _count_wet(river: DynamicRiver) -> int:
	var count := 0
	for y in range(0, 100, 2):
		for x in range(0, 300, 2):
			if river.is_water_point(river.to_global(Vector2(x, y))):
				count += 1
	return count

func _set_stage_enabled(river, value: bool) -> void:
	if river is RiverTileMap:
		river.set_river_enabled(value)
	else:
		river.set_enabled(value)

func _run() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	var shared := preload("res://data/water/river_default.tres")
	var shared_level := shared.water_level
	var detached := DynamicRiver.new()
	detached.settings = shared
	detached.set_water_level(0.2)
	detached.set_enabled(false)
	_check(shared.water_level == shared_level and shared.enabled, "pre-tree API must isolate shared settings")
	detached.free()
	var river := DynamicRiver.new()
	river.polygon = PackedVector2Array([Vector2.ZERO, Vector2(300, 0), Vector2(300, 100), Vector2(0, 100)])
	river.weather_path = NodePath()
	var island := Polygon2D.new()
	island.name = "Island"
	island.polygon = PackedVector2Array([Vector2(130, 35), Vector2(170, 35), Vector2(170, 65), Vector2(130, 65)])
	river.add_child(island)
	river.dry_islands = [NodePath("Island")]
	add_child(river)
	_check(river.settings != shared, "runtime settings must be independent")
	var image_id := river._height_image.get_instance_id()
	river.set_water_level(0.0)
	_check(_count_wet(river) == 0 and river.is_bed_point(Vector2(40, 50)), "draining leaves a dry riverbed")
	river.set_water_level(0.3)
	var low := _count_wet(river)
	river.set_water_level(0.9)
	var high := _count_wet(river)
	_check(high > low and low > 0, "water must cover more bed at higher levels")
	_check(not river.is_bed_point(Vector2(150, 50)) and not river.is_water_point(Vector2(150, 50)), "island remains dry")
	_check(not island.visible, "island helper must not draw in the game")
	_check(not river.is_water_point(Vector2(-2, 50)), "outside river stays dry")
	_check(river._height_image.get_instance_id() == image_id, "changing level must not rebuild height image")
	var count_before := _count_wet(river)
	river.position = Vector2(350, 200)
	river.rotation = 0.3
	river.scale = Vector2(1.5, 0.75)
	_check(_count_wet(river) == count_before, "wet queries must follow local rotation, translation and scale")
	river.set_water_level(0.4, 0.2)
	await get_tree().create_timer(0.08).timeout
	var elapsed := river._elapsed
	var level := river.get_water_level()
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_check(river._elapsed == elapsed and river.get_water_level() == level, "flow and water-level tween must pause")
	get_tree().paused = false
	await get_tree().create_timer(0.25).timeout
	_check(is_equal_approx(river.get_water_level(), 0.4), "water-level tween must finish")
	_check(shared.water_level == shared_level, "runtime level must not modify preset")
	# 明确的黑/白灰度图与 Alpha：水位阈值、透明区域、干涸行为。
	var map := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	map.fill(Color(0.8, 0.8, 0.8, 1))
	map.fill_rect(Rect2i(0, 0, 2, 2), Color(0.2, 0.2, 0.2, 1))
	map.set_pixel(0, 0, Color(0, 0, 0, 0))
	river.settings.height_texture = ImageTexture.create_from_image(map)
	river.apply_settings()
	river.set_water_level(0.5)
	_check(river.is_water_point(river.to_global(Vector2(90, 30))), "black height region must flood first")
	_check(not river.is_water_point(river.to_global(Vector2(240, 30))), "white height region must remain dry")
	_check(not river.is_bed_point(river.to_global(Vector2(20, 20))), "transparent height-map region must be excluded")
	river.queue_free()
	await get_tree().process_frame
	# 正式关卡接入、资源覆盖与雨天波纹共享。
	RunManager.start_new_run()
	var battle := preload("res://scenes/levels/battles/battle_001.tscn").instantiate()
	# 关卡美术可以移除河流；集成回归在内存中放置固定河床，避免依赖作者当前布局。
	var fixture_river := DynamicRiver.new()
	fixture_river.name = "RiverTestFixture"
	fixture_river.polygon = PackedVector2Array([Vector2(500, 400), Vector2(800, 400), Vector2(800, 500), Vector2(500, 500)])
	battle.get_node("Level").add_child(fixture_river)
	var config := BattleLevelConfig.new()
	config.river_settings = preload("res://data/water/river_flood.tres")
	var rain_settings := RainWeatherSettings.new()
	rain_settings.puddles_enabled = false
	rain_settings.intensity = 0.0
	config.weather_settings = rain_settings
	battle.configure_level(config)
	add_child(battle)
	await get_tree().process_frame
	# 关卡可使用多边形或 TileMap 河流，也可由作者移动和重命名。
	var stage_river
	for node in battle.find_children("*", "", true, false):
		if node is RiverTileMap or node is DynamicRiver:
			stage_river = node
			break
	_check(stage_river != null, "stage must contain a river")
	if stage_river == null:
		get_tree().quit(1)
		return
	var weather := battle.get_node("RainWeather") as RainWeather
	# 此项专测雨水共享：在内存夹具中建立连接，不修改关卡作者保存的雪天/河流布局。
	stage_river.weather_path = stage_river.get_path_to(weather)
	battle.configure_level(config)
	var surface := stage_river.surface as DynamicRiver if stage_river is RiverTileMap else stage_river as DynamicRiver
	if stage_river is RiverTileMap:
		_check(surface.settings.height_texture != null, "post-ready level override must preserve tile height map")
	_check(stage_river.get_water_level() == config.river_settings.water_level, "level resource must override scene river")
	_check(stage_river.settings != config.river_settings, "level override must be isolated")
	_set_stage_enabled(stage_river, false)
	weather.refresh_river_surfaces()
	await get_tree().process_frame
	var ground_without_river := weather._ground_mask_image.get_data()
	_set_stage_enabled(stage_river, true)
	weather.refresh_river_surfaces()
	await get_tree().process_frame
	_check(weather._rivers.has(surface), "rain must discover the stage river")
	var foot := surface.to_global(surface._bounds.get_center())
	_check(stage_river.is_water_point(foot), "example stream must contain water")
	_check(not weather.is_ground_point(foot), "puddle mask must exclude riverbed")
	_check(weather._is_wet(foot), "river must produce wet footsteps with puddles disabled")
	weather._add_splash(foot, 1.0)
	_check(not weather._events.is_empty() and weather._events[-1].wet, "river rain splash must create a wet ripple")
	stage_river.set_water_level(0.0)
	_check(not weather._is_wet(foot), "drained river must stop producing wet footsteps")
	_check(weather._reflection_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "river must retain reflection rendering with puddles disabled")
	_set_stage_enabled(stage_river, false)
	await get_tree().process_frame
	_check(weather._ground_mask_image.get_data() == ground_without_river, "disabling river must restore original terrain to puddle mask")
	_set_stage_enabled(stage_river, true)
	await get_tree().process_frame
	_check(not weather.is_ground_point(foot), "enabling river must exclude its bed again")
	var river_weak: WeakRef = weakref(stage_river)
	battle.queue_free()
	await get_tree().process_frame
	_check(river_weak.get_ref() == null, "river must be released with its battle")
	print("DYNAMIC_RIVER_METRICS: low=", low, "; high=", high)
	print("DYNAMIC_RIVER_PASS: failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
