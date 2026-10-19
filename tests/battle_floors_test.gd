# 使用真实 TileMapLayer、物理碰撞、导航和单位跑四层交叠/楼梯移动回归。
extends Node2D

const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
const TRANSITION = preload("res://scenes/world/foolrtransition/floor_transition.tscn")
var terrain: NavigationRegion2D
var failures := 0
var checks := 0
var units: Array[UnitBase] = []
var walker: UnitBase
var goal := Vector2.ZERO
var goal_floor := 1
var moving := false
var visited_floors: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if moving and is_instance_valid(walker):
		visited_floors[walker.floor_id] = true
		walker.navigation_agent_2d.move_to(goal, goal_floor)


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _build_map(split_ground: bool = false) -> void:
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	terrain = FLOORS.new()
	terrain.name = "NavigationRegion2D"
	terrain.floor_agent_radius = 24.0
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_physics_layer()
	tiles.set_physics_layer_collision_layer(0, 8)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	atlas.create_tile(Vector2i(1, 0))
	tiles.add_source(atlas, 0)
	var wall := atlas.get_tile_data(Vector2i(1, 0), 0)
	wall.add_collision_polygon(0)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)]))
	for floor_id in range(1, 5):
		var layer := TileMapLayer.new()
		layer.name = "Layer%02d" % floor_id
		# 故意共用 TileSet，验证运行时隔离资源不会互相改写楼层位。
		layer.tile_set = tiles
		for x in 12:
			if split_ground and floor_id == 1 and x >= 4 and x < 8:
				continue
			if (floor_id == 3 and x < 4) or (floor_id == 4 and x < 6):
				continue
			for y in 8:
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		if floor_id == 2:
			layer.set_cell(Vector2i(5, 3), 0, Vector2i(1, 0))
		terrain.add_child(layer)
	for floor_id in range(1, 4):
		var link := TRANSITION.instantiate()
		link.name = "Stairs%d%d" % [floor_id, floor_id + 1]
		link.from_floor = floor_id
		link.to_floor = floor_id + 1
		link.position = Vector2(160 + (floor_id - 1) * 160, 128)
		terrain.add_child(link)
	if split_ground:
		var return_stairs := TRANSITION.instantiate()
		return_stairs.name = "ReturnStairs"
		return_stairs.from_floor = 2
		return_stairs.to_floor = 1
		return_stairs.position = Vector2(600, 128)
		terrain.add_child(return_stairs)
	level.add_child(terrain)
	check(tiles.get_physics_layer_collision_layer(0) == 8, "共享 TileSet 原资源不被改写")


func _unit(point: Vector2, floor_id: int, ally: bool = false, scene_name: String = "") -> UnitBase:
	if scene_name.is_empty():
		scene_name = "soldier" if ally else "orc"
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene_name).instantiate()
	unit.position = point
	unit.floor_id = floor_id
	add_child(unit)
	units.append(unit)
	return unit


func _clear() -> void:
	moving = false
	for unit in units:
		unit.queue_free()
	units.clear()
	walker = null
	await get_tree().physics_frame
	await get_tree().physics_frame


func _move(unit: UnitBase, destination: Vector2, floor_id: int, frame_limit: int = 900) -> void:
	walker = unit
	goal = destination
	goal_floor = floor_id
	visited_floors.clear()
	moving = true
	for frame in frame_limit:
		await get_tree().physics_frame
		if walker.floor_id == floor_id and walker.global_position.distance_to(destination) <= 8.0:
			break
	moving = false
	walker.navigation_agent_2d.stop_navigation()


