# 验证波次编辑器只存 XY 的旧阵型在首轮、循环和变换后的战场按地表正确出生。
extends SceneTree

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error(label)


func _pack(points: Array[Vector2], floors: Array[int]) -> PackedScene:
	var wave := Node2D.new()
	wave.name = "Wave"
	for index in points.size():
		var unit = load("res://scenes/units/orc.tscn").instantiate()
		unit.position = points[index]
		unit.floor_id = floors[index]
		wave.add_child(unit, true)
		unit.owner = wave
	var packed := PackedScene.new()
	check(packed.pack(wave) == OK, "阵型打包成功")
	wave.free()
	return packed


func _assert_floor(unit: Node, expected: int, label: String) -> void:
	check(unit.floor_id == expected and unit.move_floor_id == expected, label + "：逻辑和移动楼层")
	check(unit.z_index == unit.floor_map.get_floor_z_index(expected), label + "：绘制高度")
	check(unit.navigation_agent_2d.get_navigation_map() == unit.floor_map.get_floor_map(expected), label + "：导航图")
	check((unit.collision_layer & FLOORS.UNIT_MASK) == FLOORS.unit_bit(expected)
		and (unit.collision_mask & FLOORS.TERRAIN_MASK) == FLOORS.terrain_bit(expected), label + "：楼层碰撞")


func _run() -> void:
	var battle := Node2D.new()
	battle.position = Vector2(85, -30)
	battle.scale = Vector2(1.2, 0.8)
	var level := Node2D.new()
	level.name = "Level"
	battle.add_child(level)
	var terrain := FLOORS.new()
	terrain.name = "NavigationRegion2D"
	level.add_child(terrain)
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	tiles.add_source(atlas, 0)
	for floor_id in range(1, 5):
		var layer := TileMapLayer.new()
		layer.name = "Layer%02d" % floor_id
		layer.tile_set = tiles
		for x in range(0 if floor_id == 1 else (floor_id - 1) * 4, 16 if floor_id == 1 else (floor_id - 1) * 4 + 3):
			for y in 4:
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		terrain.add_child(layer)
	var entities := Node2D.new()
	entities.name = "Entities"
	battle.add_child(entities)
	var team = load("res://scripts/battle/level_wave.gd").new()
	team.name = "TeamB"
	team.position = Vector2(400, 80)
	team.rotation = 0.2
	entities.add_child(team)
	root.add_child(battle)
	var points: Array[Vector2] = []
	for floor_id in range(1, 5):
		points.append(team.to_local(terrain.to_global(Vector2(64 + (floor_id - 1) * 256, 96))))
	# 最后一个站位刻意配置二层，不能因为其上有四层而覆盖显式配置。
	points.append(points[3])
	team.level_data.append(_pack(points, [1, 1, 1, 1, 2]))
	check(NavigationServer2D.map_get_iteration_id(terrain.get_floor_map(2)) == 0, "首轮夹具尚未同步导航")
	team._on_battle_round_manager_phase_changed(0, 1)
	for index in points.size():
		var unit := team.get_child(index) as Node2D
		_assert_floor(unit, index + 1 if index < 4 else 2, "首轮单位%d" % index)
		check(unit.position.is_equal_approx(points[index]), "出生认层不改变配置坐标")
	var source: Node = team.level_data[0].instantiate()
	check(source.get_child(1).floor_id == 1, "出生不修改共享阵型资源")
	source.free()
	for unit in team.get_children():
		unit.free()
	team._on_battle_round_manager_phase_changed(0, 2)
	_assert_floor(team.get_child(1), 2, "循环再次出生")
	for unit in team.get_children():
		unit.free()
	team.auto_detect_spawn_floor = false
	team._on_battle_round_manager_phase_changed(0, 3)
	_assert_floor(team.get_child(1), 1, "关闭自动认层保留桥下配置")
	terrain.get_node("Layer04").hide()
	check(terrain.spawn_floor_at(terrain.to_global(Vector2(832, 96))) == 1, "隐藏地表不参与出生认层")
	check(terrain.spawn_floor_at(terrain.to_global(Vector2(-500, -500))) == 1, "地表外站位兼容默认一层")
	battle.free()
	await process_frame

	# 使用截图对应的正式关卡和第2回合，不改写原关卡；全部六只敌人都位于二层。
	root.get_node("RunManager").start_new_run()
	var config := load("res://data/levels/level_108_1.tres").duplicate() as BattleLevelConfig
	config.cards_per_round = 0
	var actual := config.battle_scene.instantiate()
	actual.configure_level(config)
	actual.get_node("BattleRoundManager").first_round = 2
	root.add_child(actual)
	var enemies := actual.get_node("Entities/TeamB")
	check(enemies.get_child_count() == 2, "正式第2回合按模板E生成两只敌人")
	for unit in enemies.get_children():
		_assert_floor(unit, 2, "level_108_1 第2回合 " + str(unit.name))
	var actual_terrain := actual.get_node("Level/NavigationRegion2D")
	for frame in 180:
		await physics_frame
		if actual_terrain.is_walkable(enemies.get_child(0).global_position, 2):
			break
	check(NavigationServer2D.map_get_iteration_id(actual_terrain.get_floor_map(2)) > 0, "正式二层导航完成同步")
	for unit in enemies.get_children():
		check(unit.floor_id == 2, "准备阶段保持二层出生")
		check(actual_terrain.is_walkable(unit.global_position, 2), "正式怪物站位位于二层可走区域")
	if "--capture" in OS.get_cmdline_user_args():
		var camera := actual.get_node("Camera2D") as Camera2D
		camera.zoom = Vector2.ONE * 0.5
		camera.global_position = Vector2(960, 480)
		camera.force_update_scroll()
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/wave-spawn-floors")
		check(root.get_texture().get_image().save_png("res://.maintenance/wave-spawn-floors/level108-round2-fixed.png") == OK, "保存正式关卡实战截图")
	actual.free()
	await process_frame
	print("WAVE_SPAWN_FLOORS_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
