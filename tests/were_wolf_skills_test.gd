# 正式部署与真实命中动画验证一次低血隐身、最大生命索敌、Angel扑击和五连斩击。
extends Node

var battle: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
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
	check(battle.card_runtime.try_play(card, point), "通过正式出牌部署狼人或友军")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _enemy(point: Vector2) -> UnitBase:
	var unit := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(unit)
	unit.global_position = point
	unit.set_physics_process(false)
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	unit.current_health = 10000
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
	check(battle.card_runtime.try_play(card, target.global_position), "通过正式卡牌验证复制或收回")


func _wall(point: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	battle.add_child(wall)
	wall.global_position = point
	return wall


func _run() -> void:
	var source := load("res://data/units/were_wolf.tres") as UnitData
	var passive := load("res://data/skills/were_wolf_low_health_stealth.tres") as SkillBase
	var five := load("res://data/skills/were_wolf_five_attack_upgraded.tres") as SkillBase
	check(source.skills.has(passive) and passive.is_passive() and passive.stealth_duration == 5.0 and passive.stealth_health_percent == 50.0, "现有狼人拥有50%阈值、5秒隐身")
	check(five.has_custom_targeting() and not five.is_global_cast() and five.cast_range == 450 and five.hit_frame == [7, 8, 9, 10, 11], "强化五连斩击为450距离自定义索敌，保留原五个命中帧")
	check(five.stun_seconds == 2.0 and five.refresh_on_target_kill, "强化五连斩击提供2秒眩晕及击杀锁定目标刷新")
	var start := RunStartData.new()
	start.cards.assign([source, source, load("res://data/units/soldier.tres")])
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	var normal_card: CardInstance = RunManager.deck[0]
	var card: CardInstance = RunManager.deck[1]
	check(card.train(source.upgrade_ability_points, 0) and card.get_summon_data().skills.has(passive), "强化狼人也保留该被动")
	check(card.get_description().contains("最大生命最低") and normal_card.get_description().contains("350") and card.get_description().contains("450") and card.get_description().contains("每次部署只触发一次"), "卡牌说明跟随基础和强化扑击，同时保留隐身说明")
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	for unit: UnitBase in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	var wolf := _deploy(card, Vector2(500, 450))
	var peer := _deploy(normal_card, Vector2(400, 750))
	var ally := _deploy(RunManager.deck[2], Vector2(400, 650))
	var near := _enemy(Vector2(600, 450))
	var far := _enemy(Vector2(1350, 550))
	var middle := _enemy(Vector2(960, 800))
	await _settle()
	var stealth = wolf.skill_manager.get_node("LowHealthStealth")
	check(not wolf.skill_manager._skill_time_cd.has(passive) and not peer.is_stealthed, "被动独立于主动技能冷却及其他狼人")
	check(wolf.skill_manager.find_farthest_enemy() == far, "最远按世界距离选择，不受近战范围限制")
	far.set_stealthed(true)
	check(wolf.skill_manager.find_farthest_enemy() == middle, "最远索敌跳过隐身目标")
	far.set_stealthed(false)
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	wolf.current_health = wolf.unit_data.max_hp / 2
	await _settle()
	check(not wolf.is_stealthed and not stealth.triggered, "生命等于50%时不触发隐身")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	near.skill_manager.current_skill = near.unit_data.skills[0]
	near.skill_manager.current_target = wolf
	near.switch_state(UnitBase.State.ATTACK)
	near.skill_manager.attack()
	wolf.get_hurt(wolf.unit_data.defence + 1, near)
	check(wolf.is_stealthed and stealth.triggered and stealth.remaining == 5.0, "受击低于50%立刻触发五秒隐身")
	check(not near.skill_manager.is_casting and near.skill_manager.cast_target == null and near.skill_manager.current_target == null, "进入隐身取消敌军已有攻击锁定")
	check(not wolf.can_be_targeted_by(near) and wolf.can_be_targeted_by(ally), "敌军不可索敌，己方仍可选中治疗")
	check(near.skill_manager.find_nearest_enemy() != wolf and near.skill_manager.find_lowest_health_enemy(false) != wolf and near.skill_manager.find_lowest_health_enemy(true) != wolf and near.skill_manager.find_farthest_enemy() != wolf, "所有敌军索敌方式均跳过隐身狼人")
	check(ally.skill_manager.find_ally_lowest_hp() == wolf, "友军低血治疗仍识别隐身狼人")
	check(wolf.animated_sprite_2d.modulate.a < 0.3 and wolf.get_node("HealthBar/StatusDisplay").statuses.any(func(entry: Dictionary): return entry.icon == "stealth"), "隐身状态以半透明及图标表示")
	var health := int(wolf.current_health)
	check(wolf.get_hurt(wolf.unit_data.defence + 1, near) and wolf.current_health == health - 1, "隐身只限制索敌，既有伤害仍能结算")
	var before_pause := float(stealth.remaining)
	get_tree().paused = true
	for frame in 12:
		await get_tree().process_frame
	check(is_equal_approx(stealth.remaining, before_pause), "暂停不消耗隐身时长")
	get_tree().paused = false
	far.global_position = Vector2(860, 450)
	far.unit_data.max_hp = 50
	check(wolf.skill_manager.pick_skill() and wolf.skill_manager.current_skill == five and wolf.skill_manager.current_target == far, "五连斩击选择施法距离内最大生命最低的敌人")
	var origin := wolf.global_position
	var far_health := int(far.current_health)
	var near_health := int(near.current_health)
	wolf.switch_state(UnitBase.State.ATTACK)
	wolf.skill_manager.attack()
	check(wolf.global_position == origin and wolf.skill_manager.is_forced_moving, "开始施法后先真实扑击，不瞬移")
	check(wolf.skill_manager.get_cooldown_left(five) > 6.9, "扑击和五连斩击只启动一次原7秒冷却")
	var motion: Node = wolf.skill_manager.cast_data.get("wolf_pounce")
	check(is_instance_valid(motion) and motion.visual.skill.id == "angel_dash", "实战直接使用实验室Angel冲刺配方")
	check(get_tree().get_nodes_in_group("teleport_portal_burst").is_empty(), "五连斩击不再生成传送门")
	if "--capture-were-wolf" in OS.get_cmdline_user_args():
		for frame in 8:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/were-wolf-angel.png")
	for frame in 22:
		await get_tree().physics_frame
	check(wolf.global_position.distance_to(far.global_position) <= five.melee_range and wolf.animated_sprite_2d.animation == five.cast_animation, "扑击结束才播放原五连斩击动画")
	for frame in 180:
		await get_tree().physics_frame
		if not wolf.skill_manager.is_casting:
			break
	check(not wolf.skill_manager.is_casting and far_health - int(far.current_health) == int(wolf.unit_data.attack * five.attack_rate) * 5, "原五个命中帧分别造成真实伤害并正常收尾")
	check(near.current_health == near_health and wolf.is_stealthed and far.has_status(&"stun"), "仅斩击锁定目标并提供眩晕，攻击不解除隐身")
	await _settle()
	check(get_tree().get_nodes_in_group("teleport_portal_burst").is_empty(), "施法收尾没有遗留传送门")
	var elapsed := 5.0 - float(stealth.remaining)
	for frame in 360:
		if not wolf.is_stealthed:
			break
		await get_tree().physics_frame
		elapsed += wolf.get_physics_process_delta_time()
	check(not wolf.is_stealthed and absf(elapsed - 5.0) < 0.06 and wolf.animated_sprite_2d.modulate.a == 1.0, "五秒后可重新被索敌且恢复外观")
	wolf.get_heal(wolf.unit_data.max_hp)
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	wolf.take_effect_damage(wolf.unit_data.max_hp * 3 / 4, near)
	await _settle()
	check(not wolf.is_stealthed and stealth.triggered, "回血后再次低血也不会重复触发")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	wolf.global_position = origin
	var landing = five.find_landing_position(wolf, far)
	check(landing != null, "真实导航图中能找到合法扑击落点")
	if landing != null:
		var wall := _wall(landing, Vector2(24, 48))
		await _settle()
		var alternative = five.find_landing_position(wolf, far)
		check(alternative != null and alternative.distance_to(landing) > 15.0 and alternative.distance_to(far.global_position) <= five.melee_range, "首选落点有墙时改用身边其他可到达位置")
		wall.queue_free()
		await _settle()
	var blocker := _wall(far.global_position, Vector2(200, 200))
	await _settle()
	check(five.find_landing_position(wolf, far) == null, "目标周围全部被墙遮挡时不会穿墙落点")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	wolf.skill_manager.current_skill = five
	wolf.skill_manager.current_target = far
	wolf.switch_state(UnitBase.State.ATTACK)
	wolf.skill_manager.attack()
	check(not wolf.skill_manager.is_casting and wolf.global_position == origin, "无法找到合法落点时解除施法锁")
	blocker.queue_free()
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_effect(CardEffect.Kind.COPY_ALLY, wolf)
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	check(not copied.skill_manager.get_node("LowHealthStealth").triggered and not copied.is_stealthed, "复制品获得自己的未使用触发次数")
	# 复制规则沿用原单位的当前血量；只施加少量伤害，不能把低血复制品误杀。
	copied.take_effect_damage(1)
	check(copied.is_stealthed and not wolf.is_stealthed, "直接效果伤害可触发复制狼人的独立隐身")
	_effect(CardEffect.Kind.RECALL_ALLY, wolf)
	await _settle()
	var redeployed := _deploy(card, Vector2(500, 450))
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	redeployed.take_effect_damage(redeployed.unit_data.max_hp * 3 / 4)
	check(redeployed.is_stealthed and not card.unit_data.get("is_stealthed"), "同一张牌重新部署可再次触发且状态不写进卡牌")
	redeployed.die()
	check(not redeployed.is_stealthed, "死亡立即清除隐身状态")
	copied.unit_data.card_upgrade_level = 2
	await _settle()
	check(not copied.is_stealthed, "技能强化等级失效时撤销隐身")
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	peer.take_effect_damage(peer.unit_data.max_hp * 3 / 4)
	battle.battle_finished = true
	await _settle()
	check(not peer.is_stealthed, "战斗结束清除残留隐身")
	check(source.card_upgrade_level == 0 and passive.stealth_duration == 5.0 and card.permanent_buffs.is_empty(), "共享资源和原牌保持独立")
	battle.queue_free()
	await get_tree().process_frame
	check(RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "保存和恢复狼人技能配置")
	check(RunManager.deck[1].get_description().contains("最大生命最低") and RunManager.deck[1].get_summon_data().skills.any(func(skill: SkillBase): return skill.is_passive()), "继续存档后保留扑击与隐身效果")
	await _monster_test(source, passive)
	print("WERE_WOLF_SKILLS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _monster_test(source: UnitData, passive: SkillBase) -> void:
	var scene = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var wolf := scene.spawn_unit(load("res://scenes/units/were_wolf.tscn"), "team_a") as UnitBase
	var enemy := scene.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b") as UnitBase
	wolf.set_physics_process(false)
	enemy.set_physics_process(false)
	@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
	wolf.take_effect_damage(wolf.unit_data.max_hp * 3 / 4)
	check(wolf.is_stealthed and enemy.skill_manager.find_nearest_enemy() == null, "独立怪物测试场也能验证隐身")
	var custom_passive := passive.duplicate(true) as SkillBase
	custom_passive.stealth_health_percent = 40.0
	custom_passive.stealth_duration = 0.2
	var data := source.duplicate() as UnitData
	data.skills.assign([source.skills[0], source.skills[1], custom_passive])
	var custom := load("res://scenes/units/were_wolf.tscn").instantiate() as UnitBase
	custom.unit_data = data
	wolf.get_parent().add_child(custom)
	custom.set_physics_process(false)
	custom.current_health = 45
	await _settle()
	check(not custom.is_stealthed, "技能配置的40%阈值生效")
	custom.take_effect_damage(10)
	check(custom.is_stealthed and CardInstance.new(data).get_description().contains("隐身0.2秒"), "自定义时长同步到战斗和卡牌说明")
	for frame in 18:
		await get_tree().physics_frame
	check(not custom.is_stealthed and passive.stealth_duration == 5.0, "自定义时长到期且不污染原技能")
	scene.queue_free()
	await get_tree().process_frame
