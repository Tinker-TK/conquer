# 这玩意儿是干嘛的（核心逻辑）：管理战斗准备、交锋与胜负，按本场常驻效果决定是否留存己方幸存单位。
# 数据是咋流动的（数据流向）：关卡配置 → 继承 Run 血量 → 存活单位结算 → 征召牌弃牌与清场 → 下一轮或胜负；战斗栏只显示敌方 HP，玩家 HP 由顶部栏显示。
# 为啥这么写（选型决策）：清场直接退场，不冒充死亡，避免多触发爆炸；队伍容器保留以便提前刷新敌阵。
# 性能咋样（复杂度）：只在回合结束遍历双方单位，出牌时查询导航多边形，不增加每帧清场检查。
extends Node2D

@onready var battle_round_manager: BattleRoundManager = $BattleRoundManager
@onready var hand_manager: Node2D = $HandManager

## 本战场的卡牌界面 CanvasLayer 引用，用于战场卡牌界面协作；应连接当前场景的卡牌 UI 节点，而不是另一个战场的界面。
@export var card_ui: CanvasLayer
# 防止多个单位同时死亡时重复触发胜负结算。
var battle_finished: bool = false
var card_runtime: Node2D
var level_config: BattleLevelConfig
var round_damage_layer: CanvasLayer
var round_damage_effect: Control


# 在子节点入树前接好楼层系统，继承战场和编辑器旧缓存同样使用四层规则。
func _enter_tree() -> void:
	var terrain := get_node_or_null("Level/NavigationRegion2D")
	if terrain != null and terrain.get_script() == null:
		terrain.set_script(preload("res://scripts/world/battle_floor_map.gd"))


# 作用：入树前配置本场规则；config 为地图选择的资源，没有返回值。
func configure_level(config: BattleLevelConfig) -> void:
	level_config = config
	$Entities/TeamB.level_data = config.waves.duplicate()
	$Entities/TeamB.repeat_waves = config.repeat_waves
	$Entities/TeamB.repeat_start = config.repeat_start
	$Entities/TeamB.repeat_end = config.repeat_end
	$BattleRoundManager.battle_duration = config.battle_duration
	$BattleRoundManager.max_energy = config.energy_per_round
	$BattleRoundManager.energy_growth = config.energy_growth
	$BattleRoundManager.base_energy_cap = config.base_energy_cap
	$BattleRoundManager.enemy_max_hp = config.enemy_max_hp
	$HandManager.draw_per_turn = config.cards_per_round
	var snow := get_node_or_null("SnowWeather") as SnowWeather
	if snow != null:
		if config.snow_weather_settings != null:
			snow.configure(config.snow_weather_settings)
		elif config.weather_settings != null:
			# 显式雨天/晴天配置优先于继承场景的默认雪天。
			snow.set_enabled(false)
	if config.weather_settings != null:
		var weather := get_node_or_null("RainWeather") as RainWeather
		if weather != null:
			weather.configure(config.weather_settings)
	if snow != null and snow.settings.enabled:
		var weather := get_node_or_null("RainWeather") as RainWeather
		if weather != null:
			weather.set_enabled(false)
	if config.river_settings != null:
		_configure_rivers(self, config.river_settings)


func _configure_rivers(node: Node, value: RiverSettings) -> void:
	if node is RiverTileMap:
		node.configure(value)
		return
	if node is DynamicRiver:
		node.configure(value)
	for child in node.get_children():
		_configure_rivers(child, value)


# 作用：兼容旧接口；没有参数，返回敌方节点 HP 是否已归零，清场不再直接获胜。
func can_win_battle() -> bool:
	return battle_round_manager.enemy_hp <= 0


# 作用：从卡牌效果系统的正式登记集合取得活单位；team 为阵营组，返回本战场活单位。
func get_alive_units(team: StringName) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	if not is_instance_valid(card_runtime):
		return result
	for unit in card_runtime.living_units():
		if unit.unit_data.unit_team == String(team):
			result.append(unit)
	return result


# 作用：回合 HP 伤害算完后清场；常驻留存生效时保留己方活单位及其原牌绑定，没有参数和返回值。
func clear_round_units() -> void:
	# 先解除预览和选中引用，再弃置未留存的征召牌；留存原牌继续绑定同一单位。
	card_runtime.clear_cast_preview()
	$MouseSlectionController.clear_selection()
	hand_manager.discard_unused_card()
	hand_manager.draw_locked = false
	hand_manager.discard_board_cards()
	for team_path in ["Entities/TeamA", "Entities/TeamB"]:
		var team := get_node(team_path)
		for unit in team.get_children():
			if not unit is UnitBase:
				continue
			if card_runtime.should_retain_unit(unit):
				continue
			# 当场停止单位和子节点并移出树；延迟释放内存，避免旧导航/动画干扰已经刷新的敌阵。
			unit.process_mode = Node.PROCESS_MODE_DISABLED
			unit.queue_free()
			team.remove_child(unit)

