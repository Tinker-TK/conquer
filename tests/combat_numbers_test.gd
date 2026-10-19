# 验证真实结算入口、延迟投射物、暂停和退场，不改变战斗随机序列。
extends Node2D

var checks := 0
var failures: Array[String] = []
var numbers: CombatNumbers
var ally: UnitBase
var enemy: UnitBase


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _unit(scene: String, at: Vector2, container: Node = self) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene).instantiate()
	container.add_child(unit)
	unit.global_position = at
	unit.set_physics_process(false)
	unit.skill_manager.set_physics_process(false)
	unit.status_runtime.set_physics_process(false)
	unit.unit_data.max_hp = 100
	unit.current_health = 100
	unit.unit_data.attack = 20
	unit.unit_data.defence = 3
	unit.unit_data.dodge_skill = null
	unit.get_node("HealthBar").setup(100)
	return unit


func _last() -> Label:
	return numbers._entries.back().label


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	if "--combat-numbers-preview" in OS.get_cmdline_user_args():
		await _preview()
		get_tree().quit()
		return
	ally = _unit("archer", Vector2(600, 500))
	enemy = _unit("orc", Vector2(950, 500))
	var basic: SkillBase = load("res://data/skills/normal_attack.tres")
	basic.execute(ally, enemy)
	numbers = get_node("CombatNumbers")
	check(_last().text == "17" and _last().get_meta("kind") == &"normal", "普攻显示扣防后的实际白色伤害")
	check(_last().get_theme_color("font_color") == Color.WHITE, "普攻使用纯白色")
	check(_last().mouse_filter == Control.MOUSE_FILTER_IGNORE, "数字不挡鼠标和卡牌操作")
	check(numbers.get_parent() == self and numbers.z_index > enemy.z_index, "数字挂战场并覆盖单位和特效")
	var old_basic: SkillBase = load("res://data/skills/orc_attack.tres")
	check(old_basic.combat_number_kind() == &"normal", "未保存普攻标记的旧近战资源仍显示白字")
	var special: SkillBase = load("res://data/skills/elite_orc_power_attack.tres")
	special.execute(ally, enemy)
	check(_last().text == "37" and _last().get_meta("kind") == &"skill", "特殊技能使用金色且沿用伤害结算")
	check(_last().get_theme_color("font_color") == Color("ffcd62"), "技能使用金色")
	numbers.clear()
	enemy.current_health = 100
	enemy.add_shield(10)
	check(_last().text == "+10" and _last().get_meta("kind") == &"shield", "增加护盾显示蓝色加号数值")
	numbers.clear()
	enemy.get_hurt(15, ally, false, &"", 1, true)
	check(enemy.current_health == 95 and enemy.shield_amount == 0 and _last().text == "15", "护盾与生命实际扣除合成一条伤害，不重复或显示0")
	numbers.clear()
	enemy.receive_healing(14, ally, true)
	check(numbers._entries.size() == 2, "溢出治疗分别显示回血和新增护盾")
	var healing: Label = numbers._entries[0].label
	var shield: Label = numbers._entries[1].label
	check(healing.text == "+5" and healing.get_meta("kind") == &"heal", "绿色回血只显示实际恢复的5点")
	check(shield.text == "+9" and shield.get_meta("kind") == &"shield", "蓝色护盾只显示溢出的9点")
	check(not Rect2(healing.position - healing.size * 0.1, healing.size * 1.2).intersects(Rect2(shield.position - shield.size * 0.1, shield.size * 1.2)), "同帧回血和护盾放大后也不重叠")
	check(not enemy.get_heal(10, ally) and numbers._entries.size() == 2, "满血无效治疗不冒加血数字")
	enemy.apply_status(&"mortal_wounds", 2.0, 0, ally)
	check(not enemy.receive_healing(10, ally, true) and numbers._entries.size() == 2, "禁疗不会显示虚假的回血或护盾")
	enemy.remove_status(&"mortal_wounds")
	enemy.clear_shield()
	numbers.clear()
	enemy.current_health = 100
	enemy.apply_status(&"bleed", 2.0, 4, ally)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	enemy.status_runtime._physics_process(1.0)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	check(_last().text == "4" and _last().get_meta("kind") == &"bleed", "真实流血结算使用红字")
	enemy.remove_status(&"bleed")
	var count := numbers._entries.size()
	check(not enemy.get_hurt(20, enemy) and numbers._entries.size() == count, "友军拒绝命中不生成数字")
	check(CombatNumbers.show_number(enemy, 0) == null and numbers._entries.size() == count, "零变化不生成数字")
	await _projectiles()
	numbers.clear()
	seed(83242)
	var expected := randi()
	seed(83242)
	CombatNumbers.show_number(enemy, 9, &"poison")
	check(randi() == expected, "错位和动画不消耗战斗全局随机数")
	var label := _last()
	await _frames(12)
	var before := label.position
	var age: float = numbers._entries.back().age
	get_tree().paused = true
	await _frames(8)
	check(label.position == before and is_equal_approx(numbers._entries.back().age, age), "暂停冻结跳字位置和生命周期")
	get_tree().paused = false
	Engine.time_scale = 3.0
	numbers._physics_process(0.1)
	check(is_equal_approx(numbers._entries.back().age, age + 0.1), "固定物理步不重复乘战斗倍速")
	Engine.time_scale = 1.0
	check(label.position.y < before.y, "数字向上漂浮")
	numbers.clear()
	enemy.current_health = 3
	enemy.take_effect_damage(999, ally, &"true_damage")
	label = _last()
	check(label.text == "3" and enemy.current_state == UnitBase.State.DEATH, "致死显示实际损失，排除溢出伤害")
	enemy.queue_free()
	await _frames(1)
	check(is_instance_valid(label) and not numbers._entries.is_empty(), "单位释放后最后一击仍继续显示")
	await _frames(65)
	check(numbers._entries.is_empty() and not numbers.is_physics_processing(), "播放结束释放数字并停止空闲处理")
	for index in CombatNumbers.MAX_NUMBERS + 10:
		CombatNumbers.show_number(ally, 1)
	check(numbers._entries.size() == CombatNumbers.MAX_NUMBERS, "密集战斗有活动数字上限")
	numbers.clear()
	print("COMBAT_NUMBERS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _projectiles() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var arrow: SkillBase = load("res://data/skills/archer_arrow_attack.tres").duplicate()
	var power: SkillBase = load("res://data/skills/archer_power_shoot.tres").duplicate()
	check(arrow.combat_number_kind() == &"normal" and power.combat_number_kind() == &"skill", "普通射击和穿刺技能按来源区分")
	for skill: SkillBase in [arrow, power]:
		numbers.clear()
		enemy.current_health = 100
		skill.execute(ally, enemy)
		var projectile: Projectile
		for child in get_children():
			if child is Projectile:
				projectile = child
		check(projectile != null and projectile.damage_kind == skill.combat_number_kind(), "投射物在发射时保存伤害来源")
		if projectile == null:
			continue
		projectile.set_physics_process(false)
		ally.skill_manager.current_skill = power if skill == arrow else arrow
		projectile._deal_damage()
		check(_last().get_meta("kind") == skill.combat_number_kind(), "攻击者改放另一技能不改变在途弹命中颜色")
		await get_tree().process_frame
	Global.game_phase = Global.GamePhase.CARD_PLAY


func _preview() -> void:
	RunManager.start_new_run()
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	add_child(battle)
	get_tree().current_scene = self
	var samples: Array[UnitBase] = []
	var names := ["普攻", "技能", "流血", "中毒", "火焰", "回血", "增加护盾"]
	for index in 7:
		var unit := _unit("orc" if index < 5 else "soldier", Vector2(450 + index * 170, 520), battle.get_node("Entities/TeamB" if index < 5 else "Entities/TeamA"))
		samples.append(unit)
		var caption := Label.new()
		caption.text = names[index]
		caption.add_theme_font_size_override("font_size", 24)
		caption.add_theme_color_override("font_outline_color", Color("182131"))
		caption.add_theme_constant_override("outline_size", 6)
		caption.position = battle.to_local(unit.global_position) + Vector2(-70, 80)
		caption.size = Vector2(140, 40)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		battle.add_child(caption)
	await _frames(65)
	var kinds := [&"normal", &"skill", &"bleed", &"poison", &"burn"]
	for index in 5:
		samples[index].take_effect_damage(12 + index * 7, null, kinds[index])
	samples[5].current_health = 40
	samples[5].get_heal(36)
	samples[6].add_shield(48)
	await _frames(12)
	await _capture("colors")
	for index in 3:
		samples[0].get_hurt(8 + index, null, false, &"", -1, true)
		await _frames(5)
	samples[5].receive_healing(45, null, true)
	await _frames(6)
	await _capture("combo-overflow")


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/combat-numbers")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/combat-numbers/%s.png" % filename)
