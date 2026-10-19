# 用正式战场、正式单位和真实三轮结算验证固定区域雷云，不用模拟回合替代游戏流程。
extends Node

const RECIPE := preload("res://data/potions/thunder_cloud.tres")
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _unit(battle: Node2D, ally: bool, point: Vector2) -> UnitBase:
	var unit := load("res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn").instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 1000
	battle.get_node("Entities/TeamA" if ally else "Entities/TeamB").add_child(unit)
	unit.global_position = point
	unit.set_physics_process(false)
	return unit


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _capture(resource_name: String) -> void:
	if "--capture-thunder-cloud" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "res://.maintenance/thunder-cloud-potion/%s.png" % resource_name
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "真实战场截图保存成功")


func _locked_target(items: Node) -> UnitBase:
	return (items._thunder_bolts.back().target as WeakRef).get_ref() as UnitBase


func _check_path(items: Node, target: UnitBase) -> void:
	var shot: Dictionary = items._thunder_bolts.back()
	var bolt: PixelLightning = shot.visual
	var vertices: PackedVector2Array = bolt._paths[0].points
	check(bolt.to_global(vertices[0]).distance_to(shot.source) < 0.001, "实际像素雷线起点精确连接云内出雷点")
	check(bolt.to_global(vertices[-1]).distance_to(items._thunder_hit_position(target)) < 0.001, "实际像素雷线终点精确连接当前目标身体")


