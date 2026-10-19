# 这玩意儿是干嘛的（核心逻辑）：每轮交锋结算后清空双方单位，下一轮提前摆出敌阵供玩家准备。
# 数据是咋流动的（数据流向）：配置和 Run 血量 → 部署与交锋 → 存活单位扣血 → 清场 → 下一轮敌阵或胜负。
# 为啥这么写（选型决策）：先算幸存单位伤害再清场，复用阶段信号刷新敌阵；状态锁避免重复扣血。
# 性能咋样（复杂度）：只在死亡和阶段切换时遍历已登记单位，不逐帧扫描场景。
extends Node
class_name BattleRoundManager

enum BattleState { PREPARING, PLAYER_PHASE, COMBAT, ROUND_END, DAMAGE_SETTLEMENT, NEXT_ROUND, VICTORY, DEFEAT }
var battle_state: BattleState = BattleState.PREPARING
var battle: Node2D
var current_round: int = 0
var first_round: int = 1
# 旧配置字段保留为首轮基础能量；最终上限使用 final_energy_max。
## 第 1 回合的基础能量值，保留旧字段名称；每轮按 Max Energy + (回合数 - 1) × Energy Growth 增长，受 Base Energy Cap 限制，再加上本局永久附加能量。关卡配置会覆盖此值。
@export var max_energy: int = BattleLevelConfig.BASE_START_ENERGY
## 每推进 1 回合增加的基础能量，0 表示不增长；达到 Base Energy Cap 后停止增长。关卡的 Energy Growth 可覆盖此值。
@export var energy_growth: int = BattleLevelConfig.ENERGY_PER_ROUND
## 基础能量随回合增长的上限；应不低于首轮基础能量。本局永久附加能量不受此上限限制，关卡配置可覆盖此值。
@export var base_energy_cap: int = BattleLevelConfig.BASE_MAX_ENERGY
var base_energy_max: int = 0
var bonus_energy_max: int = 0
var final_energy_max: int = 0
var current_energy: int = 0
var recurring_energy: int = 0
var pending_recurring_energy: int = 0
var energy_modifiers: Dictionary = {}
var enemy_max_hp: int = BattleLevelConfig.DEFAULT_ENEMY_MAX_HP
var enemy_hp: int = 0
# 读取全局同一份 HP，不建立第二份长期生命值。
var player_hp: int:
	get: return RunManager.hp
var player_max_hp: int:
	get: return RunManager.max_hp
var round_damage: int = 0
var round_damage_from_round: int = 0
var round_damage_from_units: int = 0
var last_round_result: StringName = &"draw"
var is_round_settling := false
var _check_scheduled := false
var _settlement_generation := 0
var _damage_applied := 0
# 兼容旧工具读取；计时器不再控制回合结束。
## 兼容旧工具的交锋时长字段，单位为秒。当前回合由双方存活单位与结算状态决定结束，此值不再作为强制倒计时。
@export var battle_duration: float = 10.0
var battle_time: Timer

signal energy_changed(current: int, maximum: int)
signal phase_changed(current_phase: Global.GamePhase, round: int)
signal battle_round_ended
signal health_changed
signal settlement_finished
signal round_settled(result: StringName, damage: int, base_damage: int, unit_damage: int)

# 作用：Godot 入树时准备兼容计时器并监听全局 HP；没有参数，没有返回值。
func _ready() -> void:
	battle = get_parent() as Node2D
	battle_time = Timer.new()
	battle_time.one_shot = true
	add_child(battle_time)
	RunManager.stats_changed.connect(_on_run_stats_changed)

# 作用：进入节点时只初始化敌方 HP 和本场修正；没有参数，没有返回值。
func start_encounter() -> void:
	_settlement_generation += 1
	battle_state = BattleState.PREPARING
	current_round = maxi(1, first_round)
	enemy_hp = enemy_max_hp
	recurring_energy = 0
	pending_recurring_energy = 0
	energy_modifiers.clear()
	is_round_settling = false
	_check_scheduled = false
	health_changed.emit()
	if player_hp <= 0:
		battle.finish_battle(false)
		return
	_start_card_phase()

# 作用：开始准备，兑现延迟能量并回满最终上限；没有参数，没有返回值。
func _start_card_phase() -> void:
	if is_finished() or battle_state in [BattleState.ROUND_END, BattleState.DAMAGE_SETTLEMENT]:
		return
	recurring_energy += pending_recurring_energy
	pending_recurring_energy = 0
	calculate_energy()
	current_energy = final_energy_max
	is_round_settling = false
	battle_state = BattleState.PLAYER_PHASE
	Global.game_phase = Global.GamePhase.CARD_PLAY
	energy_changed.emit(current_energy, final_energy_max)
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		if current_round == first_round:
			relics.begin_battle()
		relics.begin_round()
	phase_changed.emit(Global.game_phase, current_round)
	if relics != null:
		relics.after_opening_draw()

