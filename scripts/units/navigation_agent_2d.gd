# 这玩意儿是干嘛的（核心逻辑）：地面单位共用寻路避让；飞行单位直行并按真实地面逐层快速升降。
# 数据是咋流动的（数据流向）：地面目标 → 路径和避让；飞行目标 → 平面直行与每层64像素升降 → 实际位置。
# 为啥这么写（选型决策）：寻路不认识移动中的单位，避让可能给出后退速度；两者之间需有稳定侧向和进展判断。
# 性能咋样（复杂度）：每物理帧只检查自身短距离路径；堵住时才尝试侧向，不扫描全场单位。
extends NavigationAgent2D

const FLIGHT_FLOOR_HEIGHT := preload("res://scripts/world/battle_floor_map.gd").FLIGHT_FLOOR_HEIGHT
const FLIGHT_VERTICAL_SPEED := 640.0 # 每层 64 像素，用 0.1 秒完成。

@onready var player_entity: CharacterBody2D = $".."
@onready var animated_sprite_2d: AnimatedSprite2D = get_node_or_null("../AnimatedSprite2D")
@onready var skill_manager: Node2D = get_node_or_null("../SkillManager")

## 寻路目标刷新和重新规划的间隔，单位为秒；越小则对移动目标反应更及时，但导航查询更频繁。
@export_range(0.1, 1.0, 0.05) var repath_interval: float = 0.3
## 移动进展不足时判定卡住的等待秒数。越小越快尝试调整绕行，越大越容忍短暂堵塞。
@export_range(0.3, 3.0, 0.1) var stuck_timeout: float = 0.8
## 沿前进方向检测附近阻挡的前瞻距离，单位为世界像素；越大越早考虑绕行，但也更容易受较远障碍影响。
@export_range(10.0, 80.0, 1.0) var obstacle_lookahead: float = 28.0
var _goal := Vector2.ZERO
var _has_goal := false
var _repath_left := 0.0
var _side := 1.0
var _request_frame: int = -1
var _request_phase: int = -1
var _detour_point := Vector2.ZERO
var _detour_origin := Vector2.ZERO
var _detour_active := false
var _detour_clear_time := 0.0
var _requested_direction := Vector2.ZERO
var _progress_origin := Vector2.ZERO
var _progress_time := 0.0
var _floor_route: Dictionary = {}
var _floor_route_goal := Vector2.INF
var _floor_route_from := -1
var _floor_route_to := -1
var _floor_route_left := 0.0
var _stair_visual_link: Node2D
var _stair_exit_link: Node2D
var _stair_exit_point := Vector2.INF
var _stair_exit_floor := 0
var _stair_exit_goal := Vector2.ZERO
var _stair_exit_repath_left := 0.0
var _stair_arrival_goal := Vector2.INF
var _stair_arrival_point := Vector2.INF
var _visual_bounds_cache: Dictionary = {}
var _flight_height := 0.0
var _flight_transition_floor := 0
var _flight_visual_floor := 0


# 作用：Godot 入树时设置避让并监听阶段和死亡；没有参数，没有返回值。
func _ready() -> void:
	if player_entity.is_initialization_rejected():
		return
	_flight_height = (player_entity.floor_id - 1) * FLIGHT_FLOOR_HEIGHT
	# 所有阵营使用同一避让空间；半径取身体而不是攻击范围。
	var body_shape := player_entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null and body_shape.shape is CircleShape2D:
		radius = body_shape.shape.radius * maxf(absf(player_entity.global_scale.x), absf(player_entity.global_scale.y))
	neighbor_distance = maxf(100.0, radius * 5.0)
	max_neighbors = 16
	time_horizon_agents = 0.45
	time_horizon_obstacles = 0.25
	path_desired_distance = 4.0
	target_desired_distance = 2.0
	path_max_distance = 48.0
	# 烘焙多边形之间可能产生共线中间点，站定队友占住它会使绕过的人又回头。
	# 去掉冗余直线点，只保留真正绕地形所需的转角。
	simplify_path = true
	simplify_epsilon = 1.0
	avoidance_layers = 1
	avoidance_mask = 1
	velocity_computed.connect(_on_velocity_computed)
	SignalBus.phase_change.connect(_on_phase_changed)
	player_entity.unit_died.connect(_on_unit_died)
	_on_phase_changed(Global.game_phase)


