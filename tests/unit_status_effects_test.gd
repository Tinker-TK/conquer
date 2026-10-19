# 走正式单位、技能、投射物和战术卡入口，覆盖状态叠加、控制优先级与视觉清理。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var ally: UnitBase
var enemy: UnitBase


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _unit(team: String, point: Vector2) -> UnitBase:
	var node := load("res://scenes/units/soldier.tscn" if team == "team_a" else "res://scenes/units/orc.tscn").instantiate() as UnitBase
	node.unit_data = node.unit_data.duplicate()
	node.unit_data.max_hp = 1000
	node.unit_data.defence = 100
	node.unit_data.attack = 120
	node.unit_data.monster_rank = UnitData.MonsterRank.NORMAL
	node.position = point
	battle.get_node("Entities/TeamA" if team == "team_a" else "Entities/TeamB").add_child(node)
	node.set_physics_process(false)
	return node


func _apply(unit: UnitBase, id: StringName, duration: float = 0, amount: int = 0, source: Node = null, key: String = "") -> void:
	check(unit.apply_status(id, duration, amount, source, key), "施加 " + String(id))
	unit.status_runtime.set_physics_process(false)


func _tick(unit: UnitBase, delta: float) -> void:
	unit.status_runtime._physics_process(delta)
	unit.status_runtime.set_physics_process(false)


func _vfx(unit: UnitBase, id: StringName, original: String) -> void:
	var visual: Node2D = unit.status_runtime.visuals.get(id)
	check(is_instance_valid(visual) and visual.get_meta("effect_id") == "scenes_vfx_statuseffects_" + original.to_lower(), String(id) + " 使用素材库动画")
	if is_instance_valid(visual):
		check(visual.get_parent() == unit, String(id) + " 跟随单位")
		check(not visual.has_node("Timer"), String(id) + " 持续动画没有12秒默认超时")


func _play(name: String, target: UnitBase) -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	var card := CardInstance.new(load("res://data/cards/%s.tres" % name))
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, target.global_position), "正式出牌 " + name)
	battle.card_runtime.tactics.set_physics_process(false)