# 位置型效果继续使用战场矩形，单位目标牌按活单位验证；deployment_rect 保留用于旧随机效果取点。
## 战场效果允许落点的世界坐标矩形，用于位置型卡牌与药水范围验证。修改不会自动改变地形、导航或相机边界。
@export var battlefield_rect := Rect2(199, 189, 1527, 695)
## 旧非征召随机效果的取点矩形，使用世界坐标。当前单位征召的部署范围由实际烘焙导航的左半边决定，不使用此矩形作为部署边界。
@export var deployment_rect := Rect2(199, 189, 761, 695)
## 旧单层导航场景的部署楼层。四层地图按落点自动选择最上方可行走楼层。
@export_range(1, 4, 1) var deployment_floor: int = 1


# 作用：读取所有楼层的真实导航并保留楼层归属；全图共用一条左右分界线。
func _get_deployment_surfaces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var terrain := get_node_or_null("Level/NavigationRegion2D") as NavigationRegion2D
	if terrain == null:
		return result
	var regions: Array[NavigationRegion2D] = [terrain]
	var has_floors := terrain.get("floor_regions") != null
	if has_floors:
		regions.assign(terrain.get("floor_regions"))
	var surfaces: Array[Dictionary] = []
	var bounds := Rect2()
	for floor_index in regions.size():
		var region := regions[floor_index]
		if region == null or not region.enabled or region.navigation_polygon == null:
			continue
		var navigation := region.navigation_polygon
		var vertices := navigation.get_vertices()
		# 只读烘焙面，不使用外轮廓，保留树木、墙壁和地形缺口。
		for i in navigation.get_polygon_count():
			var polygon := PackedVector2Array()
			for index in navigation.get_polygon(i):
				polygon.append(region.to_global(vertices[index]))
			if polygon.size() < 3:
				continue
			if surfaces.is_empty():
				bounds = Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				bounds = bounds.expand(point)
			surfaces.append({"floor_id": floor_index + 1 if has_floors else deployment_floor, "polygon": polygon})
	if surfaces.is_empty():
		return result
	var middle := bounds.position.x + bounds.size.x * 0.5
	var left_half := PackedVector2Array([bounds.position, Vector2(middle, bounds.position.y),
		Vector2(middle, bounds.end.y), Vector2(bounds.position.x, bounds.end.y)])
	for surface in surfaces:
		for polygon in Geometry2D.intersect_polygons(surface.polygon, left_half):
			result.append({"floor_id": surface.floor_id, "polygon": polygon})
	return result


# 作用：返回所有楼层左半边的可部署多边形；无导航时为空。
func get_deployment_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for surface in _get_deployment_surfaces():
		result.append(surface.polygon)
	return result


