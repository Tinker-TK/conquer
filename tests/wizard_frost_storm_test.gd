# 真实训练、部署和命中帧验证霜暴；伤害、冰晶数量、范围减速与结束清理一起检查。
extends Node2D

var checks := 0
var failures: Array[String] = []
var battle: Node2D
var normal: UnitBase
var enhanced: UnitBase
var victim: UnitBase
var neighbor: UnitBase
var outside: UnitBase
var ally: UnitBase
const VOLLEY = preload("res://scripts/combat/frost_storm_volley.gd")


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _volleys() -> Array:
	return battle.get_node("Entities/TeamA").get_children().filter(func(node: Node): return node.get_script() == VOLLEY)


func _projectiles() -> Array:
	var result: Array = []
	for volley: Node in _volleys():
		for flight: Dictionary in volley._flights:
			if is_instance_valid(flight.holder):
				result.append(flight.holder)
	return result


func _deploy(card: CardInstance, at: Vector2) -> UnitBase:
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, at), "真实出牌部署巫师")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _enemy(at: Vector2) -> UnitBase:
	var unit := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	unit.unit_data = unit.unit_data.duplicate()
	unit.unit_data.max_hp = 10000
	unit.unit_data.defence = 9999
	unit.unit_data.dodge_skill = null
	battle.get_node("Entities/TeamB").add_child(unit)
	unit.global_position = at
	unit.set_physics_process(false)
	return unit


func _exhaust() -> void:
	var definition := CardDefinition.new()
	definition.after_use = CardDefinition.AfterUse.EXHAUST
	var card := CardInstance.new(definition)
	battle.hand_manager.resolving.append(card)
	battle.hand_manager.finish_resolve(card)


func _storm(caster: UnitBase) -> Node:
	return victim.get_node_or_null("FrostStormImpact_%d" % caster.get_instance_id())


func _cast(caster: UnitBase) -> int:
	var skill: SkillBase = caster.unit_data.get_unlocked_skills()[1]
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	caster.skill_manager.current_skill = skill
	caster.skill_manager.current_target = victim
	caster.switch_state(UnitBase.State.ATTACK)
	caster.skill_manager.attack()
	check(caster.skill_manager.is_chanting and caster.skill_manager.chant_bar.visible, "霜暴先咏唱1.5秒并显示头顶进度条")
	caster.skill_manager._physics_process(skill.chant_duration)
	check(caster.skill_manager.get_cooldown_left(skill) > 7.9, "真实施法启动8秒冷却")
	check(_projectiles().is_empty(), "出招帧之前没有冰晶或伤害")
	caster.animated_sprite_2d.frame = skill.hit_frame[0]
	var count := _projectiles().size()
	for volley: Node in _volleys():
		count += volley._events.filter(func(event: Dictionary): return event.kind == "projectile").size()
	return count


func _reset() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	SignalBus.phase_change.emit(Global.GamePhase.CARD_PLAY)
	await _frames(2)
	for caster in [normal, enhanced]:
		caster.skill_manager.interrupt_actions()
		for timer: Timer in caster.skill_manager._skill_time_cd.values():
			timer.stop()
	check(_volleys().is_empty() and _projectiles().is_empty() and _storm(normal) == null and _storm(enhanced) == null, "阶段切换清理所有冰晶和风暴")
	check(not victim.has_status(&"slow") and not neighbor.has_status(&"slow"), "阶段切换恢复移速")


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/wizard-frost-storm")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/wizard-frost-storm/%s.png" % label)


