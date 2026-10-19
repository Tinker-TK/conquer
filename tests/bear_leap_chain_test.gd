extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(55.0).timeout.connect(func(): get_tree().quit(1))
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


func _unit(kind: String, point: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % kind), "team_b" if kind == "orc" else "team_a", level)
	unit.global_position = point
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.defence = 0
	unit.unit_data.attack = 15
	unit.unit_data.dodge_skill = null
	unit.get_node("HealthBar").setup(1000)
	var smoke := unit.get_node_or_null("SpawnSmoke")
	if smoke != null:
		smoke.queue_free()
	return unit


func _skill(unit: UnitBase, title: String) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == title:
			return skill
	return null


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()


func _reset() -> void:
	arena.clear_arena()
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _capture(title: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/bear-leap-chain")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/bear-leap-chain/%s.png" % title)


func _run() -> void:
	var source := load("res://data/units/were_bear.tres") as UnitData
	var card := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(2, 0), "正式训练强化熊人")
	check(card.get_description().contains("2段") and trained.get_description().contains("3段"), "卡面显示基础和强化闪电段数")
	check(card.get_summon_data().skills.size() == 3 and trained.get_summon_data().skills.size() == 2, "基础安装普攻、爪击和撼地，强化按旧规则用撼地替换普攻")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _chain(0, 2)
	await _chain(1, 3)
	await _few_enemies()
	await _jump(0, 1)
	await _jump(1, 2)
	await _interrupt()
	await _wall()
	await _independent_and_targeting()
	arena.queue_free()
	await _frames(2)
	print("BEAR_LEAP_CHAIN_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _chain(level: int, links: int) -> void:
	var bear := _unit("were_bear", Vector2(580, 500), level)
	var enemies: Array[UnitBase] = []
	for index in 5:
		enemies.append(_unit("orc", Vector2(640 + index * 180, 500)))
	var ally := _unit("soldier", Vector2(820, 510))
	var hidden := _unit("orc", Vector2(680, 520))
	hidden.set_stealthed(true)
	var foreign := _unit("orc", Vector2(690, 500))
	foreign.set_meta("battle_owner", weakref(self))
	var claw := _skill(bear, "二连爪")
	check(claw.lightning_links == links and claw.attack_rate == 0.8 and claw.cooldown == 3.0, "爪击倍率冷却保持，强化仅增加连锁段数")
	_cast(bear, enemies[0], claw)
	await _frames(26)
	for index in 5:
		check(enemies[index].current_health == 1000 - (12 if index <= links else 0), "真实第一爪按顺序连接、逐段搜索，链外不受伤：%d/%d" % [level, index])
	check(ally.current_health == 1000 and hidden.current_health == 1000 and foreign.current_health == 1000, "不连接友军、隐身或其它交锋敌人")
	var visuals: Array = bear.get_parent().get_children().filter(func(node): return node.get_script() != null and node.get_script().resource_path.ends_with("bear_lightning_vfx.gd"))
	check(visuals.size() == links, "每一段仅一条雷电Strike连接")
	if not visuals.is_empty():
		check(visuals[0].skill.id == "lightning_strike" and visuals[0].get_children().any(func(node): return node.has_meta("effect_id") and node.get_meta("effect_id") == "scenes_vfx_lightningboltvfx_premium"), "直接使用实验室雷电Strike原配方与高级雷电素材")
		check(visuals[0].to_global(visuals[0].source).distance_to(enemies[0].to_global(enemies[0]._smoke_body_rect().get_center())) < 0.01, "闪电起点为受伤主目标，不是熊人")
	await _capture("lightning-%d" % level)
	await _frames(56)
	check(enemies[links].current_health == 976 and enemies.back().current_health == 1000, "第二个真实伤害帧重新触发完整连锁，不继承上一爪已访问集合")
	foreign.remove_meta("battle_owner")
	await _reset()


func _few_enemies() -> void:
	var bear := _unit("were_bear", Vector2(600, 500), 1)
	var first := _unit("orc", Vector2(660, 500))
	var second := _unit("orc", Vector2(760, 500))
	var claw := _skill(bear, "二连爪")
	claw.execute(bear, first)
	check(first.current_health == 988 and second.current_health == 988, "只有两个敌人时只有一段闪电，绝不来回重复伤害")
	second.die()
	claw.execute(bear, first)
	check(first.current_health == 976, "只有一个敌人时无可连接目标，不重复电击主目标")
	first.current_health = 1
	var third := _unit("orc", Vector2(860, 500))
	claw.execute(bear, first)
	check(first.current_state == UnitBase.State.DEATH and third.current_health == 988, "爪击击杀主目标后仍从死亡位置继续连锁")
	await _reset()


func _jump(level: int, count: int) -> void:
	var bear := _unit("were_bear", Vector2(600, 500), level)
	var near := _unit("orc", Vector2(650, 500))
	var center := _unit("orc", Vector2(850, 500))
	var side_a := _unit("orc", Vector2(850, 580))
	var side_b := _unit("orc", Vector2(850, 420))
	var hidden := _unit("orc", Vector2(700, 450))
	hidden.set_stealthed(true)
	var smash := _skill(bear, "撼地")
	check(smash.select_target(bear) == center, "跳向最密集3人敌群，而非最近落单敌人")
	check(smash.jump_count == count and smash.knockback_distance == 250.0, "正确安装基础一跳/强化二跳及250击退")
	await _frames(2)
	_cast(bear, near, smash)
	await _frames(35)
	var motion: Node = bear.skill_manager.cast_data.get("bear_jump")
	check(is_instance_valid(motion) and motion.stage == "air" and bear.global_position.x > 600 and bear.global_position.x < 850, "动画第5帧后真实腾空移动，不瞬移")
	check(center.current_health == 1000 and side_a.current_health == 1000, "落地之前不提前结算范围伤害")
	check(is_instance_valid(motion) and motion.visual.skill.id == "abyssal_slam" and bear.animated_sprite_2d.position.y < -10, "原Abyssal重击配方、真实熊人腾空弧线")
	if is_instance_valid(motion):
		check(motion.visual._expirations.any(func(entry): return is_instance_valid(entry.node) and entry.node is Sprite2D and entry.node.get_meta("unit_ghost", false)), "跳跃残影使用熊人自身精灵")
	await _capture("leap-%d" % level)
	await _frames(17)
	check(center.current_health == 988 and side_a.current_health == 988 and side_b.current_health == 988 and near.current_health == 1000, "落地以熊人为中心AOE命中范围敌人，各80%，落单敌人不受伤")
	check(hidden.current_health == 1000, "密集区域统计与AOE都过滤隐身敌人")
	check(bear.get_parent().get_children().any(func(node): return node.get_meta("effect_id", "") == "scenes_vfx_leapgrounddecal"), "落地播放Leap地面印记原素材")
	await _capture("landing-%d" % level)
	await _frames(17)
	check(side_a.global_position.distance_to(Vector2(850, 580)) > 249.0 and side_a.global_position.distance_to(Vector2(850, 580)) < 251.0, "完整震开距离250像素")
	check(not side_a.skill_manager.is_forced_moving, "击退结束恢复敌人位移状态")
	await _frames(20)
	if count == 2:
		check(is_instance_valid(motion) and motion.jumps == 1 and motion.stage == "windup", "强化第一跳后进入第二跳动作，同次施法不中途解锁")
		for frame in 80:
			await get_tree().physics_frame
			if not bear.skill_manager.is_casting:
				break
		check(not bear.skill_manager.is_casting and bear.global_position.x < 700, "第二跳重新选择击退后的密集敌群，完成两跳才结束")
		check(near.current_health == 988, "第二跳独立造成范围伤害")
	else:
		check(not bear.skill_manager.is_casting, "基础仅一跳，动画结束后正常收尾")
	check(not bear.skill_manager.is_forced_moving and not bear.get_node("CollisionShape2D").disabled, "跳跃结束恢复碰撞及导航控制")
	await _reset()


func _interrupt() -> void:
	var bear := _unit("were_bear", Vector2(600, 500), 1)
	var enemy := _unit("orc", Vector2(880, 500))
	var smash := _skill(bear, "撼地")
	_cast(bear, enemy, smash)
	await _frames(35)
	bear.apply_status(&"stun", 2.0)
	check(bear.skill_manager.get_cooldown_left(smash) > 0.3, "眩晕打断保留已启动的技能冷却")
	var stop := bear.global_position
	await _frames(80)
	check(enemy.current_health == 1000 and bear.global_position == stop and not bear.skill_manager.is_casting, "空中中断立即停止，不触发落地或第二跳")
	check(bear.animated_sprite_2d.position == Vector2(-4, -10) and not bear.skill_manager.is_forced_moving and not bear.get_node("CollisionShape2D").disabled, "中断还原精灵高度、碰撞和强制移动锁")
	bear.remove_status(&"stun")
	_cast(bear, enemy, smash)
	await _frames(8)
	check(bear.skill_manager.get_cooldown_left(smash) > 0.7, "新施法重新进入冷却")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _frames(3)
	check(not bear.skill_manager.is_casting and not bear.skill_manager.is_forced_moving, "战斗阶段结束清理跳跃")
	await _reset()


func _wall() -> void:
	var bear := _unit("were_bear", Vector2(600, 500))
	var enemy := _unit("orc", Vector2(850, 500))
	var wall := StaticBody2D.new()
	wall.position = Vector2(750, 500)
	wall.collision_layer = 4
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 250)
	shape.shape = rectangle
	wall.add_child(shape)
	arena.add_child(wall)
	await _frames(2)
	_cast(bear, enemy, _skill(bear, "撼地"))
	await _frames(85)
	check(bear.global_position.x < 735 and not bear.get_node("CollisionShape2D").disabled, "跳跃使用完整身体地形扫描，不落进墙体")
	wall.queue_free()
	await _reset()


