# 真实冲锋动作、原实验室火花/飞踢、两段独立命中、速度、墙体与中断清理。
extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
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


func _unit(name: String, point: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), "team_b" if name == "orc" else "team_a", level)
	unit.global_position = point
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	unit.get_node("HealthBar").setup(1000)
	var smoke := unit.get_node_or_null("SpawnSmoke")
	if smoke != null:
		smoke.queue_free()
	return unit


func _dash(unit: UnitBase) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.get_script().resource_path.ends_with("dash_attack.gd"):
			return skill
	return null


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase = null) -> Node2D:
	if skill == null:
		skill = _dash(unit)
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()
	for frame in 8:
		if unit.skill_manager.cast_data.has("dash_motion"):
			break
		await get_tree().physics_frame
	return unit.skill_manager.cast_data.get("dash_motion")


func _reset() -> void:
	arena.clear_arena()
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/cavalry-charge")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/cavalry-charge/%s.png" % name)


func _run() -> void:
	var data := load("res://data/units/lancer.tres") as UnitData
	var base := CardInstance.new(data)
	var upgraded := CardInstance.new(data)
	check(upgraded.train(2, 0), "骑兵通过正式训练升级")
	var base_data := base.get_summon_data()
	var upgraded_data := upgraded.get_summon_data()
	var base_dashes := base_data.skills.filter(func(skill): return skill.get_script().resource_path.ends_with("dash_attack.gd"))
	var upgraded_dashes := upgraded_data.skills.filter(func(skill): return skill.get_script().resource_path.ends_with("dash_attack.gd"))
	check(base_dashes.size() == 1 and upgraded_dashes.size() == 1, "每个等级只装配一个冲锋版本，不再互相抢优先级")
	check(base_dashes[0].dash_count == 1 and base_dashes[0].dash_speed == 300, "基础冲锋一次，速度300")
	check(upgraded_dashes[0].dash_count == 2 and upgraded_dashes[0].dash_speed == 600, "强化冲锋两次，速度600")
	check(base_dashes[0].cooldown == 6 and upgraded_dashes[0].cooldown == 5 and upgraded_data.skills.size() == 3, "保留原冲锋冷却及强化强力刺击")
	check(base.get_description().contains("冲锋1次") and upgraded.get_description().contains("冲锋2次") and upgraded.get_description().contains("速度600"), "卡面读取实际次数与速度")
	var start := RunStartData.new()
	start.cards.assign([data])
	RunManager.start_new_run(start)
	check(RunManager.deck[0].train(2, 0) and RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "强化骑兵训练存档恢复")
	check(RunManager.deck[0].get_description().contains("冲锋2次"), "恢复后保留两次加速冲锋配置")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	await _charge(0)
	await _charge(1)
	await _interruption()
	await _wall_and_speed()
	await _independent_units()
	check(base_dashes[0].dash_count == 1 and base_dashes[0].dash_speed == 300 and data.card_upgrade_level == 0, "各施法不污染共享基础资源")
	arena.queue_free()
	await _frames(2)
	print("CAVALRY_CHARGE_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _charge(level: int) -> void:
	var caster := _unit("lancer", Vector2(500, 450), level)
	var one := _unit("orc", Vector2(650, 450))
	var two := _unit("orc", Vector2(850, 450))
	var outside := _unit("orc", Vector2(750, 650))
	var ally := _unit("soldier", Vector2(700, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	var skill := _dash(caster)
	var frame_started := Engine.get_physics_frames()
	var motion := await _cast(caster, one)
	check(motion != null and motion.segment_index == 1 and caster.skill_manager.is_forced_moving, "真实冲锋动画的释放帧启动位移")
	var visuals: Node2D = motion.visual
	check(visuals.skill.id == "flyingkick_monk" and visuals.hit_recipe.size() == 2, "复用实验室Flying Kick的冲刺和两次原始蓝色命中配方")
	await _frames(12)
	check(absf(caster.global_position.x - 500 - skill.dash_speed * 12.0 / 60.0) < 12, "真实冲锋位移符合配置速度")
	var ghosts := visuals.get_children().filter(func(node): return node is Sprite2D and node.has_meta("cavalry_ghost"))
	var sparks := visuals.get_children().filter(func(node): return node.has_meta("effect_id") and node.get_meta("effect_id") == "scenes_vfx_blazingdashtrailsparks")
	check(ghosts.size() >= 2 and ghosts[0].global_scale == caster.animated_sprite_2d.global_scale and ghosts[0].global_position != caster.animated_sprite_2d.global_position, "Flying Kick残影使用真实骑兵帧、缩放和沿途历史位置")
	check(not sparks.is_empty() and sparks[0].get_meta("visual_root").get_script().resource_path.ends_with("BlazingDashTrailSparks.gd"), "真实移动路径已经生成同名Blazing尾迹火花素材")
	await _frames(14)
	check(visuals.get_children().any(func(node): return node.has_meta("effect_id") and node.get_meta("effect_id") == "scenes_vfx_slashimpactvfx"), "真实冲锋命中后生成Flying Kick原蓝色斩击特效")
	await _capture("upgraded" if level == 1 else "base")
	var segments := 1
	var turned := false
	for frame in 250:
		await get_tree().physics_frame
		if is_instance_valid(motion):
			segments = maxi(segments, motion.segment_index)
			turned = turned or (motion.segment_index == 2 and motion.segment_to.x < motion.segment_from.x)
		if not caster.skill_manager.is_casting:
			break
	check(segments == level + 1 and (level == 0 or turned), "强化在第一段结束后重新转向并发动第二段")
	var damage := int(caster.unit_data.attack * skill.attack_rate) * (level + 1)
	check(one.current_health == 1000 - damage and two.current_health == 1000 - damage, "每段对沿途同一敌人只命中一次，两段分别造成伤害")
	check(outside.current_health == 1000 and ally.current_health == 1000, "不会伤害路径外目标或同阵营友军")
	check(not caster.skill_manager.is_forced_moving and not caster.skill_manager.is_casting and not caster.get_node("CollisionShape2D").disabled and not caster.get_node("AttackArea").monitoring, "完整技能结束恢复碰撞和技能锁")
	var seconds := float(Engine.get_physics_frames() - frame_started) / 60.0
	check(absf(caster.skill_manager.get_cooldown_left(skill) - maxf(0.0, skill.cooldown - seconds)) < 0.12, "两段共用一次冷却，第二段不重置CD")
	await _reset()


func _interruption() -> void:
	var caster := _unit("lancer", Vector2(500, 450), 1)
	var enemy := _unit("orc", Vector2(800, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	var motion := await _cast(caster, enemy)
	await _frames(10)
	caster.apply_status(&"stun", 2.0)
	var stopped := caster.global_position
	var hp := int(enemy.current_health)
	await _frames(15)
	check(caster.global_position.is_equal_approx(stopped) and enemy.current_health == hp and not caster.skill_manager.is_forced_moving, "眩晕中断第一段且不会继续位移、伤害或发动第二段")
	check(not caster.get_node("CollisionShape2D").disabled and not caster.get_node("AttackArea").monitoring and caster.skill_manager.get_cooldown_left(_dash(caster)) > 0, "中断恢复碰撞并保留已进入的冷却")
	caster.remove_status(&"stun")
	var newer := await _cast(caster, enemy)
	await _frames(3)
	check(newer != null and newer != motion and caster.skill_manager.is_forced_moving, "旧冲锋清理不会覆盖之后的新冲锋")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	await _frames(3)
	stopped = caster.global_position
	await _frames(10)
	check(caster.global_position.is_equal_approx(stopped) and not caster.skill_manager.is_casting and not caster.get_node("CollisionShape2D").disabled, "退出交锋停止后续冲锋并恢复留存单位")
	await _reset()


func _wall_and_speed() -> void:
	var caster := _unit("lancer", Vector2(500, 450))
	var enemy := _unit("orc", Vector2(900, 450))
	var wall := StaticBody2D.new()
	wall.collision_layer = 4
	wall.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 180)
	collision.shape = rectangle
	wall.add_child(collision)
	arena.add_child(wall)
	wall.global_position = Vector2(800, 450)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	await _cast(caster, enemy)
	for frame in 100:
		await get_tree().physics_frame
		if not caster.skill_manager.is_casting:
			break
	check(caster.global_position.x < 790 and caster.global_position.x > 700 and enemy.current_health == 1000, "完整身体在公共墙体之前停止，不穿墙冲刺")
	await _reset()
	caster = _unit("lancer", Vector2(500, 450))
	var targets: Array[UnitBase] = []
	for x in [650, 800, 950]:
		targets.append(_unit("orc", Vector2(x, 450)))
	var fast: SkillBase = _dash(caster).duplicate()
	fast.dash_speed = 18000
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	await _cast(caster, targets[0], fast)
	await _frames(10)
	check(targets.all(func(unit): return unit.current_health == 1000 - int(caster.unit_data.attack)), "高速跨物理帧的冲锋仍覆盖路径上全部敌人且不重复命中")
	await _reset()


func _independent_units() -> void:
	var one := _unit("lancer", Vector2(500, 350), 1)
	var two := _unit("lancer", Vector2(500, 650), 1)
	var first := _unit("orc", Vector2(700, 350))
	var second := _unit("orc", Vector2(700, 650))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	var a := await _cast(one, first)
	var b := await _cast(two, second)
	check(a != b and not is_same(a.hit_units, b.hit_units) and a.tween != b.tween, "同技能的两个骑兵各有独立冲锋、命中集合和Tween")
	await _frames(12)
	var position := one.global_position
	one.die()
	await _frames(3)
	check(one.global_position.is_equal_approx(position) and not one.skill_manager.is_forced_moving, "骑兵死亡立即停止本次冲锋")
	check(two.skill_manager.is_forced_moving and b.segment_index == 1, "一个骑兵死亡不会终止另一个的冲锋")
	for frame in 180:
		await get_tree().physics_frame
		if not two.skill_manager.is_casting:
			break
	check(second.current_health == 1000 - 2 * int(two.unit_data.attack) and not two.skill_manager.is_forced_moving, "另一名骑兵独立完成两段冲锋与两次命中")
	await _reset()
