# F6 可运行的实际战场调参示例；树木和示范单位仅存在于本演示。
extends Node

var _snow: SnowWeather
var _slider: HSlider
var _status: Label


func _ready() -> void:
	RunManager.start_new_run()
	# 演示明确指定雪天，避免策划将正式关卡改为雨天后演示也没有飘雪。
	var config := load("res://data/levels/level_001.tres").duplicate(true) as BattleLevelConfig
	config.snow_weather_settings = load("res://data/weather/snow_default.tres")
	var battle := config.battle_scene.instantiate() as Node2D
	battle.configure_level(config)
	for point in [Vector2(520, 550), Vector2(1340, 370)]:
		var tree := load("res://scenes/world/tree01.tscn").instantiate() as StaticBody2D
		tree.position = point
		# 演示树只展示覆雪，不改变正式关卡的导航或阻挡示范单位。
		tree.collision_layer = 0
		tree.collision_mask = 0
		tree.get_node("TransparentCheck").monitoring = false
		battle.get_node("Level").add_child(tree)
	add_child(battle)
	_snow = battle.get_node("SnowWeather") as SnowWeather
	var soldier := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	soldier.position = Vector2(390, 440)
	battle.get_node("Entities/TeamA").add_child(soldier)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -286
	panel.offset_right = -16
	panel.offset_top = 16
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "雪天效果 / 实时调参"
	box.add_child(title)
	for pair in [["小雪", "snow_light"], ["正常雪", "snow_default"], ["暴雪", "snow_blizzard"]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(_preset.bind(pair[1]))
		box.add_child(button)
	var stop := Button.new()
	stop.text = "停雪并逐渐融化"
	stop.pressed.connect(func():
		_snow.settings.automatic_accumulation = true
		_snow.set_snow_intensity(0.0, 1.0))
	box.add_child(stop)
	var clear := Button.new()
	clear.text = "晴天 / 关闭雪天"
	clear.pressed.connect(func(): _snow.set_enabled(false))
	box.add_child(clear)
	_status = Label.new()
	box.add_child(_status)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value_changed.connect(func(value: float):
		_snow.set_enabled(true)
		_snow.settings.automatic_accumulation = false
		_snow.set_snow_cover(value))
	box.add_child(_slider)
	var tip := Label.new()
	tip.text = "拖动滑块手动设定积雪\n点击预设恢复自动堆积\n中键拖动地图，滚轮缩放"
	box.add_child(tip)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png("res://.maintenance/snow-weather-demo.png")
		print("SNOW_WEATHER_DEMO_CAPTURED")
		get_tree().quit()


func _preset(resource_name: String) -> void:
	_snow.configure(load("res://data/weather/" + resource_name + ".tres"))


func _process(_delta: float) -> void:
	if _slider == null or not is_instance_valid(_snow):
		return
	_slider.set_value_no_signal(_snow._coverage)
	_status.text = "雪量 %d%% · 积雪 %d%%" % [roundi(_snow._intensity * 100), roundi(_snow._coverage * 100)]
