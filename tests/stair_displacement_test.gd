extends Node2D

const PATHS = preload("res://scripts/combat/unit_motion_path.gd")
var terrain: NavigationRegion2D
var units: Array[UnitBase] = []
var checks := 0
var failures: Array[String] = []
var visits: Dictionary = {}
var tracked: UnitBase

func _ready() -> void:
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if is_instance_valid(tracked):
		visits[tracked.floor_id] = true

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().physics_frame

func _unit(id: String, point: Vector2, floor_id: int) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % id).instantiate()
	unit.position = point
	unit.floor_id = floor_id
	add_child(unit)
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 10000
	unit.current_health = 10000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	unit.unit_data.attack = 100
	var smoke := unit.get_node_or_null("SpawnSmoke")
	if smoke != null:
		smoke.queue_free()
	units.append(unit)
	return unit

func _skill(unit: UnitBase, script: String) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.get_script().resource_path.ends_with(script):
			return skill
	return null

func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	tracked = unit
	visits.clear()
	visits[unit.floor_id] = true
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()

func _clear() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _frames(2)
	tracked = null
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/stair-displacement")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/stair-displacement/" + name + ".png")

func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var battle: Node = load("res://scenes/levels/battles/battle_006.tscn").instantiate()
	var level := battle.get_node("Level")
	battle.remove_child(level)
	level.owner = null
	add_child(level)
	terrain = level.get_node("NavigationRegion2D")
	battle.free()
	await _frames(8)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	# 两种坡向，上下楼均测试真实扑击和完整五连命中。
	for index in [0, 1]:
		var link: Node2D = terrain.transitions[index]
		var direction := Vector2.RIGHT if index == 0 else Vector2.LEFT
		for from_floor in [1, 2]:
			var to_floor: int = 3 - from_floor
			var sign := 1.0 if from_floor == 1 else -1.0
			var start: Vector2 = link.entry_point(from_floor) - direction * 48.0 * sign
			var goal: Vector2 = link.entry_point(to_floor) + direction * 144.0 * sign
			var wolf := _unit("were_wolf", start, from_floor)
			var target := _unit("orc", goal, to_floor)
			var five := _skill(wolf, "wolf_pounce_combo.gd")
			await _frames(2)
			check(five.select_target(wolf) == target, "坡向%d %d→%d：狼人可锁定楼梯另一端目标" % [index, from_floor, to_floor])
			_cast(wolf, target, five)
			await _frames(8)
			check(wolf.global_position.distance_to(start) > 30 and wolf.skill_manager.is_casting, "坡向%d %d→%d：扑击产生真实连续位移" % [index, from_floor, to_floor])
			if index == 0 and from_floor == 1:
				await _capture("wolf-up-mid")
			await _frames(16)
			check(wolf.floor_id == to_floor and wolf.global_position.distance_to(goal) <= five.melee_range, "坡向%d %d→%d：沿楼梯完成切层并抵达近战落点" % [index, from_floor, to_floor])
			check(wolf.navigation_agent_2d.get_navigation_map() == terrain.get_floor_map(to_floor), "扑击切层同步导航、碰撞与避让")
			if index == 0 and from_floor == 1:
				await _capture("wolf-up-attack")
			await _frames(150)
			check(target.current_health == 9600 and not wolf.skill_manager.is_casting and not wolf.skill_manager.is_forced_moving, "坡向%d %d→%d：完整五刀结算并恢复动作锁" % [index, from_floor, to_floor])
			check(not wolf.get_node("CollisionShape2D").disabled, "扑击结束恢复身体碰撞")
			await _clear()
	var link: Node2D = terrain.transitions[0]
	var low: Vector2 = link.entry_point(1) - Vector2(48, 0)
	var high: Vector2 = link.entry_point(2) + Vector2(144, 0)
	var lancer := _unit("lancer", low, 1)
	var victim := _unit("orc", high, 2)
	var underneath := _unit("orc", high, 1)
	await _frames(2)
	_cast(lancer, victim, _skill(lancer, "dash_attack.gd"))
	await _frames(180)
	check(lancer.floor_id == 2 and visits.has(1) and visits.has(2) and victim.current_health == 9900, "骑兵冲锋沿楼梯切层并命中上层敌人")
	check(underneath.current_health == 9890, "冲锋保留原跨层命中规则，切层后对下层敌人应用10%高地增伤")
	check(not lancer.skill_manager.is_casting and not lancer.get_node("CollisionShape2D").disabled, "楼梯冲锋正常收尾和恢复碰撞")
	await _clear()
	var bear := _unit("were_bear", low, 1)
	victim = _unit("orc", high, 2)
	await _frames(2)
	var slam := _skill(bear, "bear_earth_shake.gd")
	check(slam.select_target(bear) == victim, "熊人可选择楼梯相连的上层敌群")
	_cast(bear, victim, slam)
	await _frames(180)
	check(bear.floor_id == 2 and victim.current_health == 9920 and not bear.skill_manager.is_casting, "熊人沿楼梯跳至上层再结算落地攻击")
	check(not bear.get_node("CollisionShape2D").disabled and bear.animated_sprite_2d.position == Vector2(-4, -10), "熊人落地恢复精灵高度和身体碰撞")
	await _clear()
	var sword := _unit("swords_man", link.entry_point(2) + Vector2(64, 0), 2)
	victim = _unit("orc", sword.global_position + Vector2(60, 0), 2)
	var origin := sword.global_position
	await _frames(2)
	_cast(sword, victim, _skill(sword, "sword_wind_combo.gd"))
	await _frames(12)
	check(sword.floor_id == 1 and sword.global_position.x < link.entry_point(1).x, "剑士后撤可沿楼梯退至下层")
	await _frames(180)
	check(sword.floor_id == 2 and sword.global_position.distance_to(origin) < 1.0 and not sword.skill_manager.is_casting, "剑士前突原路经过楼梯返回原攻击位置及楼层")
	await _clear()
	# 空间重叠不等于楼层相连；禁用楼梯后所有主动位移均不能跨层。
	var wolf := _unit("were_wolf", low, 1)
	victim = _unit("orc", high, 2)
	await _frames(2)
	link.enabled = false
	terrain._route_cache.clear()
	check(PATHS.plan(wolf, low, high, 2).is_empty() and _skill(wolf, "wolf_pounce_combo.gd").select_target(wolf) == null, "禁用楼梯不允许跨层扑击或强制位移")
	link.enabled = true
	terrain._route_cache.clear()
	var upward := PATHS.plan(wolf, low, high, 2)
	link.bidirectional = false
	check(PATHS.plan(victim, high, low, 1).is_empty() and PATHS.reverse(upward).is_empty(), "单向楼梯不能逆向位移或后撤回穿")
	link.bidirectional = true
	terrain._route_cache.clear()
	var wall := StaticBody2D.new()
	wall.collision_layer = terrain.terrain_bit(2)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(24, 400)
	shape.shape = rectangle
	wall.position = link.entry_point(2) + Vector2(64, 0)
	wall.add_child(shape)
	add_child(wall)
	await _frames(2)
	check(PATHS.plan(wolf, low, high, 2).is_empty(), "楼梯另一端新增实体墙仍阻止整条位移路径")
	wall.free()
	await _clear()
	for reason in ["stun", "disable"]:
		wolf = _unit("were_wolf", low, 1)
		victim = _unit("orc", high, 2)
		await _frames(2)
		_cast(wolf, victim, _skill(wolf, "wolf_pounce_combo.gd"))
		await _frames(3)
		if reason == "stun":
			wolf.apply_status(&"stun", 1.0)
		else:
			link.enabled = false
			await _frames(2)
		var stop := wolf.global_position
		var stop_floor := wolf.floor_id
		await _frames(30)
		check(wolf.global_position == stop and wolf.floor_id == stop_floor and victim.current_health == 10000, reason + "：楼梯扑击中断后停止位移和伤害")
		check(not wolf.skill_manager.is_forced_moving and not wolf.skill_manager.is_casting and not wolf.get_node("CollisionShape2D").disabled, reason + "：恢复动作锁和身体碰撞")
		link.enabled = true
		await _clear()
	wolf = _unit("were_wolf", low, 1)
	victim = _unit("orc", high, 2)
	await _frames(2)
	_cast(wolf, victim, _skill(wolf, "wolf_pounce_combo.gd"))
	await _frames(3)
	get_tree().paused = true
	var paused_position := wolf.global_position
	var paused_floor := wolf.floor_id
	for _frame in 6:
		await get_tree().process_frame
	check(wolf.global_position == paused_position and wolf.floor_id == paused_floor and victim.current_health == 10000, "暂停冻结楼梯位移、切层和攻击")
	get_tree().paused = false
	await _frames(180)
	check(wolf.floor_id == 2 and victim.current_health == 9600 and not wolf.skill_manager.is_casting, "恢复后继续原扑击和五连击")
	await _clear()
	print("STAIR_DISPLACEMENT_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