# 作用：每次战斗行为调用，向当前技能目标靠近；没有参数，没有返回值。
func fight_auto_move() -> void:
	if player_entity.current_state == player_entity.State.DEATH or skill_manager.is_casting:
		stop_navigation()
		return
	# 已开始的跨层先完成，再检查射程，避免进入射程后只升到一半便停住。
	if is_flight_transitioning():
		_advance_flight_transition()
		return
	if skill_manager.current_skill == null or not is_instance_valid(skill_manager.current_target):
		stop_navigation()
		player_entity.switch_state(player_entity.State.IDLE)
		return
	# 攻击距离仍按技能规则判断，不能用路径终点距离冒充攻击距离。
	var destination: Vector2 = skill_manager.current_target.global_position
	if has_pending_stair_exit():
		move_to(destination, skill_manager.current_target.floor_id)
		return
	if player_entity.unit_data.is_flying and not is_equal_approx(_flight_height, (player_entity.floor_id - 1) * FLIGHT_FLOOR_HEIGHT):
		_move_flying(destination, skill_manager.current_target.floor_id)
		return
	if player_entity.global_position.distance_to(destination) <= skill_manager.get_attack_range(skill_manager.current_skill):
		stop_navigation()
		return
	move_to(destination, skill_manager.current_target.floor_id)


# 作用：战斗或部署提交世界坐标目标；destination 是目的地，没有返回值。
func move_to(destination: Vector2, destination_floor: int = -1) -> void:
	if player_entity.is_action_blocked():
		stop_navigation()
		return
	if player_entity.unit_data.is_flying:
		if player_entity.current_state == player_entity.State.DEATH or not player_entity.is_physics_processing() \
			or skill_manager.is_casting or skill_manager.is_reacting or skill_manager.is_forced_moving:
			stop_navigation()
			return
		_move_flying(destination, destination_floor if destination_floor > 0 else player_entity.floor_id)
		return
	if is_instance_valid(player_entity.floor_map):
		if destination_floor < 1:
			destination_floor = player_entity.floor_id
		# 同层的两块孤岛也可能需要借道上层，因此统一规划完整楼层路线。
		var next: Variant = _floor_destination(destination, destination_floor)
		if next == null:
			stop_navigation()
			return
		destination = next
	var map := get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		stop_navigation()
		return
	var delta := player_entity.get_physics_process_delta_time()
	_repath_left -= delta
	# 静止目标不每帧重算路径；追移动目标也保留短暂间隔，减少回头抖动。
	if not _has_goal or (_repath_left <= 0.0 and _goal.distance_to(destination) > 8.0):
		_goal = destination
		target_position = destination
		_has_goal = true
		_repath_left = repath_interval
	if _progress_time <= 0.0:
		_progress_origin = player_entity.global_position
	var next_point := get_next_path_position()
	if is_navigation_finished():
		stop_navigation()
		return
	# 泥潭减速即时生效；高速单位的路径点容差随速度适当增加。
	max_speed = player_entity.get_movement_speed()
	path_desired_distance = maxf(3.0, max_speed * delta * 1.2)
	var direction := player_entity.global_position.direction_to(next_point)
	# 前方单位暂时移动时仍保持绕行，直到前路持续畅通且自己已绕开原堵点。
	direction = _choose_clear_direction(direction)
	var approaching_link: Node2D = _floor_route.get("transition")
	if is_instance_valid(approaching_link) \
		and player_entity.global_position.distance_to(approaching_link.entry_point(player_entity.floor_id)) <= neighbor_distance:
		avoidance_priority = approaching_link.approach_priority(player_entity)
	_requested_direction = direction
	_request_frame = Engine.get_physics_frames()
	_request_phase = Global.game_phase
	velocity = direction * max_speed