# 作用：按世界坐标落点选择最上方可走楼层；非法落点返回 0。
func get_deployment_floor(point: Vector2) -> int:
	var surfaces := _get_deployment_surfaces()
	for index in range(surfaces.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(point, surfaces[index].polygon):
			return surfaces[index].floor_id
	return 0


# 作用：检查征召落点；point 是世界坐标，返回是否在实际导航左半边内。
func is_deployment_position(point: Vector2) -> bool:
	return get_deployment_floor(point) > 0


# 作用：为随机征召取有效落点；没有参数，返回世界坐标，无导航时返回 null。
func random_deployment_position() -> Variant:
	var polygons := get_deployment_polygons()
	polygons.shuffle()
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.size() < 3:
			continue
		# 在真实可走多边形的三角形内部采样，不向矩形里盲选后落入障碍。
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		var start := randi_range(0, indices.size() / 3 - 1) * 3
		var u := randf_range(0.05, 0.95)
		var v := randf_range(0.05, 0.95)
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var a := polygon[indices[start]]
		return a + (polygon[indices[start + 1]] - a) * u + (polygon[indices[start + 2]] - a) * v
	return null

# 作用：Godot 在战斗入树时创建本场卡牌效果管理器并开始首轮；没有参数，没有返回值。
func _ready() -> void:
	BattleSpeed.bind_battle(self)
	# 继承战场可能在编辑地形时隐藏实体/UI；开场恢复必需显示层，避免已刷出的单位不可见。
	$Entities.show()
	$Entities/TeamA.show()
	$Entities/TeamB.show()
	card_ui.show()
	card_runtime = load("res://scripts/cards/card_battle_runtime.gd").new()
	card_runtime.name = "CardBattleRuntime"
	add_child(card_runtime)
	card_runtime.setup(self)
	card_runtime.feedback.connect(_on_card_feedback)
	battle_round_manager.health_changed.connect(_refresh_battle_health)
	battle_round_manager.phase_changed.connect(_on_round_phase_changed)
	round_damage_layer = CanvasLayer.new()
	round_damage_layer.name = "RoundDamageLayer"
	round_damage_layer.layer = 35
	round_damage_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(round_damage_layer)
	round_damage_effect = preload("res://scenes/effects/round_damage_effect.tscn").instantiate()
	round_damage_effect.name = "RoundDamageEffect"
	round_damage_layer.add_child(round_damage_effect)
	# 遗物开局钩子和药水归属本场战斗，换关卡时会一起释放。
	var item_runtime = load("res://scripts/items/battle_items.gd").new()
	item_runtime.name = "BattleItems"
	item_runtime.battle = self
	add_child(item_runtime)
	# 详情挂在战斗自身的 UI 层，离开战斗会一起释放，不影响地图和顶部 HUD。
	var inspector = load("res://scenes/ui/unit_inspector.tscn").instantiate()
	inspector.battle = self
	card_ui.add_child(inspector)
	hand_manager.build_initial_deck()
	var relic_runtime := preload("res://scripts/battle/relic_runtime.gd").new()
	relic_runtime.name = "RelicRuntime"
	add_child(relic_runtime)
	RunManager.relic_battle = relic_runtime
	relic_runtime.setup(self)
	var metrics := preload("res://scripts/battle/balance_metrics.gd").new()
	metrics.name = "BalanceMetrics"
	add_child(metrics)
	metrics.setup(self)
	battle_round_manager.start_encounter()
	
# 作用：刷新顶部敌方血条和本场名称；玩家血量由本局顶部栏显示；没有参数，没有返回值。
func _refresh_battle_health() -> void:
	var battle_name := level_config.level_name if level_config != null else "战斗"
	card_ui.update_enemy_health(battle_name, battle_round_manager.enemy_hp, battle_round_manager.enemy_max_hp,
		battle_round_manager.battle_state == BattleRoundManager.BattleState.DAMAGE_SETTLEMENT)


# 作用：阶段变化更新唯一轮数和开打按钮；phase 为阶段，round_number 为轮数，没有返回值。
func _on_round_phase_changed(phase: int, round_number: int) -> void:
	card_ui.battle_time_left.text = "Round %d%s" % [round_number, " · 结算中" if phase == Global.GamePhase.ROUND_RESOLVE else ""]
	card_ui.get_node("ButtonPanel/AutoBattle").disabled = phase != Global.GamePhase.CARD_PLAY


# 将败方真实血量控件交给特效，等待所有光弹和余辉播完。
func play_round_damage(result: StringName, base_damage: int, sources: Array[Dictionary], on_impact: Callable) -> bool:
	var target: Control = card_ui.enemy_health_bar
	if result == &"enemy":
		var run_hud := get_tree().root.find_child("RunHUD", true, false)
		target = run_hud.get_node_or_null("BisicUI/Hp") as Control if run_hud != null else null
	round_damage_effect.damage_impacted.connect(on_impact)
	round_damage_effect.play(result, base_damage, sources, target)
	var completed: bool = await round_damage_effect.playback_finished
	if is_instance_valid(round_damage_effect) and round_damage_effect.damage_impacted.is_connected(on_impact):
		round_damage_effect.damage_impacted.disconnect(on_impact)
	return completed


func cancel_round_damage() -> void:
	if is_instance_valid(round_damage_effect):
		round_damage_effect.cancel()


# 查看地图时隐藏结算层；动画随战斗一起暂停，返回时继续。
func set_round_damage_visible(value: bool) -> void:
	if is_instance_valid(round_damage_layer):
		round_damage_layer.visible = value
	if battle_finished:
		$GameOver.visible = value


# 作用：兼容旧拖牌入口并交给通用卡牌系统；card 是牌，spawn_position 是世界落点，返回是否成功。
func try_play_unit_card(card: CardInstance, spawn_position: Vector2) -> bool:
	return card_runtime.try_play(card, spawn_position)


# 作用：显示无法出牌的原因；message 为空时清除提示，没有返回值。
func _on_card_feedback(message: String) -> void:
	card_ui.get_node("CardFeedback").text = message
	if not message.is_empty():
		UIAudio.play(&"error")


# 作用：点击开打后结束本轮出牌和部署；没有参数，没有返回值。
func _on_button_pressed() -> void:
	$MouseSlectionController.clear_selection()
	battle_round_manager.start_auto_battle()

# 作用：结束战斗、锁定回合系统，并显示胜负界面。
# 参数 won：true 表示胜利，false 表示失败。
# 返回值：没有返回值。
func finish_battle(won: bool) -> void:
	if battle_finished:
		return

	var had_retained_allies: bool = card_runtime.retain_allies
	get_node("BalanceMetrics").finish(won)
	get_node("RelicRuntime").finish(won)
	battle_finished = true
	battle_round_manager.stop_encounter(won)
	card_runtime.clear_battle_buffs()
	hand_manager.finish_active_cards()
	if had_retained_allies:
		clear_round_units()
	# 非回合结算触发的提前胜负也要回收剩余手牌。
	hand_manager.discard_unused_card(true)
	hand_manager.draw_locked = false

	# 整场结束就恢复基础费用，结算界面和返回地图后的牌库都读取这份原牌数据。
	RunManager.reset_battle_card_costs()

	# 切出自动战斗阶段，阻止单位继续执行正常战斗行为。
	if won:
		Global.game_phase = Global.GamePhase.VICTORY
	else:
		Global.game_phase = Global.GamePhase.DEFEAT

	$GameOver.show_result(won, level_config)
	card_ui.get_node("ButtonPanel/AutoBattle").disabled = true
