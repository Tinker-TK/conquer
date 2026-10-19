extends Node2D

@onready var river: RiverTileMap = $River
var weather: RainWeather
var _level_label: Label

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	RenderingServer.set_default_clear_color(Color(0.11, 0.17, 0.13))
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
			add_child(grass)
	var scenery := Node2D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	for point in [Vector2(240, 355), Vector2(920, 210), Vector2(1070, 510)]:
		var tree := preload("res://scenes/world/tree01.tscn").instantiate() as Node2D
		tree.position = point
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
	rain_settings.foot_offset = 0.0
	rain_settings.sky_follow_wind = false
	rain_settings.sky_scroll_speed = Vector2.ZERO
	rain_settings.reflection_height = 0.85
	weather.configure(rain_settings)
	add_child(weather)
	_build_ui()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "TileSet 河流 · 布局可在编辑器逐格绘制"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	_level_label = Label.new()
	column.add_child(_level_label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size.x = 425
	slider.value = river.get_water_level()
	slider.value_changed.connect(func(value: float): river.set_water_level(value))
	column.add_child(slider)
	river.water_level_changed.connect(func(value: float): _level_label.text = "水位 %.2f · 右侧湖中空格保留为岛" % value)
	river.set_water_level(slider.value)
	var row := HBoxContainer.new()
	column.add_child(row)
	for item in [["干涸", 0.0], ["浅水", 0.35], ["常态", 0.66], ["涨水", 0.92]]:
		var button := Button.new()
		button.text = item[0]
		var amount: float = item[1]
		button.pressed.connect(func(): slider.set_value_no_signal(amount); river.set_water_level(amount, 1.5))
		row.add_child(button)
	var rain := CheckButton.new()
	rain.text = "落雨"
	rain.toggled.connect(func(value: bool): weather.set_rain_intensity(0.65 if value else 0.0, 1.0))
	row.add_child(rain)
	var hint := Label.new()
	hint.text = "选 River → TileMap → Terrains：河道 / 水域\n布局保存在场景里；右键擦除，留空格就是岛。"
	column.add_child(hint)
