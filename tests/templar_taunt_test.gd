# 真实动作释放、范围和多来源强制索敌、临时防御、反击破甲及正式卡牌复制隔离。
extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
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


func _unit(name: String, point: Vector2, level: int = 0, team: String = "") -> UnitBase:
	var original_team := "team_b" if name == "orc" else "team_a"
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), original_team, level)
	if not team.is_empty() and team != original_team:
		unit.unit_data.unit_team = team
		unit.remove_from_group(original_team)
		unit.add_to_group(team)
		unit.reparent(arena.team_b if team == "team_b" else arena.team_a)
	unit.global_position = point
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.dodge_rate = 0.0
	return unit


func _taunt(unit: UnitBase) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == "嘲讽攻击":
			return skill
	return null


func _aim(unit: UnitBase, target: UnitBase) -> void:
	unit.skill_manager.current_skill = unit.skill_manager.group_skills.back()
	unit.skill_manager.current_target = target


func _freeze(caster: UnitBase, targets: Array[UnitBase]) -> void:
	caster.taunt_runtime.set_physics_process(false)
	for target in targets:
		target.status_runtime.set_physics_process(false)


func _reset() -> void:
	arena.clear_arena()
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _capture() -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await _frames(12)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/templar-taunt")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/templar-taunt/taunt.png")


