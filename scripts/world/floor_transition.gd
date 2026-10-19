@tool
extends Area2D

## 楼梯入口所在层，1~4 对应 Layer01~Layer04。
@export_range(1, 4, 1) var from_floor: int = 1
## 楼梯出口所在层。
@export_range(1, 4, 1) var to_floor: int = 2
## 允许从出口返回入口；关闭时只能 From → To。
@export var bidirectional: bool = true
## 关闭后该连接不再参与寻路。
@export var enabled: bool = true
## 单位脚底进入此距离才切层，不能由身体边缘提前触发。
@export_range(2.0, 24.0, 1.0) var arrival_distance: float = 6.0
## 固定出口被占时，只在同一段坡口附近寻找可容纳身体的落点。
@export_range(16.0, 128.0, 1.0) var landing_search_radius: float = 96.0

var _reservation_frame: int = -1
var _landing_reservations: Array[Dictionary] = []
var _approaching: Dictionary = {}
var _approach_leaders: Dictionary = {}
var _exiting: Dictionary = {}


# 同一入口只让一名行进单位优先靠近，后排继续避让；不抬高桥下或站定单位的优先级。
func approach_priority(unit: CharacterBody2D) -> float:
	var frame := Engine.get_physics_frames()
	_approaching[unit.get_instance_id()] = {"unit": weakref(unit), "frame": frame, "floor": unit.floor_id}
	for id in _approaching.keys():
		var request: Dictionary = _approaching[id]
		var other: Object = request.unit.get_ref()
		if not is_instance_valid(other) or frame - int(request.frame) > 3 or other.floor_id != request.floor:
			_approaching.erase(id)
	var leader: Object = null
	var previous: WeakRef = _approach_leaders.get(unit.floor_id)
	if previous != null:
		leader = previous.get_ref()
	if not is_instance_valid(leader) or leader.floor_id != unit.floor_id \
		or not _approaching.has(leader.get_instance_id()):
		var nearest := INF
		for request: Dictionary in _approaching.values():
			var candidate: Object = request.unit.get_ref()
			if request.floor != unit.floor_id:
				continue
			var distance: float = candidate.global_position.distance_to(entry_point(unit.floor_id))
			if distance < nearest:
				nearest = distance
				leader = candidate
		_approach_leaders[unit.floor_id] = weakref(leader)
	return 0.9 if leader == unit else 0.2


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func destination_floor(current: int) -> int:
	if not enabled or from_floor == to_floor:
		return current
	if current == from_floor:
		return to_floor
	return from_floor if current == to_floor and bidirectional else current


func entry_point(current: int) -> Vector2:
	var marker := get_node_or_null("From" if current == from_floor else "To") as Node2D
	return marker.global_position if marker != null else global_position


# 楼梯区域用于绘制排序，让正走在坡道上的身体显示在岩壁前；逻辑切层仍只认入口点。
func contains_visual_point(point: Vector2) -> bool:
	var area := get_node_or_null("CollisionShape2D") as CollisionShape2D
	return enabled and area != null and not area.disabled and area.shape != null \
		and area.shape.get_rect().has_point(area.to_local(point))


# 身体先于脚底接触坡道；按可见精灵范围判断，避免半个身体先被岩壁盖住才抬高绘制。
func overlaps_visual_body(bounds: Rect2) -> bool:
	var area := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not enabled or area == null or area.disabled or area.shape == null or not bounds.has_area():
		return false
	var transform_to_area := area.global_transform.affine_inverse()
	return area.shape.get_rect().intersects(transform_to_area * bounds, true)


# 只有路线明确要求经过该楼梯时才切层，桥下路过同一 XY 不会被触发。
func transfer(unit: CharacterBody2D) -> bool:
	var next := destination_floor(unit.floor_id)
	if next == unit.floor_id or unit.global_position.distance_to(entry_point(unit.floor_id)) > arrival_distance:
		return false
	# 前一人尚未走出坡口时，后来者只能使用外围空位，不能占住他的离开方向。
	var reserved_clearance := 0.0
	var previous: WeakRef = _exiting.get(next)
	if previous != null:
		var other: Object = previous.get_ref()
		if is_instance_valid(other) and other.floor_id == next \
			and other.global_position.distance_to(entry_point(next)) < exit_clearance(other):
			reserved_clearance = exit_clearance(other) + body_radius(other) + body_radius(unit) + 6.0
	var landing := entry_point(next)
	var terrain: Node = unit.floor_map
	if terrain == null or not terrain.is_walkable(landing, next, 4.0):
		return false
	if not _terrain_path_is_clear(unit, landing, landing, next):
		return false
	# 保留原落点优先；旁人占住时沿坡口错开，不移动挡路者或关闭身体碰撞。
	var direction := landing - entry_point(unit.floor_id)
	if direction.is_zero_approx():
		direction = global_transform.x
	direction = direction.normalized()
	var side := direction.orthogonal()
	var spacing := body_radius(unit) * 2.0 + 6.0
	var candidates: Array[Vector2] = [landing]
	for distance in [spacing, landing_search_radius]:
		if distance > landing_search_radius:
			continue
		for offset in [side, -side, direction, -direction,
			(direction + side).normalized(), (direction - side).normalized(),
			direction.rotated(PI * 0.375), direction.rotated(-PI * 0.375),
			direction.rotated(PI * 0.125), direction.rotated(-PI * 0.125)]:
			candidates.append(landing + offset * distance)
	for candidate in candidates:
		if candidate.distance_to(landing) < reserved_clearance:
			continue
		if not _landing_is_free(unit, candidate, next):
			continue
		if not _local_surface(terrain, landing, candidate, next):
			continue
		if not _terrain_path_is_clear(unit, landing, candidate, next):
			continue
		if not _can_leave_landing(unit, candidate, next):
			continue
		unit.global_position = candidate
		unit.set_floor(next)
		# 同一物理帧后到的单位也必须看见已分配的落点，不能依赖下一帧物理同步。
		_landing_reservations.append({"unit": weakref(unit), "floor": next, "radius": body_radius(unit)})
		if candidate.distance_to(landing) < exit_clearance(unit):
			_exiting[next] = weakref(unit)
		return true
	return false


