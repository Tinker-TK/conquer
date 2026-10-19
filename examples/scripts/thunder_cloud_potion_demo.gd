# 复用真实战场与回合结算；静止目标便于观察雷云的固定落点和三回合期限。
extends "res://scripts/battle/battle_scene.gd"

var _demo_status: Label
var _next_round: Button


func _ready() -> void:
	DisplayServer.window_set_title("雷云药水 · 三回合固定落点试玩")
	var initial := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	initial.starting_relics.clear()
	initial.starting_potions.clear()
	initial.starting_potions.append(load("res://data/potions/thunder_cloud.tres"))
	initial.starting_potions.append(load("res://data/potions/lightning.tres"))
	RunManager.start_new_run(initial)
	var config := BattleLevelConfig.new()
	config.level_name = "雷云药水试玩"
	config.enemy_max_hp = 999
	configure_level(config)
	super._ready()
	for weather_name in ["RainWeather", "SnowWeather"]:
		var weather := get_node_or_null(weather_name)
		if weather != null:
			weather.set_enabled(false)
	_build_demo_panel()
	battle_round_manager.phase_changed.connect(_on_demo_phase_changed)
	_spawn_demo_units()
	battle_round_manager.start_auto_battle()


func _build_demo_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 29
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 182)
	panel.size = Vector2(460, 250)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15202deb")
	style.border_color = Color("476675")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "雷云药水 · 固定区域"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("b9e8ec"))
	column.add_child(title)
	var instructions := Label.new()
	instructions.text = "点击顶部雷云药水，再选择敌人附近的落点。\n每 0.4 秒锁定一个敌人落雷，造成 6 点伤害。\n云团固定存在 3 回合，空范围不出雷。"
	instructions.add_theme_font_size_override("font_size", 20)
	column.add_child(instructions)
	_demo_status = Label.new()
	_demo_status.add_theme_font_size_override("font_size", 20)
	column.add_child(_demo_status)
	_next_round = Button.new()
	_next_round.text = "结束本轮交锋，查看下一回合"
	_next_round.custom_minimum_size.y = 40
	_next_round.pressed.connect(_end_demo_round)
	column.add_child(_next_round)


func _on_demo_phase_changed(phase: int, _round_number: int) -> void:
	if phase == Global.GamePhase.CARD_PLAY:
		_spawn_demo_units()
		battle_round_manager.start_auto_battle.call_deferred()


func _spawn_demo_units() -> void:
	_spawn_demo_unit(true, Vector2(600, 590))
	for point in [Vector2(1160, 555), Vector2(1230, 605), Vector2(1405, 580)]:
		_spawn_demo_unit(false, point)


func _spawn_demo_unit(ally: bool, point: Vector2) -> void:
	var unit := load("res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn").instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 500
	get_node("Entities/TeamA" if ally else "Entities/TeamB").add_child(unit)
	unit.global_position = point
	unit.set_physics_process(false)


func _end_demo_round() -> void:
	if battle_round_manager.battle_state != BattleRoundManager.BattleState.COMBAT:
		return
	for enemy in get_alive_units(&"team_b"):
		enemy.take_effect_damage(99999)


func _process(_delta: float) -> void:
	if _demo_status == null:
		return
	_demo_status.text = "第 %d 回合 · %s" % [battle_round_manager.current_round,
		"交锋中" if Global.game_phase == Global.GamePhase.AUTO_BATTLE else "回合结算中"]
	_next_round.disabled = battle_finished or Global.game_phase != Global.GamePhase.AUTO_BATTLE
