# 正式训练与部署验证治疗、溢出护盾及四种咏唱；控制与暂停必须在命中前生效。
extends Node2D

var checks := 0
var failures: Array[String] = []
var battle: Node2D
var priest: UnitBase
var enhanced: UnitBase
var wizard: UnitBase
var small: UnitBase
var large: UnitBase
var enemy: UnitBase


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _deploy(card: CardInstance, at: Vector2) -> UnitBase:
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, at), "真实出牌部署单位")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _reset(caster: UnitBase) -> void:
	caster.clear_combat_statuses()
	caster.skill_manager.interrupt_actions()
	for timer: Timer in caster.skill_manager._skill_time_cd.values():
		timer.stop()
	caster.skill_manager.set_physics_process(false)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _start(caster: UnitBase, skill: SkillBase, target: UnitBase) -> void:
	_reset(caster)
	caster.skill_manager.current_skill = skill
	caster.skill_manager.current_target = target
	caster.switch_state(UnitBase.State.ATTACK)
	caster.skill_manager.attack()


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/priest-chant-shield")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/priest-chant-shield/%s.png" % label)


func _run() -> void:
	RunManager.start_new_run()
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	for unit: UnitBase in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	var source := load("res://data/units/priest.tres") as UnitData
	var base_card := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(source.upgrade_ability_points, 0), "正式训练强化牧师")
	check(base_card.get_description().contains("生命比例") and base_card.get_description().contains("60%") and not base_card.get_description().contains("护盾"), "基础说明显示比例治疗60%")
	check(trained.get_description().contains("140%") and trained.get_description().contains("护盾") and trained.get_description().contains("全员满血"), "强化说明显示140%、满血选目标及溢出护盾")
	check(trained.get_summon_data().get_unlocked_skills().size() == 2, "强化替换治疗而非同时装备两次治疗")
	priest = _deploy(base_card, Vector2(450, 450))
	enhanced = _deploy(trained, Vector2(600, 450))
	wizard = _deploy(CardInstance.new(load("res://data/units/wizard.tres")), Vector2(450, 650))
	small = _deploy(CardInstance.new(load("res://data/units/soldier.tres")), Vector2(750, 450))
	large = _deploy(CardInstance.new(load("res://data/units/soldier.tres")), Vector2(900, 450))
	enemy = load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(1000, 650)
	enemy.unit_data.max_hp = 10000
	enemy.current_health = 10000
	enemy.unit_data.dodge_skill = null
	enemy.set_physics_process(false)
	await _frames(70)
	var heal: SkillBase = priest.unit_data.get_unlocked_skills()[1]
	var shield_heal: SkillBase = enhanced.unit_data.get_unlocked_skills()[1]
	check(heal.attack_rate == 0.6 and shield_heal.attack_rate == 1.4, "基础0.6与强化1.4治疗倍率")
	small.unit_data.max_hp = 40
	small.current_health = 20
	large.unit_data.max_hp = 200
	large.current_health = 40
	check(priest.skill_manager.find_target_for_skill(heal) == large, "40/200优先于20/40，按比例而非当前血量")
	priest.current_health = 5
	check(priest.skill_manager.find_target_for_skill(heal) == priest, "牧师自身可作为最低比例治疗目标")
	priest.current_health = priest.unit_data.max_hp
	large.current_state = UnitBase.State.DEATH
	check(priest.skill_manager.find_target_for_skill(heal) == small, "排除已有生命值但处于死亡状态的单位")
	large.current_state = UnitBase.State.IDLE
	large.floor_id = 2
	check(priest.skill_manager.find_target_for_skill(heal) == large, "存活友军比例选择覆盖其他楼层")
	large.floor_id = 1
	for unit in [priest, enhanced, wizard, small, large]:
		unit.current_health = unit.unit_data.max_hp
	check(priest.skill_manager.find_target_for_skill(heal) == null, "基础治疗在全员满血时不空放")
	check(enhanced.skill_manager.find_target_for_skill(shield_heal) == large, "强化全员满血时选当前生命最高的200血友军")
	large.unit_data.max_hp = 100
	large.current_health = 95
	enhanced.unit_data.attack = 10
	shield_heal.execute(enhanced, large)
	check(large.current_health == 100 and large.shield_amount == 9, "14点治疗先补5点生命，溢出9点转为护盾")
	var bubble: Node2D = large.shield_visual
	check(is_instance_valid(bubble) and bubble.get_meta("effect_id") == "scenes_vfx_statuseffects_shieldbubblevfx", "直接使用实验室护盾·罩")
	shield_heal.execute(enhanced, large)
	check(large.shield_amount == 23 and large.shield_visual == bubble, "满血14点全转护盾，数值累加且不重复生成罩")
	check(large.active_statuses().any(func(entry: Dictionary): return entry.icon == "shield" and entry.count == 23), "状态显示护盾实际剩余值")
	check(large.get_hurt(10, enemy, false, &"", 1, true) and large.current_health == 100 and large.shield_amount == 13, "固定伤害先扣护盾")
	large.take_effect_damage(15, enemy)
	check(large.current_health == 98 and large.shield_amount == 0 and large.shield_visual == null, "持续效果伤害先耗13护盾，仅2点伤生命并清理罩")
	large.add_shield(20)
	large.unit_data.defence = 10
	large.get_hurt(35, enemy, false)
	check(large.current_health == 93 and large.shield_amount == 0, "普通攻击先计算防御，再由护盾吸收，剩余5点扣血")
	large.apply_status(&"mortal_wounds", 2.0)
	var hp := int(large.current_health)
	shield_heal.execute(enhanced, large)
	check(large.current_health == hp and large.shield_amount == 0, "禁疗同时拦截治疗和治疗转护盾")
	large.clear_combat_statuses()
	large.current_health = 100
	shield_heal.execute(enhanced, large)
	await _capture("shield-bubble")
	check(is_instance_valid(large.shield_visual), "有护盾时持续显示罩")
	large.unit_data.max_hp = 200
	large.current_health = 200
	var auto_shield := large.shield_amount
	_reset(enhanced)
	enhanced.skill_manager.set_physics_process(true)
	enhanced.set_physics_process(true)
	await _frames(2)
	enhanced.set_physics_process(false)
	check(enhanced.skill_manager.is_chanting and enhanced.skill_manager.cast_target == large, "真实自动战斗在全员满血时选择最高当前生命友军并开始咏唱")
	await _frames(65)
	check(large.current_health == 200 and large.shield_amount == auto_shield + 14, "完整咏唱和原治疗动画命中帧后实际生成14点溢出护盾")
	_reset(enhanced)
	# 四种真实技能分别检查：进度半满前没有动作/命中，走满后才开始原动画。
	var cases := [[priest, priest.unit_data.skills[0], enemy, 0.3], [enhanced, shield_heal, large, 0.7],
		[wizard, wizard.unit_data.get_unlocked_skills()[0], enemy, 0.5], [wizard, wizard.unit_data.get_unlocked_skills()[1], enemy, 1.5]]
	for entry: Array in cases:
		var caster: UnitBase = entry[0]
		var skill: SkillBase = entry[1]
		var target: UnitBase = entry[2]
		check(is_equal_approx(skill.chant_duration, entry[3]), "%s配置咏唱%.1f秒" % [skill.skill_name, entry[3]])
		_start(caster, skill, target)
		check(caster.skill_manager.is_casting and caster.skill_manager.is_chanting and caster.skill_manager.chant_bar.visible, "咏唱锁定动作并显示头顶条")
		check(caster.animated_sprite_2d.animation == &"idle" and caster.skill_manager.get_cooldown_left(skill) == 0.0, "咏唱尚未开始既定动作或成功释放冷却")
		var before_hp := int(target.current_health)
		var before_shield := target.shield_amount
		caster.skill_manager._physics_process(skill.chant_duration * 0.5)
		check(is_equal_approx(caster.skill_manager.chant_bar.progress, 0.5), "咏唱物理时间推进到半满")
		caster.skill_manager.fire_projectile(skill)
		check(target.current_health == before_hp and target.shield_amount == before_shield, "咏唱未完成时命中入口不触发伤害或治疗")
		if caster == wizard and skill == wizard.unit_data.get_unlocked_skills()[1]:
			await _capture("wizard-frost-chant")
		if skill == shield_heal:
			await _capture("priest-heal-chant")
		caster.skill_manager._physics_process(skill.chant_duration * 0.5)
		check(not caster.skill_manager.is_chanting and not caster.skill_manager.chant_bar.visible and caster.animated_sprite_2d.animation == StringName(skill.cast_animation), "走满后隐藏条并播放既定技能动画")
		check(caster.skill_manager.get_cooldown_left(skill) >= skill.cooldown - 0.001, "完整咏唱后启动技能冷却")
		_reset(caster)
	# 控制、软性异常状态和外部状态在咏唱期间都能打断，取消效果并保留完整CD。
	for id: StringName in [&"stun", &"sleep", &"confusion", &"bleed", &"weakness", &"slow", &"mortal_wounds"]:
		_start(enhanced, shield_heal, large)
		enhanced.skill_manager._physics_process(0.2)
		var shield_before := large.shield_amount
		check(enhanced.apply_status(id, 2.0, 1, enemy, "chant-test"), "咏唱期间施加异常状态" + String(id))
		check(not enhanced.skill_manager.is_casting and not enhanced.skill_manager.is_chanting and not enhanced.skill_manager.chant_bar.visible, String(id) + "中断并隐藏进度条")
		check(enhanced.skill_manager.get_cooldown_left(shield_heal) >= 2.999 and large.shield_amount == shield_before, String(id) + "取消效果并进入完整3秒冷却")
		_reset(enhanced)
	_start(enhanced, shield_heal, large)
	enhanced.set_stunned(true)
	check(not enhanced.skill_manager.is_chanting and enhanced.skill_manager.get_cooldown_left(shield_heal) >= 2.999, "外部眩晕同样打断并进入冷却")
	_reset(enhanced)
	_start(enhanced, shield_heal, large)
	enhanced.skill_manager.set_physics_process(true)
	var before_pause_shield := large.shield_amount
	await _frames(10)
	var elapsed: float = enhanced.skill_manager.chant_elapsed
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(enhanced.skill_manager.chant_elapsed == elapsed, "游戏暂停冻结咏唱进度")
	get_tree().paused = false
	BattleSpeed.set_multiplier(3)
	await _frames(45)
	check(not enhanced.skill_manager.is_chanting and enhanced.skill_manager.get_cooldown_left(shield_heal) > 0.0, "三倍速仍按物理时间完成咏唱并进入冷却")
	check(large.shield_amount == before_pause_shield + 14, "暂停与三倍速恢复后真实治疗只生效一次")
	BattleSpeed.set_multiplier(1)
	_reset(enhanced)
	_start(enhanced, shield_heal, large)
	large.current_state = UnitBase.State.DEATH
	enhanced.skill_manager._physics_process(0.1)
	check(not enhanced.skill_manager.is_chanting and enhanced.skill_manager.get_cooldown_left(shield_heal) >= 2.999, "目标死亡取消咏唱，不对死者施法")
	large.current_state = UnitBase.State.IDLE
	_start(enhanced, shield_heal, large)
	large.add_shield(10)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	SignalBus.phase_change.emit(Global.GamePhase.CARD_PLAY)
	check(not enhanced.skill_manager.is_chanting and not enhanced.skill_manager.chant_bar.visible and large.shield_amount == 0 and large.shield_visual == null, "离开交锋立即清除咏唱与护盾")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	large.add_shield(10)
	large.die(enemy)
	check(large.shield_amount == 0 and large.shield_visual == null, "单位死亡清除护盾")
	print("PRIEST_CHANT_SHIELD_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