func _run() -> void:
	var data := load("res://data/units/wizard.tres") as UnitData
	var base_card := CardInstance.new(data)
	var trained_card := CardInstance.new(data)
	check(trained_card.train(data.upgrade_ability_points, 0), "通过正式训练强化本张巫师牌")
	check(base_card.get_description().contains("3+x") and not base_card.get_description().contains("移速"), "基础卡面说明3+x且无减速")
	check(trained_card.get_description().contains("5+x") and trained_card.get_description().contains("移速-100"), "强化卡面说明5+x和减速100")
	check(base_card.get_summon_data().get_unlocked_skills().size() == 2 and trained_card.get_summon_data().get_unlocked_skills().size() == 2, "强化替换霜暴，保留火球且不同时装配两个霜暴")
	RunManager.start_new_run()
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	battle.battle_round_manager.set_process(false)
	battle.battle_round_manager.set_physics_process(false)
	for unit: UnitBase in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	normal = _deploy(base_card, Vector2(450, 420))
	enhanced = _deploy(trained_card, Vector2(450, 600))
	victim = _enemy(Vector2(950, 420))
	neighbor = _enemy(Vector2(1100, 420))
	outside = _enemy(Vector2(1101, 420))
	ally = _deploy(CardInstance.new(load("res://data/units/soldier.tres")), Vector2(950, 490))
	await _frames(70)
	battle.hand_manager.exhaust_pile.clear()
	var health := int(victim.current_health)
	check(_cast(normal) == 3, "消耗牌堆为0时真实命中帧发射3颗")
	await _frames(20)
	check(_projectiles().size() == 3 and _projectiles().all(func(node: Node): return node.get_meta("effect_id") == "scenes_projectile_icebomb"), "每颗逻辑子弹恰有一个演示同款冰晶，无额外25颗弹雨")
	check(_projectiles().all(func(node: Node): return node.global_position.y < victim.global_position.y and absf(node.global_position.x - victim.global_position.x) <= 65.0), "冰晶从目标上方错落降下，落点汇聚目标")
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("ice_storm").duplicate(true)
	recipe.actions[0].count = 3
	recipe.cast_seconds = 0.0
	check(_volleys()[0].skill == recipe, "完整配方直接来自实验室冰霜·风暴，仅替换数量和已播过的前摇")
	check(victim.current_health == health, "冰晶飞行时不会提前造成伤害")
	await _capture("base-3-projectiles")
	await _frames(65)
	check(victim.current_health == health - 30 and neighbor.current_health == 10000, "3颗各10点固定单体伤害，无视9999防御且不伤周围")
	check(not victim.has_status(&"slow") and not neighbor.has_status(&"slow"), "基础霜暴只有风暴表现，不减速")
	check(_volleys()[0].get_children().any(func(node: Node): return node.get_meta("effect_id", "") == "scenes_vfx_arcticstormvfx"), "使用冰霜·风暴的目标风暴")
	await _reset()
	_exhaust()
	_exhaust()
	normal.unit_data.attack = 9999
	normal.floor_id = 4
	health = int(victim.current_health)
	check(_cast(normal) == 5, "消耗2张时发射3+2颗")
	_exhaust()
	await _frames(100)
	check(victim.current_health == health - 50, "发射时快照x；途中新增消耗牌、攻击力9999及高地均不改变本次5颗各10点伤害")
	await _reset()
	health = int(victim.current_health)
	BattleSpeed.set_multiplier(3)
	check(_cast(enhanced) == 8, "强化且消耗3张时发射5+3颗")
	await _frames(32)
	await _capture("enhanced-8-rain")
	var volley: Node = _volleys()[0]
	var paused_elapsed: float = volley.elapsed
	var paused_health := int(victim.current_health)
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(volley.elapsed == paused_elapsed and victim.current_health == paused_health, "暂停时原版弹雨、命中计时与伤害同时冻结")
	get_tree().paused = false
	await _frames(63)
	check(victim.current_health == health - 80 and neighbor.current_health == 10000, "3倍速与暂停恢复后8颗均只伤害目标，共80点")
	BattleSpeed.set_multiplier(1)
	check(victim.has_status(&"slow") and neighbor.has_status(&"slow") and not outside.has_status(&"slow"), "减速以目标为中心，包含150边界，排除151外敌军")
	check(not ally.has_status(&"slow") and not enhanced.has_status(&"slow"), "减速不影响友军或以巫师为中心扩散")
	check(victim.get_movement_speed() == 50.0 and victim.unit_data.speed == 150.0, "减速降低实际移动速度100，不污染基础属性")
	check(victim.status_runtime.strongest_amount(&"slow") == 100, "8次命中只刷新，减速不叠成800")
	check(victim.status_runtime.status_entries().any(func(entry: Dictionary): return entry.icon == "slow" and entry.tooltip.contains("100")), "状态图标与提示显示实际减速")
	await _capture("enhanced-8-impact")
	var storm: Node = _storm(enhanced)
	neighbor.position += Vector2(1, 0)
	await _frames(2)
	check(not neighbor.has_status(&"slow"), "离开风暴范围立即恢复")
	victim.position += Vector2(1, 0)
	await _frames(2)
	check(neighbor.has_status(&"slow") and outside.has_status(&"slow"), "风暴随目标移动，新进入的敌军获得减速")
	# 泥潭继续写基础移速；霜暴在最终移动速度上扣除，到期不会错误恢复泥潭前速度。
	battle.card_runtime.set_physics_process(false)
	victim.unit_data.speed = 75.0
	check(victim.get_movement_speed() == 1.0, "与其他移速调整叠用时最低为1")
	if is_instance_valid(storm):
		storm.seconds_left = 0.01
	await _frames(2)
	check(not victim.has_status(&"slow") and victim.get_movement_speed() == 75.0 and not outside.has_status(&"slow"), "2秒风暴结束撤销全体减速，保留其他移速调整")
	await _reset()
	check(_cast(enhanced) == 8, "下一次施法重新读取当前消耗牌堆")
	await _frames(95)
	victim.die()
	await _frames(2)
	check(not neighbor.has_status(&"slow") and not outside.has_status(&"slow"), "目标死亡立即清理其风暴和周围减速")
	await _reset()
	victim = _enemy(Vector2(950, 420))
	check(_cast(enhanced) == 8, "新目标可正常发射")
	await _frames(20)
	await _reset()
	check(preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("ice_storm").actions[0].count == 25, "多次实战不修改实验室的原版共享25颗配方")
	print("WIZARD_FROST_STORM_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