func _test_auxiliary_layers() -> void:
	get_node("Level").free()
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	terrain = FLOORS.new()
	terrain.name = "NavigationRegion2D"
	var image := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_physics_layer()
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO, Vector2i(6, 3))
	atlas.create_tile(Vector2i(6, 0))
	tiles.add_source(atlas, 0)
	atlas.get_tile_data(Vector2i.ZERO, 0).texture_origin = Vector2i(-160, -64)
	var main := TileMapLayer.new()
	main.name = "Layer02"
	main.tile_set = tiles
	main.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	var child := TileMapLayer.new()
	child.name = "RampChild"
	child.position.x = 384
	child.tile_set = tiles
	for x in 2:
		for y in 3:
			child.set_cell(Vector2i(x, y), 0, Vector2i(6, 0))
	main.add_child(child)
	terrain.add_child(main)
	var sibling := TileMapLayer.new()
	sibling.name = "stair02"
	sibling.position.x = 512
	sibling.tile_set = tiles
	for x in 2:
		for y in 3:
			sibling.set_cell(Vector2i(x, y), 0, Vector2i(6, 0))
	terrain.add_child(sibling)
	# 自定义地面含两个可走岛屿，合并图片中间应保持不可走；翻转后仍须保留缺口。
	var shaped := TileMapLayer.new()
	shaped.name = "Layer03"
	shaped.position.y = 320
	shaped.tile_set = tiles.duplicate(true)
	shaped.tile_set.add_navigation_layer()
	var navigation := NavigationPolygon.new()
	navigation.vertices = PackedVector2Array([Vector2(-32, -32), Vector2(96, -32), Vector2(96, 160), Vector2(-32, 160),
		Vector2(224, -32), Vector2(352, -32), Vector2(352, 160), Vector2(224, 160)])
	navigation.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	shaped.tile_set.get_source(0).get_tile_data(Vector2i.ZERO, 0).set_navigation_polygon(0, navigation)
	shaped.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	shaped.set_cell(Vector2i(10, 0), 0, Vector2i.ZERO, TileSetAtlasSource.TRANSFORM_FLIP_H)
	terrain.add_child(shaped)
	level.add_child(terrain)
	for frame in 180:
		await get_tree().physics_frame
		if terrain.is_walkable(Vector2(600, 96), 2) and terrain.is_walkable(Vector2(64, 416), 3):
			break
	check(terrain.is_walkable(Vector2(320, 96), 2), "合并为6×3的大瓦片完整范围参与导航")
	check(terrain.is_walkable(Vector2(480, 96), 2), "Layer02的子瓦片层归入第二层导航")
	check(terrain.is_walkable(Vector2(600, 96), 2), "stair02附属瓦片层归入第二层导航")
	check(child.tile_set.get_physics_layer_collision_layer(0) == FLOORS.terrain_bit(2) \
		and sibling.tile_set.get_physics_layer_collision_layer(0) == FLOORS.terrain_bit(2), "子层和附属坡道继承第二层碰撞位")
	check(child.z_index == 45 and not child.z_as_relative, "子坡道不会重复叠加父节点的楼层绘制顺序")
	check(not terrain.is_walkable(Vector2.ZERO, 1), "空地面层不会借用附属高层地面")
	check(terrain.is_walkable(Vector2(64, 416), 3) and terrain.is_walkable(Vector2(320, 416), 3) \
		and not terrain.is_walkable(Vector2(192, 416), 3), "显式瓦片导航保留多个可走区域和中间缺口")
	check(terrain.is_walkable(Vector2(640, 416), 3) and not terrain.is_walkable(Vector2(512, 416), 3), "翻转后的瓦片导航仍与图块方向一致")
	var unit := _unit(Vector2(96, 96), 2)
	await _move(unit, Vector2(600, 96), 2)
	check(unit.global_position.distance_to(Vector2(600, 96)) <= 10.0, "真实单位可以走过合并地面、子坡道和stair02")
	await _clear()


func _test_authored_map() -> void:
	get_node("Level").free()
	var battle: Node = load("res://scenes/levels/battles/battle_005.tscn").instantiate()
	var level: Node2D = battle.get_node("Level")
	terrain = level.get_node("NavigationRegion2D")
	var enemy_transform: Transform2D = battle.get_node("Entities/TeamB").transform
	battle.remove_child(level)
	level.owner = null
	add_child(level)
	battle.free()
	for frame in 180:
		await get_tree().physics_frame
		var links_ready := true
		for link in terrain.transitions:
			links_ready = links_ready and terrain.is_walkable(link.entry_point(1), 1) and terrain.is_walkable(link.entry_point(2), 2)
		if links_ready:
			break
	check(terrain.transitions.size() > 0, "正式battle_005包含楼梯连接")
	for link in terrain.transitions:
		var entry: Vector2 = link.entry_point(1)
		check(terrain.is_walkable(entry, 1) and terrain.is_walkable(link.entry_point(2), 2), "%s的两层连接点均在可走范围内" % link.name)
		var direction := -1.0 if entry.x > 1000 else 1.0
		var start := NavigationServer2D.map_get_closest_point(terrain.get_floor_map(1), entry - Vector2(direction * 96, 0))
		var finish := NavigationServer2D.map_get_closest_point(terrain.get_floor_map(2), entry + Vector2(direction * 160, 0))
		var unit := _unit(start, 1)
		await _move(unit, finish, 2)
		check(unit.floor_id == 2 and unit.global_position.distance_to(finish) < 10.0,
			"%s实际从第一层上坡到第二层：%s" % [link.name, unit.global_position])
		await _move(unit, start, 1)
		check(unit.floor_id == 1 and unit.global_position.distance_to(start) < 10.0,
			"%s实际从第二层返回第一层：%s" % [link.name, unit.global_position])
		await _clear()
	await _test_stair_flow()
	await _test_authored_waves(enemy_transform)


