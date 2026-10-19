# 旧连续命中被动的显式配置回归；剑士正式特性已由七伤替换。
extends Node

var battle: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _deploy(card: CardInstance, point: Vector2) -> UnitBase:
	battle.hand_manager.draw_pile.erase(card)
	battle.hand_manager.discard_pile.erase(card)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, point), "通过真实出牌部署剑士")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _effect(kind: CardEffect.Kind, target: UnitBase) -> void:
	var effect := CardEffect.new()
	effect.kind = kind
	var definition := CardDefinition.new()
	definition.effects.assign([effect])
	definition.target = CardDefinition.Target.ALLY
	var card := CardInstance.new(definition)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, target.global_position), "通过真实效果牌验证复制、狂化或收回")


func _enemy(point: Vector2) -> UnitBase:
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = point
	enemy.set_physics_process(false)
	enemy.unit_data.defence = 0
	enemy.unit_data.dodge_skill = null
	enemy.current_health = 10000
	return enemy


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> int:
	var before := int(target.current_health)
	var manager = unit.skill_manager
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	manager.current_skill = skill
	manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	for frame in 180:
		await get_tree().physics_frame
		if not manager.is_casting:
			break
	check(not manager.is_casting, "真实攻击动画正常结束")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	return before - int(target.current_health)


