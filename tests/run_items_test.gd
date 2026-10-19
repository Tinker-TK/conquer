# 这玩意儿是干嘛的（核心逻辑）：验证遗物跨回合、跨战斗，以及三种药水的消耗与伤害。
# 数据是咋流动的（数据流向）：真实配置 → 真实战场钩子 → 检查血量、护甲、抽牌和库存。
# 为啥这么写（选型决策）：使用游戏里的入口，不用另一套模拟规则代替实际效果。
# 性能咋样（复杂度）：仅手动测试，正常游戏不会加载。
extends Node


# 作用：Godot 初始化后启动测试；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：执行遗物与药水回归；没有参数，没有返回值。
func _run() -> void:
	# 单独检查获得/清空物品，隔离可配置的开局赠送物品。
	var initial = load("res://data/run/run_start_data.tres").duplicate(true)
	initial.starting_relics.clear()
	initial.starting_potions.clear()
	RunManager.start_new_run(initial)
	for resource_name in ["draw_engine", "base_heart", "opening_armour"]:
		assert(RunManager.add_relic(load("res://data/relics/%s.tres" % resource_name)))
	assert(not RunManager.add_relic(load("res://data/relics/base_heart.tres")))
	assert(RunManager.max_hp == 100 and RunManager.base_defence == 0)
	assert(not RunManager.add_relic(load("res://data/relics/base_armour.tres")))
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	var items = battle.get_node("BattleItems")
	var hand = battle.hand_manager
	var rounds = battle.battle_round_manager
	assert(battle.get_node_or_null("Entities/PlayerBase") == null)
	assert(RunManager.hp == 100)
	RunManager.relic_draw_counts[&"draw_engine"] = 9
	var before_energy: int = rounds.current_energy
	hand.draw_cards(1)
	assert(rounds.current_energy == before_energy + 1)
	assert(RunManager.relic_draw_counts[&"draw_engine"] == 0)
	hand.draw_locked = true
	hand.draw_cards(10)
	assert(RunManager.relic_draw_counts[&"draw_engine"] == 0)
	hand.draw_locked = false
	var ally: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	battle.get_node("Entities/TeamA").add_child(ally)
	ally.position = Vector2(400, 450)
	ally.set_physics_process(false)
	var defence: int = ally.unit_data.defence
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	assert(ally.unit_data.defence == defence + 2)
	battle.card_runtime._tick_buffs()
	battle.card_runtime._tick_buffs()
	assert(ally.unit_data.defence == defence + 2)
	battle.card_runtime._tick_buffs()
	assert(ally.unit_data.defence == defence)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	assert(ally.unit_data.defence == defence, "不能每轮重复加开局护甲")
	RunManager.hp -= 8
	assert(RunManager.hp == 92)
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	for unit in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	enemy.global_position = Vector2(800, 500)
	enemy.current_health = 1000
	for resource_name in ["tornado", "lightning", "fire"]:
		RunManager.add_potion(load("res://data/potions/%s.tres" % resource_name))
	# 选中后取消不消耗；同种药水再次奖励必须是一瓶独立实例。
	assert(items.select_potion(RunManager.potions[0]))
	items.clear_effect()
	assert(RunManager.potions.size() == 3)
	var lightning: PotionDefinition = RunManager.potions[1]
	assert(items.select_potion(lightning))
	assert(not items.try_cast(Vector2(-999, -999)) and RunManager.potions.size() == 3)
	for index in 4:
		assert(items.try_cast(enemy.global_position))
		assert(not items.try_cast(enemy.global_position), "连续快速点击不能跳过间隔")
		assert(not items.select_potion(RunManager.potions[0]), "上一瓶没完成不能用下一瓶")
		items._physics_process(0.41)
	assert(items.potion == null and RunManager.potions.size() == 2)
	assert(enemy.current_health == 920)
	assert(items.select_potion(RunManager.potions[0]))
	assert(items.try_cast(enemy.global_position))
	var tornado_start: Vector2 = items.effect_position
	items._physics_process(0.1)
	assert(items.effect_position.distance_to(tornado_start) > 0.0)
	assert(not items.select_potion(RunManager.potions[0]))
	items._physics_process(6.0)
	assert(items.potion == null)
	assert(items.select_potion(RunManager.potions[0]))
	assert(items.try_cast(enemy.global_position))
	var fire_hp: int = enemy.current_health
	items._physics_process(0.5)
	assert(enemy.current_health == fire_hp - 6)
	get_tree().paused = true
	items._physics_process(2.0)
	assert(enemy.current_health == fire_hp - 6)
	get_tree().paused = false
	Global.game_phase = Global.GamePhase.CARD_PLAY
	assert(items.potion == null and RunManager.potions.is_empty())
	assert(not items.select_potion(lightning))
	RunManager.add_potion(load("res://data/potions/lightning.tres"))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	assert(items.select_potion(RunManager.potions[0]))
	assert(items.try_cast(enemy.global_position))
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	assert(items.potion == null and RunManager.potions.is_empty(), "回合末剩余闪电次数作废")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	# 跨关卡保留计数和遗物，新关卡开局抽5张使8累计为13，剩3。
	RunManager.relic_draw_counts[&"draw_engine"] = 8
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	assert(not is_instance_valid(RunManager.item_battle))
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	assert(RunManager.relic_draw_counts[&"draw_engine"] == 3)
	assert(RunManager.max_hp == 100 and RunManager.hp == 92 and RunManager.base_defence == 0)
	assert(battle.battle_round_manager.current_energy == 4)
	assert(RunManager.potions.is_empty())
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	RunManager.start_new_run(initial)
	assert(RunManager.relics.is_empty() and RunManager.relic_draw_counts.is_empty())
	assert(RunManager.max_hp == 80 and RunManager.base_defence == 0)
	print("RUN_ITEMS_PASS")
	get_tree().quit()