# 单人从不同方向接近三处楼梯；必须连续通过，不能被连接点后的导航边界逼停或绕行。
func _test_stair_flow() -> void:
	for link in terrain.transitions:
		for from_floor in [1, 2]:
			# 左侧坡道下方还有独立岩壁边缘，二层起点取坡道与高地连通的一侧。
			var offsets: Array = [-100.0, 0.0, 100.0] if from_floor == 1 else [0.0, 50.0, 100.0]
			for y_offset in offsets:
				var transition_entry: Vector2 = link.entry_point(from_floor)
				var direction := -1.0 if transition_entry.x > 1000 else 1.0
				if from_floor == 2:
					direction *= -1.0
				var start := NavigationServer2D.map_get_closest_point(terrain.get_floor_map(from_floor), transition_entry - Vector2(direction * 96, y_offset))
				goal_floor = 3 - from_floor
				goal = NavigationServer2D.map_get_closest_point(terrain.get_floor_map(goal_floor), transition_entry + Vector2(direction * 160, 0))
				walker = _unit(start, from_floor)
				var previous := start
				var stopped_frames := 0
				var detour_frames := 0
				var wrong_visual_frames := 0
				moving = true
				for frame in 240:
					await get_tree().physics_frame
					if frame > 1:
						var visual_floor: int = 2 if link.overlaps_visual_body(walker.navigation_agent_2d.get_visual_body_bounds()) else walker.floor_id
						if walker.z_index != (visual_floor - 1) * terrain.floor_z_stride:
							wrong_visual_frames += 1
					if frame > 1 and walker.global_position.distance_to(transition_entry) < 80.0:
						if previous.distance_to(walker.global_position) < 0.1:
							stopped_frames += 1
						if walker.navigation_agent_2d._detour_active:
							detour_frames += 1
					previous = walker.global_position
					if walker.floor_id == goal_floor and walker.global_position.distance_to(goal) < 8.0:
						break
				moving = false
				check(walker.floor_id == goal_floor and walker.global_position.distance_to(goal) < 8.0,
					"%s第%d层偏移%.0f连续通过楼梯" % [link.name, from_floor, y_offset])
				check(stopped_frames <= 1 and detour_frames == 0,
					"%s第%d层偏移%.0f无台阶边缘假阻挡：停步%d帧，绕行%d帧" % [link.name, from_floor, y_offset, stopped_frames, detour_frames])
				check(wrong_visual_frames == 0 and walker.z_index == (walker.floor_id - 1) * terrain.floor_z_stride,
					"%s第%d层偏移%.0f坡道身体不被岩壁遮住，离开后恢复本层绘制" % [link.name, from_floor, y_offset])
				await _clear()
	# 位于楼梯投影范围内但目标仍在一层时，保留桥下的正常遮挡和物理位。
	var link: Node2D = terrain.transitions[2]
	var entry: Vector2 = link.entry_point(1)
	var unit := _unit(entry + Vector2(14, -17), 1)
	unit.navigation_agent_2d.move_to(entry + Vector2(96, 0), 1)
	check(link.contains_visual_point(unit.global_position) and unit.floor_id == 1 and unit.z_index == 0,
		"桥下路过楼梯区域而未上楼时，不提前抬高绘制层")
	unit.navigation_agent_2d.move_to(entry - Vector2(160, 0), 2)
	check(unit.floor_id == 1 and unit.z_index == terrain.floor_z_stride \
		and unit.navigation_agent_2d.get_navigation_map() == terrain.get_floor_map(1),
		"走上坡道时只调整绘制，入口前仍使用一层导航和碰撞")
	unit.global_position = entry + Vector2(48, 0)
	unit.navigation_agent_2d.reset_after_teleport()
	unit.navigation_agent_2d.move_to(entry - Vector2(160, 0), 2)
	check(not link.contains_visual_point(unit.global_position) and unit.z_index == terrain.floor_z_stride,
		"脚底尚未进入坡道时，身体接触台阶就已抬高绘制，避免半身被盖住")
	unit.global_position = entry + Vector2(96, 0)
	unit.navigation_agent_2d.reset_after_teleport()
	check(unit.z_index == 0, "瞬移离开坡道会清除临时绘制层")
	await _clear()


