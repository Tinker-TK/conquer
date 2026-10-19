# 真实训练二选一、存档、测试场动画与标记协同；成长只保留在出场实例。
extends Node2D

var checks := 0
var failures: Array[String] = []
var arena: Node2D


func _ready() -> void:
	get_tree().create_timer(35.0).timeout.connect(func(): get_tree().quit(1))
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


func _spawn(name: String, at: Vector2, level: int = 0, branch: String = "") -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), "team_b" if name == "orc" else "team_a", level, branch)
	unit.global_position = at
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 10000
	unit.current_health = 10000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	return unit


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()


func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/soldier-branches")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/soldier-branches/%s.png" % name)


func _run() -> void:
	var source := load("res://data/units/soldier.tres") as UnitData
	var start := RunStartData.new()
	start.cards.assign([source, source, source])
	RunManager.start_new_run(start)
	var base: CardInstance = RunManager.deck[2]
	check(base.get_summon_data().has_sword_arrow() and base.get_summon_data().skills.size() == 1, "基础士兵已有远近普攻，尚无强化技能")
	var panel = load("res://scripts/map/event_panel.gd").new()
	panel.size = Vector2(1920, 1080)
	add_child(panel)
	var event: Dictionary = load("res://scripts/map/fixed_map_config.gd").default_event("campfire")
	for branch in ["slash", "missile"]:
		panel.open_content(event, RunManager)
		panel._choose(1)
		panel._select_upgrade(0)
		panel.attack_input.value = 2
		check(panel.soldier_choice.visible and panel.confirm_button.disabled, "正式训练分配完点数仍必须选择士兵分支")
		panel.soldier_choice.select_branch(branch)
		check(not panel.confirm_button.disabled, "显式选择%s后可确认训练" % branch)
		await _capture("training-" + branch)
		panel._claim()
		var card: CardInstance = RunManager.deck[0 if branch == "slash" else 1]
		check(card.soldier_specialization == branch and card.upgrade_count == 1, "分支只保存到本张已选士兵牌")
		check(card.get_summon_data().has_sword_arrow() == (branch == "missile"), "斩击放弃射箭，飞弹保留射箭")
		check(card.get_summon_data().skills.size() == 2 and card.get_summon_data().skills[1].soldier_branch == branch, "仅安装对应分支及普通攻击")
		check(card.upgrade_summary().contains("保留剑矢") == (branch == "missile"), "强化摘要正确区分放弃或保留弓箭")
	check(base.soldier_specialization.is_empty() and base.upgrade_count == 0 and source.soldier_specialization.is_empty(), "同名未强化牌和共享资源互不污染")
	check(RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "分支存档保存与恢复")
	check(RunManager.deck[0].soldier_specialization == "slash" and RunManager.deck[1].soldier_specialization == "missile" and RunManager.deck[2].soldier_specialization.is_empty(), "读档保留两种分支及未强化牌")
	var temporary := CardInstance.new(source)
	check(temporary.temporary_upgrade(Vector2i(2, 0), "slash") and temporary.soldier_specialization == "slash", "进化可临时选择斩击")
	check(temporary.persistent_upgrade_state().soldier_specialization.is_empty(), "临时选择不会进入永久存档")
	temporary.restore_evolution()
	check(temporary.upgrade_count == 0 and temporary.soldier_specialization.is_empty() and temporary.get_summon_data().has_sword_arrow(), "临时进化结束恢复基础远近双能")
	panel.queue_free()
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	check(arena.branch_upgrade_buttons["res://scenes/units/soldier.tscn"][1].keys().size() == 2, "monster_test提供两个明确分支按钮")
	var missile := _spawn("soldier", Vector2(450, 500), 1, "missile")
	var slash := _spawn("soldier", Vector2(430, 600), 1, "slash")
	var ordinary := _spawn("soldier", Vector2(500, 600))
	var other := _spawn("soldier", Vector2(500, 750))
	var archer := _spawn("archer", Vector2(500, 850))
	var marked := _spawn("orc", Vector2(730, 500))
	var near := _spawn("orc", Vector2(680, 600))
	for unit in [missile, slash, ordinary, archer]:
		unit.skill_manager.current_target = marked
	other.skill_manager.current_target = near
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var missile_skill: SkillBase = missile.unit_data.get_unlocked_skills()[1]
	check(missile_skill.attack_rate == 0.8, "飞弹倍率0.8")
	var damage := int(missile.unit_data.attack * 0.8)
	var base_attacks := [missile.unit_data.attack, slash.unit_data.attack, ordinary.unit_data.attack]
	_cast(missile, marked, missile_skill)
	for frame in 150:
		await get_tree().physics_frame
		if marked.get_node_or_null("SoldierMissileMark") != null:
			break
	var mark := marked.get_node_or_null("SoldierMissileMark")
	check(mark != null and 10000 - marked.current_health == damage, "真实飞弹动画和原Wounding Arrow飞到后造成0.8倍率伤害并标记")
	check(missile.unit_data.attack == base_attacks[0] + 3 and slash.unit_data.attack == base_attacks[1] + 3 and ordinary.unit_data.attack == base_attacks[2] + 3, "3名士兵攻击同一目标，命中时各获得3点攻击")
	check(other.soldier_attack_bonus == 0 and archer.soldier_attack_bonus == 0, "不奖励攻击其他目标的士兵或非士兵")
	check(mark != null and is_instance_valid(mark.visual) and mark.visual.get_meta("effect_id") == "scenes_vfx_statuseffects_slowvfx" and not marked.has_status(&"slow") and not marked.has_status(&"mortal_wounds"), "使用实验室减速原特效作为标记，不附加减速或禁疗状态")
	await _capture("missile-mark")
	await _frames(300)
	check(is_instance_valid(mark) and is_instance_valid(mark.visual), "减速标记特效持续播放至本场结束")
	var slash_skill: SkillBase = slash.unit_data.get_unlocked_skills()[1]
	check(slash_skill.cast_range == 350.0 and not slash.skill_manager.has_sword_arrow(), "斩击350范围且禁用弓箭")
	check(slash_skill.select_target(slash) == marked, "下次斩击优先选择较远的飞弹标记敌人")
	var before := int(marked.current_health)
	var slash_damage := int(slash.unit_data.attack * slash_skill.attack_rate)
	var origin := slash.global_position
	_cast(slash, marked, slash_skill)
	await _frames(3)
	check(slash.global_position.distance_to(origin) > 1.0 and slash.skill_manager.is_forced_moving, "斩击先按原Wild Boar Gore流程飞跃")
	var leap: Node
	for node in arena.team_a.get_children():
		if node.get_script() != null and node.get_script().resource_path.ends_with("soldier_leap.gd"):
			leap = node
	check(is_instance_valid(leap) and leap.skill.id == "wild_boar_bite", "直接复用实验室wild_boar_bite配方")
	await _frames(5)
	check(slash.skill_manager.is_forced_moving and slash.global_position.distance_to(origin) < origin.distance_to(leap.landing), "0.13秒仍在连续突进途中，不瞬间到达落点")
	var ghosts: Array[Node] = leap.get_children().filter(func(node: Node): return node is Sprite2D)
	check(ghosts.size() >= 3, "突进途中保留多道士兵残影")
	check(leap.z_index > 0 and ghosts.all(func(node: Sprite2D): return node.z_index >= 0 and node.modulate.a > 0.0 and node.has_meta("soldier_ghost")), "残影显示在背景上方并使用真实士兵帧逐渐淡出")
	await _capture("slash-leap")
	await _frames(40)
	check(before - marked.current_health == slash_damage and slash.global_position.distance_to(marked.global_position) <= 80, "飞跃落地后在斩击命中帧造成一次130%伤害")
	check(slash.soldier_runtime.has_slashed(marked) and not slash_skill.begin_cast(slash, marked), "同一士兵对同一目标只能斩击一次")
	check(slash_skill.select_target(slash) == null, "已斩过的当前目标继续使用普通攻击")
	var bonus_before := slash.soldier_attack_bonus
	marked.die(ordinary)
	check(slash.soldier_attack_bonus == bonus_before + 1 and slash.soldier_runtime.slash_bonus == 1, "已斩目标被其他友军击杀也奖励该士兵1点攻击")
	marked.die(ordinary)
	check(slash.soldier_attack_bonus == bonus_before + 1, "重复死亡通知不重复增加攻击")
	slash.notify_attack_target(near)
	check(slash_skill.select_target(slash) == near, "切换新目标后可再次斩击")
	near.global_position = slash.global_position + Vector2(351, 0)
	check(slash_skill.select_target(slash) == null, "351像素不能斩击")
	near.global_position = slash.global_position + Vector2(350, 0)
	check(slash_skill.select_target(slash) == near, "350像素边界可斩击")
	slash.skill_manager._skill_time_cd[slash_skill].stop()
	slash.skill_manager.check_attack()
	check(slash.current_state == UnitBase.State.ATTACK and slash.skill_manager.current_skill == slash_skill, "350边界可通过真实技能管理器启动斩击")
	check(RunManager.deck[0].get_summon_data().attack == source.attack + 2 and source.attack == 10, "斩击和飞弹加成不写入卡牌或共享属性")
	slash.clear_combat_statuses()
	check(slash.soldier_attack_bonus == 0 and slash.soldier_runtime.slashed.is_empty() and slash.unit_data.attack == source.attack + 2, "战斗结束清除成长和已斩目标记录")
	arena.clear_arena()
	await _frames(2)
	arena.queue_free()
	await _frames(1)
	await _formal_battle()
	print("SOLDIER_BRANCHES_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _formal_battle() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	await _frames(2)
	var card: CardInstance = RunManager.deck[0]
	var hand = battle.hand_manager
	hand.draw_pile.erase(card)
	hand.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, Vector2(450, 450)), "正式战场可部署已选择斩击的原牌")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	var attack := unit.unit_data.attack
	unit.soldier_runtime.gain_missile_bonus(3)
	check(unit.unit_data.attack == attack + 3, "正式战场攻击成长经过战术属性系统结算")
	var mirror := CardInstance.new(load("res://data/cards/copy_ally.tres"))
	hand.hand.append(mirror)
	var center := unit.get_node_or_null("CastTargetCenter") as Node2D
	check(battle.card_runtime.try_play(mirror, center.global_position if center != null else unit.global_position), "可复制已获得成长的士兵")
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	check(copied.unit_data.attack == attack and copied.soldier_attack_bonus == 0 and copied.unit_data.get_soldier_specialization() == "slash", "复制继承斩击分支但不继承原单位的成长")
	battle.card_runtime.clear_battle_buffs()
	check(unit.soldier_attack_bonus == 0 and unit.unit_data.attack == attack and card.get_summon_data().attack == attack, "正式战场结束清理成长且原牌训练属性保留")
	battle.queue_free()
	await _frames(2)
