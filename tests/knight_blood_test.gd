# 骑士真实动画、分来源流血、实际生命损失回归、六秒计时与强化反击眩晕。
extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
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


func _unit(name: String, at: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), "team_b" if name == "orc" else "team_a", level)
	unit.global_position = at
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = unit.unit_data.dodge_skill if name == "knight" else null
	if unit.knight_runtime != null:
		unit.knight_runtime.set_physics_process(false)
	return unit


func _blood(unit: UnitBase) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == "血影斩击":
			return skill
	return null


func _tick(target: UnitBase, seconds: float) -> void:
	target.status_runtime._physics_process(seconds)
	target.status_runtime.set_physics_process(false)


func _reset_bleed_clock(target: UnitBase) -> void:
	target.status_runtime.set_physics_process(false)
	for entry: Dictionary in target.status_runtime.effects.get(&"bleed", {}).values():
		entry.elapsed = 0.0


func _capture() -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/knight-blood")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/knight-blood/vampiric-psalm.png")


func _run() -> void:
	var data := load("res://data/units/knight.tres") as UnitData
	var normal := CardInstance.new(data)
	var trained := CardInstance.new(data)
	check(trained.train(2, 0), "正式训练强化骑士")
	check(normal.get_summon_data().skills.size() == 2 and trained.get_summon_data().skills.size() == 2, "基础和强化均保留普攻与血影斩击")
	check(normal.get_summon_data().skills[1].cooldown == 10.0 and trained.get_summon_data().skills[1].cooldown == 8.0, "基础血影斩击10秒，强化8秒")
	check(normal.get_deployment_draw_count() == 1 and trained.get_deployment_draw_count() == 3, "强化骑士上场额外多抽2张，共3张")
	check(trained.get_description().contains("眩晕2秒") and normal.get_description().contains("鲜血回归"), "卡面说明包含当前流血回归和强化反击效果")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	var knight := _unit("knight", Vector2(650, 450))
	var peer := _unit("knight", Vector2(650, 700), 1)
	var enemy := _unit("orc", Vector2(710, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var skill := _blood(knight)
	var hp := int(enemy.current_health)
	knight.skill_manager.current_skill = skill
	knight.skill_manager.current_target = enemy
	knight.switch_state(UnitBase.State.ATTACK)
	knight.skill_manager.attack()
	for frame in 100:
		await get_tree().physics_frame
		if enemy.has_status(&"bleed"):
			break
	_reset_bleed_clock(enemy)
	check(enemy.current_health == hp - int(knight.unit_data.attack * 1.5), "真实血影斩击动画命中150%伤害")
	check(enemy.status_runtime.total_amount(&"bleed") == 1, "每次命中增加1层流血")
	check(knight.skill_manager.get_cooldown_left(skill) > 8.0, "基础释放进入10秒冷却")
	await _frames(40)
	check(not knight.skill_manager.is_casting, "血影斩击完整动画正常结束")
	enemy.unit_data.defence = 500
	hp = enemy.current_health
	_tick(enemy, 0.99)
	check(enemy.current_health == hp, "流血不足1秒不跳伤")
	_tick(enemy, 0.01)
	check(enemy.current_health == hp - 1 and knight.knight_runtime.pending_healing == 1, "每层流血每秒固定1点，忽略防御并计入回归")
	_tick(enemy, 0.6)
	skill.execute(knight, enemy)
	enemy.status_runtime.set_physics_process(false)
	check(enemy.status_runtime.total_amount(&"bleed") == 2, "再次斩击叠加层数")
	hp = enemy.current_health
	_tick(enemy, 0.4)
	check(enemy.current_health == hp - 2, "叠层不重置已有流血的秒跳进度")
	_blood(peer).execute(peer, enemy)
	_reset_bleed_clock(enemy)
	knight.knight_runtime.clear()
	peer.knight_runtime.clear()
	hp = enemy.current_health
	_tick(enemy, 1.0)
	check(enemy.current_health == hp - 3, "两名骑士的流血层数合计结算")
	check(knight.knight_runtime.pending_healing == 2 and peer.knight_runtime.pending_healing == 1, "每名骑士只记录自己的流血实际扣血")
	enemy.apply_status(&"bleed", 2.0, 7, knight, "unrelated_bleed")
	_reset_bleed_clock(enemy)
	knight.knight_runtime.clear()
	peer.knight_runtime.clear()
	_tick(enemy, 1.0)
	check(knight.knight_runtime.pending_healing == 2 and peer.knight_runtime.pending_healing == 1, "相同来源的其它流血不混入血影斩击的回血")
	knight.knight_runtime.clear()
	peer.knight_runtime.clear()
	enemy.add_shield(30)
	_tick(enemy, 1.0)
	check(knight.knight_runtime.pending_healing == 0 and peer.knight_runtime.pending_healing == 0, "护盾吸收流血不视为实际扣血")
	enemy.clear_shield()
	enemy.remove_status(&"bleed", "unrelated_bleed")
	_reset_bleed_clock(enemy)
	enemy.current_health = 1
	_tick(enemy, 1.0)
	check(knight.knight_runtime.pending_healing == 1 and peer.knight_runtime.pending_healing == 0, "致死流血只记录剩余1点生命，不计算溢出伤害")
	check(enemy.current_state == UnitBase.State.DEATH and not enemy.has_status(&"bleed"), "目标死亡清理流血")
	knight.knight_runtime.clear()
	peer.knight_runtime.clear()
	var victim := _unit("orc", Vector2(900, 450))
	skill.execute(knight, victim)
	skill.execute(knight, victim)
	_reset_bleed_clock(victim)
	_tick(victim, 1.0)
	knight.current_health = 500
	knight.knight_runtime._physics_process(5.99)
	check(knight.current_health == 500, "鲜血回归未满6秒不治疗")
	knight.knight_runtime._physics_process(0.01)
	check(knight.current_health == 502 and knight.knight_runtime.pending_healing == 0, "六秒边界返还实际流血扣血并清空本轮记录")
	await _frames(8)
	var effect: Node
	for node in arena.team_a.get_children():
		if node.get_script() != null and node.get_script().resource_path.ends_with("blood_return_vfx.gd"):
			effect = node
	check(is_instance_valid(effect) and effect.skill.id == "shadow_priest_vampiric_psalm", "鲜血回归复用实验室Vampiric Psalm完整配方")
	var roots := effect.get_children().filter(func(node: Node): return node.has_meta("effect_id") and node.get_meta("effect_id") == "vampiric_psalm_shadowpriestvfx") if effect != null else []
	check(not roots.is_empty(), "原Vampiric Psalm素材已实际生成")
	if not roots.is_empty():
		var visual: Node2D = roots[0].get_meta("visual_root")
		check(visual.points[0].distance_to(victim.to_global(victim._smoke_body_rect().get_center())) < 0.1 \
			and visual.points[1].distance_to(knight.to_global(knight._smoke_body_rect().get_center())) < 0.1, "原反向光束从流血目标返回骑士")
	await _frames(14)
	await _capture()
	knight.knight_runtime._physics_process(6.0)
	check(knight.current_health == 502, "旧流血扣血不会重复返还")
	_tick(victim, 1.0)
	knight.apply_status(&"mortal_wounds", 2.0)
	knight.knight_runtime._physics_process(6.0)
	check(knight.current_health == 502 and knight.knight_runtime.pending_healing == 0, "禁疗拦截鲜血回归且不积压重复返还")
	knight.remove_status(&"mortal_wounds")
	knight.current_health = knight.unit_data.max_hp
	_tick(victim, 1.0)
	knight.knight_runtime._physics_process(6.0)
	check(knight.current_health == knight.unit_data.max_hp and knight.shield_amount == 0, "回血不超过最大生命且不额外生成护盾")
	_tick(victim, 1.0)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var before := float(knight.knight_runtime.elapsed)
	hp = victim.current_health
	knight.knight_runtime._physics_process(20.0)
	_tick(victim, 20.0)
	check(knight.knight_runtime.elapsed == before and victim.current_health == hp, "准备阶段冻结六秒计时与流血")
	knight.clear_combat_statuses()
	check(knight.knight_runtime.pending_healing == 0 and knight.knight_runtime.elapsed == 0.0, "战斗清理清空未返还量和时钟")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	knight.die(peer)
	hp = victim.current_health
	_tick(victim, 1.0)
	check(victim.current_health == hp - 2 and knight.knight_runtime.pending_healing == 0, "骑士死亡后已有流血继续扣血，但不再积累回血")
	arena.clear_arena()
	await _frames(2)
	await _counter(0)
	await _counter(1)
	await _auto_return()
	arena.queue_free()
	await _frames(2)
	print("KNIGHT_BLOOD_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _counter(level: int) -> void:
	var knight := _unit("knight", Vector2(650, 450), level)
	var enemy := _unit("orc", Vector2(710, 450))
	knight.unit_data.dodge_rate = 1.0
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	check(not knight.get_hurt(30, enemy) and knight.current_health == 1000, "防守反击闪避原攻击")
	var previous_hp := int(enemy.current_health)
	var last_stun_left := 0.0
	for frame in 200:
		await get_tree().physics_frame
		if enemy.current_health != previous_hp and enemy.has_status(&"stun"):
			last_stun_left = enemy.status_runtime.effects[&"stun"].values()[0].left
		previous_hp = int(enemy.current_health)
		if not knight.skill_manager.is_reacting:
			break
	check(enemy.current_health == 1000 - 2 * int(knight.unit_data.attack * 1.2), "完整防守反击的两个命中帧正常结算")
	check(enemy.has_status(&"stun") == (level == 1), "只有强化防守反击附加眩晕")
	if level == 1:
		check(last_stun_left > 1.95 and last_stun_left <= 2.0 and enemy.is_action_blocked(), "强化反击末次命中刷新2秒眩晕")
		enemy.status_runtime.set_physics_process(false)
		enemy.status_runtime._physics_process(2.0)
		check(not enemy.is_stunned, "反击眩晕到期恢复行动")
	arena.clear_arena()
	await _frames(2)


func _auto_return() -> void:
	var knight := _unit("knight", Vector2(650, 450))
	var enemy := _unit("orc", Vector2(900, 450))
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	knight.current_health = 500
	_blood(knight).execute(knight, enemy)
	knight.knight_runtime.set_physics_process(true)
	for frame in 370:
		await get_tree().physics_frame
		if knight.current_health > 500:
			break
	check(knight.current_health == 506 and enemy.current_health == 1000 - int(knight.unit_data.attack * 1.5) - 6, "真实物理时钟6秒自动返还6次流血伤害")
	arena.clear_arena()
	await _frames(2)