# 真正加载关卡波次并启动自动战斗，防止只测楼梯通行却漏掉错层出生和索敌停摆。
func _test_authored_waves(enemy_transform: Transform2D) -> void:
	var config: BattleLevelConfig = load("res://data/levels/level_107_1.tres")
	# 第六轮再次使用首波，覆盖循环后的同一套寻路入口。
	for wave_index in range(config.waves.size() + 1):
		Global.game_phase = Global.GamePhase.CARD_PLAY
		if config.waves[wave_index % config.waves.size()] == null:
			check(wave_index == 3, "数值框架第4轮为空波喘息")
			continue
		var wave := config.waves[wave_index % config.waves.size()].instantiate()
		var enemies: Array[UnitBase] = []
		var starts: Array[Vector2] = []
		var previous: Array[Vector2] = []
		var max_step := 0.0
		for child in wave.get_children():
			var enemy := child as UnitBase
			if enemy == null:
				continue
			enemy.owner = null
			wave.remove_child(enemy)
			enemy.position = enemy_transform * enemy.position
			add_child(enemy)
			enemy.current_health = 1000000
			units.append(enemy)
			enemies.append(enemy)
			starts.append(enemy.global_position)
			previous.append(enemy.global_position)
			check(terrain.is_walkable(enemy.global_position, enemy.floor_id, 0.5),
				"level_107_1第%d波%s出生点位于配置楼层导航内" % [wave_index + 1, enemy.name])
		wave.free()
		var deployment := NavigationServer2D.map_get_closest_point(terrain.get_floor_map(1), Vector2(400, 700))
		var ally := _unit(deployment, 1, true)
		check(terrain.is_walkable(ally.global_position, 1, 0.5), "己方测试单位位于真实部署地面")
		ally.current_health = 1000000
		ally.set_physics_process(false)
		for enemy in enemies:
			check(not terrain.route(enemy.global_position, enemy.floor_id, ally.global_position, ally.floor_id).is_empty(),
				"level_107_1第%d波%s到己方部署区可达" % [wave_index + 1, enemy.name])
		Global.game_phase = Global.GamePhase.AUTO_BATTLE
		for frame in 2100:
			await get_tree().physics_frame
			for index in enemies.size():
				var world_position := enemies[index].global_position
				max_step = maxf(max_step, previous[index].distance_to(world_position))
				previous[index] = world_position
			if frame >= 180 and ally.current_health < 1000000:
				break
		var moved := 0
		for index in enemies.size():
			if starts[index].distance_to(enemies[index].global_position) > 16.0:
				moved += 1
		check(moved == enemies.size(), "level_107_1第%d波全部怪物自动接敌：%d/%d" % [wave_index + 1, moved, enemies.size()])
		if ally.current_health == 1000000:
			for enemy in enemies:
				print("WAVE_STUCK ", wave_index + 1, " ", enemy.name, " at=", enemy.global_position,
					" floor=", enemy.floor_id, " state=", enemy.current_state, " target=", enemy.skill_manager.current_target,
					" route=", terrain.route(enemy.global_position, enemy.floor_id, ally.global_position, ally.floor_id))
		check(ally.current_health < 1000000, "level_107_1第%d波实际寻路后攻击命中" % [wave_index + 1])
		check(max_step < 8.0, "level_107_1第%d波寻路没有从错误楼层瞬移到导航边缘" % [wave_index + 1])
		Global.game_phase = Global.GamePhase.CARD_PLAY
		await _clear()


