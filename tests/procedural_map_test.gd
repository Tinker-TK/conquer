# 真正的 Godot 生成、配置校验、房间分发、独立进程读档与批量种子回归。
extends SceneTree

const RULES = preload("res://scripts/map/route_generation_config.gd")
const GENERATOR = preload("res://scripts/map/procedural_map_generator.gd")
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error(message)

func _structure(map: Dictionary) -> bool:
	var by_id: Dictionary = {}
	for node: Dictionary in map.locations:
		by_id[node.id] = node
		if int(node.floor) == 1 and int(node.type) != 0:
			return false
		if int(node.floor) == 9 and int(node.type) != 4:
			return false
		if int(node.floor) == 15 and int(node.type) != 2:
			return false
		if (int(node.type) == 3) != node.next.is_empty():
			return false
		if int(node.type) == 6 and int(node.floor) < 6:
			return false
	var reached: Dictionary = {}
	var pending: Array = map.starting_ids.duplicate()
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if reached.has(id):
			continue
		reached[id] = true
		for target in by_id[id].next:
			if not by_id.has(target) or int(by_id[target].floor) != int(by_id[id].floor) + 1:
				return false
			if int(by_id[target].type) != 3 and absi(int(by_id[target].column) - int(by_id[id].column)) > 1:
				return false
			if int(by_id[target].type) != 3 and int(by_id[target].column) != int(by_id[id].column):
				var other_id := "floor_%02d_%02d" % [int(by_id[id].floor), int(by_id[target].column) + 1]
				if by_id.has(other_id):
					for other_target in by_id[other_id].next:
						if int(by_id[other_target].column) == int(by_id[id].column):
							return false
			pending.append(target)
	return reached.size() == by_id.size() and int(map.floors) == 16 and not map.starting_ids.is_empty()

