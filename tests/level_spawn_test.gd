# 作用：遍历正式关卡与战场，验证配置中的敌人实际出场、可见并登记到战斗系统。
# 覆盖首轮、后续波次、空回合及循环，防止继承场景的编辑显隐状态让整队消失。
extends Node

const SEQUENCE = preload("res://scripts/battle/wave_sequence.gd")
const FLOOR_TRANSITION = preload("res://scripts/world/floor_transition.gd")
var failures: Array[String] = []
var checks := 0
var level_count := 0
var scene_count := 0
var wave_count := 0
var round_count := 0
var report: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


# 从基础波次取得本轮应有的单位快照，独立于实际刷怪器的结果。
func expected_units(config: BattleLevelConfig, actual_round: int) -> Array[Dictionary]:
	var entry := SEQUENCE.resolve(actual_round, config.waves.size(), config.repeat_waves,
		config.repeat_start, config.repeat_end)
	var packed: PackedScene
	if entry.index >= 0:
		packed = config.waves[entry.index]
	elif not config.repeat_waves:
		for i in range(config.waves.size() - 1, -1, -1):
			if config.waves[i] != null:
				packed = config.waves[i]
				break
	var result: Array[Dictionary] = []
	if packed == null:
		return result
	var wave := packed.instantiate()
	for unit in wave.get_children():
		if unit is UnitBase and unit.unit_data != null:
			SEQUENCE.apply_effects(unit, entry.cycle)
			result.append({"position": unit.position, "attack": unit.unit_data.attack,
				"max_hp": unit.unit_data.max_hp, "defence": unit.unit_data.defence})
	wave.free()
	return result


func audit_level(path: String) -> void:
	var config := load(path) as BattleLevelConfig
	check(config != null, path + " 能加载关卡配置")
	if config == null:
		return
	level_count += 1
	check(config.validate().is_empty(), path + " 配置有效：" + config.validate())
	var counts: Array[int] = []
	for i in config.waves.size():
		var packed := config.waves[i]
		if packed == null:
			counts.append(0)
			continue
		wave_count += 1
		var wave := packed.instantiate()
		check(wave is Node2D, "%s 第%d波根节点为 Node2D" % [path, i + 1])
		check(wave.get_child_count() > 0, "%s 第%d波非空场景内有单位" % [path, i + 1])
		counts.append(wave.get_child_count())
		for unit in wave.get_children():
			var label := "%s 第%d波 %s" % [path, i + 1, unit.name]
			check(unit is UnitBase, label + " 是直接子单位")
			if not unit is UnitBase:
				continue
			check(unit.unit_data != null, label + " 绑定单位数据")
			if unit.unit_data == null:
				continue
			check(unit.unit_data.unit_team == "team_b", label + " 属于敌方")
			check(unit.unit_data.max_hp > 0, label + " 生命大于零")
		wave.free()
	get_tree().root.get_node("RunManager").start_new_run()
	var packed_battle := config.battle_scene if config.battle_scene != null else load("res://scenes/battle/battle_scene.tscn") as PackedScene
	var battle := packed_battle.instantiate()
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	var floor_terrain := battle.get_node("Level/NavigationRegion2D")
	check(floor_terrain.has_method("get_floor_map") and floor_terrain.get("floor_maps").size() == 4,
		path + " 正式战场实际接入四层导航")
	await get_tree().physics_frame
	var team: Node2D = battle.get_node("Entities/TeamB")
	var manager: Node = battle.get_node("BattleRoundManager")
	check(battle.get_node("Entities").is_visible_in_tree(), path + " 实体容器可见")
	check(battle.get_node("Entities/TeamA").is_visible_in_tree(), path + " 己方容器可见")
	check(team.is_visible_in_tree(), path + " 敌方容器可见")
	check(battle.card_ui.visible, path + " 手牌及战斗界面可见")
	check(not battle.get_node("GameOver").visible, path + " 开场隐藏结算界面")
	check(manager.current_round == 1 and team.last_round == 1, path + " 首轮阶段信号触发刷怪")
	var end_round := config.waves.size() + 2
	if config.repeat_waves:
		var loop_end := config.waves.size() if config.repeat_end == 0 else config.repeat_end
		end_round = maxi(end_round, loop_end + (loop_end - config.repeat_start + 1) * 2)
	for actual_round in range(1, end_round + 1):
		if actual_round > 1:
			battle.clear_round_units()
			manager.current_round = actual_round
			manager.phase_changed.emit(0, actual_round)
			await get_tree().process_frame
			await get_tree().physics_frame
		round_count += 1
		var expected := expected_units(config, actual_round)
		var label := "%s 第%d回合" % [path, actual_round]
		check(team.get_child_count() == expected.size(), label + " 实际刷怪数符合配置")
		var living: Array[UnitBase] = battle.get_alive_units(&"team_b")
		check(living.size() == expected.size(), label + " 敌人全部登记到战斗系统")
		for i in mini(team.get_child_count(), expected.size()):
			var unit: UnitBase = team.get_child(i)
			var data := expected[i]
			check(unit.position == data.position, label + " 保留配置坐标")
			check(unit.current_health == data.max_hp and unit.unit_data.attack == data.attack
				and unit.unit_data.defence == data.defence, label + " 正确初始化属性及成长")
			check(unit.get_node("AnimatedSprite2D").is_visible_in_tree()
				and unit.get_node("AnimatedSprite2D").sprite_frames != null,
				label + " 单位精灵在树中可见")
		var count_before := team.get_child_count()
		manager.phase_changed.emit(0, actual_round)
		check(team.get_child_count() == count_before, label + " 重复信号不重复出兵")
	report.append({"level": path.get_file().get_basename(), "battle_scene": packed_battle.resource_path,
		"wave_units": counts, "rounds_checked": end_round})
	print("LEVEL_SPAWN_AUDIT: ", report[-1])
	get_tree().root.remove_child(battle)
	battle.free()
	await get_tree().process_frame


