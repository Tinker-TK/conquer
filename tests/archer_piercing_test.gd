# 正式训练与独立测试场的真实攻击动画，验证两人上限、全路径穿透和快速箭矢判定。
extends Node2D

var checks := 0
var failures: Array[String] = []
var arena: Node2D
var archer: UnitBase
var fired_arrow: Projectile
var fired_count := 0
var fired_frame := -1
var fired_animation: StringName


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _spawn(name: String, team: String, at: Vector2, level: int = 0) -> UnitBase:
	var unit: UnitBase = arena.spawn_unit(load("res://scenes/units/%s.tscn" % name), team, level)
	unit.global_position = at
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 1000
	unit.current_health = 1000
	unit.unit_data.defence = 0
	unit.unit_data.dodge_skill = null
	return unit


func _on_child_added(child: Node) -> void:
	if child is Projectile:
		fired_arrow = child
		fired_count += 1
		fired_frame = archer.animated_sprite_2d.frame
		fired_animation = archer.animated_sprite_2d.animation


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _clear() -> void:
	arena.clear_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	fired_arrow = null
	fired_count = 0


func _run() -> void:
	var source := load("res://data/units/archer.tres") as UnitData
	var normal := CardInstance.new(source)
	var trained := CardInstance.new(source)
	check(trained.train(source.upgrade_ability_points, 0), "正式训练强化弓箭手")
	check(normal.get_description().contains("最多2名") and normal.get_description().contains("造成100%"), "基础卡面说明100%伤害、最多2人")
	check(trained.get_description().contains("所有敌人") and trained.get_description().contains("120%") and not trained.get_description().contains("最多2名"), "强化卡面说明120%伤害、沿途全部敌人")
	check(normal.get_summon_data().get_unlocked_skills().size() == 2 and trained.get_summon_data().get_unlocked_skills().size() == 2, "基础与强化各装备一个穿刺技能并保留普通射击")
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	arena.child_entered_tree.connect(_on_child_added)
	await _frames(2)
	for level in [0, 1]:
		archer = _spawn("archer", "team_a", Vector2(450, 400), level)
		var victims: Array[UnitBase] = []
		# 故意反向添加：穿透上限必须按路线前后，不能按场景树中单位的创建顺序。
		for index in range(4, -1, -1):
			victims.push_front(_spawn("orc", "team_b", Vector2(650 + index * 120, 390)))
		var outside := _spawn("orc", "team_b", Vector2(800, 490))
		var ally := _spawn("soldier", "team_a", Vector2(900, 390))
		var piercing: SkillBase = archer.unit_data.get_unlocked_skills()[1]
		check(piercing.skill_name == "穿刺射击" and piercing.attack_rate == (1.0 if level == 0 else 1.2), "测试场按强化等级安装正确倍率")
		check(piercing.pierce_count == 2 and piercing.pierce_all == (level == 1), "基础限2人，强化明确启用全路径穿透")
		check(piercing.cooldown == 4.0 and piercing.cast_range == 600.0, "穿刺射击仍使用4秒冷却和600射程")
		var basic: SkillBase = archer.unit_data.get_unlocked_skills()[0]
		archer.skill_manager._skill_time_cd[basic].start(99.0)
		archer.set_physics_process(true)
		arena.start_button.pressed.emit()
		for frame in 160:
			await get_tree().physics_frame
			if is_instance_valid(fired_arrow):
				break
		check(is_instance_valid(fired_arrow) and fired_animation == &"attack_02" and fired_frame == 9, "真实自动战斗播放attack_02并在第9帧发箭")
		if is_instance_valid(fired_arrow):
			check(fired_arrow.pierce_all == (level == 1) and fired_arrow.trajectory == Projectile.Trajectory.STRAIGHT, "实际箭矢携带对应穿透模式")
		# 发射后关闭施法者自动行为，继续让真实箭矢走完路径，避免普攻混入伤害统计。
		archer.set_physics_process(false)
		await _frames(100)
		var damage := int(archer.unit_data.attack * piercing.attack_rate)
		for index in victims.size():
			var expected := damage if level == 1 or index < 2 else 0
			check(1000 - victims[index].current_health == expected, "等级%d路线第%d人伤害%d，且不重复命中" % [level, index + 1, expected])
		check(outside.current_health == 1000 and ally.current_health == 1000, "穿刺不伤路线外敌人或友军")
		check(fired_count == 1, "一轮穿刺只生成一颗真实箭矢")
		await _clear()
	# 一步跨过整排敌人时仍应按路线顺序命中；死亡和无关节点不能消耗两人上限。
	archer = _spawn("archer", "team_a", Vector2(450, 400))
	var victims: Array[UnitBase] = []
	for index in range(4, -1, -1):
		victims.push_front(_spawn("orc", "team_b", Vector2(650 + index * 120, 390)))
	var dead := _spawn("orc", "team_b", Vector2(550, 390))
	dead.current_state = UnitBase.State.DEATH
	var stray := Node2D.new()
	stray.add_to_group("team_b")
	arena.add_child(stray)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	for unlimited in [false, true]:
		for victim in victims:
			victim.current_health = 1000
		var arrow := load("res://scenes/projectiles/power_arrow.tscn").instantiate() as Projectile
		arrow.pierce_all = unlimited
		arrow.speed = 30000.0
		arena.add_child(arrow)
		arrow.set_physics_process(false)
		arrow.global_position = Vector2(450, 390)
		arrow.fire(archer, victims[0], 10, Projectile.Trajectory.STRAIGHT, 2, "team_b")
		arrow._move_straight(0.05)
		for index in victims.size():
			var expected := 10 if unlimited or index < 2 else 0
			check(1000 - victims[index].current_health == expected, "快箭整段检测：全穿透=%s，第%d名按路径顺序结算" % [unlimited, index + 1])
		if unlimited:
			arrow.global_position = victims[0].global_position
			arrow._move_straight(0.0)
			check(victims[0].current_health == 990 and arrow._hit_list.size() == 5, "全穿透每个敌人只命中一次，不因持续重叠重复扣血")
		arrow.queue_free()
		await _frames(1)
	await _clear()
	check(source.card_upgrade_level == 0 and source.get_unlocked_skills()[1].attack_rate == 1.0 and not source.get_unlocked_skills()[1].pierce_all, "训练、发射和测试不污染基础共享配置")
	print("ARCHER_PIERCING_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