func _run() -> void:
	var initial := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	initial.starting_relics.clear()
	initial.starting_potions.clear()
	RunManager.start_new_run(initial)
	check(RECIPE.kind == PotionDefinition.Kind.THUNDER_CLOUD and RECIPE.rounds == 3, "正式资源是三回合雷云")
	check(RECIPE.effect_scene.resource_path == "res://scenes/effects/pixel_thunder_cloud.tscn", "复用原像素雷云场景")
	var shop: Dictionary = load("res://scripts/shop/shop_catalog.gd").read_catalog()
	check(not shop.has("error"), "商店配置有效")
	var in_shop := false
	for entry in shop.get("data", {}).get("potions", []):
		in_shop = in_shop or entry.path == RECIPE.resource_path
	check(in_shop, "正式商店商品池包含雷云药水")
	check(load("res://scripts/events/event_rewards.gd").pool([], "potion").has(RECIPE), "随机药水奖励池包含雷云")
	check(ResourceSaver.save(RECIPE, "user://thunder_cloud_fixture.tres") == OK, "药水资源可保存")
	var restored := ResourceLoader.load("user://thunder_cloud_fixture.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PotionDefinition
	check(restored.rounds == 3 and is_equal_approx(restored.interval, 0.4) and restored.damage == 6, "三回合、0.4秒周期和6点伤害可保存重读")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://thunder_cloud_fixture.tres"))

	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.enemy_max_hp = 999
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	var items = battle.get_node("BattleItems")
	items.set_physics_process(false)
	# 运行器带有平移仍须使用世界落点；画面偏移和缩放不能改变伤害中心。
	items.position = Vector2(37, 23)
	var point := Vector2(1190, 570)
	var ally := _unit(battle, true, point)
	var enemy := _unit(battle, false, point)
	var boundary := _unit(battle, false, point + Vector2(RECIPE.radius, 0))
	var outside := _unit(battle, false, point + Vector2(RECIPE.radius + 3, 0))
	RunManager.add_potion(RECIPE)
	RunManager.add_potion(load("res://data/potions/lightning.tres"))
	var owned: PotionDefinition = RunManager.potions[0]
	check(not items.select_potion(owned), "准备阶段不能施放")
	battle.battle_round_manager.start_auto_battle()
	await get_tree().process_frame
	var hud = get_tree().get_first_node_in_group("run_items_hud")
	check(hud._item_description(owned) == owned.description, "HUD 优先展示已配置的自定义说明")
	var fallback := owned.duplicate() as PotionDefinition
	fallback.description = ""
	check(hud._item_description(fallback).contains("3 回合") and hud._item_description(fallback).contains("6 点") and hud._item_description(fallback).contains("0.4"), "未填写说明时 HUD 从实际配置生成数值说明")
	await _click(hud.potion_row.get_child(0).get_global_rect().get_center())
	check(items.potion == owned and not items.committed, "真实 HUD 点击选择雷云且暂不扣瓶")
	check(not items.try_cast(Vector2(-999, -999)) and RunManager.potions.size() == 2, "无效落点不扣瓶")
	items.clear_effect()
	check(RunManager.potions.size() == 2, "施放前取消保留药水")
	await _click(hud.potion_row.get_child(0).get_global_rect().get_center())
	owned.effect_scale = Vector2(1.3, 1.2)
	owned.effect_offset = Vector2(17, -9)
	await _click(battle.get_canvas_transform() * point)
	check(items.committed and RunManager.potions.size() == 1, "真实战场选点只消耗一瓶")
	check(items.effect_position.is_equal_approx(point), "相机下鼠标选点落在指定世界位置")
	var cloud: PixelThunderCloud = items._thunder_visual
	check(is_instance_valid(cloud) and cloud.global_position.is_equal_approx(point + owned.effect_offset), "配置偏移用于视觉")
	check(cloud.scale == owned.effect_scale and cloud.playing == false, "复用特效实例由药水控制时钟")
	check(cloud.cloud_size == Vector2(224, 116) and not cloud.lightning_enabled, "药水云团宽高加倍且关闭固定落点循环雷")
	check(enemy.current_health == 1000, "施放瞬间不抢先结算伤害")
	check(items.remaining_rounds == 3 and items.status_text().contains("3 回合"), "首次施放显示三回合")
	check(not items.try_cast(point + Vector2(80, 80)), "第二次点击不能移动已经释放的雷云")
	check(not items.select_potion(RunManager.potions[0]), "雷云存在时沿用单瓶使用限制")
	items._physics_process(owned.interval - 0.001)
	check(items._thunder_bolts.is_empty() and enemy.current_health == 1000, "0.4秒之前不释放雷电")
	items._physics_process(0.0011)
	check(items._thunder_bolts.size() == 1, "0.4秒只释放一条锁定雷电")
	var first := _locked_target(items)
	check(first == enemy or first == boundary, "只锁定范围内敌人")
	_check_path(items, first)
	# 发射途中移动目标并加入美术命中标记，云团不能跟着移动，雷线两端必须重新对接。
	var cloud_position := cloud.global_position
	var source: Vector2 = items._thunder_bolts.back().source
	first.global_position = point + Vector2(24, -7)
	var marker := Marker2D.new()
	marker.name = "ThunderHitPoint"
	marker.position = Vector2(4, -26)
	first.add_child(marker)
	items._physics_process(0.02)
	check(first.current_health == 1000, "雷线未到达目标时不抢先扣血")
	_check_path(items, first)
	check(cloud.global_position == cloud_position and (items._thunder_bolts.back().source as Vector2) == source, "目标移动时雷云和出雷点保持固定")
	var impact := (items._thunder_bolts.back().visual as PixelLightning).strike_duration
	items._physics_process(impact - 0.02 + 0.001)
	check(first.current_health == 994 and enemy.current_health + boundary.current_health == 1994, "一次只对锁定单位造成6点伤害，不伤害旁边单位")
	check(ally.current_health == 1000 and outside.current_health == 1000, "不伤害友军或范围外敌人")
	await _capture("battle-strike")
	marker.free()
	items._physics_process(0.0)
	_check_path(items, first)
	items._physics_process(items._thunder_next_cast - items._thunder_elapsed)
	var second := _locked_target(items)
	check(second != first and (second == enemy or second == boundary), "范围内两个敌人轮流锁定")
	items._physics_process(impact + 0.001)
	check(enemy.current_health == 994 and boundary.current_health == 994, "第二击只命中另一个敌人")
	items._physics_process(owned.interval)
	check(first.current_health == 988 and second.current_health == 994, "第三击轮转回首个目标，每次仍是6点单体伤害")
	# 全部移出范围：连续检查也不能生成空雷或云内闪光。
	enemy.global_position = point + Vector2(300, 0)
	boundary.global_position = point + Vector2(310, 0)
	var sequence: int = items._thunder_sequence
	items._physics_process(owned.interval * 5)
	check(items._thunder_bolts.is_empty() and items._thunder_sequence == sequence, "空范围连续多个周期也不释放雷电")
	check(is_zero_approx(float(cloud.get_node("Cloud").material.get_shader_parameter("flash_amount"))), "空范围云团不产生放电闪光")
	check(not cloud.get_lightning().visible, "原组合内部的固定落点雷始终关闭")
	outside.global_position = point + Vector2(20, 0)
	items._physics_process(owned.interval)
	check(outside.current_health == 994, "敌人进入空范围后恢复索敌落雷，不补发空范围期间伤害")
	check(items.effect_position.is_equal_approx(point) and cloud.global_position.is_equal_approx(point + owned.effect_offset), "敌人移动不改变雷云固定位置")
	var elapsed := cloud.get_elapsed()
	get_tree().paused = true
	items._physics_process(30.0)
	check(cloud.get_elapsed() == elapsed and outside.current_health == 994, "暂停冻结雷云画面和伤害")
	get_tree().paused = false
	items._physics_process(owned.interval * 3)
	check(outside.current_health == 976, "低帧率跨过三周期仍各命中一次，每次6点")
	# 发射后离开范围或退场，在触地前取消，禁止旧引用和范围外伤害。
	items._physics_process(items._thunder_next_cast - items._thunder_elapsed)
	check(_locked_target(items) == outside, "离开测试前雷电已锁定唯一目标")
	outside.global_position = point + Vector2(320, 0)
	items._physics_process(impact + 0.001)
	check(items._thunder_bolts.is_empty() and outside.current_health == 976, "目标在触地前离开范围，取消雷击")
	var departing := _unit(battle, false, point)
	items._physics_process(items._thunder_next_cast - items._thunder_elapsed)
	check(_locked_target(items) == departing, "新进入单位能够被锁定")
	departing.get_parent().remove_child(departing)
	departing.queue_free()
	items._physics_process(impact + 0.001)
	check(items._thunder_bolts.is_empty(), "发射途中目标退场安全取消雷线")

	# 真正结束三轮交锋，观察清兵、抽牌和下一轮重新部署后的同一个雷云实例。
	for round_number in range(1, 4):
		elapsed = cloud.get_elapsed()
		for foe in battle.get_alive_units(&"team_b"):
			foe.take_effect_damage(99999)
		battle.battle_round_manager.finish_unit_combat()
		items._physics_process(30.0)
		if round_number < 3:
			check(items.remaining_rounds == 3 - round_number and cloud.get_elapsed() == elapsed, "结算扣除当回合且停止放电")
			battle.battle_round_manager.battle_round_ended.emit()
			check(items.remaining_rounds == 3 - round_number, "同回合重复通知不额外消耗期限")
		await battle.battle_round_manager.settlement_finished
		await get_tree().process_frame
		check(battle.battle_round_manager.current_round == round_number + 1, "真实结算推进下一轮")
		if round_number < 3:
			check(items.potion == owned and items._thunder_visual == cloud, "回合清兵后雷云仍是同一个实例")
			check(cloud.global_position.is_equal_approx(point + owned.effect_offset), "准备阶段保留世界位置")
			items._physics_process(30.0)
			check(cloud.get_elapsed() == elapsed, "准备阶段不积累伤害时间")
			_unit(battle, true, Vector2(450, 500))
			enemy = _unit(battle, false, point)
			battle.battle_round_manager.start_auto_battle()
			items._physics_process(owned.interval)
			check(enemy.current_health == 994, "下一回合重新生成的敌人受到6点锁定雷击")
		else:
			check(items.potion == null and items._thunder_visual == null and not is_instance_valid(cloud), "第三轮结束清理云与药水状态")
	check(RunManager.potions.size() == 1 and hud.potion_row.get_child_count() == 1, "三回合仅消耗原来的雷云瓶")

	# 晚回合施放同样按相对三回合计算；整场结束无需等待三回合。
	battle.battle_round_manager.current_round = 8
	_unit(battle, true, Vector2(450, 500))
	_unit(battle, false, point)
	battle.battle_round_manager.start_auto_battle()
	RunManager.add_potion(RECIPE)
	owned = RunManager.potions.back()
	check(items.select_potion(owned) and items.try_cast(point), "第八回合仍可施放雷云")
	check(items.remaining_rounds == 3 and items._cloud_end_round == 10, "三回合期限相对于实际施放轮数")
	cloud = items._thunder_visual
	battle.finish_battle(false)
	check(items.potion == null and cloud.is_queued_for_deletion(), "整场结束立即清理雷云")
	battle.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(RunManager.item_battle) and not is_instance_valid(cloud), "离开战场无遗留入口或视觉")
	var fresh := RECIPE.effect_scene.instantiate() as PixelThunderCloud
	check(fresh.playing and fresh.auto_start and fresh.cycle_duration == 2.4 and fresh.scale == Vector2.ONE, "玩法只修改实例，原雷云配置保持不变")
	fresh.free()
	# 专用试玩也走同一个药水入口；它的推进按钮必须触发真实回合结算。
	var demo = load("res://examples/scenes/thunder_cloud_potion_demo.tscn").instantiate()
	get_tree().root.add_child(demo)
	await get_tree().process_frame
	items = demo.get_node("BattleItems")
	items.set_physics_process(false)
	check(demo.get_alive_units(&"team_a").size() == 1 and demo.get_alive_units(&"team_b").size() == 3, "试玩场景生成静止参照目标")
	hud = get_tree().get_first_node_in_group("run_items_hud")
	await _click(hud.potion_row.get_child(0).get_global_rect().get_center())
	point = Vector2(1190, 580)
	await _click(demo.get_canvas_transform() * point)
	check(items._has_committed_cloud(), "专用试玩能通过真实鼠标选择并施放雷云")
	cloud = items._thunder_visual
	items._physics_process(RECIPE.interval + cloud.get_lightning().strike_duration + 0.001)
	await _capture("demo")
	var foes: Array[UnitBase] = demo.get_alive_units(&"team_b")
	check(foes[0].current_health + foes[1].current_health == 994 and foes[2].current_health == 500, "试玩每次只命中范围内一个敌人，范围外敌人不受伤")
	items._physics_process(RECIPE.interval)
	check(foes[0].current_health == 494 and foes[1].current_health == 494, "试玩第二次落雷轮流攻击另一个目标")
	# 连续真实施放覆盖底部四个云团，验证每一处的实际雷线与云内闪光一致。
	var seen_sources: Array[int] = []
	var bottom_points := [Vector2(-29, 11), Vector2(-9, 13), Vector2(9, 14), Vector2(26, 16)]
	var cloud_position_before := cloud.global_position
	for strike in 32:
		items._physics_process(items._thunder_next_cast - items._thunder_elapsed + impact + 0.001)
		check(items._thunder_bolts.size() == 1, "随机出雷点仍然每次只生成一条单体雷电")
		var shot: Dictionary = items._thunder_bolts.back()
		var index: int = shot.source_index
		check(index >= 0 and index < 4 and shot.flash_position == bottom_points[index], "出雷位置只从底部四块云团中选择")
		var expected := cloud.to_global(Vector2(0, -cloud.cloud_altitude) + bottom_points[index] * cloud.cloud_size / Vector2(112, 58))
		check((shot.source as Vector2).distance_to(expected) < 0.001, "随机云块的出雷点正确使用云团尺寸和世界变换")
		check(cloud.get_node("Cloud").material.get_shader_parameter("flash_position") == bottom_points[index], "实际闪光位于本次出雷的云块")
		_check_path(items, _locked_target(items))
		if not seen_sources.has(index):
			seen_sources.append(index)
			await _capture("bottom-cloud-%d" % index)
	check(seen_sources.size() == 4, "连续攻击随机覆盖底部全部四块云团")
	check(cloud.global_position == cloud_position_before, "更换出雷云块不会移动整片雷云")
	for round_number in range(1, 4):
		demo._end_demo_round()
		await demo.battle_round_manager.settlement_finished
		await get_tree().process_frame
		await get_tree().process_frame
		check(demo.battle_round_manager.current_round == round_number + 1 and demo.get_alive_units(&"team_b").size() == 3, "试玩推进真实回合并刷新新目标")
	check(items.potion == null, "试玩第三回合结束后雷云消失")
	demo.queue_free()
	await get_tree().process_frame
	print("THUNDER_CLOUD_POTION_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
