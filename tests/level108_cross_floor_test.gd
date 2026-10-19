# 保存重载后检查第5回合四只一层近战怪实际上楼并命中，同时让真实士兵逐个往返四处坡道。
extends SceneTree

var checks := 0
var failures: Array[String] = []
var hits: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error(label)


func _world_position(node: Node2D) -> Vector2:
	var transform := Transform2D.IDENTITY
	var current: Node = node
	while current != null:
		if current is Node2D:
			transform = current.transform * transform
		current = current.get_parent()
	return transform.origin


func _saved_endpoints(battle: Node, label: String) -> void:
	var expected_from: Array[Vector2] = [Vector2(112, 375), Vector2(1808, 438), Vector2(1808, 955), Vector2(112, 887)]
	var expected_to: Array[Vector2] = [Vector2(176, 375), Vector2(1744, 438), Vector2(1744, 955), Vector2(176, 887)]
	var links := battle.get_node("Level/NavigationRegion2D/LayerChange/1-2").get_children()
	check(links.size() == 4, label + "：四处坡道")
	for index in links.size():
		check(_world_position(links[index].get_node("From")).is_equal_approx(expected_from[index]), label + "：一层入口被保留")
		check(_world_position(links[index].get_node("To")).is_equal_approx(expected_to[index]), label + "：二层出口被保留")


func _roundtrip() -> void:
	var source: Node = load("res://scenes/levels/battles/battle_007.tscn").instantiate()
	_saved_endpoints(source, "原场景")
	# 保存地形及其完整实例关系，不把战斗 UI 自带的持久信号重复打包进测试夹具。
	var fixture := Node2D.new()
	fixture.name = "RoundtripFixture"
	var level := source.get_node("Level")
	source.remove_child(level)
	source.free()
	fixture.add_child(level)
	level.owner = fixture
	for child in level.find_children("*", "", true, false):
		if child.owner == null:
			child.owner = fixture
	var saved := PackedScene.new()
	check(saved.pack(fixture) == OK, "重新打包战场地形")
	fixture.free()
	var path := "user://level108_cross_floor_roundtrip.tscn"
	check(ResourceSaver.save(saved, path) == OK, "将战场写入临时场景")
	var reloaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	check(reloaded != null, "从磁盘重新读取战场")
	if reloaded != null:
		var instance := reloaded.instantiate()
		_saved_endpoints(instance, "保存重载后")
		instance.free()
	DirAccess.remove_absolute(path)


func _battle(round_number: int) -> Node2D:
	root.get_node("RunManager").start_new_run()
	var config := load("res://data/levels/level_108_1.tres").duplicate() as BattleLevelConfig
	config.cards_per_round = 0
	if round_number == 0:
		config.waves = [] # 测试副本不清空共享资源的数组，后续仍需读取正式第5波。
	var battle: Node2D = config.battle_scene.instantiate()
	battle.configure_level(config)
	battle.get_node("BattleRoundManager").first_round = maxi(round_number, 1)
	root.add_child(battle)
	return battle


func _wait_navigation(battle: Node) -> void:
	var terrain := battle.get_node("Level/NavigationRegion2D")
	for frame in 180:
		await physics_frame
		if terrain.is_walkable(Vector2(112, 887), 1) and terrain.is_walkable(Vector2(520, 810), 2):
			return
	check(false, "两层导航完成同步")


