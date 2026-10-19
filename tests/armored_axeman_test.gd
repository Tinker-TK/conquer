# 真实测试场动画与物理墙体，验证击退、撞墙眩晕、双刀护盾快照和原实验室特效。
extends Node2D

const PUSH = preload("res://scripts/combat/knockback_motion.gd")
const FLOORS = preload("res://scripts/world/battle_floor_map.gd")
var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(50.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _unit(name: String, at: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), "team_b" if name == "orc" else "team_a", level)
	unit.global_position = at
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 10000
	unit.current_health = 10000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	return unit


func _skill(unit: UnitBase, name: String) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == name:
			return skill
	return null


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	unit.skill_manager.interrupt_actions()
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()


func _clear() -> void:
	arena.clear_arena()
	await _frames(2)


func _wall(at: Vector2, layer: int = 8) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = layer
	wall.collision_mask = 0
	wall.position = at
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(20, 160)
	wall.add_child(shape)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-10, -80), Vector2(10, -80), Vector2(10, 80), Vector2(-10, 80)])
	visual.color = Color("7795a5")
	wall.add_child(visual)
	arena.add_child(wall)
	return wall


func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/armored-axeman")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/armored-axeman/%s.png" % name)


func _run() -> void:
	var source := load("res://data/units/armored_axeman.tres") as UnitData
	var card := CardInstance.new(source)
	check(card.get_summon_data().skills.size() == 3, "未强化保留普攻、劈砍和旋转")
	check(card.train(2, 0) and card.get_summon_data().skills.size() == 3, "强化后仍保留三个技能并替换为强化版本")
	check(card.get_description().contains("护盾") and card.get_description().contains("2秒"), "强化卡面显示护盾双刀与撞墙眩晕")
	check(source.card_upgrade_level == 0 and source.skills.size() == 5, "训练不修改共享技能配置")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	await _open_spin()
	await _wall_spin(0)
	await _wall_spin(1)
	await _chop(0)
	await _chop(1)
	await _chop_interrupt()
	await _motion_interrupt()
	await _floor_walls()
	arena.queue_free()
	await _frames(2)
	print("ARMORED_AXEMAN_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _open_spin() -> void:
	var axe := _unit("armored_axeman", Vector2(650, 450))
	var right := _unit("orc", Vector2(710, 450))
	var left := _unit("orc", Vector2(590, 450))
	var ally := _unit("soldier", Vector2(650, 420))
	var outside := _unit("orc", Vector2(1000, 450))
	await _frames(2)
	var spin := _skill(axe, "旋转攻击")
	_cast(axe, right, spin)
	for frame in 50:
		await get_tree().physics_frame
		if right.skill_manager.is_forced_moving:
			break
	check(right.current_health == 10000 - int(axe.unit_data.attack * 0.8), "旋转真实命中帧造成80%伤害")
	await _frames(5)
	var prayer := axe.get_node_or_null("Eslabong_scenes_arcaneprayer")
	check(prayer != null and prayer.get_meta("effect_id") == "scenes_arcaneprayer", "旋转释放时在自身播放实验室奥术祈祷")
	check(prayer != null and prayer.get_parent() == axe, "奥术祈祷以施法者为中心并跟随自身")
	await _capture("arcane-prayer")
	await _frames(50)
	check(right.global_position.distance_to(Vector2(910, 450)) < 0.1 and left.global_position.distance_to(Vector2(390, 450)) < 0.1, "周围两侧敌军各向外击退200像素")
	check(not right.is_stunned and not left.is_stunned, "空地击退不造成眩晕")
	check(ally.global_position == Vector2(650, 420) and ally.current_health == 10000 and outside.current_health == 10000, "不伤害友军或攻击范围外敌人")
	check(not right.skill_manager.is_forced_moving and not axe.skill_manager.is_casting, "击退与旋转结束后解除技能锁")
	await _clear()


func _wall_spin(level: int) -> void:
	var axe := _unit("armored_axeman", Vector2(650, 450), level)
	var enemy := _unit("orc", Vector2(710, 450))
	_wall(Vector2(820, 450), 4 if level == 1 else 8)
	await _frames(2)
	_cast(axe, enemy, _skill(axe, "旋转攻击"))
	for frame in 80:
		await get_tree().physics_frame
		if enemy.current_health < 10000 and not enemy.skill_manager.is_forced_moving:
			break
	check(enemy.global_position.x > 790 and enemy.global_position.x <= 795.1, "强化%d：完整身体停在墙前，不穿透碰撞体" % level)
	check(enemy.has_status(&"stun") == (level == 1), "仅强化旋转撞墙后产生眩晕")
	if level == 1:
		var status: Dictionary = enemy.status_runtime.effects[&"stun"].values()[0]
		check(status.left > 1.95 and status.left <= 2.0 and enemy.is_action_blocked(), "撞墙产生完整2秒眩晕并禁止行动")
		await _capture("wall-stun")
		enemy.status_runtime.set_physics_process(false)
		enemy.status_runtime._physics_process(1.9)
		check(enemy.is_stunned, "眩晕未到2秒不会提前解除")
		enemy.status_runtime._physics_process(0.11)
		check(not enemy.is_stunned and not enemy.has_status(&"stun"), "2秒到期正确解除眩晕")
	await _clear()


func _chop(level: int) -> void:
	var axe := _unit("armored_axeman", Vector2(650, 450), level)
	var enemy := _unit("orc", Vector2(710, 450))
	var hits: Array[int] = []
	enemy.hit_received.connect(func(_unit, _attacker): hits.append(int(enemy.current_health)))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	axe.add_shield(30)
	var peer: UnitBase
	var peer_enemy: UnitBase
	if level == 1:
		peer = _unit("armored_axeman", Vector2(650, 700), 1)
		peer_enemy = _unit("orc", Vector2(710, 700))
		peer.add_shield(7)
		_cast(peer, peer_enemy, _skill(peer, "劈砍攻击"))
	_cast(axe, enemy, _skill(axe, "劈砍攻击"))
	await _frames(85)
	var per_hit := int(axe.unit_data.attack * 1.2) + (30 if level == 1 else 0)
	check(hits == [10000 - per_hit, 10000 - per_hit * 2], "强化%d：真实双命中帧分别结算基础伤害与护盾快照" % level)
	check(axe.shield_amount == (0 if level == 1 else 30), "仅强化劈砍消耗护盾")
	check(axe.skill_manager.cast_data.is_empty(), "劈砍完成后清除本次护盾快照")
	if level == 1:
		check(peer_enemy.current_health == 10000 - 2 * (int(peer.unit_data.attack * 1.2) + 7), "共享技能资源的两个斧手独立保存各自护盾值")
		check(axe.shield_visual == null and peer.shield_visual == null, "护盾消耗后立即清除护盾罩特效")
		enemy.current_health = 10000
		_cast(axe, enemy, _skill(axe, "劈砍攻击"))
		await _frames(85)
		check(enemy.current_health == 10000 - 2 * int(axe.unit_data.attack * 1.2), "无盾的下一轮劈砍不继承旧护盾加伤")
	await _clear()


func _chop_interrupt() -> void:
	var axe := _unit("armored_axeman", Vector2(650, 450), 1)
	var enemy := _unit("orc", Vector2(710, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	axe.add_shield(20)
	_cast(axe, enemy, _skill(axe, "劈砍攻击"))
	await _frames(8)
	axe.apply_status(&"stun", 0.1, 0, enemy)
	await _frames(60)
	check(enemy.current_health == 10000 and axe.shield_amount == 20, "首刀前打断不结算伤害或消耗护盾")
	_cast(axe, enemy, _skill(axe, "劈砍攻击"))
	for frame in 40:
		await get_tree().physics_frame
		if enemy.current_health < 10000:
			break
	var hp := int(enemy.current_health)
	axe.apply_status(&"stun", 0.1, 0, enemy)
	await _frames(40)
	check(enemy.current_health == hp and hp == 10000 - int(axe.unit_data.attack * 1.2) - 20, "首刀后打断取消第二刀，已消耗护盾不返还")
	check(axe.shield_amount == 0 and axe.skill_manager.cast_data.is_empty(), "打断清除本次护盾快照")
	await _clear()


func _motion_interrupt() -> void:
	var axe := _unit("armored_axeman", Vector2(650, 450), 1)
	var enemy := _unit("orc", Vector2(710, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	PUSH.push(enemy, axe, 200, 0.3, 2)
	await _frames(4)
	var point := enemy.global_position
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _frames(30)
	check(enemy.global_position == point and not enemy.skill_manager.is_forced_moving, "离开战斗阶段立即停止旧击退")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	PUSH.push(enemy, axe, 200, 0.3, 2)
	await _frames(3)
	enemy.die(axe)
	point = enemy.global_position
	await _frames(30)
	check(enemy.global_position == point and not enemy.has_status(&"stun"), "目标死亡后不继续移动或追加撞墙眩晕")
	await _clear()


func _floor_walls() -> void:
	# 真实多层导航与24像素导航留白，防止把导航边界误当作墙体。
	arena.get_node("Navigation").enabled = false
	var level := Node2D.new()
	level.name = "Level"
	arena.add_child(level)
	var terrain := FLOORS.new()
	terrain.name = "NavigationRegion2D"
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(64, 64)
	tiles.add_physics_layer()
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
		layer.tile_set = tiles
		for x in range(6, 24):
			for y in range(3, 13):
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		if floor_id == 1:
			layer.set_cell(Vector2i(12, 7), 0, Vector2i(1, 0))
		terrain.add_child(layer)
	level.add_child(terrain)
	await _frames(3)
	var axe := _unit("armored_axeman", Vector2(630, 480), 1)
	var enemy := _unit("orc", Vector2(690, 480))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	PUSH.push(enemy, axe, 200, 0.3, 2)
	await _frames(25)
	check(enemy.global_position.x > 750 and enemy.global_position.x <= 753.1 and enemy.is_stunned, "真实第一层墙体命中眩晕，导航留白不会让击退提前停止")
	check(terrain.has_ground_at(enemy.global_position, 1) and enemy.floor_id == 1, "击退撞墙后仍处于原楼层的真实地表")
	enemy.clear_combat_statuses()
	enemy.global_position = Vector2(690, 480)
	axe.set_floor(2)
	enemy.set_floor(2)
	PUSH.push(enemy, axe, 200, 0.3, 2)
	await _frames(25)
	check(enemy.global_position.distance_to(Vector2(890, 480)) < 0.1 and not enemy.is_stunned, "第二层击退忽略同位置的第一层墙体")
	await _clear()