# 飞行在统一地面平面上直行，身体、血条和命中位置随实际高度一起升降。
# 不查询路径、不投影导航、不使用 RVO 或地面碰撞，因此也能越过水面和断开的岛屿。
func _move_flying(destination: Vector2, destination_floor: int) -> void:
	if is_flight_transitioning():
		_advance_flight_transition()
		return
	_goal = destination
	_has_goal = true
	var delta := player_entity.get_physics_process_delta_time()
	max_speed = player_entity.get_movement_speed()
	var ground: Vector2 = player_entity.global_position + Vector2.DOWN * _flight_height
	var goal_ground := destination + Vector2.DOWN * (destination_floor - 1) * FLIGHT_FLOOR_HEIGHT
	var next_ground := ground.move_toward(goal_ground, max_speed * delta)
	var next_floor: int = player_entity.floor_id
	if next_ground.distance_to(goal_ground) <= 2.0:
		# 精确落点允许选择桥下楼层；不能被重叠的上层地面反复抬起。
		next_floor = destination_floor
	elif is_instance_valid(player_entity.floor_map):
		next_floor = player_entity.floor_map.flight_floor_at_ground(next_ground)
	if next_floor != player_entity.floor_id or not is_equal_approx(_flight_height, (player_entity.floor_id - 1) * FLIGHT_FLOOR_HEIGHT):
		# 连跨多层时每层单独升降 64 像素。
		_flight_transition_floor = player_entity.floor_id + clampi(next_floor - player_entity.floor_id, -1, 1)
		_flight_visual_floor = maxi(_flight_visual_floor, maxi(player_entity.floor_id, _flight_transition_floor))
		_advance_flight_transition()
		return
	var travelled := next_ground - ground
	player_entity.global_position += travelled
	player_entity.velocity = travelled / delta
	_update_flight_visual()
	_play_movement(travelled)


func is_flight_transitioning() -> bool:
	return _flight_transition_floor > 0


func _advance_flight_transition() -> void:
	var delta := player_entity.get_physics_process_delta_time()
	var target_height := (_flight_transition_floor - 1) * FLIGHT_FLOOR_HEIGHT
	var next_height := move_toward(_flight_height, target_height, FLIGHT_VERTICAL_SPEED * delta)
	var travelled := Vector2(0.0, _flight_height - next_height)
	_flight_height = next_height
	player_entity.global_position += travelled
	player_entity.velocity = travelled / delta
	if is_equal_approx(_flight_height, target_height):
		var next_floor := _flight_transition_floor
		var visual_floor := _flight_visual_floor
		_flight_transition_floor = 0
		player_entity.set_floor(next_floor)
		_flight_visual_floor = visual_floor
	_update_flight_visual()
	_play_movement(travelled)


func _update_flight_visual() -> void:
	if not player_entity.unit_data.is_flying or not is_instance_valid(player_entity.floor_map):
		return
	var minimum := maxi(player_entity.floor_id, _flight_transition_floor)
	var visual_floor := maxi(minimum, _flight_visual_floor)
	if visual_floor > minimum:
		var bounds := get_visual_body_bounds()
		while visual_floor > minimum and not player_entity.floor_map.flight_overlaps_floor(bounds, visual_floor):
			visual_floor -= 1
	_flight_visual_floor = visual_floor
	player_entity.z_index = player_entity.floor_map.get_floor_z_index(visual_floor)


# 跨层目标先走到楼梯入口；只有到达入口后才更换物理位、导航图和避让位。
func _floor_destination(destination: Vector2, destination_floor: int) -> Variant:
	if has_pending_stair_exit():
		_stair_exit_repath_left -= player_entity.get_physics_process_delta_time()
		if _stair_exit_repath_left <= 0.0:
			_stair_exit_point = _stair_exit_link.exit_position(player_entity, _stair_exit_goal)
			_stair_exit_repath_left = repath_interval
		if not _stair_exit_point.is_finite():
			return null
		return _stair_exit_point
	_floor_route_left -= player_entity.get_physics_process_delta_time()
	var cached_link: Node2D = _floor_route.get("transition")
	if is_instance_valid(cached_link) and (not cached_link.enabled \
		or cached_link.destination_floor(player_entity.floor_id) == player_entity.floor_id):
		_floor_route_from = -1
	if _floor_route_from != player_entity.floor_id or _floor_route_to != destination_floor \
		or (_floor_route_left <= 0.0 and (_floor_route.is_empty() or _floor_route_goal.distance_to(destination) > 8.0)):
		_floor_route = player_entity.floor_map.route(player_entity.global_position, player_entity.floor_id, destination, destination_floor)
		_floor_route_goal = destination
		_floor_route_from = player_entity.floor_id
		_floor_route_to = destination_floor
		_floor_route_left = repath_interval
	var link: Node2D = _floor_route.get("transition")
	_update_stair_visual()
	if _floor_route.is_empty():
		return null
	if link == null:
		return destination
	if not is_instance_valid(link) or not link.enabled:
		return null
	var entry: Vector2 = link.entry_point(player_entity.floor_id)
	if player_entity.global_position.distance_to(entry) <= link.arrival_distance:
		if link.transfer(player_entity):
			# 切层会重置寻路缓存；走出坡道前仍保留高层绘制，避免下楼时突然被岩壁遮住。
			_stair_visual_link = link
			# 远目标自然会离开出口；只有近处的停止指令需要补一段出口清空动作。
			if destination_floor == player_entity.floor_id \
				and destination.distance_to(link.entry_point(player_entity.floor_id)) \
					<= link.exit_clearance(player_entity) + link.body_radius(player_entity):
				_stair_exit_point = link.exit_position(player_entity, destination)
				_stair_exit_link = link
				_stair_exit_floor = player_entity.floor_id
				_stair_exit_goal = destination
				_stair_exit_repath_left = repath_interval
			_update_stair_visual()
		return null
	return entry