func _run() -> void:
	RunManager.start_new_run()
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	config.enemy_max_hp = 1000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	battle.card_runtime.set_physics_process(false)
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "导航同步")
	ally = _unit("team_a", Vector2(450, 450))
	enemy = _unit("team_b", Vector2(750, 450))
	await get_tree().process_frame
	var smoke := ally.get_node("SpawnSmoke")
	check(smoke.get_child(0).get_meta("effect_id") == "scenes_vfx_smokevfx", "出生使用烟团")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	seed(67321)
	var expected_random := randi()
	seed(67321)
	preload("res://scripts/effects/combat_vfx.gd").hit(enemy)
	check(randi() == expected_random, "命中特效不消耗玩法随机数")
	_bleeding()
	_sleep_and_control()
	_healing()
	_skill_hits()
	await _confusion()
	await _pause_and_phase()
	await _summon_control()
	await _death_cleanup()
	_tactics()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture()
	_cleanup()
	battle.queue_free()
	await get_tree().process_frame
	print("UNIT_STATUS_EFFECTS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _bleeding() -> void:
	var hp := int(enemy.current_health)
	_apply(enemy, &"bleed", 2.0, 7, ally)
	_vfx(enemy, &"bleed", "BleedVFX")
	_tick(enemy, 0.99)
	check(enemy.current_health == hp, "流血不足一秒不扣血")
	_tick(enemy, 0.01)
	check(enemy.current_health == hp - 7, "流血每秒固定7点，忽略100防御")
	_tick(enemy, 1.0)
	check(enemy.current_health == hp - 14 and not enemy.has_status(&"bleed"), "到期边界结算最后一次并解除")
	check(not enemy.status_runtime.visuals.has(&"bleed"), "到期清除流血动画")
	hp = int(enemy.current_health)
	_apply(enemy, &"bleed", 5, 4, ally, "same")
	_tick(enemy, 0.6)
	_apply(enemy, &"bleed", 5, 4, ally, "same")
	_tick(enemy, 0.4)
	check(enemy.current_health == hp - 4 and enemy.status_runtime.total_amount(&"bleed") == 4, "刷新期限不重置秒跳且不重复叠加")
	_apply(enemy, &"bleed", 5, 3, ally, "second")
	_tick(enemy, 1)
	check(enemy.current_health == hp - 11, "不同来源流血分别结算")
	enemy.remove_status(&"bleed", "same")
	check(enemy.status_runtime.total_amount(&"bleed") == 3, "仅移除指定来源")
	enemy.clear_combat_statuses()
	var source := Node.new()
	add_child(source)
	_apply(enemy, &"bleed", 1.5, 2, source)
	source.free()
	hp = int(enemy.current_health)
	_tick(enemy, 2.0)
	check(enemy.current_health == hp - 2 and not enemy.has_status(&"bleed"), "来源释放仍正确结算有效时段，过期不多跳")
	check(not enemy.apply_status(&"bleed", 2, 0) and not enemy.apply_status(&"bleed", -1, 5), "拒绝无效流血配置")


func _sleep_and_control() -> void:
	_apply(enemy, &"sleep", 1.0)
	_vfx(enemy, &"sleep", "SleepVFX")
	_tick(enemy, 120)
	check(enemy.has_status(&"sleep") and enemy.is_action_blocked(), "睡眠不因时间流逝自然醒来")
	check(not enemy.animated_sprite_2d.is_playing() and not enemy.can_use_skills(), "睡眠停止行动")
	enemy.take_effect_damage(1, ally)
	check(enemy.has_status(&"sleep"), "持续伤害不唤醒")
	enemy.get_hurt(1, enemy, false)
	check(enemy.has_status(&"sleep"), "友军拒绝命中不唤醒")
	enemy.get_hurt(1, ally, false)
	check(not enemy.has_status(&"sleep") and enemy.animated_sprite_2d.is_playing(), "攻击命中唤醒并恢复动画")
	_apply(enemy, &"stun", 1.0)
	_vfx(enemy, &"stun", "StunVFX")
	check(enemy.is_stunned and not enemy.skill_manager.is_casting, "眩晕清除施法锁")
	var hp := int(ally.current_health)
	enemy.skill_manager.current_skill = enemy.unit_data.skills[0]
	enemy.skill_manager.current_target = ally
	enemy.skill_manager.attack()
	enemy.skill_manager.fire_projectile(enemy.unit_data.skills[0])
	check(ally.current_health == hp and not enemy.skill_manager.is_casting, "眩晕阻止开火及攻击")
	enemy.set_stunned(true)
	_tick(enemy, 1)
	check(enemy.is_stunned and not enemy.has_status(&"stun"), "技能眩晕到期不解除其它眩晕来源")
	enemy.set_stunned(false)
	check(not enemy.is_stunned, "最后一个来源解除后恢复")
	_apply(enemy, &"sleep")
	_apply(enemy, &"stun", 1)
	_tick(enemy, 1)
	check(enemy.is_action_blocked() and not enemy.animated_sprite_2d.is_playing(), "眩晕解除后睡眠继续限制行动")
	enemy.clear_combat_statuses()
	check(enemy.can_use_skills() and enemy.animated_sprite_2d.is_playing(), "全部清理恢复行动")


func _healing() -> void:
	_apply(enemy, &"mortal_wounds", 1)
	_vfx(enemy, &"mortal_wounds", "MortalWoundsVFX")
	var hp := int(enemy.current_health)
	check(not enemy.get_heal(50, ally) and enemy.current_health == hp, "禁疗拦截普通治疗")
	load("res://data/skills/priest_healer.tres").execute(ally, enemy)
	check(enemy.current_health == hp, "牧师技能无法治疗禁疗单位")
	load("res://data/skills/bloodthirst_attack.tres").execute(enemy, ally)
	check(enemy.current_health == hp, "禁疗拦截吸血恢复")
	_tick(enemy, 1)
	check(enemy.get_heal(10) and enemy.current_health == hp + 10, "禁疗到期恢复治疗")


func _skill_hits() -> void:
	var skill: SkillBase = load("res://data/skills/normal_attack.tres").duplicate()
	var status := UnitStatusEffect.new()
	status.amount = 9
	status.duration = 2
	skill.status_effects.append(status)
	skill.execute(ally, enemy)
	enemy.status_runtime.set_physics_process(false)
	check(enemy.has_status(&"bleed") and enemy.status_runtime.total_amount(&"bleed") == 9, "近战使用技能配置的流血数值")
	enemy.remove_status(&"bleed")
	var arrow: SkillBase = load("res://data/skills/archer_arrow_attack.tres").duplicate()
	status.kind = UnitStatusEffect.Kind.MORTAL_WOUNDS
	arrow.status_effects.append(status)
	arrow.execute(ally, enemy)
	var projectile: Projectile
	for child in battle.get_children():
		if child is Projectile:
			projectile = child
	check(projectile != null and not enemy.has_status(&"mortal_wounds"), "投射物发射时不提前附加状态")
	if projectile != null:
		status.kind = UnitStatusEffect.Kind.STUN
		projectile._deal_damage()
		check(enemy.has_status(&"mortal_wounds"), "投射物实际命中才施加状态")
		check(not enemy.has_status(&"stun"), "弹上状态保留发射时快照")
		enemy.status_runtime.set_physics_process(false)
	enemy.clear_combat_statuses()
	status.kind = UnitStatusEffect.Kind.SLEEP
	skill.execute(ally, enemy)
	check(enemy.has_status(&"sleep"), "睡眠攻击先扣血再施加睡眠")
	enemy.clear_combat_statuses()
	var attack := enemy.unit_data.attack
	_apply(enemy, &"weakness", 1, 8, ally)
	_vfx(enemy, &"weakness", "WeakenVFX")
	check(enemy.unit_data.attack == attack - 8, "技能虚弱降低固定攻击")
	_tick(enemy, 1)
	check(enemy.unit_data.attack == attack, "虚弱到期精确恢复攻击")


func _confusion() -> void:
	_apply(enemy, &"confusion", 5)
	_vfx(enemy, &"confusion", "ConfusionVFX")
	check(not enemy.can_use_skills() and not enemy.is_action_blocked(), "混乱允许行走但不施法")
	var initial := enemy.global_position
	enemy.set_physics_process(true)
	for i in 70:
		await get_tree().physics_frame
	enemy.set_physics_process(false)
	check(enemy.global_position.distance_to(initial) > 5 and not enemy.skill_manager.is_casting, "混乱在实际导航中随机移动")
	_apply(enemy, &"stun", 5)
	initial = enemy.global_position
	enemy.set_physics_process(true)
	for i in 8:
		await get_tree().physics_frame
	enemy.set_physics_process(false)
	check(enemy.global_position.distance_to(initial) < 0.1, "眩晕优先于混乱，不再移动")
	enemy.clear_combat_statuses()


func _pause_and_phase() -> void:
	_apply(enemy, &"bleed", 10, 4)
	enemy.status_runtime.set_physics_process(true)
	await get_tree().physics_frame
	get_tree().paused = true
	var entry: Dictionary = enemy.status_runtime.effects[&"bleed"].values()[0]
	var elapsed := float(entry.elapsed)
	for i in 4:
		await get_tree().process_frame
	check(is_equal_approx(entry.elapsed, elapsed), "暂停冻结流血计时")
	get_tree().paused = false
	Global.game_phase = Global.GamePhase.CARD_PLAY
	for i in 5:
		await get_tree().physics_frame
	check(is_equal_approx(entry.elapsed, elapsed), "准备阶段不消耗战斗秒数")
	enemy.clear_combat_statuses()


func _tactics() -> void:
	enemy.global_position = Vector2(750, 450)
	_play("weakness", enemy)
	_vfx(enemy, &"weakness", "WeakenVFX")
	_apply(enemy, &"weakness", 1, 3)
	enemy.remove_status(&"weakness")
	check(enemy.status_runtime.visuals.has(&"weakness"), "技能虚弱解除不移除战术卡虚弱动画")
	battle.card_runtime.tactics.end_round()
	check(not enemy.status_runtime.visuals.has(&"weakness"), "战术卡虚弱回合结束清理动画")
	_play("convert_enemy", enemy)
	_vfx(enemy, &"converted", "CharmVFX")
	check(enemy.unit_data.unit_team == "team_a", "策反实际换队并显示魅惑")
	var attack := ally.unit_data.attack
	_apply(ally, &"weakness", 5, 7)
	_play("copy_ally", ally)
	var copied: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	copied.set_physics_process(false)
	check(copied != ally and copied.unit_data.attack == attack and not copied.has_status(&"weakness"), "复制不烘焙技能虚弱扣减")
	ally.clear_combat_statuses()


func _summon_control() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var team: Node2D = battle.get_node("Entities/TeamB")
	var caster: UnitBase = load("res://scenes/units/necromancer.tscn").instantiate()
	team.add_child(caster)
	caster.set_physics_process(false)
	var skill: SkillBase = caster.unit_data.skills[0]
	skill.execute(caster)
	var effect: AnimatedSprite2D
	for child in team.get_children():
		if child is AnimatedSprite2D and child.get_script() == preload("res://scripts/combat/summon_effect.gd"):
			effect = child
	check(effect != null, "召唤前摇已创建")
	_apply(caster, &"stun", 1)
	check(effect != null and effect.resolved and effect.is_queued_for_deletion(), "眩晕立即取消未完成召唤")
	caster.remove_status(&"stun")
	await get_tree().process_frame
	check(not is_instance_valid(effect), "控制解除后旧召唤不能补出单位")
	caster.queue_free()
	await get_tree().process_frame


func _death_cleanup() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var victim := _unit("team_b", Vector2(1100, 650))
	var deaths := [0]
	victim.unit_died.connect(func(_unit): deaths[0] += 1)
	_apply(victim, &"bleed", 5, 2000, ally)
	_apply(victim, &"mortal_wounds", 5)
	_tick(victim, 1)
	check(victim.current_state == UnitBase.State.DEATH and deaths[0] == 1, "流血致死只结算一次死亡")
	check(victim.status_runtime.effects.is_empty() and victim.status_runtime.visuals.is_empty(), "死亡清除所有状态和循环动画")
	check(victim.get_node("HealthBar").pending_statuses.is_empty(), "死亡清理状态图标")
	for i in 180:
		if not is_instance_valid(victim) or victim.has_node("DeathSmoke"):
			break
		await get_tree().physics_frame
	check(is_instance_valid(victim) and victim.has_node("DeathSmoke"), "死亡动作后播放烟团")
	if is_instance_valid(victim) and victim.has_node("DeathSmoke"):
		check(victim.get_node("DeathSmoke").get_child(0).get_meta("effect_id") == "scenes_vfx_smokevfx", "死亡也使用素材库烟团")


func _cleanup() -> void:
	_apply(ally, &"bleed", 10, 5)
	_apply(ally, &"sleep")
	battle.finish_battle(true)
	check(ally.status_runtime.effects.is_empty() and ally.status_runtime.visuals.is_empty(), "战斗结束清空状态和动画")
	check(enemy.status_runtime.visuals.is_empty(), "战斗结束清理策反魅惑")
	check(not ally.is_action_blocked(), "战斗结束不遗留控制状态")
	var dying := _unit("team_b", Vector2(1000, 600))
	# 战斗已结束时拒绝新增状态。
	check(not dying.apply_status(&"bleed", 3, 5), "结束战场拒绝新增状态")


func _capture() -> void:
	# 用正式单位展示全部动画；测试窗口为离屏截图用途。
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	battle.card_ui.hide()
	battle.get_node("Label").hide()
	for unit in battle.card_runtime.living_units():
		unit.hide()
	for child in battle.get_children():
		if child is CanvasLayer:
			child.hide()
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.global_position = Vector2(960, 540)
	camera.zoom = Vector2.ONE * 1.7
	camera.force_update_scroll()
	var labels := ["流血", "魅惑 / 策反", "混乱", "禁止治疗", "睡眠", "晕眩", "虚弱", "烟团", "攻击命中"]
	var ids := [&"bleed", &"converted", &"confusion", &"mortal_wounds", &"sleep", &"stun", &"weakness"]
	var units: Array[UnitBase] = []
	for i in 9:
		var unit := _unit("team_a", Vector2(680 + (i % 3) * 260, 330 + (i / 3) * 175))
		units.append(unit)
		var initial_smoke := unit.get_node("SpawnSmoke")
		initial_smoke.hide()
		initial_smoke.queue_free()
		if i < 7:
			if ids[i] == &"converted":
				unit.status_runtime.set_visual(ids[i], true, &"preview")
			else:
				_apply(unit, ids[i], 0, 5)
		var caption := Label.new()
		caption.text = labels[i]
		caption.position = Vector2(-55, 25)
		caption.add_theme_font_size_override("font_size", 18)
		unit.add_child(caption)
	for i in 60:
		await get_tree().physics_frame
	units[7]._play_spawn_smoke()
	preload("res://scripts/effects/combat_vfx.gd").hit(units[8])
	for i in 12:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.maintenance/status-vfx-preview.png")
