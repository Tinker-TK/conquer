# 宝箱回归：真实地图/会话/HUD、只读查看、防重复发奖、遗物生效与奖励池耗尽。
extends SceneTree

var CONFIG
var REWARDS
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.maintenance/treasure-" + name + ".png")

func fixture() -> Dictionary:
	return {"schema_version": 1, "mode": "fixed", "name": "宝箱测试", "floors": 4,
		"starting_ids": ["chest_a"], "locations": [
			{"id": "chest_a", "title": "遗物宝箱", "type": 4, "floor": 1, "map_pos": {"x": 0.5, "y": 0.93}, "next": ["chest_b"]},
			{"id": "chest_b", "title": "遗物宝箱", "type": 4, "floor": 2, "map_pos": {"x": 0.5, "y": 0.64}, "next": ["chest_c"]},
			{"id": "chest_c", "title": "遗物宝箱", "type": 4, "floor": 3, "map_pos": {"x": 0.5, "y": 0.36}, "next": ["boss"]},
			{"id": "boss", "title": "Boss", "type": 3, "event_id": "level_002", "floor": 4, "map_pos": {"x": 0.5, "y": 0.07}, "next": []}]}

func _run() -> void:
	CONFIG = load("res://scripts/map/fixed_map_config.gd")
	REWARDS = load("res://scripts/events/event_rewards.gd")
	var run = root.get_node("RunManager")
	root.size = Vector2i(1920, 1080)
	# 隔离开局赠送与外部导入配置，并补齐烟测关卡的内存波次。
	var level: Resource = load("res://data/levels/level_002.tres")
	if level.waves.is_empty():
		level.waves.append(load("res://scenes/levels/waves/wave_01.tscn"))
	var data := fixture()
	check(CONFIG.parse_text(JSON.stringify(data)).has("data"), "无需事件或关卡字段的宝箱可导入")
	var invalid := data.duplicate(true)
	invalid.locations[0].type = 99
	check(not CONFIG.validate(invalid).is_empty(), "非法类型仍被拒绝")
	var inherited: Dictionary = data.locations[0].duplicate(true)
	inherited.event = CONFIG.default_event("campfire")
	inherited.event_source = "catalog"
	inherited.event_id = "campfire"
	check(CONFIG.event_content(inherited).choices[0].effect.type == "random_relic", "改为宝箱后不会沿用休息奖励")
	var initial: Resource = load("res://data/run/run_start_data.tres").duplicate(true)
	initial.starting_relics.clear()
	run.selected_map = data
	run.start_new_run(initial)
	var game = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var map = game.map_view
	var panel = map.event_panel
	check(map.locations[0].type == map.NodeType.TREASURE and map.locations[0].event_id == "", "导入宝箱转换为运行节点")
	check(map.node_views.chest_a.icon_texture != null and map.has_node("HUD/TreasureLegend"), "地图宝箱有独立图标与图例")
	map._on_legend_entered(map.NodeType.TREASURE)
	map._on_legend_exited()
	await capture("map")
	map.set_view_only(true)
	map._on_node_enter_requested(map.node_views.chest_a)
	check(map.pending_id.is_empty() and run.relics.is_empty(), "只读地图不能开箱")
	map.set_view_only(false)
	map._on_node_selection_started(map.node_views.chest_a)
	map._on_node_enter_requested(map.node_views.chest_a)
	check(panel.treasure_mode and panel.chest_button.visible and run.relics.is_empty(), "进入宝箱后等待玩家点击才发奖")
	check(not map._can_enter("chest_b"), "宝箱处理中锁住后续路线")
	await capture("closed")
	var session = panel.session
	game._on_map_pressed()
	panel._open_treasure()
	check(not panel.visible and run.relics.is_empty(), "查看地图时隐藏的宝箱不能发奖")
	game._on_map_pressed()
	check(panel.session == session and panel.visible, "返回保留同一宝箱会话")
	# 使用真实按钮的 pressed 信号，随后模拟快速重复点击。
	panel.chest_button.pressed.emit()
	if panel.get_node_or_null("RelicChoice") != null:
		var picker = panel.get_node("RelicChoice")
		check(run.relics.is_empty(), "宝箱三选一确认前不发放")
		picker.selected.emit(0)
		picker.queue_free()
	check(run.relics.size() == 1 and panel.session.claimed, "点击宝箱恰好获得一件随机遗物")
	check(run.relics[0].kind != RelicDefinition.Kind.BASE_DEFENCE, "停用遗物不会进入随机池")
	check(panel.chest_button.disabled and panel.chest_button.texture_normal == panel.CHEST_OPEN, "开箱后切换已打开外观")
	panel._open_treasure()
	panel.choice_1.pressed.emit()
	check(run.relics.size() == 1 and panel.session.claim().has("error"), "连续点击与重复结算不会再次发奖")
	game._on_map_pressed()
	game._on_map_pressed()
	check(panel.session == session and run.relics.size() == 1, "开箱后查看地图不会重抽")
	await capture("opened")
	check(not run.completed_ids.has("chest_a"), "奖励展示完点击继续前不推进")
	panel._finish()
	panel._finish()
	check(run.current_id == "chest_a" and run.completed_ids.size() == 1 and map._can_enter("chest_b"), "继续后插旗并解锁下一站")
	map._on_node_enter_requested(map.node_views.chest_a)
	check(map.pending_id.is_empty() and run.relics.size() == 1, "已完成宝箱不可重进领奖")
	# 填满除最后一件以外的遗物，验证去重以及实际永久效果。
	var pool: Array[Resource] = REWARDS.pool([], "relic")
	var missing: Resource
	for relic in pool:
		if relic.id != run.relics[0].id and relic.rarity != RelicDefinition.Rarity.BOSS:
			missing = relic
	for relic in pool:
		if relic.id != missing.id:
			run.add_relic(relic)
	var count_before: int = run.relics.size()
	var hp_before: int = run.max_hp
	var energy_before: int = run.bonus_energy_max
	map._on_node_selection_started(map.node_views.chest_b)
	map._on_node_enter_requested(map.node_views.chest_b)
	panel.choice_1.pressed.emit()
	check(run.relics.size() == count_before + 1 and panel.session.prepared.reward.id == missing.id, "只剩一件时必定获得未拥有遗物")
	if missing.kind == RelicDefinition.Kind.BASE_HEALTH:
		check(run.max_hp == hp_before + missing.amount, "生命遗物立即生效")
	elif missing.kind == RelicDefinition.Kind.MAX_ENERGY:
		check(run.bonus_energy_max == energy_before + missing.amount, "能量遗物立即生效")
	panel._finish()
	map._on_node_selection_started(map.node_views.chest_c)
	map._on_node_enter_requested(map.node_views.chest_c)
	panel.chest_button.pressed.emit()
	check(panel.session.claimed and run.relics.size() == pool.size(), "收集齐后不再发放重复遗物")
	check("都已收集" in panel.description_label.text and panel.result_box.visible, "空奖励池给出说明并可继续")
	await capture("exhausted")
	panel._finish()
	check(map._can_enter("boss") and run.completed_ids.size() == 3, "奖励池耗尽不会卡住路线")
	# 开启另一种事件会清理宝箱外观，预览也不写入本局。
	panel.open_treasure(CONFIG.treasure_event(), null, true)
	panel._open_treasure()
	if panel.get_node_or_null("RelicChoice") != null:
		var picker = panel.get_node("RelicChoice")
		picker.selected.emit(0)
		picker.queue_free()
	check(panel.session.claimed and run.relics.size() == pool.size(), "宝箱预览不发放真实奖励")
	panel.open_content(CONFIG.default_event("campfire"), run)
	check(not panel.treasure_mode and not panel.chest_button.visible, "普通事件不会残留宝箱按钮")
	game.queue_free()
	await process_frame
	run.selected_map = {}
	run.start_new_run(initial)
	var fallback = load("res://scenes/map/map.tscn").instantiate()
	root.add_child(fallback)
	await process_frame
	var chests := 0
	for location in fallback.locations:
		if location.type == fallback.NodeType.TREASURE:
			chests += 1
	check(chests == 2 and fallback.locations.size() == 19, "内置第五层提供宝箱，路线长度保持十层")
	fallback.queue_free()
	await process_frame
	print("TREASURE_NODE_TEST: %d checks; %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)
