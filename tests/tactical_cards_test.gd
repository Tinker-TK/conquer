# 实际资源与正式出牌入口：覆盖阵容变化、伤害、换队、动作中断和跨回合清理。
extends Node

const NAMES := ["weakness", "vulnerability", "intimidation", "paralysis", "convert_enemy", "frenzy", "retreat_draw", "diverse_army", "keep_distance", "judger"]
const COSTS := [1, 1, 1, 1, 2, 2, 1, 2, 2, 2]
var checks := 0
var failures: Array[String] = []
var battle
var hand
var runtime
var rounds
var tactics


func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _create_battle() -> void:
	var start := RunStartData.new()
	for i in 15:
		start.cards.append(load("res://data/units/soldier.tres"))
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	config.enemy_max_hp = 1000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	tactics = runtime.tactics
	runtime.set_physics_process(false)
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "战术测试导航已同步")


func _unit(team: String, point: Vector2, type: int = 0, scene_name: String = "") -> UnitBase:
	if scene_name.is_empty():
		scene_name = "soldier" if team == "team_a" else "orc"
	var unit := load("res://scenes/units/%s.tscn" % scene_name).instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.attack = 20
	unit.unit_data.defence = 10
	unit.unit_data.max_hp = 1000
	unit.unit_data.unit_type = type as Global.UnitType
	unit.unit_data.monster_rank = UnitData.MonsterRank.NORMAL
	unit.unit_data.unit_team = team
	unit.remove_from_group("team_a" if team == "team_b" else "team_b")
	unit.add_to_group(team)
	unit.set_collision_layer_value(1, team == "team_a")
	unit.set_collision_layer_value(2, team == "team_b")
	var parent: Node2D = battle.get_node("Entities/TeamA" if team == "team_a" else "Entities/TeamB")
	unit.position = parent.to_local(point)
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _give(resource_name: String) -> CardInstance:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % resource_name))
	hand.hand.append(card)
	return card


func _play(resource_name: String, unit: UnitBase = null) -> CardInstance:
	var card := _give(resource_name)
	rounds.current_energy = card.get_cost()
	var point := unit.global_position if unit != null else Vector2(450, 450)
	var reason: String = runtime._validate_card({"runtime": runtime, "card": card, "position": point, "target": runtime.pick_target(card.definition, point), "depth": 0, "prepared": null}, false)
	check(runtime.try_play(card, point), resource_name + "正式出牌：" + reason)
	check(rounds.current_energy == 0 and not hand.hand.has(card), resource_name + "扣费和移牌")
	tactics.set_physics_process(false)
	return card


func _blocked(resource_name: String, point: Vector2, label: String) -> void:
	var card := _give(resource_name)
	rounds.current_energy = 10
	check(not runtime.try_play(card, point) and hand.hand.has(card) and rounds.current_energy == 10, label)
	hand.hand.erase(card)


func _dispose() -> void:
	battle.finish_battle(false)
	battle.queue_free()
	await get_tree().process_frame