# 作用：计算基础成长与四类附加上限；没有参数，没有返回值。
func calculate_energy() -> void:
	base_energy_max = mini(max_energy + maxi(current_round - 1, 0) * energy_growth, base_energy_cap)
	bonus_energy_max = RunManager.bonus_energy_max + recurring_energy
	for source in [&"permanent", &"relic", &"card", &"status"]:
		for modifier: Dictionary in energy_modifiers.get(source, []):
			if current_round < modifier.start or (modifier.end > 0 and current_round > modifier.end):
				continue
			if modifier.period > 0 and current_round % modifier.period != 0:
				continue
			bonus_energy_max += modifier.amount
	# 只保证最终上限不为负；基础 10 点封顶不截断额外效果。
	final_energy_max = maxi(0, base_energy_max + bonus_energy_max)

# 作用：登记上限效果；source 为永久/遗物/卡牌/状态来源，amount 可负，start/end 为轮数（end=0永久），
# period=3 表示每三轮生效；没有返回值。准备中改变上限不会自动回复已消耗能量。
func add_energy_modifier(source: StringName, amount: int, start: int = 1, end: int = 0, period: int = 0) -> void:
	if is_finished() or source not in [&"permanent", &"relic", &"card", &"status"]:
		return
	if not energy_modifiers.has(source):
		energy_modifiers[source] = []
	energy_modifiers[source].append({"amount": amount, "start": maxi(1, start), "end": end, "period": maxi(0, period)})
	calculate_energy()
	energy_changed.emit(current_energy, final_energy_max)

# 作用：玩家结束部署后开始不限时交锋；没有参数，没有返回值。
func start_auto_battle() -> void:
	if battle_state != BattleState.PLAYER_PHASE or is_finished():
		return
	battle_state = BattleState.COMBAT
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	phase_changed.emit(Global.game_phase, current_round)
	# 空阵容也能开打，按败北或平局规则结算。
	request_round_check()

# 作用：死亡或退场请求在本帧结束后统一检查；没有参数，没有返回值。
func request_round_check() -> void:
	if battle_state != BattleState.COMBAT or _check_scheduled or is_finished():
		return
	_check_scheduled = true
	finish_unit_combat.call_deferred()

# 作用：停止交锋、结算回合末效果与 HP；没有参数，没有返回值。
func finish_unit_combat() -> void:
	_check_scheduled = false
	if battle_state != BattleState.COMBAT or is_round_settling or is_finished():
		return
	if not battle.get_alive_units(&"team_a").is_empty() and not battle.get_alive_units(&"team_b").is_empty():
		return
	# 先锁住再发毒和爆炸信号；连锁死亡不能重新进入结算。
	is_round_settling = true
	battle_state = BattleState.ROUND_END
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	phase_changed.emit(Global.game_phase, current_round)
	battle_time.stop()
	var relics := battle.get_node_or_null("RelicRuntime")
	if relics != null:
		relics.end_round()
	battle_round_ended.emit()
	if is_finished():
		return
	battle_state = BattleState.DAMAGE_SETTLEMENT
	var allies: Array[UnitBase] = battle.get_alive_units(&"team_a")
	var enemies: Array[UnitBase] = battle.get_alive_units(&"team_b")
	round_damage = 0
	round_damage_from_round = 0
	round_damage_from_units = 0
	last_round_result = &"draw"
	var sources: Array[Dictionary] = []
	# 回合末毒和爆炸已完成，固定幸存者伤害，动画期间不再重新计算。
	if not allies.is_empty() or not enemies.is_empty():
		var survivors := allies if enemies.is_empty() else enemies
		round_damage = calculate_round_hp_damage(current_round, survivors)
		round_damage_from_round = current_round
		round_damage_from_units = round_damage - round_damage_from_round
		last_round_result = &"player" if enemies.is_empty() else &"enemy"
		for unit in survivors:
			sources.append({"position": unit.get_global_transform_with_canvas().origin,
				"damage": maxi(0, unit.unit_data.hp_damage_value)})
	_damage_applied = 0
	_settlement_generation += 1
	var generation := _settlement_generation
	# 命中逐次扣唯一 HP；全部光弹和余辉播完才能清场、抽牌或显示胜负。
	var completed: bool = await battle.play_round_damage(last_round_result, round_damage_from_round, sources,
		_apply_settlement_damage.bind(generation))
	if generation != _settlement_generation or not is_inside_tree() or is_finished() or not completed:
		return
	health_changed.emit()
	round_settled.emit(last_round_result, round_damage, round_damage_from_round, round_damage_from_units)
	if relics != null:
		relics.settled()
	battle.clear_round_units()
	if is_finished():
		return
	if player_hp <= 0 or enemy_hp <= 0:
		battle.finish_battle(player_hp > 0 and enemy_hp <= 0)
	else:
		battle_state = BattleState.NEXT_ROUND
		_start_next_round.call_deferred()
	settlement_finished.emit()


