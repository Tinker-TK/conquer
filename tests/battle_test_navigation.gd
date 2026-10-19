# 卡牌/技能回归使用固定地面与真实导航服务器，避免正式地图编辑影响非寻路测试。
# 四层瓦片、碰撞与楼梯的完整验证由 battle_floors_test.gd 单独负责。
extends RefCounted


static func install(battle: Node2D) -> bool:
	var terrain: NavigationRegion2D = battle.get_node("Level/NavigationRegion2D")
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([Vector2(100, 100), Vector2(1800, 100), Vector2(1800, 1000), Vector2(100, 1000)])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	terrain.navigation_polygon = polygon
	var map := terrain.get_navigation_map()
	for frame in 60:
		await battle.get_tree().physics_frame
		if NavigationServer2D.map_get_iteration_id(map) > 0 \
			and NavigationServer2D.map_get_closest_point(map, Vector2(700, 450)).distance_to(Vector2(700, 450)) < 1.0 \
			and not NavigationServer2D.map_get_path(map, Vector2(700, 450), Vector2(1050, 450), true).is_empty():
			return true
	return false
