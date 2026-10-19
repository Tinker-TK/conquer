extends Node2D

var river: DynamicRiver
var weather: RainWeather
var _level_label: Label


func _ready() -> void:
	get_viewport().get_window().size = Vector2i(1280, 720)
	get_viewport().get_window().content_scale_size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color(0.11, 0.17, 0.13))
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var atlas := preload("res://assets/tilemap/field_128_128.png")
	for y in 6:
		for x in 10:
			var grass := Sprite2D.new()
			grass.texture = atlas
			grass.region_enabled = true
			grass.region_rect = Rect2(128, 128, 128, 128)
			grass.centered = false
			grass.position = Vector2(x * 128, y * 128)
			grass.z_index = -20
			terrain.add_child(grass)
	var rivers := Node2D.new()
	rivers.name = "Rivers"
	add_child(rivers)
	river = preload("res://scenes/effects/dynamic_river.tscn").instantiate()
	river.polygon = PackedVector2Array([Vector2(48, 318), Vector2(240, 278), Vector2(440, 342), Vector2(640, 294),
		Vector2(820, 342), Vector2(1050, 286), Vector2(1230, 326), Vector2(1230, 555), Vector2(1040, 498),
		Vector2(820, 564), Vector2(650, 510), Vector2(450, 580), Vector2(250, 490), Vector2(48, 548)])
	river.settings = preload("res://data/water/river_default.tres").duplicate(true)
	river.settings.bank_slope = 78.0
	river.settings.tide_amplitude = 0.20
	var island := Polygon2D.new()
	island.name = "DryIsland"
	island.polygon = PackedVector2Array([Vector2(623, 388), Vector2(665, 368), Vector2(714, 394),
		Vector2(701, 433), Vector2(655, 448), Vector2(619, 422)])
	river.add_child(island)
	river.dry_islands = [NodePath("DryIsland")]
	rivers.add_child(river)
	var scenery := Node2D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	for i in 3:
		var tree := preload("res://scenes/world/tree01.tscn").instantiate() as Node2D
		tree.position = Vector2(190 + i * 380, 283)
		tree.scale = Vector2.ONE * 0.6
		tree.set_meta("rain_foot_offset", 0.0)
		scenery.add_child(tree)
	weather = RainWeather.new()
	weather.name = "RainWeather"
	weather.use_terrain_mask = false
	weather.ground_rect = Rect2(0, 0, 1280, 720)
	weather.scenery_path = NodePath("../Scenery")
	var rain_settings := RainWeatherSettings.new()
	rain_settings.intensity = 0.0
	rain_settings.puddles_enabled = false
	rain_settings.sky_follow_wind = false
	rain_settings.sky_scroll_speed = Vector2.ZERO
	rain_settings.foot_offset = 0.0
	rain_settings.reflection_height = 0.85
	weather.configure(rain_settings)
	add_child(weather)
	_build_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.size = Vector2(430, 206)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "动态水位河流 · 配置预览"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_level_label = Label.new()
	column.add_child(_level_label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = river.get_water_level()
	slider.custom_minimum_size.x = 380
	slider.value_changed.connect(func(value: float): river.set_water_level(value))
	column.add_child(slider)
	river.water_level_changed.connect(func(value: float): _level_label.text = "水位 %.2f  ·  0 干涸 / 1 满水" % value)
	river.set_water_level(slider.value)
	var row := HBoxContainer.new()
	column.add_child(row)
	for item in [["干涸", 0.0], ["浅水", 0.35], ["常态", 0.66], ["涨水", 0.92]]:
		var button := Button.new()
		button.text = item[0]
		var amount: float = item[1]
		button.pressed.connect(func(): slider.set_value_no_signal(amount); river.set_water_level(amount, 1.5))
		row.add_child(button)
	var options := HBoxContainer.new()
	column.add_child(options)
	var tide := CheckButton.new()
	tide.text = "自动涨退水"
	tide.toggled.connect(func(value: bool): river.settings.tide_enabled = value)
	options.add_child(tide)
	var flow := CheckButton.new()
	flow.text = "流水"
	flow.button_pressed = true
	flow.toggled.connect(func(value: bool):
		river.settings.flow_velocity = Vector2(18, 4) if value else Vector2.ZERO
		river.apply_settings())
	options.add_child(flow)
	var rain := CheckButton.new()
	rain.text = "落雨"
	rain.toggled.connect(func(value: bool): weather.set_rain_intensity(0.65 if value else 0.0, 1.0))
	options.add_child(rain)