# 每束光弹命中时扣血；generation 阻断结束或切场后的旧动画回调。
func _apply_settlement_damage(amount: int, generation: int) -> void:
	if generation != _settlement_generation or battle_state != BattleState.DAMAGE_SETTLEMENT or is_finished() or not is_inside_tree():
		return
	var damage := clampi(amount, 0, round_damage - _damage_applied)
	_damage_applied += damage
	if last_round_result == &"player":
		enemy_hp = maxi(0, enemy_hp - damage)
	elif last_round_result == &"enemy":
		RunManager.hp -= damage
	health_changed.emit()

# 作用：计算胜者存活单位的扣血；round_number 为轮数，surviving_units 为正式活单位，返回 HP 伤害。
func calculate_round_hp_damage(round_number: int, surviving_units: Array[UnitBase]) -> int:
	var damage := maxi(1, round_number)
	for unit in surviving_units:
		if is_instance_valid(unit) and unit.is_alive():
			damage += maxi(0, unit.unit_data.hp_damage_value)
	return damage

# 作用：清场完成后推进轮数，并在准备阶段信号中生成下一轮敌阵与抽牌；没有参数，没有返回值。
func _start_next_round() -> void:
	if battle_state != BattleState.NEXT_ROUND or is_finished() or not is_inside_tree():
		return
	current_round += 1
	_start_card_phase()

# 作用：判断节点是否结束；没有参数，返回是否禁止旧事件继续运行。
func is_finished() -> bool:
	return battle_state in [BattleState.VICTORY, BattleState.DEFEAT] or (is_instance_valid(battle) and battle.battle_finished)

# 作用：战场结束时锁住系统；won 为胜负，没有返回值。
func stop_encounter(won: bool) -> void:
	_settlement_generation += 1
	battle.cancel_round_damage()
	battle_state = BattleState.VICTORY if won else BattleState.DEFEAT
	_check_scheduled = false
	battle_time.stop()

# 作用：Run 血量变化刷新 UI；结算中的归零等待特效收尾，其余阶段立即失败。
func _on_run_stats_changed() -> void:
	health_changed.emit()
	if is_instance_valid(battle) and not is_finished() and current_round > 0 and player_hp <= 0 and not is_round_settling:
		battle.finish_battle(false)
	elif battle_state == BattleState.PLAYER_PHASE and not is_finished():
		# 在准备中获得永久能量遗物，立即更新分母；实际回复仍只在新轮开始执行。
		calculate_energy()
		energy_changed.emit(current_energy, final_energy_max)

# 作用：兼容旧倒计时入口；没有参数，没有返回值。到期只检查全灭，不能截断交锋。
func _on_battle_timer_timeout() -> void:
	request_round_check()

# 作用：即时获得本轮能量；amount 为点数，没有返回值，不改变上限。
func gain_energy(amount: int) -> void:
	if not can_play_cards() or amount <= 0:
		return
	current_energy += amount
	energy_changed.emit(current_energy, final_energy_max)


func skip_round_error() -> String:
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or battle_state != BattleState.COMBAT or is_round_settling or is_finished():
		return "只能在交锋中使用烟雾弹。"
	for unit: UnitBase in battle.get_alive_units(&"team_b"):
		if unit.unit_data.monster_rank in [UnitData.MonsterRank.BOSS, UnitData.MonsterRank.LEGENDARY]:
			return "Boss 波不能使用烟雾弹。"
	# 地图的 Boss 节点没有首领单位时也保护，不能通过策反或击杀首领后绕过。
	if RunManager.is_boss_battle():
		return "Boss 战不能使用烟雾弹。"
	return ""


## 烟雾弹是一次无扣血、无奖励的本轮撤退；仍推进区域和增益期限。
func skip_round() -> bool:
	if not skip_round_error().is_empty():
		return false
	is_round_settling = true
	battle_state = BattleState.ROUND_END
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	phase_changed.emit(Global.game_phase, current_round)
	battle_time.stop()
	battle_round_ended.emit()
	round_damage = 0
	round_damage_from_round = 0
	round_damage_from_units = 0
	last_round_result = &"draw"
	round_settled.emit(last_round_result, 0, 0, 0)
	battle.clear_round_units()
	battle_state = BattleState.NEXT_ROUND
	_start_next_round.call_deferred()
	settlement_finished.emit()
	return true

# 作用：支付卡牌能量；cost 为费用，返回是否成功，结束后不可再扣费。
func try_spend_energy(cost: int) -> bool:
	if not can_play_cards() or cost < 0 or current_energy < cost:
		return false
	current_energy -= cost
	energy_changed.emit(current_energy, final_energy_max)
	return true


# 作用：准备和交锋共用同一轮手牌与能量，结算锁住后禁止继续施放；没有参数，返回是否允许。
func can_play_cards() -> bool:
	return Global.is_card_play_phase() and battle_state in [BattleState.PLAYER_PHASE, BattleState.COMBAT] and not is_round_settling and not is_finished()