func has_pending_stair_exit() -> bool:
	if not is_instance_valid(_stair_exit_link):
		return false
	if player_entity.floor_id == _stair_exit_floor \
		and player_entity.global_position.distance_to(_stair_exit_link.entry_point(_stair_exit_floor)) \
			< _stair_exit_link.exit_clearance(player_entity):
		return true
	_stair_exit_link = null
	_stair_exit_point = Vector2.INF
	_stair_arrival_goal = _stair_exit_goal
	_stair_arrival_point = player_entity.global_position
	# 出口走完后重新以真实目的地规划，不能继续使用刚才的出入口路径。
	_has_goal = false
	_floor_route_from = -1
	return false


# 多人点同一个近处出口时，允许在刚让开的身体间距内站定，不再回挤固定切层点。
func has_reached_stair_destination(destination: Vector2, tolerance: float) -> bool:
	return tolerance >= radius * 2.0 and _stair_arrival_goal.is_equal_approx(destination) \
		and player_entity.floor_id == _stair_exit_floor \
		and player_entity.global_position.distance_to(_stair_arrival_point) <= radius * 0.5


# 只有路线正在经过的楼梯才临时抬高绘制；桥下路过同一坐标不改变楼层或遮挡。
func refresh_forced_movement_visual(links: Array) -> void:
	for link: Node2D in links:
		if is_instance_valid(link) and link.enabled and link.overlaps_visual_body(get_visual_body_bounds()):
			_stair_visual_link = link
			break
	_update_stair_visual()


func _update_stair_visual() -> void:
	if player_entity.unit_data.is_flying or not is_instance_valid(player_entity.floor_map):
		return
	var link: Node2D = _floor_route.get("transition")
	var bounds := get_visual_body_bounds()
	if is_instance_valid(link) and link.overlaps_visual_body(bounds):
		_stair_visual_link = link
	var visual_floor: int = player_entity.floor_id
	if is_instance_valid(_stair_visual_link) \
		and player_entity.floor_id in [_stair_visual_link.from_floor, _stair_visual_link.to_floor] \
		and _stair_visual_link.overlaps_visual_body(bounds):
		visual_floor = maxi(_stair_visual_link.from_floor, _stair_visual_link.to_floor)
	else:
		_stair_visual_link = null
	player_entity.z_index = (visual_floor - 1) * player_entity.floor_map.floor_z_stride


# 只在首次使用动画/朝向时读取透明边，合并整段动画的可见范围，避免行走帧宽变化引起遮挡闪烁。
func get_visual_body_bounds() -> Rect2:
	var frames := animated_sprite_2d.sprite_frames
	var animation := animated_sprite_2d.animation
	var key := "%d:%s:%s:%s:%s" % [frames.get_instance_id(), animation, animated_sprite_2d.centered,
		animated_sprite_2d.flip_h, animated_sprite_2d.flip_v]
	if not _visual_bounds_cache.has(key):
		var bounds := Rect2()
		for index in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation, index)
			if texture == null:
				continue
			var image := texture.get_image()
			if image == null:
				continue
			var used := Rect2(image.get_used_rect())
			if not used.has_area():
				continue
			var size := texture.get_size()
			if animated_sprite_2d.flip_h:
				used.position.x = size.x - used.end.x
			if animated_sprite_2d.flip_v:
				used.position.y = size.y - used.end.y
			if animated_sprite_2d.centered:
				used.position -= size * 0.5
			bounds = bounds.merge(used) if bounds.has_area() else used
		_visual_bounds_cache[key] = bounds
	var local_bounds: Rect2 = _visual_bounds_cache[key]
	local_bounds.position += animated_sprite_2d.offset
	return animated_sprite_2d.global_transform * local_bounds