func _run() -> void:
	var run = root.get_node("RunManager")
	if "--verify-random-save" in OS.get_cmdline_user_args():
		# 此进程不读取新局规则，旧地图、问号房结果及元数据仍能完整恢复。
		run.generation_config_path = "res://missing-rules.json"
		check(run.load_saved_run().is_empty(), "独立进程恢复随机地图")
		check(run.map_seed == "SAVE-SEED" and run.current_act == 2 and run.active_act_maps.size() == 3, "恢复种子和三幕快照")
		check(run.map_generator_version == 1 and run.map_config_version == 1 and run.map_difficulty == "normal", "恢复生成器和配置版本")
		check(not run.resolved_rooms.is_empty() and not run.pending_route_node.is_empty(), "恢复问号结果与未完成节点锁定")
		for location: Dictionary in run.active_map.locations:
			if str(location.id) == run.pending_route_node:
				check(run.resolve_map_location(location) == run.route_location(str(location.id)), "重进问号沿用存档结果")
		print("RANDOM_SAVE_RESTART_PASS: %d checks; failures=%s" % [checks, failures])
		quit(0 if failures.is_empty() else 1)
		return
	var loaded: Dictionary = RULES.read_file()
	check(not loaded.has("error"), "随机规则与所有遭遇覆盖合法：" + str(loaded.get("error", "")))
	if loaded.has("error"):
		quit(1)
		return
	var rules: Dictionary = loaded.data
	var encounters: Dictionary = loaded.encounters
	var one: Dictionary = GENERATOR.new().generate("SAME-SEED", 1, rules, "normal", encounters)
	var two: Dictionary = GENERATOR.new().generate("SAME-SEED", 1, rules, "normal", encounters)
	check(one == two, "相同种子逐字段生成相同地图")
	check(CONFIG.validate(one).is_empty() and _structure(one), "16层、强制行、相邻层和可达性")
	check(one != GENERATOR.new().generate("OTHER-SEED", 1, rules, "normal", encounters), "不同种子改变路线")
	check(one != GENERATOR.new().generate("SAME-SEED", 2, rules, "normal", encounters), "各幕使用独立地图流")
	check(one.generation.pruned_nodes > 0, "按类型序列实际剪除了节点")
	var elite_count := 0
	var unknown_count := 0
	for node: Dictionary in one.locations:
		if int(node.type) == 6:
			elite_count += 1
			check(node.battle_rewards == (load("res://data/battle_rewards/elite.tres") as BattleRewardConfig).to_content(), "精英使用独立奖励")
		if int(node.type) == 7:
			unknown_count += 1
			check(CONFIG.unknown_error(node).is_empty(), "问号房所有候选可执行")
	check(elite_count == 5 and unknown_count >= 10, "普通难度精英/问号配额")
	var hard: Dictionary = GENERATOR.new().generate("SAME-SEED", 1, rules, "hard", encounters)
	check(hard.locations.filter(func(n): return int(n.type) == 6).size() == 8, "困难难度8个精英")
	print("RANDOM_MAP_STAGE: deterministic generation and encounter rules")
	var bad := rules.duplicate(true)
	bad.rooms = 3
	check(not RULES.validate(bad).is_empty(), "拒绝不支持的层数")
	var broken := encounters.duplicate(true)
	broken.rules = []
	check(not load("res://scripts/map/encounter_catalog.gd").validate(broken, ["normal", "hard"]).is_empty(), "拒绝空遭遇池")
	check(run.reload_map_selection().is_empty() and run.selected_map.mode == "procedural", "正式默认入口选择随机征途")
	check(run.start_new_run(null, "save-seed", "normal").is_empty(), "创建三幕随机征途")
	check(run.active_act_maps.size() == 3 and run.map_seed == "SAVE-SEED", "开局冻结三幕及规范化种子")
	var frozen: Array = run.active_act_maps.duplicate(true)
	var before: Resource = run.create_save_data()
	check(not run.start_new_run(null, "invalid", "missing").is_empty() and run.active_act_maps == frozen, "失败建局保留原征途")
	# 不依赖概率命中，分别强制五种问号结果并走真实地图入口。
	# 同时模拟工坊 JSON 往返，候选中的数字会变成 float。
	run.active_map = run._snapshot_map(JSON.parse_string(JSON.stringify(run.active_map, "", true, true)))
	var map = load("res://scenes/map/map.tscn").instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	var unknowns: Array = run.active_map.locations.filter(func(n): return int(n.type) == 7)
	for kind in [0, 1, 4, 5, 6]:
		var location: Dictionary = unknowns.pop_front()
		var odds := {"battle": 0.0, "elite": 0.0, "shop": 0.0, "treasure": 0.0}
		if kind != 1:
			odds[{0: "battle", 4: "treasure", 5: "shop", 6: "elite"}[kind]] = 1.0
		run.active_map.generation.unknown_base_odds = odds
		run.unknown_room_odds.clear()
		run.pending_route_node = ""
		run.current_id = ""
		var result: Dictionary = run.resolve_map_location(location)
		check(int(result.type) == kind and result.source_type == 7, "问号解析类型 %d" % kind)
		check(typeof(result.type) == TYPE_INT, "JSON 问号结果转换为枚举整数 %d" % kind)
		check(result == run.resolve_map_location(location), "问号重入不重掷 %d" % kind)
		map.resume_after_battle()
		check(map._can_enter(str(location.id)), "恢复只允许进入未完成问号")
		var requested: Array = []
		var callback := func(id): requested.append(id)
		map.battle_requested.connect(callback)
		map._on_node_enter_requested(map.node_views[location.id])
		if kind in [0, 6]:
			check(requested == [result.event_id] and run.pending_event_id == result.event_id, "问号分发战斗 %d" % kind)
		elif kind == 5:
			check(map.shop_panel.visible and run.shop_visits.has(location.id), "问号分发商店")
			map.shop_panel.closed.emit()
			check(run.completed_ids.has(location.id), "问号商店关闭正确推进")
		else:
			check(map.event_panel.visible, "问号分发事件/宝箱 %d" % kind)
		map.battle_requested.disconnect(callback)
		map.event_panel.hide()
		map.shop_panel.hide()
		map.cancel_pending_battle()
	map.free()
	print("RANDOM_MAP_STAGE: all five unknown-room dispatches")
	# 元数据保存与跨幕不会重新生成；配置更改不影响已冻结的后续幕。
	run.start_new_run(null, "SAVE-SEED", "normal")
	var frozen_second: Dictionary = run.active_act_maps[1].duplicate(true)
	run.complete_location(str(run.map_terminal_ids[0]))
	check(run.advance_act().is_empty() and run.current_act == 2 and run.active_map == frozen_second, "跨幕恢复开局快照")
	var unknown: Dictionary = run.active_map.locations.filter(func(n): return int(n.type) == 7)[0]
	run.resolve_map_location(unknown)
	check(run.save_run(true).is_empty(), "保存问号房及地图元数据")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/procedural_map_test.gd", "--", "--no-mcp-server", "--verify-random-save"], output, true)
	check(code == 0 and "RANDOM_SAVE_RESTART_PASS" in "\n".join(output) and "failures=[]" in "\n".join(output), "独立进程在规则文件不可用时恢复快照")
	print("RANDOM_MAP_STAGE: snapshot save and cross-process restore")
	# 旧存档没有新增字段时仍按原地图恢复。
	for key in run.MAP_SAVE_KEYS:
		before.state.erase(key)
	ResourceSaver.save(before, run.SAVE_PATH)
	check(run.load_saved_run().is_empty() and run.map_seed.is_empty(), "旧存档缺少种子字段仍可读")
	var workshop = load("res://addons/map_editor/editor.gd").new()
	root.add_child(workshop)
	await process_frame
	workshop.route_seed_input.text = "SAME-SEED"
	workshop._generate_random_route()
	check(workshop.kind_input.item_count == 8 and workshop.doc.data.generation.seed == "SAME-SEED", "原生工坊支持八种节点和按种子生成")
	check(workshop.doc.save("user://random_route_roundtrip.json"), "随机路线可保存供固定路线试玩")
	var roundtrip: Dictionary = CONFIG.read_file("user://random_route_roundtrip.json")
	check(not roundtrip.has("error") and roundtrip.data == JSON.parse_string(JSON.stringify(workshop.doc.data, "", true, true)), "编辑器往返保留问号候选和生成元数据")
	workshop.free()
	# 真实 GameSession 加载精英关卡、展示胜利奖励并返回随机地图。
	run.start_new_run(load("res://data/run/run_start_data.tres"), "BATTLE-SEED", "normal")
	var elite: Dictionary = run.active_map.locations.filter(func(n): return int(n.type) == 6)[0]
	var transition := root.get_node("SceneTransition")
	var old_motion: bool = transition.reduced_motion
	transition.reduced_motion = true
	var game = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.map_view._on_node_enter_requested(game.map_view.node_views[elite.id])
	var deadline := Time.get_ticks_msec() + 15000
	while transition.busy:
		assert(Time.get_ticks_msec() < deadline, "精英战斗切场超时")
		await process_frame
	check(is_instance_valid(game.current_battle) and run.is_elite_battle(), "精英通过真实地图进入战斗")
	check(game.current_battle.level_config == game.resolve_level(str(elite.event_id)), "真实战斗加载遭遇池指定的精英资源")
	game.current_battle.finish_battle(true)
	await process_frame
	var result = game.current_battle.get_node("GameOver")
	check(result.reward_session.offers[0].amount == elite.battle_rewards.gold, "精英胜利发放冻结的节点奖励")
	result.reward_session.skip_cards()
	result._on_button_pressed()
	await process_frame
	await process_frame
	while transition.busy:
		assert(Time.get_ticks_msec() < deadline, "精英返回地图超时")
		await process_frame
	check(run.completed_ids.has(elite.id) and not run.chapter_cleared and not is_instance_valid(game.current_battle), "精英奖励后返回同一地图并正确推进")
	game.free()
	transition.reduced_motion = old_motion
	var samples := 10000 if "--map-sweep" in OS.get_cmdline_user_args() else 100
	var started := Time.get_ticks_msec()
	var removed := 0
	var shortfalls := 0
	for seed_index in samples:
		var sample: Dictionary = GENERATOR.new().generate("SWEEP-%d" % seed_index, seed_index % 3 + 1, rules, "normal" if seed_index % 2 == 0 else "hard", encounters, seed_index < 100)
		check(_structure(sample), "批量种子结构 %d" % seed_index)
		if seed_index < 100:
			check(CONFIG.validate(sample).is_empty(), "批量内容与资源校验 %d" % seed_index)
		removed += int(sample.generation.pruned_nodes)
		if not sample.generation.quota_shortfalls.is_empty():
			shortfalls += 1
		if seed_index % 500 == 499:
			print("RANDOM_MAP_SWEEP_PROGRESS: %d/%d" % [seed_index + 1, samples])
	print("RANDOM_MAP_SWEEP: samples=%d; elapsed_ms=%d; removed=%d; soft_quota_shortfalls=%d" % [samples, Time.get_ticks_msec() - started, removed, shortfalls])
	print("PROCEDURAL_MAP_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