func check_hidden_scene_startup() -> void:
	# 故意保留编辑器隐藏状态，验证游戏、F6 与波次实战共用的 _ready 会恢复必要显示层。
	get_tree().root.get_node("RunManager").start_new_run()
	var config := load("res://data/levels/level_107_2.tres") as BattleLevelConfig
	var battle := config.battle_scene.instantiate()
	battle.configure_level(config)
	for path in ["Entities", "Entities/TeamA", "Entities/TeamB", "CardUI"]:
		battle.get_node(path).hide()
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	await get_tree().physics_frame
	var team: Node2D = battle.get_node("Entities/TeamB")
	check(team.get_child_count() == 2, "隐藏场景启动仍生成 level_107_2 新首波两怪")
	for path in ["Entities", "Entities/TeamA", "Entities/TeamB"]:
		check(battle.get_node(path).is_visible_in_tree(), "开场恢复隐藏层 " + path)
	check(battle.card_ui.visible, "开场恢复隐藏战斗界面")
	for unit in team.get_children():
		check(unit.get_node("AnimatedSprite2D").is_visible_in_tree(), "隐藏场景启动恢复怪物显示")
	check(not battle.get_node("GameOver").visible, "显示层恢复后结算界面仍按开场规则隐藏")
	get_tree().root.remove_child(battle)
	battle.free()
	await get_tree().process_frame


