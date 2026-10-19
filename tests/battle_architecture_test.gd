# 这玩意儿是干嘛的（核心逻辑）：用真实战场验证多回合扣血、清场与提前刷新敌阵，以及生命和能量规则。
# 数据是咋流动的（数据流向）：测试配置 → 正式单位与卡牌 → 回合结算、清场和敌阵刷新 → 检查 HP、牌堆、UI 与待机动画推进。
# 为啥这么写（选型决策）：复用正式入口，不另写模拟规则；待机既要检查不移动，也要确认动画真的在播放。
# 性能咋样（复杂度）：只在手动运行测试时加载，小规模单位可在数秒内完成检查。
extends Node

var settlements := 0

# 作用：隔离策划配置中的开局赠品，避免抽牌赠能量干扰基础回合断言；没有参数，没有返回值。
func _start_clean_run() -> void:
	var start_data := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	start_data.starting_relics.clear()
	start_data.starting_potions.clear()
	RunManager.start_new_run(start_data)


# 作用：Godot 入树后启动验收并设置失败超时；没有参数，没有返回值。
func _ready() -> void:
	get_tree().create_timer(55.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

# 作用：创建真实战场；enemy_hp 为敌方生命，waves 为准备时刷出的阵型（默认空），返回场景。
func _battle(enemy_hp: int = 45, waves: Array[PackedScene] = []) -> Node2D:
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.enemy_max_hp = enemy_hp
	config.waves = waves
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	battle.battle_round_manager.round_settled.connect(_count_settlement)
	assert(battle.get_node_or_null("Entities/PlayerBase") == null)
	assert(battle.battle_round_manager.enemy_hp == enemy_hp)
	return battle

# 作用：统计真实回合结算通知；四个参数为胜方与伤害分项，没有返回值。
func _count_settlement(_result: StringName, _damage: int, _base: int, _units: int) -> void:
	settlements += 1

# 作用：生成静止正式单位；battle 为场景，ally 为阵营，damage 为结算值，返回单位。
func _unit(battle: Node2D, ally: bool, damage: int) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn").instantiate()
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.hp_damage_value = damage
	battle.get_node("Entities/TeamA" if ally else "Entities/TeamB").add_child(unit)
	unit.set_physics_process(false)
	return unit

# 作用：移走旧场景并等待退出完成；battle 为待清理场景，没有返回值。
func _dispose(battle: Node2D) -> void:
	get_tree().root.remove_child(battle)
	battle.queue_free()
	await get_tree().process_frame

# 作用：运行设计文档的 HP 与能量验收及事件边界；没有参数，没有返回值。
func _run() -> void:
	if "--capture-battle" in OS.get_cmdline_user_args():
		await _capture_preview()
		get_tree().quit()
		return
	_start_clean_run()
	var battle := _battle()
	var rounds: BattleRoundManager = battle.battle_round_manager
	var soldier := _unit(battle, true, 1)
	var enemy := _unit(battle, false, 1)
	# 两队仍活着时，旧计时到期不能结算或推进回合。
	rounds.start_auto_battle()
	rounds._on_battle_timer_timeout()
	await get_tree().process_frame
	assert(rounds.current_round == 1 and rounds.battle_state == BattleRoundManager.BattleState.COMBAT)
	# Round 1 士兵存活：1+1=2；死亡动画尚未结束也应立刻结算一次。
	enemy.take_effect_damage(9999)
	assert(enemy.current_state == UnitBase.State.DEATH)
	rounds.request_round_check()
	await get_tree().process_frame
	assert(rounds.current_round == 1 and rounds.enemy_hp == 45)
	await rounds.settlement_finished
	await get_tree().process_frame
	assert(rounds.enemy_hp == 43 and rounds.round_damage == 2 and settlements == 1)
	assert(battle.card_ui.enemy_health_bar.value == 43 and battle.card_ui.enemy_health_bar.max_value == 45)
	assert(battle.card_ui.enemy_health_value.text == "43 / 45")
	assert(rounds.current_round == 2 and rounds.current_energy == 4)
	assert(not battle.battle_finished and battle.get_alive_units(&"team_a").is_empty())
	assert(not is_instance_valid(soldier) or soldier.is_queued_for_deletion())
	# 正式集合排除特效、尸体、零血量、待删除对象，每轮幸存者同样清掉，需要重新部署。
	var decoration := Node2D.new()
	battle.get_node("Entities/TeamB").add_child(decoration)
	var doomed := _unit(battle, false, 50)
	doomed.queue_free()
	var zero_hp := _unit(battle, false, 50)
	zero_hp.current_health = 0
	assert(battle.get_alive_units(&"team_b").is_empty())
	# Round 3：1+3+3=7；重复结算请求不能再次扣血。
	rounds.current_round = 3
	_unit(battle, true, 1)
	_unit(battle, true, 3)
	rounds.start_auto_battle()
	rounds.finish_unit_combat()
	rounds.finish_unit_combat()
	assert(rounds.battle_state == BattleRoundManager.BattleState.DAMAGE_SETTLEMENT)
	await rounds.settlement_finished
	assert(rounds.enemy_hp == 36 and rounds.round_damage == 7 and settlements == 2)
	assert(rounds.round_damage_from_round == 3 and rounds.round_damage_from_units == 4)
	await get_tree().process_frame
	await _dispose(battle)

	# Round 5 敌方两单位：5+1+2=8，玩家仅有一份 Run HP。
	RunManager.hp = 80
	battle = _battle()
	rounds = battle.battle_round_manager
	rounds.current_round = 5
	_unit(battle, false, 1)
	_unit(battle, false, 2)
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(RunManager.hp == 72 and rounds.player_hp == 72 and rounds.round_damage == 8)
	await get_tree().process_frame
	await _dispose(battle)

	# 同帧两边最后一兵死亡是平局，两种死亡顺序均不得扣 HP。
	for reverse in [false, true]:
		battle = _battle()
		rounds = battle.battle_round_manager
		var round_ally := _unit(battle, true, 1)
		var round_foe := _unit(battle, false, 2)
		var hp_before := RunManager.hp
		var count_before := settlements
		rounds.start_auto_battle()
		(round_foe if reverse else round_ally).take_effect_damage(9999)
		(round_ally if reverse else round_foe).take_effect_damage(9999)
		await get_tree().process_frame
		if rounds.is_round_settling:
			await rounds.settlement_finished
		await get_tree().process_frame
		assert(rounds.last_round_result == &"draw" and rounds.round_damage == 0)
		assert(RunManager.hp == hp_before and rounds.enemy_hp == 45)
		assert(rounds.current_round == 2 and settlements == count_before + 1)
		await _dispose(battle)

	# 死亡爆炸和回合末毒均需在决定赢家之前完成。
	battle = _battle()
	rounds = battle.battle_round_manager
	var ally := _unit(battle, true, 1)
	var foe := _unit(battle, false, 1)
	var explosion := CardEffect.new()
	explosion.kind = CardEffect.Kind.DEATH_EXPLOSION
	explosion.amount = 9999
	explosion.radius = 9999
	battle.card_runtime._add_buff(ally, explosion, "测试爆炸")
	rounds.start_auto_battle()
	ally.take_effect_damage(9999)
	await get_tree().process_frame
	assert(rounds.last_round_result == &"draw" and rounds.enemy_hp == 45)
	await _dispose(battle)
	battle = _battle()
	rounds = battle.battle_round_manager
	ally = _unit(battle, true, 1)
	battle.card_runtime.states[ally.get_instance_id()].poison = 9999
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(rounds.last_round_result == &"draw" and rounds.enemy_hp == 45)
	await _dispose(battle)

	# 敌 HP 5 受到7，归零胜利；延后推进、旧伤害、抽能量与生成均失效。
	battle = _battle(5)
	rounds = battle.battle_round_manager
	rounds.current_round = 3
	ally = _unit(battle, true, 1)
	_unit(battle, true, 3)
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(rounds.enemy_hp == 0 and battle.battle_finished)
	assert(battle.card_ui.enemy_health_bar.value == 0 and battle.card_ui.enemy_health_value.text == "0 / 5")
	assert(rounds.battle_state == BattleRoundManager.BattleState.VICTORY)
	var health_before: int = ally.current_health
	var energy_before := rounds.current_energy
	rounds.gain_energy(10)
	assert(not rounds.try_spend_energy(0))
	ally.take_effect_damage(9999)
	assert(not ally.get_hurt(9999) and ally.current_health == health_before)
	rounds._start_next_round()
	await rounds.finish_unit_combat()
	assert(rounds.current_round == 3 and rounds.current_energy == energy_before)
	var stale_cost := CardEffect.new()
	stale_cost.kind = CardEffect.Kind.PAY_HP
	stale_cost.amount = 99
	var run_hp_before := RunManager.hp
	battle.card_runtime.apply_effect(stale_cost, {"target": null})
	assert(RunManager.hp == run_hp_before)
	var late := _unit(battle, false, 1)
	assert(late.is_queued_for_deletion())
	await _dispose(battle)

	# 玩家 HP 4 受到8，钳制为0并进入现有失败流程。
	RunManager.hp = 4
	battle = _battle()
	rounds = battle.battle_round_manager
	rounds.current_round = 5
	_unit(battle, false, 1)
	_unit(battle, false, 2)
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(RunManager.hp == 0 and battle.battle_finished)
	assert(rounds.battle_state == BattleRoundManager.BattleState.DEFEAT)
	await _dispose(battle)

	# 跨节点保留63 HP；敌方每场读取独立配置并回满。
	_start_clean_run()
	RunManager.hp = 63
	battle = _battle(45)
	battle.battle_round_manager.enemy_hp = 0
	battle.finish_battle(true)
	await _dispose(battle)
	battle = _battle(70)
	rounds = battle.battle_round_manager
	assert(RunManager.hp == 63 and rounds.enemy_hp == 70)
	# 玩家 HP 仍由顶部栏统一显示；新战斗名称和敌方血条读取独立关卡配置。
	assert(not battle.card_ui.has_node("BisicUI/PlayerHealth"))
	assert(battle.card_ui.battle_name_label.text == battle.level_config.level_name)
	assert(battle.card_ui.enemy_health_bar.max_value == 70 and battle.card_ui.enemy_health_bar.value == 70)
	assert(battle.card_ui.enemy_health_value.text == "70 / 70")
	battle.level_config.level_name = "翠绿原野"
	battle._refresh_battle_health()
	assert(battle.card_ui.battle_name_label.text == "翠绿原野")
	# Round 1~10及20基础能量；+2永远不被10点上限截断。
	for round_number in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20]:
		rounds.current_round = round_number
		rounds._start_card_phase()
		assert(rounds.base_energy_max == mini(round_number + 2, 10))
		assert(rounds.current_energy == rounds.final_energy_max)
	rounds.add_energy_modifier(&"relic", 2)
	for round_number in [1, 8, 20]:
		rounds.current_round = round_number
		rounds._start_card_phase()
		assert(rounds.final_energy_max == mini(round_number + 2, 10) + 2)
	# 首轮额外、每三轮额外、下一轮减能量，四类修正可独立组合。
	rounds.add_energy_modifier(&"relic", 2, 1, 1)
	rounds.add_energy_modifier(&"status", 1, 1, 0, 3)
	rounds.add_energy_modifier(&"card", -1, 2, 2)
	for round_number in [1, 2, 3]:
		rounds.current_round = round_number
		rounds._start_card_phase()
		assert(rounds.final_energy_max == {1: 7, 2: 5, 3: 8}[round_number])
	rounds.energy_modifiers.clear()
	rounds.current_round = 1
	rounds.pending_recurring_energy = 1
	rounds._start_card_phase()
	assert(rounds.current_energy == 4 and rounds.recurring_energy == 1)
	rounds.gain_energy(3)
	assert(rounds.current_energy == 7 and rounds.final_energy_max == 4)
	var energy_relic := RelicDefinition.new()
	energy_relic.id = &"test_max_energy"
	energy_relic.kind = RelicDefinition.Kind.MAX_ENERGY
	energy_relic.amount = 2
	assert(RunManager.add_relic(energy_relic))
	assert(rounds.final_energy_max == 6 and rounds.current_energy == 7)
	await _dispose(battle)
	battle = _battle()
	assert(battle.battle_round_manager.current_energy == 5)
	await _dispose(battle)
	# 自定义开局生命配置也必须继承，防止隐含的 80 点硬编码回满。
	var custom_run := RunStartData.new()
	custom_run.max_hp = 103
	custom_run.starting_hp = 37
	RunManager.start_new_run(custom_run)
	battle = _battle()
	assert(RunManager.hp == 37 and battle.battle_round_manager.player_max_hp == 103)
	await _dispose(battle)

	# 有限阵型耗尽后仍刷最后有效阵型，空项仍是休整轮。
	battle = _battle()
	var spawner = battle.get_node("Entities/TeamB")
	spawner.level_data.assign([load("res://scenes/levels/waves/wave_01.tscn"), null])
	spawner.repeat_waves = false
	spawner._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 2)
	assert(battle.get_alive_units(&"team_b").is_empty())
	spawner._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 3)
	assert(not battle.get_alive_units(&"team_b").is_empty())
	await _dispose(battle)

	# 实际动画、索敌和普通攻击连打两轮；第一轮清场不会直接结束敌方节点。
	_start_clean_run()
	battle = _battle(5)
	rounds = battle.battle_round_manager
	ally = _unit(battle, true, 1)
	ally.global_position = Vector2(600, 500)
	ally.unit_data.attack = 9999
	ally.current_health = 99999
	ally.set_physics_process(true)
	foe = _unit(battle, false, 1)
	foe.global_position = Vector2(630, 500)
	foe.set_physics_process(true)
	rounds.start_auto_battle()
	for frame in 300:
		await get_tree().physics_frame
		if rounds.current_round == 2:
			break
	assert(rounds.current_round == 2 and rounds.enemy_hp == 3 and not battle.battle_finished)
	# 第一轮胜者已经退场；第二轮重新部署强力士兵，不能再沿用旧实例。
	assert(battle.get_alive_units(&"team_a").is_empty())
	ally = _unit(battle, true, 1)
	ally.global_position = Vector2(600, 500)
	ally.unit_data.attack = 9999
	ally.current_health = 99999
	ally.set_physics_process(true)
	foe = _unit(battle, false, 1)
	foe.global_position = ally.global_position + Vector2(30, 0)
	foe.set_physics_process(true)
	rounds.start_auto_battle()
	for frame in 300:
		await get_tree().physics_frame
		if battle.battle_finished:
			break
	assert(battle.battle_finished and rounds.enemy_hp == 0 and rounds.last_round_result == &"player")
	assert(battle.get_node("Entities/TeamA").get_child_count() == 0)
	assert(battle.get_node("Entities/TeamB").get_child_count() == 0)
	await _dispose(battle)
	await _test_round_cleanup_and_preview()
	print("BATTLE_ARCHITECTURE_PASS: HP, draw, damage, persistence, energy, waves, cleanup, preview, stale events")
	get_tree().quit()


