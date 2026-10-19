# 真实战场验证命中扣血、动画完成推进、暂停、致命伤害及切场取消。
extends Node

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _clean() -> void:
	var data := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	data.starting_relics.clear()
	data.starting_potions.clear()
	RunManager.start_new_run(data)

func _battle(hp: int = 45, parent: Node = null) -> Node2D:
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.enemy_max_hp = hp
	battle.configure_level(config)
	(parent if parent != null else get_tree().root).add_child(battle)
	return battle

func _unit(battle: Node2D, ally: bool, damage: int, point: Vector2) -> void:
	var unit: UnitBase = load("res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn").instantiate()
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.hp_damage_value = damage
	battle.get_node("Entities/TeamA" if ally else "Entities/TeamB").add_child(unit)
	unit.global_position = point
	unit.set_physics_process(false)

func _dispose(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.queue_free()
	await get_tree().process_frame

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func _settled(battle: Node2D) -> void:
	if battle.round_damage_effect.playing:
		await battle.battle_round_manager.settlement_finished
	await get_tree().process_frame

func _run() -> void:
	_clean()
	if "--round-damage-preview" in OS.get_cmdline_user_args():
		await _capture()
		get_tree().quit()
		return
	var battle := _battle()
	var rounds: BattleRoundManager = battle.battle_round_manager
	for index in 3:
		_unit(battle, true, index + 1, Vector2(610 + index * 170, 540))
	var count: Array[int] = [0]
	rounds.round_settled.connect(func(_r, _d, _b, _u): count[0] += 1)
	rounds.start_auto_battle()
	rounds.finish_unit_combat()
	rounds.finish_unit_combat()
	assert(rounds.battle_state == BattleRoundManager.BattleState.DAMAGE_SETTLEMENT)
	assert(rounds.current_round == 1 and rounds.enemy_hp == 45 and rounds.round_damage == 7)
	assert(battle.round_damage_effect.playing and battle.get_alive_units(&"team_a").size() == 3)
	assert(battle.card_ui.get_node("ButtonPanel/AutoBattle").disabled)
	var hand_before: int = battle.hand_manager.hand.size()
	var energy_before := rounds.current_energy
	rounds.start_auto_battle()
	rounds._start_next_round()
	rounds._start_card_phase()
	rounds.request_round_check()
	assert(not rounds.try_spend_energy(0))
	await _frames(15)
	assert(rounds.enemy_hp == 45 and rounds.current_round == 1 and count[0] == 0)
	assert(battle.hand_manager.hand.size() == hand_before and rounds.current_energy == energy_before)
	var elapsed_before: float = battle.round_damage_effect.elapsed
	get_tree().paused = true
	await _frames(15)
	assert(is_equal_approx(battle.round_damage_effect.elapsed, elapsed_before))
	assert(rounds.enemy_hp == 45 and rounds.current_round == 1)
	get_tree().paused = false
	await _settled(battle)
	assert(rounds.current_round == 2 and rounds.enemy_hp == 38 and rounds.current_energy == 4 and count[0] == 1)
	assert(battle.get_alive_units(&"team_a").is_empty() and not battle.round_damage_effect.visible)
	assert(battle.card_ui.enemy_health_bar.value == 38 and battle.card_ui.enemy_health_value.text == "38 / 45")
	await _dispose(battle)
	# 玩家扣血使用常驻 HUD 的真实控件。
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(session)
	session.map_layer.hide()
	battle = _battle(45, session.content_root)
	session.current_battle = battle
	rounds = battle.battle_round_manager
	RunManager.hp = 20
	_unit(battle, false, 2, Vector2(1120, 540))
	rounds.current_round = 5
	rounds.start_auto_battle()
	rounds.finish_unit_combat()
	assert(battle.round_damage_effect.target_control == session.get_node("HUDLayer/RunHUD/BisicUI/Hp"))
	await _frames(15)
	assert(RunManager.hp == 20 and rounds.current_round == 5)
	# 查看地图时特效隐藏，返回后继续播放。
	session._set_battle_map_visible(true)
	assert(not battle.round_damage_layer.visible and get_tree().paused)
	await _frames(12)
	assert(RunManager.hp == 20)
	session._set_battle_map_visible(false)
	assert(battle.round_damage_layer.visible and not get_tree().paused)
	await _settled(battle)
	assert(RunManager.hp == 13 and rounds.current_round == 6)
	assert(session.get_node("HUDLayer/RunHUD/BisicUI/Hp/Hp").text == "13/80")
	await _dispose(session)
	for won in [true, false]:
		_clean()
		RunManager.hp = 80 if won else 1
		battle = _battle(1 if won else 45)
		rounds = battle.battle_round_manager
		_unit(battle, won, 3, Vector2(860, 560))
		rounds.start_auto_battle()
		rounds.finish_unit_combat()
		while battle.round_damage_effect.applied_damage < battle.round_damage_effect.total_damage:
			await get_tree().physics_frame
		assert(rounds.enemy_hp == 0 if won else RunManager.hp == 0)
		assert(not battle.battle_finished and not battle.get_node("GameOver").visible)
		assert(rounds.current_round == 1 and battle.round_damage_effect.playing)
		await _settled(battle)
		assert(battle.battle_finished and battle.get_node("GameOver").visible and rounds.current_round == 1)
		assert(rounds.battle_state == (BattleRoundManager.BattleState.VICTORY if won else BattleRoundManager.BattleState.DEFEAT))
		await _dispose(battle)
	_clean()
	battle = _battle()
	rounds = battle.battle_round_manager
	rounds.start_auto_battle()
	rounds.finish_unit_combat()
	assert(rounds.current_round == 1 and battle.round_damage_effect.playing and rounds.round_damage == 0)
	await _settled(battle)
	assert(rounds.current_round == 2 and rounds.enemy_hp == 45 and RunManager.hp == 80)
	await _dispose(battle)
	battle = _battle()
	rounds = battle.battle_round_manager
	_unit(battle, true, 3, Vector2(750, 520))
	rounds.start_auto_battle()
	rounds.finish_unit_combat()
	battle.finish_battle(false)
	assert(not battle.round_damage_effect.playing)
	await _frames(130)
	assert(rounds.current_round == 1 and rounds.enemy_hp == 45)
	await _dispose(battle)
	battle = _battle()
	_unit(battle, false, 20, Vector2(1100, 520))
	battle.battle_round_manager.start_auto_battle()
	battle.battle_round_manager.finish_unit_combat()
	await _dispose(battle)
	await _frames(130)
	assert(RunManager.hp == 80)
	print("ROUND_DAMAGE_EFFECT_PASS: impact HP, completion gate, HUD, pause, lethal, draw, duplicates, exit")
	get_tree().quit()

func _capture() -> void:
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(session)
	session.map_layer.hide()
	for won in [true, false]:
		var battle := _battle(45, session.content_root)
		session.current_battle = battle
		battle.battle_round_manager.current_round = 3
		for index in 5:
			_unit(battle, won, 1 + index % 3, Vector2(650 + index * 140, 500 + index % 2 * 100))
		battle.battle_round_manager.start_auto_battle()
		battle.battle_round_manager.finish_unit_combat()
		for stage in ["flight", "impact"]:
			if stage == "flight":
				while battle.round_damage_effect.elapsed < 0.65:
					await get_tree().process_frame
			else:
				while battle.round_damage_effect.applied_damage < battle.round_damage_effect.total_damage:
					await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var filename := "res://.maintenance/round-damage-%s-%s.png" % ["win" if won else "loss", stage]
			assert(get_viewport().get_texture().get_image().save_png(filename) == OK)
			print("ROUND_DAMAGE_PREVIEW: " + filename)
		await _settled(battle)
		await _dispose(battle)
	await _dispose(session)