func check_map_entry() -> void:
	var run := get_tree().root.get_node("RunManager")
	var route: Dictionary = load("res://scripts/map/fixed_map_config.gd").read_file("res://data/levels/第一章 ·  翠绿原野.json")
	check(route.has("data"), "第一章实际路线全部引用有效")
	if not route.has("data"):
		return
	for level_id in ["level_107_2", "level_108_1", "level_108_2", "level_110_1"]:
		run.selected_map = route.data
		run.start_new_run()
		var session: Node = load("res://scenes/app/game_session.tscn").instantiate()
		get_tree().root.add_child(session)
		await get_tree().process_frame
		var found := false
		for location in session.map_view.locations:
			if location.get("event_id", "") == level_id:
				found = true
		check(found, level_id + " 存在于实际地图节点")
		var entered: bool = session._enter_battle(level_id)
		check(entered, level_id + " 从游戏外壳进入战斗")
		if entered:
			await get_tree().process_frame
			await get_tree().physics_frame
			var battle: Node = session.current_battle
			var enemies: Array[UnitBase] = battle.get_alive_units(&"team_b")
			check(battle.level_config.resource_path.ends_with(level_id + ".tres"), level_id + " 使用指定关卡")
			check(enemies.size() == expected_units(battle.level_config, 1).size(), level_id + " 地图入口首波数量正确")
			check(battle.card_ui.visible and not session.map_layer.visible, level_id + " 战斗界面显示且地图收起")
			check(not battle.hand_manager.hand.is_empty(), level_id + " 首轮正常抽牌")
			for unit in enemies:
				check(unit.get_node("AnimatedSprite2D").is_visible_in_tree(), level_id + " 地图入口怪物可见")
			if level_id == "level_107_2" and "--level-spawn-preview" in OS.get_cmdline_user_args():
				await get_tree().create_timer(0.8).timeout
				await RenderingServer.frame_post_draw
				var image := get_viewport().get_texture().get_image()
				check(image.save_png("res://.maintenance/level_107_2_spawn.png") == OK, "保存 level_107_2 实际战斗截图")
			session._set_battle_map_visible(true)
			check(get_tree().paused and session.map_layer.visible, level_id + " 查看地图暂停战斗")
			session._set_battle_map_visible(false)
			check(not get_tree().paused and battle.card_ui.visible, level_id + " 返回战斗恢复显示")
			check(battle.get_alive_units(&"team_b").size() == enemies.size(), level_id + " 查看地图不会丢失怪物")
		get_tree().root.remove_child(session)
		session.free()
		await get_tree().process_frame
	run.selected_map = {}


func _run() -> void:
	if "--level-spawn-preview" in OS.get_cmdline_user_args():
		await check_map_entry()
		print("LEVEL_SPAWN_PREVIEW: ", "PASS" if failures.is_empty() else str(failures))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	# 检查所有战场，包括尚未被关卡引用的模板，避免复制后再次出现隐形单位。
	var scenes := DirAccess.get_files_at("res://scenes/levels/battles")
	scenes.sort()
	for file in scenes:
		if file.get_extension() != "tscn":
			continue
		var path := "res://scenes/levels/battles/" + file
		var packed := load(path) as PackedScene
		check(packed != null, path + " 可加载")
		if packed == null:
			continue
		scene_count += 1
		var scene := packed.instantiate()
		# 楼层连接组件与战场保存在同一目录，只对完整战场要求实体层和手牌 UI。
		if scene is FLOOR_TRANSITION:
			scene.free()
			continue
		for node_path in ["Entities", "Entities/TeamA", "Entities/TeamB", "CardUI"]:
			var node := scene.get_node_or_null(node_path)
			check(node != null and node.visible, path + " 保存的 " + node_path + " 可见")
		scene.free()
	var levels := DirAccess.get_files_at("res://data/levels")
	levels.sort()
	for file in levels:
		if file.begins_with("level_") and file.get_extension() == "tres":
			await audit_level("res://data/levels/" + file)
	await check_hidden_scene_startup()
	await check_map_entry()
	var output := FileAccess.open("res://.maintenance/level_spawn_audit.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"levels": report, "failures": failures,
			"checks": checks, "scenes": scene_count, "waves": wave_count, "rounds": round_count}, "\t"))
	print("LEVEL_SPAWN_TEST: %d checks; %d levels; %d scenes; %d waves; %d rounds; %s" % [
		checks, level_count, scene_count, wave_count, round_count, "PASS" if failures.is_empty() else "%d failures" % failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