# 作用：检查胜败后双方清场、原牌回收和下一轮敌阵提前待机；没有参数，没有返回值。
func _test_round_cleanup_and_preview() -> void:
	_start_clean_run()
	var recruit := CardInstance.new(load("res://data/units/soldier.tres"))
	var permanent := CardEffect.new()
	permanent.kind = CardEffect.Kind.ATTACK_UP
	permanent.amount = 5
	permanent.lifetime = CardEffect.Lifetime.RUN
	recruit.permanent_buffs.append({"effect": permanent, "label": "测试永久强化"})
	# 单牌牌组要求清场的原牌在下一轮抽牌之前回收，否则玩家下一轮将无牌可部署。
	RunManager.deck.assign([recruit])
	var battle := _battle(45, [load("res://scenes/levels/waves/wave_01.tscn")])
	var rounds: BattleRoundManager = battle.battle_round_manager
	var hand = battle.hand_manager
	var team = battle.get_node("Entities/TeamB")
	assert(rounds.battle_state == BattleRoundManager.BattleState.PLAYER_PHASE and team.get_child_count() == 5)
	assert(battle.card_runtime.try_play(recruit, Vector2(450, 500)))
	var ally: UnitBase = battle.get_alive_units(&"team_a")[0]
	ally.set_physics_process(false)
	var copied := _unit(battle, true, 1)
	var deaths: Array[int] = [0]
	ally.unit_died.connect(func(_subject): deaths[0] += 1)
	copied.unit_died.connect(func(_subject): deaths[0] += 1)
	# 给幸存者附加死亡爆炸，清场也不得触发死亡信号和伤亡光环。
	var explosion := CardEffect.new()
	explosion.kind = CardEffect.Kind.DEATH_EXPLOSION
	explosion.amount = 9999
	explosion.radius = 9999
	battle.card_runtime._add_buff(ally, explosion, "清场不爆炸")
	var original_ids: Array[int] = []
	var positions: Array[Vector2] = []
	for enemy: UnitBase in battle.get_alive_units(&"team_b"):
		original_ids.append(enemy.get_instance_id())
		positions.append(enemy.position)
		# 验证准备期间静止时使用真实物理处理；交锋验收阶段再停住，避免随机攻击影响结果。
		assert(enemy.current_state == UnitBase.State.IDLE)
		assert(enemy.current_health == enemy.unit_data.max_hp)
	await _assert_idle_preview(battle.get_alive_units(&"team_b"))
	rounds.start_auto_battle()
	for enemy: UnitBase in battle.get_alive_units(&"team_b"):
		enemy.set_physics_process(false)
		enemy.take_effect_damage(9999)
	await rounds.finish_unit_combat()
	assert(rounds.round_damage == 3 and rounds.enemy_hp == 42)
	assert(battle.get_node("Entities/TeamA").get_child_count() == 0 and team.get_child_count() == 0)
	assert(hand.board_cards.is_empty() and hand.discard_pile.count(recruit) == 1)
	assert(battle.card_runtime.states.is_empty() and deaths[0] == 0 and battle.card_runtime.ally_deaths == 0)

	# 新敌阵在开打前已经可见，并且恢复配置阵型和满血；重复阶段通知不能叠出第二份。
	await get_tree().process_frame
	assert(rounds.current_round == 2 and Global.game_phase == Global.GamePhase.CARD_PLAY)
	assert(hand.hand.size() == 1 and hand.hand[0] == recruit and hand.board_cards.is_empty())
	assert(recruit.permanent_buffs.size() == 1)
	team._on_battle_round_manager_phase_changed(Global.GamePhase.CARD_PLAY, 2)
	assert(team.get_child_count() == positions.size())
	for i in positions.size():
		var enemy: UnitBase = team.get_child(i)
		assert(enemy.get_instance_id() not in original_ids and enemy.position == positions[i])
		assert(enemy.current_health == enemy.unit_data.max_hp)
	for frame in 3:
		await get_tree().physics_frame
	for i in positions.size():
		var enemy: UnitBase = team.get_child(i)
		assert(enemy.position == positions[i] and enemy.current_state == UnitBase.State.IDLE)
	await _assert_idle_preview(battle.get_alive_units(&"team_b"))
	# 重新征召同一张牌，临时爆炸清掉而永久攻击加成仍然保留；随后正常死亡只弃置一次。
	assert(battle.card_runtime.try_play(recruit, Vector2(450, 500)))
	ally = battle.get_alive_units(&"team_a")[0]
	assert(ally.unit_data.attack == recruit.unit_data.attack + 5)
	assert(battle.card_runtime.states[ally.get_instance_id()].explosions.is_empty())
	ally.take_effect_damage(9999)
	var hp_before := RunManager.hp
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(rounds.last_round_result == &"enemy" and RunManager.hp == hp_before - rounds.round_damage)
	assert(team.get_child_count() == 0 and battle.get_node("Entities/TeamA").get_child_count() == 0)
	assert(hand.board_cards.is_empty() and hand.discard_pile.count(recruit) == 1)
	await get_tree().process_frame
	assert(rounds.current_round == 3 and team.get_child_count() == positions.size())
	assert(hand.hand.size() == 1 and hand.hand[0] == recruit)
	await _assert_idle_preview(battle.get_alive_units(&"team_b"))
	await _dispose(battle)
	print("ROUND_CLEANUP_PREVIEW_PASS: both teams, cards, permanent buffs, no cleanup deaths, idle preview")