func _run() -> void:
	for i in NAMES.size():
		var card := load("res://data/cards/%s.tres" % NAMES[i]) as CardDefinition
		check(card.card_cost == COSTS[i], NAMES[i] + "费用配置")
		check(card.rarity == (CardDefinition.Rarity.RARE if i in [5, 7, 8, 9] else CardDefinition.Rarity.COMMON), NAMES[i] + "稀有度配置")
		check(card.effects[0].kind == 20 + i, NAMES[i] + "效果编号")
	await _debuffs_and_conversion()
	await _conversion_selection()
	await _formations_and_damage()
	await _paralysis_and_rounds()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	print("TACTICAL_CARDS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _debuffs_and_conversion() -> void:
	await _create_battle()
	var ally := _unit("team_a", Vector2(450, 450))
	var enemy := _unit("team_b", Vector2(700, 450))
	var other := _unit("team_b", Vector2(900, 450))
	_blocked("weakness", ally.global_position, "敌方减益拒绝己方目标")
	var costly := _give("vulnerability")
	rounds.current_energy = 0
	check(not runtime.try_play(costly, enemy.global_position) and rounds.current_energy == 0 and hand.hand.has(costly), "费用不足保留牌和能量")
	hand.hand.erase(costly)
	_play("weakness", enemy)
	_play("weakness", enemy)
	_play("intimidation", enemy)
	_play("intimidation", enemy)
	_play("vulnerability", enemy)
	check(enemy.unit_data.attack == 16 and enemy.unit_data.defence == 6, "虚弱与恐吓各两层减4")
	check(tactics.records[enemy.get_instance_id()].effects[CardEffect.Kind.WEAKNESS].stacks == 2, "虚弱记录叠层")
	_blocked("vulnerability", enemy.global_position, "易伤不叠加且失败不扣费")
	var hp: int = enemy.current_health
	load("res://data/skills/normal_attack.tres").execute(ally, enemy)
	check(enemy.current_health == hp - 16, "易伤按(20-6)×1.2取整数16")
	check(tactics.attack_damage(enemy, ally, 1) == 1, "攻击结算保留最低1伤害")
	# 子弹和近战共用受伤入口。
	rounds.start_auto_battle()
	var projectile := Projectile.new()
	battle.add_child(projectile)
	projectile.global_position = enemy.global_position
	projectile.fire(ally, enemy, 20)
	projectile._physics_process(0.0)
	check(enemy.current_health == hp - 32, "远程投射物同样结算易伤")
	var area_caster := _unit("team_a", Vector2(700, 460), 0, "lancer")
	area_caster.get_node("AttackArea").monitoring = true
	for i in 3:
		await get_tree().physics_frame
	load("res://scripts/skills/area_attack.gd").new().execute(area_caster, enemy)
	check(enemy.current_health == hp - 48, "物理范围攻击同样结算扣防御后的易伤")
	area_caster.get_parent().remove_child(area_caster)
	area_caster.queue_free()
	# 策反拒绝每一档非普通敌人，接受受伤且已有减益的普通敌人。
	for rank in [UnitData.MonsterRank.ELITE, UnitData.MonsterRank.BOSS, UnitData.MonsterRank.LEGENDARY]:
		other.unit_data.monster_rank = rank
		_blocked("convert_enemy", other.global_position, "策反拒绝等级%d" % rank)
	other.unit_data.monster_rank = UnitData.MonsterRank.NORMAL
	ally.skill_manager._nearest_enemy_target = enemy
	ally.skill_manager.current_target = enemy
	ally.skill_manager.cast_target = enemy
	var old_projectile := Projectile.new()
	battle.add_child(old_projectile)
	old_projectile.position = Vector2(500, 450)
	old_projectile.fire(enemy, ally, 16)
	var health: int = enemy.current_health
	var count: int = runtime.states.size()
	_play("convert_enemy", enemy)
	check(enemy.get_parent() == battle.get_node("Entities/TeamA") and enemy.unit_data.unit_team == "team_a", "策反更新父节点和阵营")
	check(enemy.is_in_group("team_a") and not enemy.is_in_group("team_b"), "策反更新分组")
	check(enemy.get_collision_layer_value(1) and not enemy.get_collision_layer_value(2), "策反更新碰撞阵营")
	check(enemy.current_health == health and runtime.states.size() == count and enemy.unit_data.attack == 16, "策反保留生命和原状态且不重复登记")
	check(ally.skill_manager.cast_target == null and ally.skill_manager._nearest_enemy_target == null, "策反清除旧己方攻击锁")
	check(enemy.skill_manager.find_nearest_enemy() == other, "策反单位主动索敌敌军")
	check(not ally.skill_manager._can_target_enemy(enemy) and other.skill_manager._can_target_enemy(enemy), "双方索敌随策反更新")
	old_projectile._physics_process(0.0)
	check(old_projectile.is_queued_for_deletion(), "策反中断换队前发出的敌军子弹")
	var ally_hp: int = ally.current_health
	check(not ally.get_hurt(999, enemy) and ally.current_health == ally_hp, "换队后的旧攻击不会误伤友军")
	var other_hp: int = other.current_health
	load("res://data/skills/normal_attack.tres").execute(enemy, other)
	check(other.current_health < other_hp, "策反敌人协助攻击原队友")
	var cards: int = hand.discard_pile.size()
	enemy.die()
	check(hand.discard_pile.size() == cards and not hand.board_cards.has(enemy.get_instance_id()), "策反单位退场不产生原征召牌")
	var inspector = battle.card_ui.get_node("UnitInspector")
	other.unit_data.monster_rank = UnitData.MonsterRank.BOSS
	inspector.open_unit(other)
	check(inspector.unit_title.get_parsed_text().contains("首领"), "单位详情显示怪物等级")
	await _dispose()


func _conversion_selection() -> void:
	await _create_battle()
	var ally := _unit("team_a", Vector2(450, 450))
	var enemy := _unit("team_b", Vector2(700, 450))
	# 即使敌军使用有选中属性的原己方脚本，策反后也不允许手动操控。
	var converted_controlled := _unit("team_b", Vector2(900, 450), 0, "lancer")
	var remaining_enemy := _unit("team_b", Vector2(1050, 450))
	_play("convert_enemy", enemy)
	_play("convert_enemy", converted_controlled)
	var selection = battle.get_node("MouseSlectionController")
	selection._finish_selected(enemy.global_position, enemy.global_position)
	check(selection.selected_units.is_empty(), "点击策反后的普通敌军不选中且不访问缺失属性")
	selection._finish_selected(converted_controlled.global_position, converted_controlled.global_position)
	check(selection.selected_units.is_empty() and not converted_controlled.is_selected, "有操控脚本的策反单位同样不可点击选中")
	selection._finish_selected(Vector2(400, 400), Vector2(1000, 500))
	check(selection.selected_units == [ally] and ally.is_selected, "混合框选只选择原己方，跳过所有策反单位")
	selection._finish_selected(enemy.global_position - Vector2(30, 30), enemy.global_position + Vector2(30, 30))
	check(selection.selected_units.is_empty() and not ally.is_selected, "只框选策反单位时清除旧选择")
	# 兼容此前报错后已被写入选择列表的无操控属性对象。
	selection.selected_units.append(enemy)
	selection.clear_selection()
	check(selection.selected_units.is_empty(), "清理残留选择不访问敌军缺失属性")
	selection._add_seleted(enemy)
	selection._add_seleted(converted_controlled)
	check(selection.selected_units.is_empty(), "直接加入选择也拒绝策反单位")
	converted_controlled.is_selected = true
	var command := InputEventAction.new()
	command.action = &"move"
	command.pressed = true
	converted_controlled._unhandled_input(command)
	check(converted_controlled.target_position == null, "策反单位拒绝右键部署指令")
	converted_controlled.is_selected = false
	selection._finish_selected(ally.global_position, ally.global_position)
	check(selection.selected_units == [ally] and ally.is_selected, "原己方点击选择仍正常")
	battle._on_button_pressed()
	check(Global.game_phase == Global.GamePhase.AUTO_BATTLE and selection.selected_units.is_empty() and not ally.is_selected, "策反后点击开打安全清除选择")
	check(enemy.skill_manager.find_nearest_enemy() == remaining_enemy and converted_controlled.skill_manager.find_nearest_enemy() == remaining_enemy, "不可操控的策反单位仍自动索敌")
	await _dispose()


func _formations_and_damage() -> void:
	await _create_battle()
	var hero := _unit("team_a", Vector2(450, 450), 0)
	var second := _unit("team_a", Vector2(450, 650), 1)
	var third := _unit("team_a", Vector2(450, 850), 2)
	var enemy := _unit("team_b", Vector2(1050, 450))
	var common_attack := hero.unit_data.attack
	var common_defence := hero.unit_data.defence
	_play("frenzy", hero)
	check(hero.unit_data.attack == 14 and hero.unit_data.defence == 7, "狂化恰好3友军攻防70%")
	_blocked("frenzy", hero.global_position, "同单位狂化不可重复叠加")
	for i in 100:
		tactics.refresh_all()
	check(hero.unit_data.attack == 14 and hero.unit_data.defence == 7, "实时刷新不连续累乘")
	var composition_card := _play("diverse_army")
	check(hand.active_cards.has(composition_card) and hero.unit_data.attack == 15 and second.unit_data.attack == 22, "三兵种全体+2再计算狂化70%")
	var inspector = battle.card_ui.get_node("UnitInspector")
	inspector.open_unit(hero)
	check(inspector.stat_labels.attack.get_parsed_text().contains("15 (-5)"), "详情显示动态攻防差值")
	check(inspector.status_cells.has("composition") and inspector.status_cells.has("frenzy"), "详情提供全局和单体状态图标")
	_blocked("diverse_army", Vector2(450, 450), "合理搭配常驻不重复叠加")
	third.die()
	check(hero.unit_data.attack == 20 and hero.unit_data.defence == 10 and second.unit_data.attack == 20, "两友军恢复100%且兵种不足撤销+2")
	var same_type_unit := _unit("team_a", Vector2(550, 650), 0)
	check(hero.unit_data.attack == 14 and second.unit_data.attack == 20, "同类兵种不重复计种但计入狂化人数")
	var diverse := _unit("team_a", Vector2(550, 850), 2)
	check(hero.unit_data.attack == 15 and diverse.unit_data.attack == 22, "后来入场第三兵种恢复合理搭配")
	diverse.die()
	same_type_unit.die()
	var skill: SkillBase = hero.unit_data.skills[0]
	var timer: Timer = hero.skill_manager._skill_time_cd[skill]
	timer.start(skill.cooldown)
	var fraction: float = hero.skill_manager.get_cooldown_fraction(skill)
	second.die()
	check(hero.unit_data.attack == 30 and hero.unit_data.defence == 13, "独存狂化攻击150%防御130%")
	check(is_equal_approx(hero.skill_manager.cooldown_multiplier, 0.8) and is_equal_approx(timer.wait_time, skill.cooldown * 0.8), "独存技能冷却减少20%")
	check(is_equal_approx(hero.skill_manager.get_cooldown_fraction(skill), fraction), "阵容切换保持正在运行冷却的完成比例")
	check(inspector.status_cells.has("frenzy"), "狂化状态继续存在")
	# 其它卡的加法增益加入基础后实时重算。
	var buff := CardEffect.new()
	buff.amount = 4
	runtime._add_buff(hero, buff, "测试攻击强化")
	check(hero.unit_data.attack == 36, "加法强化立即进入狂化乘数")
	_play("judger", hero)
	_play("vulnerability", enemy)
	var distance_card := _play("keep_distance")
	check(hand.active_cards.has(distance_card), "保持距离常驻区")
	_blocked("keep_distance", Vector2(450, 450), "保持距离全局效果不重复叠加")
	for entry in [[0.0, 12], [300.0, 19], [600.0, 27], [900.0, 27]]:
		enemy.global_position = hero.global_position + Vector2(entry[0], 0)
		check(tactics.attack_damage(enemy, hero, 25) == int(entry[1]), "距离%.0f的扣防御后易伤伤害" % entry[0])
	# 怪物攻击不受己方全场距离加成。
	check(tactics.attack_damage(hero, enemy, 25) == 12, "距离效果仅作用己方攻击")
	enemy.global_position = Vector2(1050, 450)
	hero.set_floor(3)
	var before_high_ground := int(enemy.current_health)
	var tactical_damage: int = tactics.attack_damage(enemy, hero, 25)
	enemy.get_hurt(25, hero, false)
	check(before_high_ground - enemy.current_health == roundi(tactical_damage * 1.2), "高地增伤在距离、扣防御和易伤结算后仅应用一次")
	hero.set_floor(1)
	hero.current_health = 100
	rounds.start_auto_battle()
	var health: int = enemy.current_health
	load("res://data/skills/normal_attack.tres").execute(hero, enemy)
	var actual: int = health - enemy.current_health
	check(hero.current_health == 100 + int(actual * 0.2), "狂化吸血回复实际伤害×20%")
	var victim := _unit("team_b", Vector2(800, 650))
	victim.current_health = 3
	hero.current_health = 100
	load("res://data/skills/normal_attack.tres").execute(hero, victim)
	check(hero.current_health == 100, "吸血按剩余3生命的20%取整，排除过量伤害")
	check(hero.unit_data.attack == 39, "审判者击杀+2再进入150%狂化")
	var poison_victim := _unit("team_b", Vector2(850, 800))
	poison_victim.current_health = 2
	poison_victim.take_effect_damage(10, hero)
	check(hero.unit_data.attack == 42 and hero.current_health == 100, "带来源的效果伤害结算审判者与实际伤害吸血")
	var judge: Dictionary = tactics.records[hero.get_instance_id()].effects[CardEffect.Kind.JUDGER]
	check(judge.kills == 2, "每名敌人计击杀一次")
	poison_victim.die(hero)
	check(judge.kills == 2, "重复死亡不能重复激励")
	# 复制原属性与传统强化；全场效果实时应用，单体状态不烘焙进新单位。
	var copy_definition := CardDefinition.new()
	copy_definition.target = CardDefinition.Target.ALLY
	var copy_effect := CardEffect.new()
	copy_effect.kind = CardEffect.Kind.COPY_ALLY
	copy_definition.effects.append(copy_effect)
	var copy := CardInstance.new(copy_definition)
	hand.hand.append(copy)
	rounds.current_energy = 99
	check(runtime.try_play(copy, hero.global_position), "复制受战术状态影响的单位")
	var clone: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	clone.set_physics_process(false)
	check(clone.unit_data.attack == common_attack + 4 and clone.unit_data.defence == common_defence, "复制不永久烘焙狂化或击杀加成")
	check(hero.unit_data.attack == 28 and hero.unit_data.defence == 10 and hero.skill_manager.cooldown_multiplier == 1.0, "新增友军恢复100%并保留击杀和基础强化")
	runtime._on_round_ended()
	check(hero.unit_data.attack == 28 and tactics.composition != null and tactics.distance_effect != null, "单体战斗状态与全场常驻跨回合保留")
	check(not tactics.records[enemy.get_instance_id()].effects.has(CardEffect.Kind.VULNERABILITY), "易伤回合末清除")
	battle.finish_battle(false)
	check(tactics.composition == null and tactics.distance_effect == null and hand.active_cards.is_empty(), "战斗结束清除全场常驻")
	check(hero.unit_data.attack == common_attack and hero.unit_data.defence == common_defence and hero.skill_manager.cooldown_multiplier == 1.0, "战斗结束恢复原属性与冷却")
	battle.queue_free()
	await get_tree().process_frame


func _paralysis_and_rounds() -> void:
	await _create_battle()
	var ally := _unit("team_a", Vector2(450, 450))
	var peer := _unit("team_a", Vector2(450, 650))
	var enemy := _unit("team_b", Vector2(700, 450), 0, "lancer")
	_play("undying_army")
	_play("weakness", enemy)
	_play("intimidation", enemy)
	_play("vulnerability", enemy)
	_play("paralysis", enemy)
	_blocked("paralysis", enemy.global_position, "麻痹不可叠加")
	_play("retreat_draw")
	rounds.start_auto_battle()
	tactics._physics_process(2.99)
	check(not enemy.is_stunned, "麻痹3秒前正常")
	var dash: SkillBase = load("res://data/skills/lancer_dash_attack.tres").duplicate()
	dash.dash_speed = 30.0
	enemy.skill_manager.current_skill = dash
	enemy.skill_manager.is_casting = true
	enemy.switch_state(UnitBase.State.ATTACK)
	dash.execute(enemy, ally)
	for i in 4:
		await get_tree().physics_frame
	check(enemy.skill_manager.is_forced_moving and enemy.skill_manager.forced_movement_tween != null, "真实冲刺已经开始")
	tactics._physics_process(0.02)
	check(enemy.is_stunned and enemy.current_state == UnitBase.State.IDLE, "3秒触发眩晕并重置行动状态")
	check(not enemy.skill_manager.is_casting and not enemy.skill_manager.is_forced_moving, "麻痹中断攻击和冲刺")
	var stop := enemy.global_position
	var hp: int = ally.current_health
	enemy.skill_manager.current_target = ally
	enemy.skill_manager.current_skill = enemy.unit_data.skills[0]
	enemy.skill_manager.cast_target = ally
	enemy.skill_manager.attack()
	enemy.skill_manager.fire_projectile(enemy.unit_data.skills[0])
	check(not enemy.skill_manager.is_casting and ally.current_health == hp, "眩晕不能发起或结算攻击")
	enemy.skill_manager.start_reaction(enemy.unit_data.skills[0], ally)
	check(not enemy.skill_manager.is_reacting, "眩晕不能反击")
	for i in 4:
		await get_tree().physics_frame
	check(enemy.global_position.is_equal_approx(stop) and not enemy.get_node("CollisionShape2D").disabled and not enemy.get_node("AttackArea").monitoring, "眩晕停住冲刺并恢复碰撞")
	check(not enemy.animated_sprite_2d.is_playing(), "眩晕暂停动画")
	var clock: float = tactics.records[enemy.get_instance_id()].effects[CardEffect.Kind.PARALYSIS].elapsed
	Global.game_phase = Global.GamePhase.CARD_PLAY
	tactics._physics_process(10.0)
	check(tactics.records[enemy.get_instance_id()].effects[CardEffect.Kind.PARALYSIS].elapsed == clock, "准备阶段不累计麻痹时间")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	enemy.status_runtime._physics_process(1.0)
	tactics._physics_process(1.0)
	check(not enemy.is_stunned, "眩晕1秒后恢复")
	tactics._physics_process(2.0)
	check(enemy.is_stunned, "第6秒再次眩晕")
	# 存活者按结算时计算；毒会先使一名友军死亡。
	runtime.states[peer.get_instance_id()].poison = int(peer.current_health)
	var current_round: int = rounds.current_round
	enemy.die()
	await rounds.finish_unit_combat()
	await get_tree().process_frame
	check(rounds.current_round == current_round + 1 and not battle.battle_finished, "推进真实下一回合")
	check(hand.hand.size() == 1 and hand.pending_bonus_draw == 0, "鸣金收兵按毒结算后的1存活者多抽1张且消费一次")
	check(is_instance_valid(ally) and ally.is_inside_tree() and not is_instance_valid(peer), "留存友军与毒死亡正常处理")
	check(tactics.retreat_uses == 0, "鸣金收兵不重复进入后续回合")
	var next_enemy := _unit("team_b", Vector2(750, 450))
	_play("weakness", next_enemy)
	_play("intimidation", next_enemy)
	_play("vulnerability", next_enemy)
	_play("paralysis", next_enemy)
	# 单独回合清理可验证被保留单位恢复；实际敌人随后照常清场。
	runtime._on_round_ended()
	check(next_enemy.unit_data.attack == 20 and next_enemy.unit_data.defence == 10 and not next_enemy.is_stunned, "回合结束撤销属性减益和眩晕")
	check(tactics.records[next_enemy.get_instance_id()].effects.is_empty(), "四种当回合减益全部移除")
	check(hand.pending_bonus_draw == 0, "无新收兵牌不再加抽")
	await _dispose()
	await _create_battle()
	check(hand.pending_bonus_draw == 0 and tactics.records.is_empty() and tactics.composition == null and tactics.distance_effect == null, "新战斗状态完全隔离")
	await _dispose()


func _capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 880)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("0b1c2b")
	background.size = Vector2(1600, 880)
	viewport.add_child(background)
	var views: Array[UnitCard] = []
	for i in NAMES.size():
		var view := load("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
		view.is_playable = false
		viewport.add_child(view)
		view.setup(CardInstance.new(load("res://data/cards/%s.tres" % NAMES[i])))
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		view.position = Vector2(175 + (i % 5) * 320, 220 + (i / 5) * 440)
		views.append(view)
	await get_tree().process_frame
	for view in views:
		var description := view.get_node("CardDiscription") as RichTextLabel
		check(description.get_content_height() <= description.size.y and not description.scroll_active, view.card_instance.definition.card_name + "文案完整显示")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance")
	viewport.get_texture().get_image().save_png("res://.maintenance/tactical_cards_preview.png")
	viewport.queue_free()
