# 这玩意儿是干嘛的（核心逻辑）：验证最低血量和最低生命比例能够选出不同敌人。
# 数据是咋流动的（数据流向）：真实单位场景与测试血量 → 技能管理器索敌 → 检查目标。
# 为啥这么写（选型决策）：同时覆盖阵营、死亡、同值择近和旧基地不可索敌，避免只验证枚举名称。
# 性能咋样（复杂度）：手动运行一次，不进入正式游戏。
extends Node2D


# 作用：Godot 初始化测试时启动检查；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：创建静止测试单位；ally 表示己方，hp/max_hp 为生命值，point 为位置，返回单位。
func _unit(ally: bool, hp: int, max_hp: int, point: Vector2) -> UnitBase:
	var path := "res://scenes/units/soldier.tscn" if ally else "res://scenes/units/orc.tscn"
	var unit: UnitBase = load(path).instantiate()
	unit.position = point
	add_child(unit)
	unit.set_physics_process(false)
	unit.unit_data.max_hp = max_hp
	unit.current_health = hp
	return unit


# 作用：检查新索敌规则和原枚举兼容性；没有参数，没有返回值。
func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var serialized_target_types: Array[int] = [SkillBase.TargetType.ENEMY_NEAREST, SkillBase.TargetType.ALLY_LOWEST_HP, SkillBase.TargetType.SELF]
	assert(serialized_target_types == [0, 1, 2])
	var caster := _unit(true, 100, 100, Vector2.ZERO)
	var low_hp := _unit(false, 20, 100, Vector2(200, 0))
	var low_percent := _unit(false, 30, 300, Vector2(80, 0))
	var skill := SkillBase.new()
	skill.target_type = SkillBase.TargetType.ENEMY_LOWEST_HP
	assert(caster.skill_manager.find_target_for_skill(skill) == low_hp)
	skill.target_type = SkillBase.TargetType.ENEMY_LOWEST_HP_PERCENT
	assert(caster.skill_manager.find_target_for_skill(skill) == low_percent)
	# 同值时选近处；满血单位也不能导致攻击技能无目标。
	low_percent.current_health = 20
	low_percent.unit_data.max_hp = 100
	assert(caster.skill_manager.find_lowest_health_enemy(false) == low_percent)
	assert(caster.skill_manager.find_lowest_health_enemy(true) == low_percent)
	low_hp.current_health = 100
	low_percent.current_health = 100
	assert(caster.skill_manager.find_lowest_health_enemy(true) == low_percent)
	# 死亡、等待释放、错误分组里的普通节点和零生命都不能被选择。
	low_percent.current_state = UnitBase.State.DEATH
	assert(caster.skill_manager.find_lowest_health_enemy(false) == low_hp)
	low_percent.current_state = UnitBase.State.IDLE
	low_percent.queue_free()
	var stray := Node.new()
	add_child(stray)
	stray.add_to_group("team_b")
	assert(caster.skill_manager.find_lowest_health_enemy(false) == low_hp)
	low_hp.current_health = 0
	assert(caster.skill_manager.find_lowest_health_enemy(false) == null)
	# 旧基地测试对象永远不能成为目标，士兵全灭后返回空。
	low_hp.current_health = 50
	var base := _unit(true, 1, 100, Vector2(10, 0))
	base.add_to_group("player_base")
	assert(low_hp.skill_manager.find_lowest_health_enemy(false) == caster)
	assert(low_hp.skill_manager.find_lowest_health_enemy(true) == caster)
	caster.current_health = 0
	assert(low_hp.skill_manager.find_lowest_health_enemy(false) == null)
	assert(low_hp.skill_manager.find_lowest_health_enemy(true) == null)
	base.current_state = UnitBase.State.DEATH
	assert(low_hp.skill_manager.find_lowest_health_enemy(true) == null)
	queue_free()
	print("SKILL_TARGETING_PASS")
	get_tree().quit()