# 作用：取消旧移动请求，让其它单位把自己当作暂时站定的障碍；没有参数，没有返回值。
func stop_navigation() -> void:
	if is_flight_transitioning():
		_flight_transition_floor = 0
	_request_frame = -1
	velocity = Vector2.ZERO
	player_entity.velocity = Vector2.ZERO
	_detour_active = false
	_detour_clear_time = 0.0
	_requested_direction = Vector2.ZERO
	_progress_time = 0.0
	_progress_origin = player_entity.global_position
	avoidance_priority = 1.0
	_update_flight_visual()


# 瞬移后抛弃旧追击路线，避免延迟的避让请求把单位拉回起点。
func reset_after_teleport() -> void:
	_stair_arrival_goal = Vector2.INF
	_stair_arrival_point = Vector2.INF
	_stair_exit_link = null
	_stair_exit_point = Vector2.INF
	_flight_transition_floor = 0
	_flight_height = (player_entity.floor_id - 1) * FLIGHT_FLOOR_HEIGHT
	_flight_visual_floor = 0
	stop_navigation()
	_stair_visual_link = null
	_has_goal = false
	_repath_left = 0.0
	_goal = player_entity.global_position
	target_position = player_entity.global_position
	_floor_route_from = -1
	_floor_route.clear()
	_update_stair_visual()


# 作用：检查方向是否在导航内且容得下身体；direction 为方向、distance 为探测距离，返回能否通行。
func _can_travel(direction: Vector2, distance: float) -> bool:
	var map := get_navigation_map()
	var start: Vector2 = player_entity.global_position
	# 中点、终点不能掉进导航缺口；完整碰撞体扫描防止蹭墙或穿过单位。
	var start_error := NavigationServer2D.map_get_closest_point(map, start).distance_to(start)
	for fraction in [0.5, 1.0]:
		var point: Vector2 = start + direction * distance * fraction
		# 已被挤到边缘外时允许朝导航内恢复，禁止继续往外走。
		if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) > maxf(0.5, start_error - 0.05):
			return false
	return not player_entity.test_move(player_entity.global_transform, direction * distance)


# 作用：路径前方堵住时选可走的侧向；forward 是原方向，返回新方向或零向量。
func _choose_clear_direction(forward: Vector2) -> Vector2:
	avoidance_priority = 0.5
	# 楼梯入口可能紧贴本层导航边缘；到入口就会切层，不能把入口以后的边界当成墙。
	var goal_distance := player_entity.global_position.distance_to(_goal)
	var forward_clear := _can_travel(forward, minf(obstacle_lookahead, goal_distance))
	if _detour_active:
		# 短探针刚好避开队友不代表已经绕过；要走离堵点且连续几帧能看清更远的前路。
		var rejoin_distance := minf(goal_distance, maxf(obstacle_lookahead, maxf(radius * 3.5, 52.0)))
		if player_entity.global_position.distance_to(_detour_origin) >= radius * 2.0 \
			and _can_travel(forward, rejoin_distance):
			_detour_clear_time += player_entity.get_physics_process_delta_time()
			if _detour_clear_time >= 0.2:
				_detour_active = false
				_detour_clear_time = 0.0
				return forward
		else:
			_detour_clear_time = 0.0
		# 固定的一小段走完后继续沿同一侧找下一段，不因原路径一瞬间可走就掉头。
		var remaining: float = player_entity.global_position.distance_to(_detour_point)
		var detour_direction: Vector2 = player_entity.global_position.direction_to(_detour_point)
		if remaining > 8.0 and _can_travel(detour_direction, minf(obstacle_lookahead, remaining)):
			return detour_direction
	elif forward_clear:
		return forward
	var best := Vector2.ZERO
	var best_score := -INF
	var best_side := _side
	var detour_distance := maxf(radius * 3.5, 52.0)
	# 已在绕行时只沿选定一侧继续；真走不通时由卡住检测换侧，而不是每帧来回试探。
	for angle in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		if _detour_active and signf(angle) != _side:
			continue
		var candidate := forward.rotated(deg_to_rad(angle))
		if not _can_travel(candidate, detour_distance):
			continue
		var score: float = candidate.dot(forward) * 0.3 + (0.6 if signf(angle) == _side else 0.0)
		if score > best_score:
			best_score = score
			best = candidate
			best_side = signf(angle)
	if best != Vector2.ZERO:
		if not _detour_active:
			_detour_origin = player_entity.global_position
			_side = best_side
			_detour_active = true
		_detour_point = player_entity.global_position + best * detour_distance
	return best