func _run() -> void:
	var source := load("res://data/units/swords_man.tres").duplicate() as UnitData
	var base := source.attack
	var passive := load("res://data/skills/swords_man_consecutive_attack.tres") as SkillBase
	var triple := load("res://scripts/skills/normal_attack.gd").new() as SkillBase
	triple.skill_name = "三连击"
	triple.attack_rate = 0.7
	triple.cooldown = 3.0
	triple.cast_animation = "attack_02"
	triple.hit_frame = [3, 6, 12]
	source.skills = [source.skills[0], triple, source.skills[2], passive]
	check(source.skills.has(passive) and passive.is_passive() and passive.attack_bonus_per_hit == 1, "现有剑士拥有每次命中攻击+1的被动")
	var start := RunStartData.new()
	start.cards.assign([source, source])
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	var card: CardInstance = RunManager.deck[0]
	var trained: CardInstance = RunManager.deck[1]
	check(trained.train(source.upgrade_ability_points, 0), "原训练入口保持正常")
	check(card.get_description().contains("攻击力增加1") and card.get_description().contains("切换目标"), "普通卡牌显示被动说明")
	check(card.get_summon_data().skills.has(passive) and trained.get_summon_data().skills.has(passive), "未强化和强化剑士都保留被动")
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	for unit: UnitBase in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	var sword := _deploy(card, Vector2(500, 450))
	var peer := _deploy(trained, Vector2(400, 650))
	var a := _enemy(Vector2(560, 450))
	var b := _enemy(Vector2(580, 500))
	await _settle()
	var combo = sword.skill_manager.get_node("ConsecutiveAttack")
	var normal: SkillBase = source.skills[0]
	check(not sword.skill_manager._skill_time_cd.has(passive), "被动不占普通攻击冷却")
	check(await _cast(sword, a, normal) == int(base * normal.attack_rate), "首击使用原攻击力")
	check(sword.consecutive_attack_bonus == 1 and sword.unit_data.attack == base + 1, "首击之后叠加一层")
	check(sword.skill_manager.current_target == null and combo.hits == 1, "攻击收尾清空索敌字段不丢失连击")
	check(await _cast(sword, a, normal) == int((base + 1) * normal.attack_rate), "同目标第二次攻击伤害增加")
	check(sword.consecutive_attack_bonus == 2 and peer.consecutive_attack_bonus == 0, "不同剑士的层数互不影响")
	var status = sword.get_node("HealthBar/StatusDisplay")
	check(status.statuses.any(func(entry: Dictionary): return entry.icon == "consecutive_attack" and entry.tooltip.contains("命中2次")), "血条状态显示当前命中次数与增益")
	var inspector = battle.card_ui.get_node("UnitInspector")
	inspector.open_unit(sword)
	inspector.refresh_details()
	check(inspector.stat_labels.attack.text.contains("+2") and inspector.skill_cells.any(func(cell: Dictionary): return cell.skill == passive and cell.parameters.text.contains("每次命中攻击 +1")), "详情同步显示实际攻击增益和被动参数")
	if "--capture-consecutive-attack" in OS.get_cmdline_user_args():
		for frame in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/swordsman-consecutive-attack.png")
	inspector.close_details()
	sword.skill_manager.current_target = b
	check(combo.hits == 0 and sword.unit_data.attack == base, "选中另一个敌人立即清除旧目标增益")
	check(await _cast(sword, b, normal) == int(base * normal.attack_rate), "新目标首击不继承旧目标加成")
	normal.execute(sword, a)
	check(combo.hits == 1 and sword.unit_data.attack == base + 1, "直接执行技能仍在换目标后重新计数")
	var health := int(a.current_health)
	a.unit_data.dodge_skill = SkillBase.new()
	a.unit_data.dodge_rate = 1.0
	normal.execute(sword, a)
	check(a.current_health == health and combo.hits == 1, "闪避命中不叠层")
	a.unit_data.dodge_skill = null
	a.take_effect_damage(3, sword)
	check(combo.hits == 1, "毒或区域直接伤害不叠连击")
	normal.execute(sword, peer)
	check(combo.hits == 1, "攻击友军被拒绝不改变敌方连击")
	sword.skill_manager.current_target = b
	sword.skill_manager.current_target = a
	triple = source.skills[1]
	var expected := 0
	for hit in triple.hit_frame.size():
		expected += int((base + hit) * triple.attack_rate)
	check(await _cast(sword, a, triple) == expected, "三连击各命中帧伤害依次使用递增攻击力")
	check(combo.hits == triple.hit_frame.size(), "三连击每次命中都计数")
	var thrust: SkillBase = source.skills[2]
	expected = 0
	for hit in thrust.hit_frame.size():
		expected += int((base + combo.hits + hit) * thrust.attack_rate)
	check(await _cast(sword, a, thrust) == expected, "六连刺继续同目标已有层数计算伤害")
	check(combo.hits == triple.hit_frame.size() + thrust.hit_frame.size(), "不同攻击技能共用该目标的连击层数")
	sword.set_stunned(true)
	await _settle()
	check(combo.hits == triple.hit_frame.size() + thrust.hit_frame.size(), "短暂眩晕没有换目标时保留连击")
	sword.set_stunned(false)
	_effect(CardEffect.Kind.COPY_ALLY, sword)
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	check(copied.unit_data.attack == base and copied.consecutive_attack_bonus == 0, "复制品不烘焙原单位临时连击攻击")
	check(copied.skill_manager.get_node_or_null("ConsecutiveAttack") != null, "复制品保留技能但从零层开始")
	sword.set_protection_source(12345, 2, "庇护光环", 200)
	_effect(CardEffect.Kind.FRENZY, sword)
	check(sword.unit_data.attack == roundi((base + combo.hits + 2) * 0.7), "狂化与庇护按当前连击攻击共同计算")
	sword.skill_manager.current_target = b
	check(sword.unit_data.attack == roundi((base + 2) * 0.7), "切换目标仅撤销连击，庇护与狂化正确保留")
	normal.execute(sword, b)
	check(sword.unit_data.attack == roundi((base + 3) * 0.7), "狂化状态重新叠层没有属性漂移")
	sword.remove_protection_source(12345)
	check(sword.unit_data.attack == roundi((base + 1) * 0.7), "撤销庇护不会误删连击")
	b.die()
	check(combo.hits == 0 and sword.unit_data.attack == roundi(base * 0.7), "目标死亡立即清除连击并正确重算狂化")
	normal.execute(sword, a)
	_effect(CardEffect.Kind.RECALL_ALLY, sword)
	await _settle()
	check(card.unit_data.attack == base and card.permanent_buffs.is_empty(), "收回后的卡牌没有永久连击属性")
	var redeployed := _deploy(card, Vector2(500, 450))
	check(redeployed.unit_data.attack == base and redeployed.consecutive_attack_bonus == 0, "同一张卡重新部署从零层开始")
	normal.execute(redeployed, a)
	redeployed.unit_data.card_upgrade_level = 2
	await _settle()
	check(redeployed.consecutive_attack_bonus == 0, "精确强化等级不再匹配时撤销被动贡献")
	redeployed.unit_data.card_upgrade_level = 0
	normal.execute(redeployed, a)
	a.current_health = 1
	normal.execute(redeployed, a)
	check(redeployed.consecutive_attack_bonus == 0, "致命命中清零，不在已死亡目标上重新叠层")
	var c := _enemy(Vector2(550, 470))
	normal.execute(redeployed, c)
	redeployed.die()
	check(redeployed.consecutive_attack_bonus == 0, "施放者死亡撤销增益")
	check(source.attack == base and passive.attack_bonus_per_hit == 1 and peer.unit_data.attack == base + source.upgrade_ability_points, "共享资源、原牌和其他剑士不受连击污染")
	normal.execute(copied, c)
	battle.battle_finished = true
	await _settle()
	check(copied.consecutive_attack_bonus == 0 and copied.unit_data.attack == base, "战斗结束撤销残留连击")
	battle.queue_free()
	await get_tree().process_frame
	check(RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "保存和继续保留剑士被动配置")
	check(RunManager.deck[0].get_summon_data().attack == base and RunManager.deck[0].get_description().contains("攻击力增加1"), "存档不继承战斗临时层数")
	await _monster_test(source, passive)
	print("CONSECUTIVE_ATTACK_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _monster_test(source: UnitData, passive: SkillBase) -> void:
	var scene = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var configured := passive.duplicate(true) as SkillBase
	configured.attack_bonus_per_hit = 3
	var data := source.duplicate() as UnitData
	data.skills = [source.skills[0], configured]
	var sword := scene.spawn_unit(load("res://scenes/units/swords_man.tscn"), "team_a") as UnitBase
	check(sword.skill_manager.get_node_or_null("SeventhStrike") != null and sword.skill_manager.get_node_or_null("ConsecutiveAttack") == null, "怪物测试场正式剑士使用七伤，旧连击仅显式配置时生效")
	var custom := load("res://scenes/units/swords_man.tscn").instantiate() as UnitBase
	custom.unit_data = data
	sword.get_parent().add_child(custom)
	custom.set_physics_process(false)
	sword.set_physics_process(false)
	var enemy := scene.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b") as UnitBase
	enemy.set_physics_process(false)
	enemy.current_health = 10000
	source.skills[0].execute(custom, enemy)
	source.skills[0].execute(custom, enemy)
	check(custom.consecutive_attack_bonus == 6 and custom.unit_data.attack == source.attack + 6, "技能配置修改为每击+3实际生效")
	check(custom.get_node("HealthBar/StatusDisplay").statuses.any(func(entry: Dictionary): return entry.icon == "consecutive_attack"), "独立测试场显示连击增益状态")
	check(CardInstance.new(data).get_description().contains("攻击力增加3"), "卡牌说明跟随被动配置数值")
	check(passive.attack_bonus_per_hit == 1 and sword.consecutive_attack_bonus == 0, "配置变体不污染默认技能或其他单位")
	enemy.queue_free()
	await _settle()
	check(custom.consecutive_attack_bonus == 0 and custom.unit_data.attack == source.attack, "目标直接退树也清除连击")
	scene.queue_free()
	await get_tree().process_frame