func _test_high_ground_combat() -> void:
	var attacker := _unit(Vector2(500, 128), 3, true)
	var target := _unit(Vector2(560, 128), 1)
	attacker.set_physics_process(false)
	target.set_physics_process(false)
	target.unit_data.max_hp = 10000
	target.current_health = 10000
	target.unit_data.defence = 0
	target.unit_data.dodge_skill = null
	for entry in [[2, 1, 110], [3, 1, 120], [4, 1, 130], [4, 3, 110], [3, 3, 100], [1, 4, 100]]:
		attacker.set_floor(entry[0])
		target.set_floor(entry[1])
		var before := int(target.current_health)
		check(target.get_hurt(100, attacker, false) and before - target.current_health == entry[2],
			"第%d层打第%d层：基础100伤害结算为%d" % entry)
	attacker.set_floor(3)
	target.set_floor(1)
	target.unit_data.defence = 20
	var health := int(target.current_health)
	target.get_hurt(100, attacker, false)
	check(health - target.current_health == 96, "先扣20防御再加20%高地伤害")
	target.unit_data.defence = 0
	health = target.current_health
	target.get_hurt(100, null, false)
	check(health - target.current_health == 100, "无攻击来源的伤害不获得高地加成")
	health = target.current_health
	target.take_effect_damage(100, attacker)
	check(health - target.current_health == 100, "毒与环境直接伤害保持原有规则")
	attacker.unit_data.unit_team = target.unit_data.unit_team
	health = target.current_health
	check(not target.get_hurt(100, attacker, false) and target.current_health == health, "跨层攻击仍拒绝友军伤害")
	attacker.unit_data.unit_team = "team_a"

	# 关闭所有楼梯，验证实际近战在射程内索敌、停步并播放动画命中。
	for link in terrain.transitions:
		link.enabled = false
	attacker.unit_data.attack = 100
	attacker.skill_manager.group_skills.assign([attacker.unit_data.skills[0]])
	attacker.skill_manager.clear_target_cache()
	check(attacker.skill_manager.find_nearest_enemy() == target, "射程内跨层目标不需要楼梯也能被索敌")
	attacker.set_physics_process(true)
	health = target.current_health
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for frame in 180:
		await get_tree().physics_frame
		if target.current_health < health:
			break
	check(health - target.current_health == 120, "真实近战动画跨层命中并增加20%伤害")
	check(attacker.floor_id == 3 and target.floor_id == 1 and attacker.global_position.distance_to(Vector2(500, 128)) < 1.0,
		"射程内跨层攻击停在原地，不绕路下楼")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _clear()

	# 实际远程动画发箭后释放射手，箭仍按第四层来源结算。
	attacker = _unit(Vector2(500, 128), 4, false, "skeleton_archer")
	target = _unit(Vector2(250, 128), 1, true)
	target.set_physics_process(false)
	target.unit_data.max_hp = 10000
	target.current_health = 10000
	target.unit_data.defence = 0
	target.unit_data.dodge_skill = null
	attacker.unit_data.attack = 100
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var arrow: Projectile
	for frame in 180:
		await get_tree().physics_frame
		for child in get_children():
			if child is Projectile:
				arrow = child
		if is_instance_valid(arrow):
			break
	check(is_instance_valid(arrow), "真实远程动画向没有楼梯的异层目标发箭")
	if is_instance_valid(arrow):
		check(arrow.z_index == attacker.z_index, "跨层箭矢显示在高层地形之上")
	attacker.set_floor(1)
	units.erase(attacker)
	attacker.queue_free()
	for frame in 180:
		await get_tree().physics_frame
		if target.current_health < 10000:
			break
	check(10000 - target.current_health == 130, "发射后切层并释放射手，箭仍保留三层差的30%加成")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _clear()

	# 穿透弹逐个按目标楼层结算，同一弹不能复用首个目标的加成。
	attacker = _unit(Vector2(400, 128), 4)
	attacker.set_physics_process(false)
	var low := _unit(Vector2(500, 128), 1, true)
	var high := _unit(Vector2(600, 128), 3, true)
	for victim in [low, high]:
		victim.set_physics_process(false)
		victim.unit_data.max_hp = 10000
		victim.current_health = 10000
		victim.unit_data.defence = 0
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	arrow = load("res://scenes/projectiles/projectile.tscn").instantiate()
	add_child(arrow)
	arrow.global_position = attacker.global_position
	arrow.fire(attacker, low, 100, Projectile.Trajectory.STRAIGHT, 2, "team_a")
	for frame in 180:
		await get_tree().physics_frame
		if high.current_health < 10000:
			break
	check(10000 - low.current_health == 130 and 10000 - high.current_health == 110,
		"穿透箭对第一层加30%、第三层加10%，每个目标仅命中一次")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _clear()
	for link in terrain.transitions:
		link.enabled = true


