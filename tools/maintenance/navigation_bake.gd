# 这玩意儿是干嘛的（核心逻辑）：维护工具，重新计算现有关卡的导航并输出结果供补丁使用。
# 数据是咋流动的（数据流向）：场景里的地形碰撞 → 独立导航资源 → 24 像素留白 → JSON 输出。
# 为啥这么写（选型决策）：只把导航区域加入树，不运行战斗；复制资源避免子关卡污染父场景。
# 性能咋样（复杂度）：仅手动运行，每张地图烘焙一次，游戏运行时不会调用。
extends SceneTree


# 作用：Godot 启动后延迟执行工具；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()


# 作用：输出父场景与独立子关卡的烘焙数据；没有参数，没有返回值。
func _run() -> void:
	for path in ["res://scenes/battle/battle_scene.tscn", "res://scenes/levels/battles/battle_001.tscn"]:
		var battle: Node = load(path).instantiate()
		var region: NavigationRegion2D = battle.get_node("Level/NavigationRegion2D")
		region.owner = null
		region.get_parent().remove_child(region)
		root.add_child(region)
		var polygon := region.navigation_polygon.duplicate(true) as NavigationPolygon
		polygon.agent_radius = 24.0
		var source := NavigationMeshSourceGeometryData2D.new()
		NavigationServer2D.parse_source_geometry_data(polygon, source, region)
		NavigationServer2D.bake_from_source_geometry_data(polygon, source)
		assert(polygon.get_polygon_count() > 0, "导航烘焙结果为空")
		# 输出数值，不重新打包整个继承场景，以免改变用户的其它地形配置。
		var vertices: Array = []
		for point in polygon.get_vertices():
			vertices.append(point.x)
			vertices.append(point.y)
		var polygons: Array = []
		for index in polygon.get_polygon_count():
			polygons.append(Array(polygon.get_polygon(index)))
		print("BAKE_JSON:", JSON.stringify({"path": path, "vertices": vertices, "polygons": polygons}))
		region.free()
		battle.free()
	quit()
