# 使用 level_108_1 的真实第2回合，验证两种己方单位与六只敌人的自动索敌、移动和实际命中。
extends SceneTree

var checks := 0
var failures: Array[String] = []
var ally_hits := 0
var enemy_hits := 0


func _initialize() -> void:
	_run.call_deferred()


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error(label)


func _fight(scene_name: String) -> void:
	root.get_node("RunManager").start_new_run()
	ally_hits = 0
	enemy_hits = 0
	var config := load("res://data/levels/level_108_1.tres").duplicate() as BattleLevelConfig
	config.cards_per_round = 0
	var battle: Node2D = config.battle_scene.instantiate()
	battle.configure_level(config)
	battle.get_node("BattleRoundManager").first_round = 2
	root.add_child(battle)
	var terrain := battle.get_node("Level/NavigationRegion2D")
	for frame in 180:
		await physics_frame
		if terrain.is_walkable(Vector2(520, 810), 2) and terrain.is_walkable(Vector2(1500, 900), 2):
			break
	var point := Vector2(520, 810)
	check(battle.get_deployment_floor(point) == 2, scene_name + "：左侧真实部署点属于二层")
	var ally = load("res://scenes/units/%s.tscn" % scene_name).instantiate()
	ally.position = battle.get_node("Entities/TeamA").to_local(point)
	ally.floor_id = battle.get_deployment_floor(point)
	ally.unit_data = ally.unit_data.duplicate()
	ally.unit_data.max_hp = 2000
	battle.get_node("Entities/TeamA").add_child(ally)
	ally.attack_landed.connect(func(_target): ally_hits += 1)
	var enemies: Array[Node] = []
	var origins: Dictionary = {ally.get_instance_id(): ally.global_position}
	var moved: Dictionary = {}
	var targeted: Dictionary = {}
	for unit in battle.get_node("Entities/TeamB").get_children():
		if not unit is CharacterBody2D:
			continue
		enemies.append(unit)
		origins[unit.get_instance_id()] = unit.global_position
		unit.attack_landed.connect(func(_target): enemy_hits += 1)
		check(unit.floor_id == 2, scene_name + "：敌人出生在二层")
		check(not terrain.route(ally.global_position, 2, unit.global_position, 2).is_empty(), scene_name + "：敌我之间存在路线")
	check(enemies.size() == 2, scene_name + "：正式第2回合按模板E生成两只敌人")
	for link in terrain.transitions:
		check(terrain.is_walkable(link.entry_point(1), 1) and terrain.is_walkable(link.entry_point(2), 2), scene_name + "：切层端点均可走")
	var units: Array[Node] = [ally]
	units.append_array(enemies)
	battle.battle_round_manager.start_auto_battle()
	for frame in 900:
		await physics_frame
		for unit in units:
			if not is_instance_valid(unit):
				continue
			var id := unit.get_instance_id()
			if is_instance_valid(unit.skill_manager.current_target):
				targeted[id] = true
			if unit.global_position.distance_to(origins[id]) > 20.0:
				moved[id] = true
		if frame >= 120 and ally_hits > 0 and enemy_hits > 0 and moved.size() == units.size():
			break
	for unit in units:
		var id := unit.get_instance_id()
		check(targeted.has(id), "%s：%s 自动选中敌人" % [scene_name, unit.name])
		check(moved.has(id), "%s：%s 实际接近敌人" % [scene_name, unit.name])
	check(ally_hits > 0, scene_name + "：己方完成动画并实际命中")
	check(enemy_hits > 0 and ally.current_health < 2000, scene_name + "：敌方完成动画并造成伤害")
	print("LEVEL108_COMBAT: %s ally_hits=%d enemy_hits=%d moved=%d/%d" % [scene_name, ally_hits, enemy_hits, moved.size(), units.size()])
	if "--capture" in OS.get_cmdline_user_args():
		var camera := battle.get_node("Camera2D") as Camera2D
		camera.zoom = Vector2.ONE * 0.7
		camera.global_position = Vector2(960, 600)
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/battle007-navigation")
		check(root.get_texture().get_image().save_png("res://.maintenance/battle007-navigation/%s-auto-battle.png" % scene_name) == OK, "保存自动战斗截图")
	battle.battle_finished = true
	battle.free()
	await process_frame


func _run() -> void:
	# 音频由专用真实混音测试验证，避免 headless 立即退出时播放流仍持有资源。
	if DisplayServer.get_name() == "headless":
		var audio := root.get_node("CombatAudio")
		audio.settings = audio.settings.duplicate()
		audio.settings.enabled = false
	await _fight("soldier")
	await _fight("knight")
	print("LEVEL108_NAVIGATION_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
