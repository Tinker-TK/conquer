# 这玩意儿是干嘛的（核心逻辑）：用真实单位验证绕墙、绕队友、部署与停止移动。
# 数据是咋流动的（数据流向）：合成导航和物理墙 → 真实单位移动 → 检查位置和阶段状态。
# 为啥这么写（选型决策）：不能只验证代码能编译，必须真正经过物理帧和避让回调。
# 性能咋样（复杂度）：仅手动测试运行，每个案例最多模拟十五秒，不参与游戏。
extends Node

var goals: Dictionary = {}
var units: Array[UnitBase] = []
var failures: int = 0
var region: NavigationRegion2D
var wall: StaticBody2D


# 作用：Godot 初始化测试后开始执行；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：Godot 每个物理帧提交测试移动；delta 为间隔，没有返回值。
func _physics_process(_delta: float) -> void:
	for unit in goals:
		if not is_instance_valid(unit):
			continue
		if unit.global_position.distance_to(goals[unit]) > 10.0:
			unit.navigation_agent_2d.move_to(goals[unit])
		else:
			unit.navigation_agent_2d.stop_navigation()


# 作用：记录条件是否通过；condition 是结果，message 是案例名称，没有返回值。
func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


# 作用：创建一个真实单位；point 为位置，ally 决定阵营，返回该单位。
func _unit(point: Vector2, ally: bool = false) -> UnitBase:
	var path := "res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn"
	var unit: UnitBase = load(path).instantiate()
	unit.position = point
	add_child(unit)
	units.append(unit)
	return unit


# 作用：移除上个案例中的单位；没有参数，没有返回值。
func _clear_units() -> void:
	goals.clear()
	for unit in units:
		if is_instance_valid(unit):
			unit.queue_free()
	units.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame


# 作用：创建带矩形墙的导航与实际碰撞；没有参数，没有返回值。
func _build_map() -> void:
	region = NavigationRegion2D.new()
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 24.0
	polygon.add_outline(PackedVector2Array([Vector2(100, 100), Vector2(900, 100), Vector2(900, 800), Vector2(100, 800)]))
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_obstruction_outline(PackedVector2Array([Vector2(460, 330), Vector2(540, 330), Vector2(540, 570), Vector2(460, 570)]))
	NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	region.navigation_polygon = polygon
	add_child(region)
	wall = StaticBody2D.new()
	wall.position = Vector2(500, 450)
	wall.collision_layer = 8
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(80, 240)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)