func _independent_and_targeting() -> void:
	var first := _unit("were_bear", Vector2(600, 400), 1)
	var second := _unit("were_bear", Vector2(600, 700), 1)
	var enemy := _unit("orc", Vector2(850, 400))
	var other := _unit("orc", Vector2(850, 700))
	var skill := _skill(first, "撼地")
	check(first.skill_manager.pick_skill() and first.skill_manager.current_skill == skill, "远处敌人在跳跃施法距离内时可自主选择撼地，不必先贴身")
	_cast(first, enemy, skill)
	_cast(second, other, _skill(second, "撼地"))
	await _frames(35)
	var peer_motion: Node = second.skill_manager.cast_data.get("bear_jump")
	check(first.skill_manager.cast_data.get("bear_jump") != peer_motion, "共享强化技能资源的两名熊人各自保有跳跃进度")
	first.die()
	await _frames(60)
	check(enemy.current_health == 1000 and not first.skill_manager.is_forced_moving and first.animated_sprite_2d.position == Vector2(-4, -10), "空中死亡立即清理，不落地伤害、不发动后续跳跃")
	check(other.current_health == 988 and is_instance_valid(peer_motion) and second.skill_manager.is_casting, "一名熊人死亡不取消另一名熊人的二连跳")
	second.apply_status(&"confusion", 1.0)
	await _frames(2)
	check(not second.skill_manager.is_casting and not second.skill_manager.is_forced_moving, "混乱同样打断跳跃并恢复动作控制")
	await _reset()
	var bear := _unit("were_bear", Vector2(600, 500))
	var main := _unit("orc", Vector2(850, 500))
	var side := _unit("orc", Vector2(850, 570))
	var isolated := _unit("orc", Vector2(650, 500))
	var jump := _skill(bear, "撼地")
	check(bear.apply_status(&"taunt", 3.0, 0, isolated) and bear.skill_manager.find_target_for_skill(jump) == isolated, "嘲讽优先于密集区域索敌")
	bear.remove_status(&"taunt")
	isolated.die()
	_cast(bear, main, jump)
	main.die()
	await _frames(55)
	check(side.current_health == 988 and bear.global_position.distance_to(Vector2(850, 570)) < 0.1, "起跳前主目标死亡，重新选择有效敌群并正常落地")
	await _reset()
