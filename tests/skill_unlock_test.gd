# 真实出牌、训练和命中验证强化等级精确匹配，旧技能替换、预览与反击共用同一规则。
extends Node

var battle: Node2D
var hand: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _recruit(card: CardInstance) -> UnitBase:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	hand.draw_pile.erase(card)
	hand.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, Vector2(450, 450)), "真实出牌生成单位")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _wait_cast(unit: UnitBase) -> void:
	for frame in 240:
		await get_tree().physics_frame
		if not unit.skill_manager.is_casting and not unit.skill_manager.is_reacting:
			break
	check(not unit.skill_manager.is_casting and not unit.skill_manager.is_reacting, "技能动画正常结束")


func _run() -> void:
	var source := load("res://data/units/soldier.tres").duplicate() as UnitData
	source.max_upgrade_count = 3
	source.skills = []
	var active_levels := [[0], [0, 1], [1], [2]]
	var expected := [[0, 1], [1, 2], [3], []]
	for index in active_levels.size():
		var skill := load("res://data/skills/normal_attack.tres").duplicate() as SkillBase
		skill.skill_name = "生效等级 %s 技能" % str(active_levels[index])
		skill.unlock_upgrade_levels.assign(active_levels[index])
		skill.priority = index * 10
		skill.attack_rate = float(index + 1)
		skill.on_hit_effect = null
		source.skills.append(skill)
	var start := RunStartData.new()
	start.cards.assign([source, source, source, source])
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "技能测试导航已同步")
	hand = battle.hand_manager
	battle.card_runtime.set_process(false)
	var units: Array[UnitBase] = []
	var inspector = load("res://scripts/ui/unit_inspector.gd").new()
	inspector.battle = battle
	get_tree().root.add_child(inspector)
	var preview_source := Control.new()
	get_tree().root.add_child(preview_source)
	for level in 4:
		var card: CardInstance = RunManager.deck[level]
		for training in level:
			check(card.train(source.upgrade_ability_points, 0), "通过正式训练达到强化等级 %d" % level)
		var preview := card.get_summon_data()
		var expected_skills: Array[SkillBase] = []
		for index in expected[level]:
			expected_skills.append(source.skills[index])
		check(preview.card_upgrade_level == level and preview.skills == expected_skills, "强化 %d 次的卡牌预览精确匹配配置等级" % level)
		inspector.open_card(card, preview_source)
		check(inspector.skill_cells.map(func(cell): return cell.skill) == expected_skills, "强化 %d 次的卡牌详情不显示已经失效的技能" % level)
		var unit := _recruit(card)
		units.append(unit)
		check(unit.unit_data.card_upgrade_level == level, "入树复制属性后保留原牌强化等级")
		check(unit.skill_manager.group_skills.size() == expected_skills.size() and expected_skills.all(func(skill): return unit.skill_manager.group_skills.has(skill)), "单位实际技能包符合强化等级")
		check(unit.skill_manager._skill_time_cd.size() == expected_skills.size(), "失效技能不创建冷却计时器")
		inspector.open_unit(unit)
		check(inspector.skill_cells.size() == expected_skills.size(), "真实单位详情同步当前生效的技能")
	check(source.skills.size() == 4 and source.card_upgrade_level == 0, "共享单位配置不被过滤或写入强化次数")
	check(RunManager.deck[0].get_summon_data().skills.size() == 2, "强化其它同名牌不改变未强化原牌的技能")
	check(RunManager.deck[2].upgrade_summary().contains(source.skills[3].skill_name) and not RunManager.deck[2].upgrade_summary().contains(source.skills[1].skill_name), "卡牌强化说明只显示当前生效技能")
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	enemy.position = Vector2(480, 450)
	battle.get_node("Entities/TeamB").add_child(enemy)
	# TeamB 有场景偏移；使用全局位置，确保本用例实际验证近战技能命中。
	enemy.global_position = units[0].global_position + Vector2(30, 0)
	enemy.set_physics_process(false)
	enemy.unit_data.dodge_skill = null
	enemy.unit_data.defence = 0
	enemy.unit_data.max_hp = 10000
	enemy.current_health = 10000
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for level in 4:
		var unit := units[level]
		var unit_manager := unit.skill_manager
		if expected[level].is_empty():
			check(not unit_manager.pick_skill() and unit_manager.current_skill == null, "离开全部配置等级后不会补回默认普通攻击")
			continue
		check(unit_manager.pick_skill(), "已解锁技能能选择合法敌人")
		check(unit_manager.current_skill == source.skills[expected[level].back()], "仅在当前生效技能中按优先级选择")
		unit_manager.current_target = enemy
		var skill: SkillBase = unit_manager.current_skill
		var health_before: int = enemy.current_health
		unit.switch_state(UnitBase.State.ATTACK)
		unit_manager.attack()
		await _wait_cast(unit)
		check(health_before - enemy.current_health == int(unit.unit_data.attack * skill.attack_rate), "强化等级 %d 的真实命中使用对应技能倍率" % level)
	var manager := units[0].skill_manager
	var before: int = enemy.current_health
	manager.fire_projectile(source.skills[3])
	check(enemy.current_health == before, "未解锁技能不能通过命中入口结算伤害")
	manager.current_skill = source.skills[3]
	manager.current_target = enemy
	manager.attack()
	check(not manager.is_casting and manager.current_skill == null, "未解锁技能不能绕过选择流程开始施法")
	# 直接从场景生成的单位没有原牌强化，也只能使用等级 0 技能。
	var direct := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	direct.unit_data = source
	battle.get_node("Entities/TeamA").add_child(direct)
	direct.set_physics_process(false)
	check(direct.skill_manager.group_skills.size() == 2, "直接生成或召唤的未强化单位使用包含等级0的技能")
	var copied := battle.card_runtime._prepare_unit(units[2].unit_data.duplicate()) as UnitBase
	battle.get_node("Entities/TeamA").add_child(copied)
	copied.set_physics_process(false)
	check(copied.unit_data.card_upgrade_level == 2 and copied.skill_manager.group_skills.size() == 1, "复制已强化单位保留强化等级和当前技能")
	# 已被替换的技能即使通过直接施法/命中入口调用，也不能再生效。
	before = enemy.current_health
	units[1].skill_manager.fire_projectile(source.skills[0])
	units[1].skill_manager.current_skill = source.skills[0]
	units[1].skill_manager.current_target = enemy
	units[1].skill_manager.attack()
	check(enemy.current_health == before and not units[1].skill_manager.is_casting, "[0]技能强化一次后不能绕过限制重新施放")
	units[2].skill_manager.fire_projectile(source.skills[1])
	check(enemy.current_health == before, "[0,1]技能强化两次后不能结算伤害")
	# 防守反击既不能使未解锁单位闪避，也不能通过直接反击入口绕过限制。
	var knight_data := load("res://data/units/knight.tres").duplicate(true) as UnitData
	knight_data.max_upgrade_count = 2
	knight_data.dodge_rate = 1.0
	knight_data.dodge_skill.unlock_upgrade_levels = [1]
	var locked_knight := load("res://scenes/units/knight.tscn").instantiate() as UnitBase
	locked_knight.unit_data = knight_data
	battle.get_node("Entities/TeamA").add_child(locked_knight)
	locked_knight.set_physics_process(false)
	before = locked_knight.current_health
	check(locked_knight.get_hurt(20, enemy) and locked_knight.current_health < before, "未解锁防守反击不触发闪避")
	locked_knight.skill_manager.start_reaction(knight_data.dodge_skill, enemy)
	check(not locked_knight.skill_manager.is_reacting, "未解锁反击不能通过直接入口触发")
	var knight_card := CardInstance.new(knight_data)
	check(knight_card.get_summon_data().dodge_skill == null, "未强化卡牌预览不包含锁定反击")
	check(knight_card.train(knight_data.upgrade_ability_points, 0), "骑士卡训练一次")
	var knight := _recruit(knight_card)
	enemy.global_position = knight.global_position + Vector2(30, 0)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	before = knight.current_health
	check(not knight.get_hurt(20, enemy) and knight.current_health == before, "强化后解锁防守反击并正常闪避")
	check(knight.skill_manager.is_reacting, "已解锁反击播放实际防守动画")
	before = enemy.current_health
	await _wait_cast(knight)
	check(enemy.current_health < before, "已解锁反击实际命中敌人")
	check(knight_card.train(knight_data.upgrade_ability_points, 0), "骑士卡训练第二次")
	check(knight_card.get_summon_data().dodge_skill == null, "[1]反击技能强化两次后从卡牌预览移除")
	var knight_second := _recruit(knight_card)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	before = knight_second.current_health
	check(knight_second.get_hurt(20, enemy) and knight_second.current_health < before, "离开反击生效等级后不会继续闪避")
	knight_second.skill_manager.start_reaction(knight_data.dodge_skill, enemy)
	check(not knight_second.skill_manager.is_reacting, "离开反击等级后不能通过直接入口反击")
	# 非连续数组和空数组也精确匹配，并通过真正的资源保存/回读保持配置。
	var persistent := source.skills[0].duplicate() as SkillBase
	persistent.unlock_upgrade_levels = [0, 2]
	check(persistent.is_active_at_upgrade_level(0) and not persistent.is_active_at_upgrade_level(1) and persistent.is_active_at_upgrade_level(2) and not persistent.is_active_at_upgrade_level(3), "非连续数组只在列出的等级生效")
	var path := "user://skill_level_array.tres"
	check(ResourceSaver.save(persistent, path) == OK, "强化数组可以保存到技能资源")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SkillBase
	check(restored != null and restored.unlock_upgrade_levels == [0, 2] and not restored.is_active_at_upgrade_level(1), "资源回读保留等级数组及精确匹配规则")
	persistent.unlock_upgrade_levels = []
	check(not persistent.is_active_at_upgrade_level(0) and not persistent.is_active_at_upgrade_level(1), "空数组在任何等级都不生效")
	check(source.skills[0].unlock_upgrade_levels == [0], "编辑副本的数组不会修改其它技能")
	var legacy := '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://scripts/skills/normal_attack.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nunlock_upgrade_level = 1\n'
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(legacy)
	file.close()
	restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SkillBase
	check(restored != null and not restored.is_active_at_upgrade_level(0) and restored.is_active_at_upgrade_level(1) and restored.is_active_at_upgrade_level(2), "旧存档的整数技能配置可回读并保留原有语义")
	DirAccess.remove_absolute(path)
	inspector.queue_free()
	preview_source.queue_free()
	battle.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("SKILL_UNLOCK_PASS: %d checks" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)