func _soldier_stairs() -> void:
	var battle := _battle(0)
	await _wait_navigation(battle)
	var cases := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle_007_movement.json")) as Dictionary
	for passage: Dictionary in cases.passages:
		for reverse in [false, true]:
			var lower := Vector2(passage.lower_start[0], passage.lower_start[1])
			var upper := Vector2(passage.upper_goal[0], passage.upper_goal[1])
			var start := upper if reverse else lower
			var finish := lower if reverse else upper
			var floor_id := 1 if reverse else 2
			var soldier = load("res://scenes/units/soldier.tscn").instantiate()
			soldier.position = battle.get_node("Entities/TeamA").to_local(start)
			soldier.floor_id = 2 if reverse else 1
			soldier.arrival_distance = 5.0
			battle.get_node("Entities/TeamA").add_child(soldier)
			soldier.target_position = finish
			soldier.move_floor_id = floor_id
			for frame in 1200:
				await physics_frame
				if soldier.floor_id == floor_id and soldier.global_position.distance_to(finish) < 8.0:
					break
			check(soldier.floor_id == floor_id and soldier.global_position.distance_to(finish) < 8.0,
				"士兵%s %s 实际到达：%s" % ["下坡" if reverse else "上坡", passage.path, soldier.global_position])
			soldier.free()
			await physics_frame
	battle.battle_finished = true
	battle.free()
	await process_frame


func _record_hit(_target, name: String) -> void:
	hits[name] = int(hits.get(name, 0)) + 1


func _fifth_round() -> void:
	var battle := _battle(5)
	await _wait_navigation(battle)
	var terrain := battle.get_node("Level/NavigationRegion2D")
	var ally = load("res://scenes/units/soldier.tscn").instantiate()
	ally.position = battle.get_node("Entities/TeamA").to_local(Vector2(520, 810))
	ally.floor_id = 2
	ally.unit_data = ally.unit_data.duplicate()
	ally.unit_data.max_hp = 10000
	battle.get_node("Entities/TeamA").add_child(ally)
	# 固定二层活目标，确保测到怪物主动上楼；不让己方先下楼接走怪物。
	ally.set_physics_process(false)
	ally.navigation_agent_2d.stop_navigation()
	var lower_units: Array[Node] = []
	var upper_units: Array[Node] = []
	var climbed: Dictionary = {}
	for unit in battle.get_node("Entities/TeamB").get_children():
		if not unit is CharacterBody2D:
			continue
		unit.attack_landed.connect(_record_hit.bind(str(unit.name)))
		if unit.floor_id != 1:
			upper_units.append(unit)
			continue
		lower_units.append(unit)
		var route: Dictionary = terrain.route(unit.global_position, 1, ally.global_position, 2)
		check(not route.is_empty() and route.transition != null, "%s：出生后存在上楼路线" % unit.name)
	check(lower_units.size() == 1 and upper_units.size() == 2, "模板E第5回合按原落点生成一只低地近战怪及两只高地怪")
	battle.battle_round_manager.start_auto_battle()
	for frame in 1800:
		await physics_frame
		for unit in lower_units:
			if unit.floor_id == 2:
				climbed[str(unit.name)] = true
		if climbed.size() == lower_units.size() and hits.size() == lower_units.size() + upper_units.size():
			break
	for unit in lower_units:
		check(climbed.has(str(unit.name)), "%s：实际从一层切到二层，最终位置%s" % [unit.name, unit.global_position])
		check(hits.has(str(unit.name)), "%s：上楼后实际命中二层目标" % unit.name)
	for unit in upper_units:
		check(hits.has(str(unit.name)), "%s：高地单位按真实射程接敌并命中目标" % unit.name)
	check(ally.global_position.is_equal_approx(Vector2(520, 810)) and ally.floor_id == 2, "测试目标保持原二层位置")
	print("LEVEL108_ROUND5: climbed=%s hits=%s" % [climbed.keys(), hits])
	if "--capture" in OS.get_cmdline_user_args():
		var camera := battle.get_node("Camera2D") as Camera2D
		camera.zoom = Vector2.ONE * 0.7
		camera.global_position = Vector2(960, 600)
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/battle007-round5")
		check(root.get_texture().get_image().save_png("res://.maintenance/battle007-round5/round5-upstairs.png") == OK, "保存第5回合上楼接敌截图")
	battle.battle_finished = true
	battle.free()
	await process_frame


func _run() -> void:
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	_roundtrip()
	await _soldier_stairs()
	await _fifth_round()
	print("LEVEL108_CROSS_FLOOR_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
