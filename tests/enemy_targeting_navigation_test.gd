# 这玩意儿是干嘛的（核心逻辑）：验证小怪隔着障碍索敌时按可走距离选择，并且不会轻易来回换目标。
# 数据是咋流动的（数据流向）：测试导航和真实单位位置 → 技能管理器选敌 → 断言目标死亡及释放后的重选。
# 为啥这么写（选型决策）：真实导航会绕过水和墙；单纯比较坐标无法复现隔水目标更近的问题。
# 性能咋样（复杂度）：只在手动回归时创建三名单位和一张小地图，正常游戏不会加载。
extends Node2D


# 作用：Godot 入树后安排导航同步，再运行测试；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：在指定坐标放置静止测试单位；ally 表示阵营、point 是位置，返回创建的单位。
func _unit(ally: bool, point: Vector2) -> UnitBase:
	var path := "res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn"
	var unit: UnitBase = load(path).instantiate()
	unit.position = point
	add_child(unit)
	unit.set_physics_process(false)
	return unit


# 作用：烘焙一块中间有深水般障碍的场地；没有参数，没有返回值。
func _build_navigation() -> void:
	var region := NavigationRegion2D.new()
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 24.0
	polygon.add_outline(PackedVector2Array([Vector2(100, 100), Vector2(900, 100),
		Vector2(900, 800), Vector2(100, 800)]))
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_obstruction_outline(PackedVector2Array([Vector2(460, 300), Vector2(540, 300),
		Vector2(540, 600), Vector2(460, 600)]))
	NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	region.navigation_polygon = polygon
	add_child(region)


# 作用：检查隔墙路径、目标稳定和失效重选；没有参数，没有返回值，失败时以错误码退出。
func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_build_navigation()
	# 导航区域进树后要等服务器同步；只看 map 的版本号可能早于实际路径可用。
	for frame in 20:
		await get_tree().physics_frame
		var map := get_world_2d().navigation_map
		if NavigationServer2D.map_get_iteration_id(map) > 0 \
			and NavigationServer2D.map_get_closest_point(map, Vector2(400, 450)) != Vector2.ZERO:
			break
	var hunter := _unit(true, Vector2(400, 450))
	var across_water := _unit(false, Vector2(570, 450))
	var same_bank := _unit(false, Vector2(200, 450))
	# 隔墙者直线只隔 170 像素，同岸者隔 200 像素；追击必须选择实际路线更短的同岸者。
	assert(hunter.skill_manager.find_nearest_enemy() == same_bank, "索敌需要计算绕墙路径")
	# 两个敌人的距离很接近时保留原目标；明显更近时才允许改追击方向。
	across_water.global_position = Vector2(210, 450)
	assert(hunter.skill_manager.find_nearest_enemy() == same_bank, "微小距离变化不能反复切目标")
	across_water.global_position = Vector2(300, 450)
	assert(hunter.skill_manager.find_nearest_enemy() == across_water, "明显更近的敌人应接管目标")
	across_water.current_health = 0
	assert(hunter.skill_manager.find_nearest_enemy() == same_bank, "目标死亡后需要立即重选")
	# 再次锁定后真正释放节点，复现上一轮报错的悬空引用；自动战斗缓存也必须安全重选。
	across_water.current_health = 100
	assert(hunter.skill_manager.find_nearest_enemy() == across_water)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	across_water.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(hunter.skill_manager.find_nearest_enemy() == same_bank, "节点释放后不能把旧引用传给强类型参数")
	print("ENEMY_TARGETING_NAVIGATION_PASS")
	get_tree().quit()
