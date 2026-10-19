extends Node2D

var arena: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(55.0).timeout.connect(func(): get_tree().quit(1))
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


func _unit(kind: String, point: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % kind), "team_b" if kind == "orc" else "team_a", level)
	unit.global_position = point
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.defence = 0
	unit.unit_data.attack = 15
	unit.unit_data.dodge_skill = null
	unit.get_node("HealthBar").setup(1000)
	var smoke := unit.get_node_or_null("SpawnSmoke")
	if smoke != null:
		smoke.queue_free()
	return unit


func _five(unit: UnitBase) -> SkillBase:
	for skill: SkillBase in unit.skill_manager.group_skills:
		if skill.skill_name == "五连斩击":
			return skill
	return null


func _cast(unit: UnitBase, target: UnitBase, skill: SkillBase) -> void:
	unit.skill_manager.current_skill = skill
	unit.skill_manager.current_target = target
	unit.switch_state(UnitBase.State.ATTACK)
	unit.skill_manager.attack()


func _reset() -> void:
	arena.clear_arena()
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE


func _capture(title: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/wolf-pounce")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/wolf-pounce/%s.png" % title)


func _run() -> void:
	var source := load("res://data/units/were_wolf.tres") as UnitData
	var card := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(2, 0), "正式训练强化狼人")
	check(card.get_summon_data().skills.size() == 3 and trained.get_summon_data().skills.size() == 3, "基础和强化均安装普攻、唯一五连斩击及原隐身被动")
	check(card.get_description().contains("350") and not card.get_description().contains("眩晕") and trained.get_description().contains("450") and trained.get_description().contains("刷新CD"), "卡面同步基础距离与强化眩晕、刷新")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await _frames(2)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await _targeting()
	await _combat(0)
	await _combat(1)
	await _kill(0)
	await _kill(1)
	await _unrelated_kills()
	await _interruptions()
	await _wall_and_range()
	arena.queue_free()
	await _frames(2)
	print("WOLF_POUNCE_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _targeting() -> void:
	var wolf := _unit("were_wolf", Vector2(600, 500))
	var upgraded := _unit("were_wolf", Vector2(600, 500), 1)
	var wounded := _unit("orc", Vector2(660, 500))
	wounded.unit_data.max_hp = 100
	wounded.current_health = 1
	var fragile := _unit("orc", Vector2(900, 500))
	fragile.unit_data.max_hp = 40
	fragile.current_health = 40
	var distant := _unit("orc", Vector2(1000, 500))
	distant.unit_data.max_hp = 5
	var outside := _unit("orc", Vector2(1200, 500))
	outside.unit_data.max_hp = 1
	var hidden := _unit("orc", Vector2(720, 550))
	hidden.unit_data.max_hp = 2
	hidden.set_stealthed(true)
	var upstairs := _unit("orc", Vector2(720, 420))
	upstairs.unit_data.max_hp = 2
	upstairs.set_floor(2)
	var ally := _unit("soldier", Vector2(700, 500))
	ally.unit_data.max_hp = 1
	var elsewhere := Node2D.new()
	add_child(elsewhere)
	var other_team := Node2D.new()
	elsewhere.add_child(other_team)
	var foreign := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	other_team.add_child(foreign)
	foreign.global_position = Vector2(650, 520)
	foreign.set_physics_process(false)
	foreign.unit_data.max_hp = 1
	check(_five(wolf).select_target(wolf) == fragile, "基础按最大生命选择40满血者，跳过1当前生命的100最大生命者及350外更脆目标")
	check(_five(upgraded).select_target(upgraded) == distant, "强化450距离可选择400外目标，仍排除450外、隐身、异层、友军及其它战场")
	check(wolf.skill_manager.pick_skill() and wolf.skill_manager.current_skill == _five(wolf) and wolf.skill_manager.current_target == fragile, "真实技能选择优先五连斩击最大生命目标")
	fragile.unit_data.max_hp = wounded.unit_data.max_hp
	check(_five(wolf).select_target(wolf) == wounded, "最大生命相同时选较近的敌人")
	distant.global_position = Vector2(950, 500)
	check(_five(wolf).select_target(wolf) == distant, "350像素边界可发动")
	distant.global_position = Vector2(1050, 500)
	check(_five(upgraded).select_target(upgraded) == distant, "强化450像素边界可发动")
	wolf.apply_status(&"taunt", 3.0, 0, wounded)
	check(wolf.skill_manager.find_target_for_skill(_five(wolf)) == wounded, "嘲讽仍优先约束五连斩击目标")
	elsewhere.queue_free()
	await _reset()


func _combat(level: int) -> void:
	var wolf := _unit("were_wolf", Vector2(600, 500), level)
	var target := _unit("orc", Vector2(900, 500))
	var other := _unit("orc", Vector2(900, 700))
	var five := _five(wolf)
	await _frames(2)
	_cast(wolf, target, five)
	check(wolf.global_position == Vector2(600, 500) and wolf.skill_manager.get_cooldown_left(five) > 6.9, "开始扑击不瞬移，并只启动一次7秒冷却")
	await _frames(8)
	var motion: Node = wolf.skill_manager.cast_data.get("wolf_pounce")
	check(is_instance_valid(motion) and motion.stage == "pounce" and wolf.global_position.x > 600 and wolf.global_position.x < 845, "0.3秒途中有真实连续位移")
	check(target.current_health == 1000 and motion.visual.skill.id == "angel_dash" and motion.visual.skill.actions[0].ghost_tint == [1.0, 0.9, 0.52, 0.48], "原Angel金色冲刺配方，扑击途中不提前结算斩击")
	check(motion.visual._expirations.any(func(entry): return is_instance_valid(entry.node) and entry.node is Sprite2D and entry.node.get_meta("unit_ghost", false) and entry.node.hframes == 1 and entry.node.global_scale == wolf.animated_sprite_2d.global_scale), "原配方残影换为真实狼人帧、缩放和位置")
	check(get_tree().get_nodes_in_group("teleport_portal_burst").is_empty(), "没有旧传送门特效")
	await _capture("angel-%d" % level)
	await _frames(13)
	check(motion.stage == "attack" and wolf.global_position.distance_to(target.global_position) < five.melee_range and wolf.animated_sprite_2d.animation == &"attack_02", "扑击结束后开始原五连斩击动画，落点在近战距离")
	var hits := 0
	var health := int(target.current_health)
	var last_left := 0.0
	for frame in 140:
		await get_tree().physics_frame
		if target.current_health != health:
			hits += 1
			health = int(target.current_health)
			if target.has_status(&"stun"):
				last_left = target.status_runtime.effects[&"stun"].values()[0].left
		if not wolf.skill_manager.is_casting:
			break
	check(hits == 5 and target.current_health == 940 and other.current_health == 1000, "原7/8/9/10/11五帧各80%伤害，只命中锁定目标")
	check(target.has_status(&"stun") == (level == 1), "仅强化五连斩击附加眩晕")
	if level == 1:
		check(last_left > 1.95 and last_left <= 2.0, "每刀成功命中刷新目标2秒眩晕")
	check(wolf.skill_manager.get_cooldown_left(five) > 4.0 and not wolf.skill_manager.is_forced_moving and not wolf.get_node("CollisionShape2D").disabled, "未击杀不会刷新，完整连击恢复碰撞及移动控制")
	await _reset()


func _kill(level: int) -> void:
	var wolf := _unit("were_wolf", Vector2(600, 500), level)
	var target := _unit("orc", Vector2(900, 500))
	target.current_health = 12
	var next := _unit("orc", Vector2(900, 650))
	var five := _five(wolf)
	_cast(wolf, target, five)
	for frame in 90:
		await get_tree().physics_frame
		if target.current_state == UnitBase.State.DEATH:
			break
	check(target.current_state == UnitBase.State.DEATH and not wolf.skill_manager.is_casting, "击杀锁定目标立即结束旧连击，不等待剩余空挥动画")
	check(is_zero_approx(wolf.skill_manager.get_cooldown_left(five)) if level == 1 else wolf.skill_manager.get_cooldown_left(five) > 5.0, "强化击杀立即刷新，基础击杀不刷新")
	check(wolf.skill_manager.get_cooldown_fraction(five) == 0.0 if level == 1 else wolf.skill_manager.get_cooldown_fraction(five) > 0.0, "冷却显示同步刷新结果")
	if level == 1:
		check(wolf.skill_manager.pick_skill() and wolf.skill_manager.current_skill == five and wolf.skill_manager.current_target == next, "刷新后下一次索敌立即可对新目标再发动")
		wolf.switch_state(UnitBase.State.ATTACK)
		wolf.skill_manager.attack()
		check(wolf.skill_manager.is_casting and wolf.skill_manager.get_cooldown_left(five) > 6.9, "再次发动独立扑击并重新启动7秒冷却")
	await _reset()


func _unrelated_kills() -> void:
	var wolf := _unit("were_wolf", Vector2(600, 500), 1)
	var peer := _unit("were_wolf", Vector2(600, 750), 1)
	var target := _unit("orc", Vector2(900, 500))
	var other := _unit("orc", Vector2(900, 750))
	var five := _five(wolf)
	_cast(wolf, target, five)
	_cast(peer, other, _five(peer))
	await _frames(8)
	other.die(wolf)
	check(wolf.skill_manager.get_cooldown_left(five) > 6.7, "击杀未锁定敌人不会刷新五连斩击")
	check(peer.skill_manager.get_cooldown_left(_five(peer)) > 6.7, "共享资源的另一狼人不会因别人的击杀刷新")
	target.die(peer)
	check(wolf.skill_manager.get_cooldown_left(five) > 6.7 and not wolf.skill_manager.is_casting, "友军击杀锁定目标只取消旧连击，不提供刷新")
	await _reset()
	var caster := _unit("were_wolf", Vector2(600, 500), 1)
	var victim := _unit("orc", Vector2(900, 500))
	var skill := _five(caster)
	_cast(caster, victim, skill)
	await _frames(8)
	caster.apply_status(&"stun", 2.0)
	victim.die(caster)
	check(caster.skill_manager.get_cooldown_left(skill) > 6.7, "扑击被打断后解除击杀监听，后续伤害杀死旧目标不刷新")
	await _reset()


func _interruptions() -> void:
	for reason in ["stun", "death", "phase"]:
		var wolf := _unit("were_wolf", Vector2(600, 500), 1)
		var enemy := _unit("orc", Vector2(900, 500))
		var five := _five(wolf)
		_cast(wolf, enemy, five)
		await _frames(8)
		if reason == "stun":
			wolf.apply_status(&"stun", 2.0)
		elif reason == "death":
			wolf.die()
		else:
			Global.game_phase = Global.GamePhase.CARD_PLAY
			await _frames(2)
		var stop := wolf.global_position
		await _frames(12)
		check(wolf.global_position == stop and enemy.current_health == 1000 and not wolf.skill_manager.is_casting and not wolf.skill_manager.is_forced_moving, "%s打断扑击：停止位移、取消伤害并恢复动作锁" % reason)
		check(not wolf.get_node("CollisionShape2D").disabled and wolf.skill_manager.get_cooldown_left(five) > 6.0, "%s打断后碰撞恢复且保留冷却" % reason)
		await _reset()


func _wall_and_range() -> void:
	var wolf := _unit("were_wolf", Vector2(600, 500))
	var enemy := _unit("orc", Vector2(951, 500))
	var five := _five(wolf)
	_cast(wolf, enemy, five)
	check(not wolf.skill_manager.is_casting and wolf.global_position == Vector2(600, 500), "超过基础350距离不能直接扑击")
	enemy.global_position = Vector2(900, 500)
	var wall := StaticBody2D.new()
	wall.position = Vector2(750, 500)
	wall.collision_layer = 4
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 400)
	shape.shape = rectangle
	wall.add_child(shape)
	arena.add_child(wall)
	await _frames(2)
	check(five.find_landing_position(wolf, enemy) == null, "完整身体扫描阻止隔墙扑击，不继承旧传送穿墙")
	_cast(wolf, enemy, five)
	await _frames(25)
	check(not wolf.skill_manager.is_casting and wolf.global_position == Vector2(600, 500) and enemy.current_health == 1000, "路径封锁时安全收尾，不穿墙或造成远程斩击")
	wall.queue_free()
	await _reset()