func _run() -> void:
	var source := load("res://data/units/knight_templar.tres") as UnitData
	var normal := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(0, 2), "正式训练强化圣殿骑士")
	check(normal.get_summon_data().skills.size() == 2 and trained.get_summon_data().skills.size() == 2, "基础及强化仅保留普攻与嘲讽，不再装配旧光环")
	var base_skill: SkillBase = normal.get_summon_data().skills[1]
	var upgraded_skill: SkillBase = trained.get_summon_data().skills[1]
	check(base_skill.cooldown == 10 and base_skill.taunt_duration == 3 and upgraded_skill.cooldown == 10 and upgraded_skill.taunt_duration == 5, "基础嘲讽3秒、强化5秒，均10秒冷却")
	check(base_skill.taunt_radius == 200 and upgraded_skill.defence_per_attacker == 1, "沿用200范围，强化每名瞄准敌人+1防御")
	check(upgraded_skill.taunt_effect == load("res://data/skills/knight_templar_protection_aura.tres").aura_effect, "嘲讽直接复用圣殿骑士原光环场景")
	check(not normal.get_description().contains("连续攻击") and not trained.get_description().contains("庇护") and trained.get_description().contains("防御-1"), "卡牌替换旧效果并显示反击破甲")
	check(not normal.get_summon_data().is_skill_unlocked(source.dodge_skill) and trained.get_summon_data().is_skill_unlocked(source.dodge_skill), "保留防守反击原有强化解锁条件")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	await _release()
	await _overlap()
	await _control_and_special_targets()
	await _automatic_combat()
	await _counter()
	arena.queue_free()
	await _frames(2)
	await _formal_battle(source)
	print("TEMPLAR_TAUNT_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _release() -> void:
	var caster := _unit("knight_templar", Vector2(650, 450))
	var ally := _unit("soldier", Vector2(855, 450))
	var enemy := _unit("orc", Vector2(840, 450))
	var edge := _unit("orc", Vector2(650, 650))
	var outside := _unit("orc", Vector2(650, 650.1))
	var hp := int(enemy.current_health)
	var attack := int(ally.unit_data.attack)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	_aim(enemy, ally)
	var skill := _taunt(caster)
	caster.skill_manager.current_skill = skill
	caster.skill_manager.current_target = enemy
	caster.switch_state(UnitBase.State.ATTACK)
	caster.skill_manager.attack()
	check(not enemy.has_status(&"taunt"), "嘲讽在动作释放帧生效，开始动作不提前生效")
	for frame in 80:
		await get_tree().physics_frame
		if enemy.has_status(&"taunt"):
			break
	_freeze(caster, [enemy, edge, outside])
	check(enemy.has_status(&"taunt") and edge.has_status(&"taunt") and not outside.has_status(&"taunt"), "嘲讽覆盖200边界，范围外不受影响")
	check(enemy.current_health == hp, "嘲讽替换原连续伤害，普攻仍由原攻击技能负责")
	check(enemy.skill_manager.current_target == caster and enemy.status_runtime.taunt_target() == caster, "敌人从更近的士兵转攻嘲讽者")
	check(caster.skill_manager.get_cooldown_left(skill) > 8.0, "真实动作释放后进入10秒冷却")
	check(ally.unit_data.attack == attack and ally.protection_attack_bonus == 0 and caster.taunt_defence_bonus == 0, "基础嘲讽不提供旧光环攻击加成或强化防御")
	check(caster.taunt_runtime.visual is GPUParticles2D and caster.taunt_runtime.visual.process_material.emission_ring_radius == 200.0 and caster.taunt_runtime.visual.local_coords, "原光环粒子半径200且随施法者移动")
	check(enemy.active_statuses().any(func(entry): return entry.icon == "taunt"), "被嘲讽者显示状态与剩余时间")
	enemy.global_position.x = 1100
	check(enemy.skill_manager.find_target_for_skill(enemy.skill_manager.group_skills[0]) == caster, "被嘲讽后离开初始范围仍保持强制目标")
	caster.set_stunned(true)
	check(enemy.status_runtime.taunt_target() == caster and caster.taunt_runtime.left > 0, "释放者受眩晕不撤销已经生效的嘲讽")
	caster.set_stunned(false)
	await _capture()
	enemy.status_runtime._physics_process(3.0)
	check(not enemy.has_status(&"taunt") and enemy.status_runtime.taunt_target() == null, "3秒到期解除强制索敌")
	caster.taunt_runtime._physics_process(3.0)
	check(caster.taunt_runtime.left == 0 and caster.taunt_runtime.visual == null and not edge.has_status(&"taunt"), "嘲讽结束清理原光环和剩余目标状态")
	await _reset()


func _overlap() -> void:
	var first := _unit("knight_templar", Vector2(650, 450))
	var second := _unit("knight_templar", Vector2(850, 450), 1)
	var ally := _unit("soldier", Vector2(770, 450))
	var enemy := _unit("orc", Vector2(760, 450))
	var two := _unit("orc", Vector2(850, 540))
	var three := _unit("orc", Vector2(900, 440))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	_taunt(first).execute(first, enemy)
	_taunt(second).execute(second, enemy)
	_freeze(first, [enemy, two, three])
	_freeze(second, [enemy, two, three])
	check(enemy.status_runtime.effects[&"taunt"].size() == 2 and enemy.status_runtime.taunt_target() == second, "两个同时嘲讽时选择距离较近的圣殿骑士")
	second.taunt_runtime.refresh_defence()
	var base_defence := int(second.unit_data.defence) - second.taunt_defence_bonus
	check(second.taunt_attackers == 3 and second.unit_data.defence == base_defence + 3, "强化嘲讽按当前瞄准自己的3名敌人增加3防御")
	second.get_hurt(100, two, false)
	check(second.current_health == 1000 - (100 - base_defence - 3), "动态防御实际参与伤害减免")
	_aim(three, ally)
	second.taunt_runtime.refresh_defence()
	check(second.taunt_attackers == 2 and second.taunt_defence_bonus == 2, "敌人瞄准其他友军时立即退出防御计数")
	for frame in 20:
		second.taunt_runtime.refresh_defence()
	check(second.unit_data.defence == base_defence + 2, "持续刷新防御不会重复叠加")
	second.global_position.x = 1000
	enemy.status_runtime._physics_process(0.01)
	check(enemy.skill_manager.current_target == first, "嘲讽者移动后实时切换到较近者")
	enemy.status_runtime._physics_process(3.0)
	check(enemy.status_runtime.taunt_target() == second and enemy.has_status(&"taunt"), "较近的3秒嘲讽到期后仍受另一个5秒来源约束")
	second.die()
	check(enemy.status_runtime.taunt_target() == null and not enemy.has_status(&"taunt") and second.taunt_defence_bonus == 0, "嘲讽来源死亡立即解除该来源与自身临时防御")
	check(second.unit_data.defence == base_defence, "嘲讽防御撤销后保留基础及训练防御")
	await _reset()


func _control_and_special_targets() -> void:
	var caster := _unit("knight_templar", Vector2(650, 450), 1)
	var ally := _unit("soldier", Vector2(835, 450))
	var soldier := _unit("soldier", Vector2(820, 450), 1, "team_b")
	var sleeper := _unit("orc", Vector2(700, 500))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	check(not sleeper.apply_status(&"taunt", 3.0) and not caster.apply_status(&"taunt", 3.0, 0, ally), "嘲讽拒绝缺失来源或友军来源")
	sleeper.apply_status(&"sleep", 0.0)
	_taunt(caster).execute(caster, sleeper)
	_freeze(caster, [soldier, sleeper])
	check(sleeper.has_status(&"sleep") and sleeper.is_action_blocked() and not sleeper.skill_manager.is_casting, "嘲讽不唤醒或绕过睡眠")
	sleeper.remove_status(&"sleep")
	sleeper.status_runtime._physics_process(0.01)
	check(sleeper.skill_manager.current_target == caster, "控制结束后恢复攻击嘲讽者")
	check(soldier.skill_manager.pick_skill() and soldier.skill_manager.current_target == caster, "士兵剑矢近敌优先规则不能绕过嘲讽")
	soldier.soldier_runtime.register_slash(caster)
	var slash := load("res://data/skills/soldier_power_attack.tres") as SkillBase
	check(soldier.skill_manager.find_target_for_skill(slash) == null, "已斩击过的嘲讽者不会让士兵重复斩击或转斩其他敌人")
	var wizard := _unit("wizard", Vector2(750, 450), 0, "team_b")
	var basic := load("res://data/skills/wizard_fire_ball.tres") as SkillBase
	wizard.skill_manager.current_skill = basic
	wizard.skill_manager.current_target = ally
	wizard.switch_state(UnitBase.State.ATTACK)
	wizard.skill_manager.attack()
	check(wizard.skill_manager.is_chanting, "敌方巫师开始对旧目标咏唱")
	_taunt(caster).execute(caster, sleeper)
	_freeze(caster, [soldier, sleeper, wizard])
	check(not wizard.skill_manager.is_chanting and wizard.skill_manager.get_cooldown_left(basic) > 0 \
		and wizard.skill_manager.find_target_for_skill(basic) == caster, "嘲讽打断原攻击咏唱，旧技能进入冷却并改选嘲讽者")
	var healer := load("res://data/skills/priest_healer.tres") as SkillBase
	if healer != null:
		check(sleeper.skill_manager.find_target_for_skill(healer) != caster, "嘲讽不会把友方治疗目标错误改成敌人")
	var foreign := Node2D.new()
	var foreign_team := Node2D.new()
	add_child(foreign)
	foreign.add_child(foreign_team)
	var other := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	foreign_team.add_child(other)
	other.set_physics_process(false)
	other.global_position = caster.global_position
	_taunt(caster).execute(caster, sleeper)
	_freeze(caster, [soldier, sleeper])
	check(not other.has_status(&"taunt"), "嘲讽不影响相同坐标的其他测试场单位")
	foreign.queue_free()
	Global.game_phase = Global.GamePhase.CARD_PLAY
	caster.taunt_runtime._physics_process(0.01)
	check(not soldier.has_status(&"taunt") and caster.taunt_defence_bonus == 0 and caster.taunt_runtime.visual == null, "离开战斗阶段清空嘲讽、动态防御及特效")
	await _reset()


func _automatic_combat() -> void:
	var caster := _unit("knight_templar", Vector2(650, 450), 1)
	var ally := _unit("soldier", Vector2(850, 450))
	var enemy := _unit("orc", Vector2(800, 450))
	var hits: Array[UnitBase] = []
	enemy.attack_landed.connect(func(target): hits.append(target))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	_taunt(caster).execute(caster, enemy)
	enemy.set_physics_process(true)
	for frame in 170:
		await get_tree().physics_frame
		if not hits.is_empty():
			break
	check(not hits.is_empty() and hits.all(func(target): return target == caster), "真实自动战斗会寻路靠近并攻击嘲讽者")
	check(caster.current_health < 1000 and ally.current_health == 1000, "自动战斗伤害落到圣殿骑士而非原本更近的友军")
	ally.global_position = enemy.global_position + Vector2(20, 0)
	check(enemy.skill_manager.find_target_for_skill(enemy.skill_manager.group_skills[0]) == caster, "嘲讽期间新的更近目标不会抢走仇恨")
	for frame in 310:
		await get_tree().physics_frame
		if caster.taunt_runtime.left == 0:
			break
	enemy.set_physics_process(false)
	check(not enemy.has_status(&"taunt") and caster.taunt_runtime.visual == null and caster.taunt_defence_bonus == 0, "真实物理时钟5秒自动结束嘲讽及动态防御")
	check(enemy.skill_manager.find_target_for_skill(enemy.skill_manager.group_skills[0]) == ally, "嘲讽到期后恢复普通最近目标选择")
	await _reset()


func _counter() -> void:
	var caster := _unit("knight_templar", Vector2(650, 450), 1)
	var enemy := _unit("orc", Vector2(710, 450))
	caster.unit_data.dodge_rate = 1.0
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var original_defence := int(enemy.unit_data.defence)
	for attempt in 2:
		check(not caster.get_hurt(30, enemy), "成功防守反击闪避原攻击")
		for frame in 160:
			await get_tree().physics_frame
			if not caster.skill_manager.is_reacting:
				break
		check(enemy.unit_data.defence == original_defence - attempt - 1, "每次真实反击累计减少1防御")
	check(enemy.status_runtime.total_amount(&"armor_break") == 2, "破甲层数可叠加且单位显示真实防御")
	var multi: SkillBase = caster.unit_data.dodge_skill.duplicate()
	multi.hit_frame = [3, 5]
	caster.skill_manager.start_reaction(multi, enemy)
	for frame in 160:
		await get_tree().physics_frame
		if not caster.skill_manager.is_reacting:
			break
	check(enemy.unit_data.defence == original_defence - 3, "一次反击即使多命中帧也只破甲1点")
	var copied_data := enemy.unit_data.duplicate() as UnitData
	enemy.status_runtime.strip_stat_contributions(copied_data)
	check(copied_data.defence == original_defence, "复制属性剥离本场破甲，不继承临时扣减")
	enemy.clear_combat_statuses()
	check(enemy.unit_data.defence == original_defence and not enemy.has_status(&"armor_break"), "战斗清理恢复破甲扣除的防御")
	await _reset()


func _formal_battle(source: UnitData) -> void:
	var start := RunStartData.new()
	start.cards.assign([source, load("res://data/units/soldier.tres")])
	RunManager.start_new_run(start)
	check(RunManager.deck[0].train(0, 2), "正式卡牌训练防御分配")
	check(RunManager.save_run().is_empty() and RunManager.load_saved_run().is_empty(), "圣殿骑士强化记录可以存档恢复")
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	var card: CardInstance = RunManager.deck[0]
	battle.hand_manager.draw_pile.erase(card)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, Vector2(450, 450)), "存档恢复后通过正式出牌部署圣殿骑士")
	var caster: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	caster.set_physics_process(false)
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(600, 450)
	enemy.set_physics_process(false)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	_taunt(caster).execute(caster, enemy)
	_freeze(caster, [enemy])
	var base_defence := int(caster.unit_data.defence) - caster.taunt_defence_bonus
	check(caster.taunt_defence_bonus == 1 and _taunt(caster).taunt_duration == 5.0, "正式部署也有强化5秒嘲讽和实时防御")
	var frenzy := CardEffect.new()
	frenzy.kind = CardEffect.Kind.FRENZY
	frenzy.amount = 20.0
	frenzy.crowded_unit_count = 2
	battle.card_runtime.tactics.apply_effect(frenzy, {"target": caster, "card": card})
	check(caster.unit_data.defence == roundi((base_defence + 1) * 1.3), "嘲讽防御在狂化百分比之前计算")
	var copy := CardDefinition.new()
	copy.target = CardDefinition.Target.ALLY
	var effect := CardEffect.new()
	effect.kind = CardEffect.Kind.COPY_ALLY
	copy.effects.assign([effect])
	var copy_card := CardInstance.new(copy)
	battle.hand_manager.hand.append(copy_card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(copy_card, caster.global_position), "通过正式复制牌复制嘲讽期间的圣殿骑士")
	var copied: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	copied.set_physics_process(false)
	check(copied.unit_data.defence == base_defence and copied.taunt_runtime == null and copied.taunt_defence_bonus == 0, "复制品保留训练防御，不烘焙原骑士的嘲讽或狂化加成")
	caster.taunt_runtime.clear()
	check(caster.unit_data.defence == roundi(base_defence * 0.7), "友军数量改变后撤销嘲讽防御，狂化重算不残留")
	check(source.defence == 6 and source.card_upgrade_level == 0, "临时防御及存档操作不污染共享配置")
	battle.queue_free()
	await _frames(2)