func _terrain_path_is_clear(unit: CharacterBody2D, start: Vector2, finish: Vector2, floor_id: int, include_units: bool = false) -> bool:
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.transform.origin += start - unit.global_position
	query.collision_mask = unit.floor_map.terrain_bit(floor_id) | 4
	if include_units:
		query.collision_mask |= unit.floor_map.unit_bit(floor_id)
	query.exclude = [unit.get_rid()]
	var space := unit.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = finish - start
	return start.is_equal_approx(finish) or space.cast_motion(query)[0] >= 0.999


# 不把后到的人放进已被站定队友围住的出口中心；至少留出一个身体的可行走方向。
func _can_leave_landing(unit: CharacterBody2D, landing: Vector2, floor_id: int) -> bool:
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.transform.origin += landing - unit.global_position
	query.collision_mask = unit.floor_map.terrain_bit(floor_id) | unit.floor_map.unit_bit(floor_id) | 4
	query.exclude = [unit.get_rid()]
	for index in 16:
		query.motion = Vector2.RIGHT.rotated(index * TAU / 16.0) * maxf(body_radius(unit) * 2.0 + 6.0, exit_clearance(unit) + 10.0)
		var finish := landing + query.motion
		if not _landing_is_free(unit, finish, floor_id) or not _local_surface(unit.floor_map, landing, finish, floor_id):
			continue
		var sweep := unit.get_world_2d().direct_space_state.cast_motion(query)
		if sweep[0] >= 0.999:
			return true
	return false


func body_radius(unit: CharacterBody2D) -> float:
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null:
		return 16.0
	var scale_factor := maxf(absf(shape.global_scale.x), absf(shape.global_scale.y))
	if shape.shape is CircleShape2D:
		return shape.shape.radius * scale_factor
	return shape.shape.get_rect().size.length() * 0.5 * scale_factor


# 出口清空后才允许准备阶段按较大的到达容差停步，避免第一人停在切层点上。
func exit_clearance(unit: CharacterBody2D) -> float:
	return body_radius(unit) + unit.floor_map.floor_agent_radius + 6.0


func exit_position(unit: CharacterBody2D, destination: Vector2) -> Vector2:
	var anchor := entry_point(unit.floor_id)
	var direction := anchor.direction_to(destination)
	if direction.is_zero_approx():
		direction = (anchor - entry_point(destination_floor(unit.floor_id))).normalized()
	if direction.is_zero_approx():
		direction = global_transform.x.normalized()
	for distance in [exit_clearance(unit) + 10.0, exit_clearance(unit) + 40.0]:
		for angle in [0.0, 22.5, -22.5, 45.0, -45.0, 67.5, -67.5, 90.0, -90.0,
			112.5, -112.5, 135.0, -135.0, 157.5, -157.5, 180.0]:
			var candidate: Vector2 = anchor + direction.rotated(deg_to_rad(angle)) * distance
			if _landing_is_free(unit, candidate, unit.floor_id) \
				and _local_surface(unit.floor_map, unit.global_position, candidate, unit.floor_id) \
				and _terrain_path_is_clear(unit, unit.global_position, candidate, unit.floor_id, true):
				return candidate
	return Vector2.INF


func _local_surface(terrain: Node, anchor: Vector2, candidate: Vector2, floor_id: int) -> bool:
	if anchor.is_equal_approx(candidate):
		return terrain.is_walkable(candidate, floor_id, 4.0)
	if not terrain.is_walkable(candidate, floor_id):
		return false
	# 相邻孤岛或墙另一侧的空位不能被当作同一个出口；只接受局部连通的地面。
	return terrain.path_distance(anchor, candidate, floor_id) <= anchor.distance_to(candidate) * 1.5 + 8.0


func _landing_is_free(unit: CharacterBody2D, landing: Vector2, floor_id: int) -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _reservation_frame:
		_reservation_frame = frame
		_landing_reservations.clear()
	for reservation in _landing_reservations:
		var other: Object = reservation.unit.get_ref()
		if is_instance_valid(other) and other != unit and other.floor_id == floor_id and reservation.floor == floor_id \
			and other.global_position.distance_to(landing) < float(reservation.radius) + body_radius(unit) + 2.0:
			return false
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape != null:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.transform.origin += landing - unit.global_position
		query.collision_mask = unit.floor_map.terrain_bit(floor_id) | unit.floor_map.unit_bit(floor_id) | 4
		query.exclude = [unit.get_rid()]
		if not unit.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var start := to_local(entry_point(from_floor))
	var finish := to_local(entry_point(to_floor))
	draw_circle(start, arrival_distance, Color(0.2, 0.8, 1.0, 0.5))
	draw_circle(finish, arrival_distance, Color(1.0, 0.7, 0.2, 0.5))
	draw_line(start, finish, Color(0.2, 1.0, 0.7), 2.0)