# 作用：执行真实物理移动案例；没有参数，没有返回值，最终用退出码报告失败。
func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_build_map()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walker := _unit(Vector2(280, 450))
	goals[walker] = Vector2(740, 450)
	var crossed_wall := false
	for frame in 900:
		await get_tree().physics_frame
		if Rect2(445, 315, 110, 270).has_point(walker.global_position):
			crossed_wall = true
		if walker.global_position.distance_to(goals[walker]) <= 12.0:
			break
	_check(walker.global_position.distance_to(goals[walker]) <= 15.0, "绕过物理墙到达目的地 " + str(walker.global_position))
	_check(not crossed_wall, "绕墙全过程身体不穿墙")
	await _clear_units()

	# 在墙的左侧设置站定前排，后排必须绕过去，不能一直贴着它等待。
	var front := _unit(Vector2(300, 240))
	front.navigation_agent_2d.stop_navigation()
	walker = _unit(Vector2(240, 240))
	goals[walker] = Vector2(700, 240)
	var backward_frames := 0
	var backward_distance := 0.0
	var previous_x: float = walker.global_position.x
	for frame in 600:
		await get_tree().physics_frame
		var step_x: float = walker.global_position.x - previous_x
		if step_x < -0.5:
			backward_frames += 1
			backward_distance -= step_x
		previous_x = walker.global_position.x
		if walker.global_position.distance_to(goals[walker]) <= 12.0:
			break
	print("站定前排反向移动：%d 帧，%.1f 像素" % [backward_frames, backward_distance])
	_check(walker.global_position.distance_to(goals[walker]) <= 15.0, "后排绕过站定前排 " + str(walker.global_position))
	_check(backward_frames <= 2, "后排绕过站定前排时不反复倒退：%d 帧" % backward_frames)
	_check(front.global_position.distance_to(Vector2(300, 240)) < 0.1, "站定前排不被旧避让速度推走")
	await _clear_units()

	# 同时让六人经过墙边，目标稍微错开以便所有人都有真实站立空间。
	for index in 6:
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		walker = _unit(Vector2(230 - (index % 2) * 40, 210 + (index / 2) * 42))
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		goals[walker] = Vector2(700 + (index % 2) * 45, 210 + (index / 2) * 45)
	var crowd_backwards := 0
	var previous_positions: Dictionary = {}
	for unit in goals:
		previous_positions[unit] = unit.global_position
	for frame in 900:
		await get_tree().physics_frame
		for unit in goals:
			if unit.global_position.x < previous_positions[unit].x - 0.5:
				crowd_backwards += 1
			previous_positions[unit] = unit.global_position
	print("六人拥挤反向移动帧数：", crowd_backwards)
	var arrived := 0
	for unit in goals:
		if unit.global_position.distance_to(goals[unit]) < 20.0:
			arrived += 1
		else:
			print("未到达单位：", unit.global_position, " 目标：", goals[unit])
	_check(arrived == 6, "六人同时移动到达：%d/6" % arrived)
	# 过去只验证终点，六人仍会累计 131 帧向后走；这条断言专门防止拥挤时的折返回归。
	_check(crowd_backwards <= 40, "六人拥挤时少量避让且不反复倒退：%d 帧" % crowd_backwards)
	await _clear_units()

	# 己方在打牌时也能绕墙调整站位，开战时旧部署指令立即停止。
	walker = _unit(Vector2(280, 450), true)
	walker.target_position = Vector2(740, 450)
	for frame in 900:
		await get_tree().physics_frame
		if walker.target_position == null:
			break
	_check(walker.global_position.distance_to(Vector2(740, 450)) <= walker.arrival_distance + 2.0, "己方部署入口绕墙")
	walker.target_position = Vector2(280, 450)
	for frame in 20:
		await get_tree().physics_frame
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var stopped: Vector2 = walker.global_position
	for frame in 20:
		await get_tree().physics_frame
	_check(walker.global_position.distance_to(stopped) < 0.1, "开战后没有残余部署移动")
	await _clear_units()

	# 提交移动后立刻进入施法，回调不得推动正在攻击的单位。
	Global.game_phase = Global.GamePhase.CARD_PLAY
	walker = _unit(Vector2(250, 220))
	walker.navigation_agent_2d.move_to(Vector2(700, 220))
	stopped = walker.global_position
	walker.skill_manager.is_casting = true
	for frame in 10:
		await get_tree().physics_frame
	_check(walker.global_position.distance_to(stopped) < 0.1, "施法取消待执行移动")
	walker.skill_manager.is_casting = false
	walker.die()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not walker.navigation_agent_2d.avoidance_enabled and walker.collision_layer == 0, "死亡立即释放避让和身体阻挡")
	await _clear_units()

	# 最后启用真正的索敌与攻击：三对三从远处接近，不能只会走路却无法开打。
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for index in 3:
		var ally := _unit(Vector2(220, 200 + index * 50), true)
		var enemy := _unit(Vector2(750, 200 + index * 50))
		ally.current_health = 10000
		enemy.current_health = 10000
	for frame in 900:
		await get_tree().physics_frame
	var injured := 0
	for unit in units:
		if unit.current_health < 10000:
			injured += 1
	_check(injured >= 4, "三对三自动接敌并造成伤害：%d 人受到伤害" % injured)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _clear_units()
	if failures == 0:
		print("NAVIGATION_MOVEMENT_PASS")
	get_tree().quit(0 if failures == 0 else 1)