# 作用：Godot 算好避让后执行一次移动；safe_velocity 是避让速度，没有返回值。
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if player_entity.unit_data.is_flying:
		return
	# 攻击可能在提交速度之后开始；过期、跨阶段、死亡后的回调不能推动身体。
	if _request_frame != Engine.get_physics_frames() or _request_phase != Global.game_phase:
		# 没有新请求就清除避让服务器里的旧意图，但不能改掉冲刺技能自己的身体速度。
		velocity = Vector2.ZERO
		avoidance_priority = 1.0
		return
	if not player_entity.is_physics_processing() or player_entity.current_state == player_entity.State.DEATH or player_entity.is_action_blocked():
		return
	if skill_manager.is_casting or skill_manager.is_reacting or skill_manager.is_forced_moving:
		stop_navigation()
		return
	_request_frame = -1
	var delta := player_entity.get_physics_process_delta_time()
	var motion := safe_velocity * delta
	# RVO 不认识墙，其修正方向也要检查；最终交给物理系统，而不是直接改坐标。
	if motion.length() > 0.001:
		var next_position: Vector2 = player_entity.global_position + motion
		var on_map := NavigationServer2D.map_get_closest_point(get_navigation_map(), next_position)
		# 把越界的这一小步压回导航边缘，保留沿边移动，而不是整个速度强制归零。
		safe_velocity = ((on_map - player_entity.global_position) / delta).limit_length(max_speed)
	# 避让或导航边缘投影都可能给出后退速度；绕人时宁可短暂停下等待换侧，也不反复倒退。
	if _detour_active and _requested_direction != Vector2.ZERO \
		and safe_velocity.dot(_requested_direction) < -max_speed * 0.05:
		safe_velocity = Vector2.ZERO
	var before: Vector2 = player_entity.global_position
	player_entity.velocity = safe_velocity
	player_entity.move_and_slide()
	_update_stair_visual()
	var travelled: Vector2 = player_entity.global_position - before
	# 看一整个时间窗的净位移；原地前后抖动也算卡住，正常侧绕则有足够位移。
	_progress_time += delta
	if _progress_time >= stuck_timeout:
		if player_entity.global_position.distance_to(_progress_origin) < maxf(radius, 12.0):
			_side *= -1.0
			_detour_active = false
			_detour_clear_time = 0.0
			target_position = _goal
			_repath_left = repath_interval
		_progress_origin = player_entity.global_position
		_progress_time = 0.0
	_play_movement(travelled)


func _play_movement(travelled: Vector2) -> void:
	if travelled.length() > 0.01:
		player_entity.switch_state(player_entity.State.WALK)
		animated_sprite_2d.play("walk")
		if absf(travelled.x) > 0.05:
			animated_sprite_2d.flip_h = travelled.x < 0.0
	elif player_entity.current_state == player_entity.State.WALK:
		player_entity.switch_state(player_entity.State.IDLE)
		animated_sprite_2d.play("idle")


# 作用：阶段切换时丢弃旧路径和速度；phase 是新阶段，没有返回值。
func _on_phase_changed(phase: Global.GamePhase) -> void:
	_stair_arrival_goal = Vector2.INF
	_stair_arrival_point = Vector2.INF
	_stair_exit_link = null
	_stair_exit_point = Vector2.INF
	stop_navigation()
	_has_goal = false
	avoidance_enabled = not player_entity.unit_data.is_flying and player_entity.current_state != player_entity.State.DEATH \
		and (phase == Global.GamePhase.CARD_PLAY or phase == Global.GamePhase.AUTO_BATTLE)


# 作用：死亡立即退出避让并释放身体阻挡；unit 是死亡者，没有返回值。
func _on_unit_died(_unit: UnitBase) -> void:
	stop_navigation()
	avoidance_enabled = false
	player_entity.set_deferred("collision_layer", 0)
	player_entity.set_deferred("collision_mask", 0)