# 作用：验证准备阶段敌阵原地播放待机动画；enemies 为本轮活敌人，没有返回值。
func _assert_idle_preview(enemies: Array[UnitBase]) -> void:
	assert(not enemies.is_empty() and Global.game_phase == Global.GamePhase.CARD_PLAY)
	var positions: Array[Vector2] = []
	var animation_times: Array[float] = []
	# IDLE 状态和静态帧都不能证明正在播放，记录帧内进度才能发现动画资源替换后停播。
	for enemy in enemies:
		var sprite := enemy.animated_sprite_2d
		assert(sprite.animation == &"idle" and sprite.is_playing())
		positions.append(enemy.position)
		animation_times.append(float(sprite.frame) + sprite.frame_progress)
	# 等待四分之一秒，足够让当前兽人的待机动画推进，且尚未完成一个循环。
	for frame in 15:
		await get_tree().physics_frame
	for i in enemies.size():
		var enemy := enemies[i]
		var sprite := enemy.animated_sprite_2d
		assert(enemy.position == positions[i] and enemy.current_state == UnitBase.State.IDLE)
		assert(sprite.animation == &"idle" and sprite.is_playing())
		assert(not is_equal_approx(float(sprite.frame) + sprite.frame_progress, animation_times[i]))


# 作用：用真实渲染生成战斗 UI 校验截图；没有参数，没有返回值，仅 --capture-battle 时执行。
func _capture_preview() -> void:
	_start_clean_run()
	RunManager.hp = 63
	var battle := _battle()
	var rounds: BattleRoundManager = battle.battle_round_manager
	rounds.current_round = 3
	battle.hand_manager.discard_unused_card()
	rounds._start_card_phase()
	var ally := _unit(battle, true, 1)
	ally.global_position = Vector2(550, 480)
	var enemy := _unit(battle, false, 2)
	enemy.global_position = Vector2(1250, 480)
	battle._show_round_damage(&"player", 7, 3, 4)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://.maintenance/battle_architecture_preview.png")
	assert(result == OK)
	print("BATTLE_PREVIEW_SAVED")
	await _dispose(battle)
