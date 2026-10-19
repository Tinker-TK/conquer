# 主动位移共用完整身体扫描与地表检查，不把其他单位当作地形墙体。
extends RefCounted


static func endpoint(unit: UnitBase, from: Vector2, planned: Vector2, floor_id: int = -1) -> Vector2:
	if floor_id < 1:
		floor_id = unit.floor_id
	var fraction := 1.0
	var collision := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.transform.origin += from - unit.global_position
		query.motion = planned - from
		query.margin = 0.1
		query.collision_mask = (unit.floor_map.terrain_bit(floor_id) | 4) if is_instance_valid(unit.floor_map) else 12
		query.exclude = [unit.get_rid()]
		var sweep := unit.get_world_2d().direct_space_state.cast_motion(query)
		if sweep.size() == 2:
			fraction = sweep[0]
	var end := from.lerp(planned, fraction)
	var steps := maxi(1, ceili(from.distance_to(end) / 12.0))
	var valid := from
	var map: RID = unit.floor_map.get_floor_map(floor_id) if is_instance_valid(unit.floor_map) else unit.navigation_agent_2d.get_navigation_map()
	for step in range(1, steps + 1):
		var point := from.lerp(end, float(step) / steps)
		if is_instance_valid(unit.floor_map):
			if not unit.floor_map.has_ground_at(point, floor_id):
				return valid
		elif map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 and not NavigationServer2D.map_get_regions(map).is_empty():
			if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) > 2.0:
				return valid
		valid = point
	return end


# 位移只在实际坡口附近借用已配置的楼梯，不从桥下的 XY 投影自动跳层。
static func _near_link(unit: UnitBase, from: Vector2, link: Node2D, floor_id: int) -> bool:
	return is_instance_valid(link) and link.enabled and link.destination_floor(floor_id) != floor_id \
		and from.distance_to(link.entry_point(floor_id)) <= maxf(96.0, link.exit_clearance(unit))


static func can_cross_stairs(unit: UnitBase, target: UnitBase, distance_limit: float) -> bool:
	if not is_instance_valid(unit.floor_map) or unit.is_on_same_floor(target) \
		or unit.global_position.distance_to(target.global_position) > distance_limit:
		return false
	var connection: Dictionary = unit.floor_map.route(unit.global_position, unit.floor_id, target.global_position, target.floor_id)
	return connection.get("distance", INF) <= distance_limit \
		and _near_link(unit, unit.global_position, connection.get("transition"), unit.floor_id)


static func _path(points: PackedVector2Array, floors: PackedInt32Array, links: Array = []) -> Dictionary:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return {"points": points, "floors": floors, "links": links, "length": length}


# 返回连续折线及每个节点所属楼层；同坐标的两个节点表示经过显式楼梯连接后切层。
static func plan(unit: UnitBase, from: Vector2, planned: Vector2, destination_floor: int = -1) -> Dictionary:
	var floor_id := unit.floor_id
	if destination_floor < 1:
		destination_floor = floor_id
		# 后撤没有目标楼层；仅当地表已结束且方向通向真实坡口时允许退下楼梯。
		if is_instance_valid(unit.floor_map) and not unit.floor_map.has_ground_at(planned, floor_id):
			for link: Node2D in unit.floor_map.transitions:
				if _near_link(unit, from, link, floor_id) \
					and unit.floor_map.is_walkable(planned, link.destination_floor(floor_id)):
					destination_floor = link.destination_floor(floor_id)
					break
	if destination_floor == floor_id:
		var end := endpoint(unit, from, planned)
		var straight := _path(PackedVector2Array([from, end]), PackedInt32Array([floor_id, floor_id]))
		if end.distance_to(planned) <= 0.5 or not is_instance_valid(unit.floor_map):
			return straight
		var nearby: Array = []
		for link: Node2D in unit.floor_map.transitions:
			if _near_link(unit, from, link, floor_id):
				nearby.append(link)
		if not nearby.is_empty():
			var ramp_path := _navigation_leg(unit, from, planned, floor_id)
			if not ramp_path.is_empty():
				var floors := PackedInt32Array()
				floors.resize(ramp_path.size())
				floors.fill(floor_id)
				return _path(ramp_path, floors, nearby)
		return straight
	if not is_instance_valid(unit.floor_map):
		return {}
	var points := PackedVector2Array([from])
	var floors := PackedInt32Array([floor_id])
	var links: Array = []
	var cursor := from
	for _step in 4:
		if floor_id == destination_floor:
			break
		var connection: Dictionary = unit.floor_map.route(cursor, floor_id, planned, destination_floor)
		var link: Node2D = connection.get("transition")
		if not is_instance_valid(link) or (links.is_empty() and not _near_link(unit, from, link, floor_id)):
			return {}
		var leg := _navigation_leg(unit, cursor, link.entry_point(floor_id), floor_id)
		if leg.is_empty():
			return {}
		for point in leg:
			points.append(point)
			floors.append(floor_id)
		var next: int = link.destination_floor(floor_id)
		cursor = link.entry_point(next)
		if next == floor_id or not unit.floor_map.is_walkable(cursor, next, 4.0) \
			or not _terrain_clear(unit, cursor, next):
			return {}
		points.append(cursor)
		floors.append(next)
		links.append(link)
		floor_id = next
	if floor_id != destination_floor:
		return {}
	var final_leg := _navigation_leg(unit, cursor, planned, floor_id)
	if final_leg.is_empty():
		return {}
	for point in final_leg:
		points.append(point)
		floors.append(floor_id)
	return _path(points, floors, links)


