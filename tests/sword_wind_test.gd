extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []
var winds: Array[Node2D] = []


func _ready() -> void:
	get_tree().create_timer(70.0).timeout.connect(func(): get_tree().quit(1))
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


func _passive(unit: UnitBase) -> Node:
	return unit.skill_manager.get_node("SeventhStrike")


func _combo(unit: UnitBase) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == "三连击":
			return skill
	return null


func _reset() -> void:
	arena.clear_arena()
	await _frames(2)
	winds.clear()
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()


func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/sword-wind")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/sword-wind/%s.png" % name)


func _run() -> void:
	var source := load("res://data/units/swords_man.tres") as UnitData
	var card := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(2, 0), "剑士正式训练成功")
	check(card.get_summon_data().skills.size() == 4 and trained.get_summon_data().skills.size() == 4, "按等级替换三连击和七伤，保留普攻与六连刺")
	check(card.get_description().contains("6%") and trained.get_description().contains("8%") and not card.get_description().contains("攻击力增加"), "基础3+3=6%、强化5+3=8%，移除旧攻击成长")
	card.cost_increase = 2
	card.next_unit_discount = true
	check(card.get_cost() == 0 and card.get_intrinsic_cost() == 5 and card.get_summon_data().combat_card_cost == 5, "临时0费不改变原牌费用x，退场加费计入x")
	check(card.get_description().contains("8%"), "卡面真伤按原牌当前费用计算，不受0费显示影响")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	arena.team_a.child_entered_tree.connect(func(node):
		if node.get_script() != null and node.get_script().resource_path.ends_with("sword_wind_projectile.gd"):
			winds.append(node))
	await _frames(2)
	await _counter()
	await _base_combo()
	await _upgraded_combo()
	await _interrupted_combo()
	arena.queue_free()
	await _frames(2)
	await _formal_cost(source)
	print("SWORD_WIND_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _counter() -> void:
	var sword := _unit("swords_man", Vector2(800, 500))
	var peer := _unit("swords_man", Vector2(800, 700), 1)
	var enemy := _unit("orc", Vector2(860, 500))
	var other := _unit("orc", Vector2(860, 700))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var normal: SkillBase = sword.unit_data.skills[0]
	for hit in 6:
		normal.execute(sword, enemy)
	check(_passive(sword).hits == 6 and enemy.current_health == 892, "前6次伤害仅计数，不提前触发真伤或攻击成长")
	normal.execute(sword, enemy)
	check(_passive(sword).hits == 0 and enemy.current_health == 814 and sword.unit_data.attack == 18, "第7次追加最大生命6%真伤并清零，真伤不递归计数")
	normal.execute(sword, enemy)
	normal.execute(sword, other)
	check(_passive(sword).hits == 2 and _passive(peer).hits == 0, "换目标仍累计，不同剑士独立计数")
	enemy.take_effect_damage(10, sword)
	check(_passive(sword).hits == 2, "持续伤害与效果卡伤害不计入攻击技能计数")
	enemy.add_shield(100)
	normal.execute(sword, enemy)
	check(_passive(sword).hits == 2, "护盾完全吸收未扣生命的攻击不计数")
	enemy.clear_shield()
	enemy.unit_data.dodge_skill = SkillBase.new()
	enemy.unit_data.dodge_rate = 1.0
	normal.execute(sword, enemy)
	check(_passive(sword).hits == 2, "闪避攻击不触发伤害计数")
	enemy.unit_data.dodge_skill = null
	normal.execute(sword, peer)
	check(_passive(sword).hits == 2, "被拒绝的友军伤害不计数")
	_passive(peer).clear()
	enemy.current_health = 1000
	enemy.unit_data.defence = 999
	for hit in 7:
		peer.unit_data.skills[0].execute(peer, enemy)
	check(enemy.current_health == 913 and _passive(peer).hits == 0, "强化第7击追加8%最大生命真伤，无视高防御")
	_passive(sword).clear()
	var thrust: SkillBase = sword.skill_manager.group_skills.filter(func(skill): return skill.skill_name == "六连刺")[0]
	enemy.unit_data.defence = 0
	enemy.current_health = 1000
	_cast(sword, enemy, thrust)
	await _frames(150)
	check(enemy.current_health == 1000 - 7 * int(18 * 0.4) - 60 and _passive(sword).hits == 0, "六连刺真实7个伤害帧共触发一次费用真伤")
	for hit in 6:
		normal.execute(sword, other)
	other.current_health = 1
	normal.execute(sword, other)
	check(_passive(sword).hits == 0 and other.current_state == UnitBase.State.DEATH, "第7次原攻击致死仍清零，不在死者身上递归触发")
	check(sword.active_statuses().any(func(entry): return entry.icon == "seventh_strike" and entry.tooltip.contains("x=3")), "状态显示原牌费用和七次计数")
	sword.clear_combat_statuses()
	check(_passive(sword).hits == 0, "交锋清理清除计数")
	await _reset()


func _base_combo() -> void:
	var sword := _unit("swords_man", Vector2(800, 500))
	var enemy := _unit("orc", Vector2(860, 500))
	var farther := _unit("orc", Vector2(1100, 500))
	var outside := _unit("orc", Vector2(850, 700))
	var ally := _unit("soldier", Vector2(700, 500))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	_cast(sword, enemy, _combo(sword))
	await _frames(6)
	check(sword.global_position.x < 800 and sword.global_position.x > 500 and winds.is_empty(), "先真实后撤，不瞬移，不提前发风")
	await _capture("holy-step")
	await _frames(6)
	check(sword.global_position.distance_to(Vector2(500, 500)) < 0.1 and sword.animated_sprite_2d.animation == &"attack_02", "后撤300后才开始三连击动画")
	var motion: Node = sword.skill_manager.cast_data.get("sword_combo")
	check(motion.visuals[0].skill.id == "holy_step" and motion.visuals[0].get_children().any(func(node): return node.has_meta("effect_id") and node.get_meta("effect_id") == "scenes_vfx_holywarpvfx"), "后撤直接复用神圣Step配方及HolyWarp原素材")
	for frame in 60:
		await get_tree().physics_frame
		if not winds.is_empty():
			break
	check(winds.size() == 1 and sword.animated_sprite_2d.frame == 3, "基础三连击第一个伤害帧只释放一道风")
	check(winds[0].visual.get_meta("effect_id") == "scenes_projectiles_mediumtornadoprojectile", "吹风使用Lord of the Storm原中型龙卷风")
	await _frames(12)
	check(motion.visuals.size() == 2 and motion.visuals[1].skill.id == "dash" and sword.global_position.x > 500, "第一次放风后使用实验室冲刺配方向前突进")
	await _capture("base-wind")
	await _frames(160)
	check(enemy.current_health == 1000 - int(18 * 1.6) - 2 * int(18 * 0.7), "基础三连击结算1道160%风和剩下两帧70%近战")
	check(farther.current_health == 1000 - int(18 * 1.6), "同一道风穿过当前目标后继续伤害后排敌人")
	check(outside.current_health == 1000 and ally.current_health == 1000, "风不伤害路径外敌人或友军")
	check(_passive(sword).hits == 4, "两次近战加一道风命中两个目标，逐次累计4次伤害")
	check(not sword.skill_manager.is_casting and not sword.skill_manager.is_forced_moving and not sword.get_node("CollisionShape2D").disabled, "完整三连击收尾恢复技能锁和碰撞")
	await _reset()


func _upgraded_combo() -> void:
	var sword := _unit("swords_man", Vector2(800, 500), 1)
	var enemy := _unit("orc", Vector2(860, 500))
	var up := _unit("orc", Vector2(812, 320))
	var down := _unit("orc", Vector2(812, 680))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	_cast(sword, enemy, _combo(sword))
	var directions: Array[Vector2] = []
	var frames: Array[int] = []
	for frame in 160:
		await get_tree().physics_frame
		if winds.size() > directions.size():
			directions.append(winds.back().direction)
			frames.append(sword.animated_sprite_2d.frame)
			if directions.size() < 3:
				check(absf(sword.global_position.x - 500) < 0.1, "强化前两道风期间保持后撤位置")
			else:
				break
	check(directions.size() == 3 and frames == [3, 6, 12], "强化三个伤害帧依次释放三道风")
	check(is_equal_approx(directions[0].angle(), -PI / 6) and is_equal_approx(directions[1].angle(), PI / 6) and directions[2].is_equal_approx(Vector2.RIGHT), "强化依次向上30度、向下30度、正前方释放")
	await _capture("upgraded-winds")
	await _frames(130)
	check(sword.global_position.distance_to(Vector2(800, 500)) < 0.1 and not sword.skill_manager.is_casting, "第三道风后前突回原攻击位置并正常结束")
	check(enemy.current_health == 968 and up.current_health == 968 and down.current_health == 968, "三条路径上的敌人各受到160%伤害，无额外未指定近战帧")
	check(_passive(sword).hits == 3, "三道风的伤害均参与七伤计数")
	await _reset()


func _interrupted_combo() -> void:
	var sword := _unit("swords_man", Vector2(800, 500), 1)
	var enemy := _unit("orc", Vector2(860, 500))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _frames(2)
	_cast(sword, enemy, _combo(sword))
	await _frames(4)
	sword.apply_status(&"stun", 2.0)
	var at := sword.global_position
	await _frames(90)
	check(sword.global_position.is_equal_approx(at) and winds.is_empty() and enemy.current_health == 1000, "后撤中眩晕取消后续三道风和前突")
	check(not sword.skill_manager.is_casting and not sword.get_node("CollisionShape2D").disabled and sword.skill_manager.get_cooldown_left(_combo(sword)) > 0, "中断恢复碰撞并保留三连击冷却")
	sword.remove_status(&"stun")
	sword.global_position = Vector2(800, 500)
	_cast(sword, enemy, _combo(sword))
	for frame in 60:
		await get_tree().physics_frame
		if not winds.is_empty():
			break
	enemy.die()
	await _frames(120)
	check(winds.size() == 3 and not sword.skill_manager.is_casting, "初始目标死亡后仍完成已开始的三道方向风")
	await _reset()


func _formal_cost(source: UnitData) -> void:
	var start := RunStartData.new()
	start.cards.assign([source])
	RunManager.start_new_run(start)
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	var card: CardInstance = RunManager.deck[0]
	card.cost_increase = 2
	card.next_unit_discount = true
	battle.hand_manager.draw_pile.erase(card)
	battle.hand_manager.hand.append(card)
	battle.card_runtime.plays.next_unit_free = true
	battle.battle_round_manager.current_energy = 0
	check(battle.card_runtime.try_play(card, Vector2(500, 500)), "真正以0费出牌部署已有退场加费的剑士")
	var sword: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	sword.set_physics_process(false)
	check(sword.unit_data.combat_card_cost == 5 and _passive(sword).cost() == 5 and battle.battle_round_manager.current_energy == 0, "实际支付0费但七伤按原费用5计算")
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(560, 500)
	enemy.set_physics_process(false)
	enemy.unit_data.max_hp = 1000
	enemy.current_health = 1000
	enemy.unit_data.defence = 999
	enemy.unit_data.dodge_skill = null
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for hit in 7:
		sword.unit_data.skills[0].execute(sword, enemy)
	check(enemy.current_health == 913 and _passive(sword).hits == 0, "0费部署实际触发3+5=8%最大生命真伤")
	for hit in 3:
		sword.unit_data.skills[0].execute(sword, enemy)
	var copy := CardDefinition.new()
	copy.target = CardDefinition.Target.ALLY
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.COPY_ALLY
	copy.effects.assign([effect])
	var copy_card := CardInstance.new(copy)
	battle.hand_manager.hand.append(copy_card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(copy_card, sword.global_position), "通过真实复制牌复制剑士")
	var copied: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	copied.set_physics_process(false)
	check(_passive(copied).hits == 0 and _passive(copied).cost() == 5 and _passive(sword).hits == 3, "复制品保留原牌费用但独立从零计数")
	check(source.attack == 18 and source.card_cost == 3 and source.combat_card_cost == -1, "出场费用快照不修改共享剑士资源")
	battle.queue_free()
	await _frames(2)