func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_build_map()
	for frame in 180:
		await get_tree().physics_frame
		var synchronized := true
		for floor_id in range(1, 5):
			synchronized = synchronized and terrain.is_walkable(Vector2(600, 96), floor_id)
		if synchronized:
			break
	for floor_id in range(1, 5):
		check(terrain.is_walkable(Vector2(600, 96), floor_id), "第%d层导航服务器完成同步" % floor_id)
	for floor_id in range(1, 5):
		var unit := _unit(Vector2(96, 96), floor_id)
		check(unit.floor_map == terrain, "第%d层单位找到本场楼层系统" % floor_id)
		check(unit.navigation_agent_2d.get_navigation_map() == terrain.get_floor_map(floor_id), "第%d层绑定独立导航图" % floor_id)
		check(unit.navigation_agent_2d.avoidance_mask == 1 << (floor_id - 1), "第%d层只避让同层单位" % floor_id)
		check(unit.collision_layer & 2 != 0, "第%d层保留敌方阵营标记" % floor_id)
		check(unit.collision_mask & 3 == 0, "第%d层身体不通过阵营位碰到异层单位" % floor_id)
		check(unit.z_index == (floor_id - 1) * 64, "第%d层单位绘制在本层地形上方" % floor_id)
	check(terrain.get_floor_map(1) != terrain.get_floor_map(2), "桥上和桥下的导航图隔离")
	check(terrain.is_walkable(Vector2(352, 224), 1), "上层障碍不会从地面导航挖洞")
	check(not terrain.is_walkable(Vector2(352, 224), 2), "上层自己的障碍会从导航挖洞")
	check(terrain.floor_at(Vector2(160, 128), 1) == 1, "重叠位置优先保留当前楼层")
	check(terrain.floor_at(Vector2(600, 128), 1, 1) == 2, "上层移动指令能选择重叠位置的桥面")
	check(terrain.floor_at(Vector2(600, 128), 4, -1) == 3, "下层移动指令能选择重叠位置的下一层")
	check(not terrain.is_walkable(Vector2(96, 96), 3) and not terrain.is_walkable(Vector2(96, 96), 4), "上层导航不会借用其它层的地表范围")
	await _clear()
	await _test_high_ground_combat()

	var lower := _unit(Vector2(300, 224), 1, true)
	var upper := _unit(Vector2(300, 224), 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not lower.test_move(lower.global_transform, Vector2(104, 0)), "地面身体穿过桥上障碍和异层单位")
	check(upper.test_move(upper.global_transform, Vector2(104, 0)), "桥上身体被本层障碍阻挡")
	var health: int = upper.current_health
	check(upper.get_hurt(10, lower, false) and health - upper.current_health == maxi(10 - upper.unit_data.defence, 1), "重叠位置可以跨层命中，低打高不加成")
	upper.global_position = Vector2(200, 224)
	lower.global_position = Vector2(140, 224)
	upper.set_floor(1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(lower.test_move(lower.global_transform, Vector2(100, 0)), "同层单位仍会互相阻挡")
	await _clear()

	lower = _unit(Vector2(96, 224), 1)
	upper = _unit(Vector2(440, 224), 2)
	await _move(lower, Vector2(680, 224), 1)
	check(lower.global_position.distance_to(Vector2(680, 224)) <= 10.0, "实际移动从桥底通过且不被桥上单位避让推开")
	check(absf(lower.global_position.y - 224.0) < 2.0, "桥底路线保持直行")
	await _clear()

	upper = _unit(Vector2(96, 224), 2)
	await _move(upper, Vector2(680, 224), 2)
	check(upper.global_position.distance_to(Vector2(680, 224)) <= 10.0, "桥上单位实际绕过本层障碍")
	await _clear()

	lower = _unit(Vector2(96, 128), 1)
	await _move(lower, Vector2(680, 128), 1)
	check(lower.floor_id == 1, "桥下经过楼梯的 XY 投影不会自动切层")
	await _clear()

	lower = _unit(Vector2(96, 128), 1)
	await _move(lower, Vector2(680, 128), 4)
	check(lower.floor_id == 4 and lower.global_position.distance_to(Vector2(680, 128)) < 10.0, "跨三段楼梯从第一层到第四层")
	await _move(lower, Vector2(96, 128), 1)
	check(lower.floor_id == 1 and lower.global_position.distance_to(Vector2(96, 128)) < 10.0, "双向楼梯可从第四层返回第一层")
	await _clear()

	var link := terrain.get_node("Stairs34")
	link.bidirectional = false
	check(terrain.route(Vector2(600, 128), 4, Vector2(96, 128), 1).is_empty(), "单向楼梯禁止逆向寻路")
	link.enabled = false
	check(terrain.route(Vector2(96, 128), 1, Vector2(600, 128), 4).is_empty(), "关闭楼梯后不再跨层连接")
	link.enabled = true
	link.bidirectional = true
	lower = _unit(Vector2(160, 128), 1)
	upper = _unit(Vector2(160, 128), 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	link = terrain.get_node("Stairs12")
	check(link.transfer(lower) and lower.floor_id == 2 and lower.global_position.distance_to(upper.global_position) >= 30.0,
		"楼梯出口被占用时选择附近空位，不叠入同层单位")
	lower.set_floor(1)
	lower.global_position = Vector2(160, 128)
	upper.set_floor(3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(link.transfer(lower) and lower.floor_id == 2, "出口清空后正确切换碰撞和导航")
	lower.die()
	await get_tree().physics_frame
	await get_tree().physics_frame
	lower.set_floor(4)
	check(lower.collision_layer == 0 and lower.collision_mask == 0, "死亡单位切层不会恢复身体阻挡")
	await _clear()

	link = terrain.get_node("Stairs34")
	link.enabled = false
	var hunter := _unit(Vector2(96, 128), 1, true)
	var unreachable := _unit(Vector2(96, 128), 4)
	var reachable := _unit(Vector2(260, 128), 1)
	check(hunter.skill_manager.find_nearest_enemy() == unreachable, "自动索敌可选择射程内没有楼梯的异层敌人")
	unreachable.global_position = Vector2(650, 128)
	hunter.skill_manager.clear_target_cache()
	check(hunter.skill_manager.find_nearest_enemy() == reachable, "射程外仍忽略没有楼梯可达的异层敌人")
	link.enabled = true
	await _clear()
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	# 基础士兵已有远程普攻，此处用近战骑士验证真正经过楼梯接敌。
	hunter = _unit(Vector2(96, 128), 1, true, "knight")
	var enemy := _unit(Vector2(680, 128), 4)
	hunter.current_health = 10000
	enemy.current_health = 10000
	for frame in 1500:
		await get_tree().physics_frame
		if hunter.current_health < 10000 or enemy.current_health < 10000:
			break
	check(hunter.current_health < 10000 or enemy.current_health < 10000, "真实自动战斗会经过楼梯接敌并造成伤害")
	check(hunter.global_position.distance_to(enemy.global_position) <= 80.0, "跨层寻路后在攻击射程内接敌")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _clear()
	terrain.floor_regions[3].navigation_polygon = NavigationPolygon.new()
	await get_tree().physics_frame
	check(not terrain.is_walkable(Vector2.ZERO, 4), "空楼层不会把导航返回的原点误当成可走地面")
	get_node("Level").free()
	_build_map(true)
	for frame in 180:
		await get_tree().physics_frame
		if terrain.is_walkable(Vector2(96, 128), 1) and terrain.is_walkable(Vector2(680, 128), 1) \
			and not terrain.is_walkable(Vector2(384, 128), 1) and terrain.is_walkable(Vector2(600, 128), 2):
			break
	lower = _unit(Vector2(96, 128), 1)
	await _move(lower, Vector2(680, 128), 1)
	check(lower.floor_id == 1 and lower.global_position.distance_to(Vector2(680, 128)) <= 10.0 \
		and visited_floors.has(2), "同层孤岛可以先上桥再下桥到达目标")
	await _clear()
	await _test_auxiliary_layers()
	await _test_authored_map()
	print("BATTLE_FLOORS_TEST: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