static func _navigation_leg(unit: UnitBase, from: Vector2, to: Vector2, floor_id: int) -> PackedVector2Array:
	if not unit.floor_map.is_walkable(to, floor_id, 4.0) or unit.floor_map.path_distance(from, to, floor_id) == INF:
		return PackedVector2Array()
	var points := PackedVector2Array([from])
	points.append_array(NavigationServer2D.map_get_path(unit.floor_map.get_floor_map(floor_id), from, to, true))
	points.append(to)
	for index in range(1, points.size()):
		if endpoint(unit, points[index - 1], points[index], floor_id).distance_to(points[index]) > 0.5:
			return PackedVector2Array()
	return points


static func _terrain_clear(unit: UnitBase, point: Vector2, floor_id: int) -> bool:
	var collision := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.transform.origin += point - unit.global_position
	query.collision_mask = unit.floor_map.terrain_bit(floor_id) | 4
	query.exclude = [unit.get_rid()]
	return unit.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


static func sample(path: Dictionary, progress: float) -> Dictionary:
	var remaining: float = clampf(progress, 0.0, 1.0) * path.length
	var points: PackedVector2Array = path.points
	var floors: PackedInt32Array = path.floors
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if remaining < length - 0.0001:
			return {"point": points[index - 1].lerp(points[index], remaining / length), "floor": floors[index - 1]}
		remaining -= length
	return {"point": points[-1], "floor": floors[-1]}


static func extend(path: Dictionary, point: Vector2, floor_id: int) -> Dictionary:
	var points: PackedVector2Array = path.points.duplicate()
	var floors: PackedInt32Array = path.floors.duplicate()
	points.append(point)
	floors.append(floor_id)
	return _path(points, floors, path.links)


static func reverse(path: Dictionary) -> Dictionary:
	if path.floors[0] != path.floors[-1]:
		for link: Node2D in path.links:
			if not is_instance_valid(link) or not link.enabled or not link.bidirectional:
				return {}
	var points: PackedVector2Array = path.points.duplicate()
	var floors: PackedInt32Array = path.floors.duplicate()
	points.reverse()
	floors.reverse()
	return _path(points, floors, path.links)


static func limit(path: Dictionary, distance: float) -> Dictionary:
	if path.length <= distance:
		return path
	var points := PackedVector2Array([path.points[0]])
	var floors := PackedInt32Array([path.floors[0]])
	var remaining := distance
	for index in range(1, path.points.size()):
		var length: float = path.points[index - 1].distance_to(path.points[index])
		if length > remaining:
			points.append(path.points[index - 1].lerp(path.points[index], remaining / length))
			floors.append(path.floors[index - 1])
			break
		points.append(path.points[index])
		floors.append(path.floors[index])
		remaining -= length
	return _path(points, floors, path.links)


static func move(unit: UnitBase, path: Dictionary, progress: float) -> bool:
	if path.floors[0] != path.floors[-1]:
		for link: Node2D in path.links:
			if not is_instance_valid(link) or not link.enabled:
				return false
	var location := sample(path, progress)
	unit.global_position = location.point
	if unit.floor_id != location.floor:
		unit.set_floor(location.floor)
	unit.navigation_agent_2d.refresh_forced_movement_visual(path.links)
	return true
