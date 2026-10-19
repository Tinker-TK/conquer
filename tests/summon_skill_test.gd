# 这玩意儿是干嘛的（核心逻辑）：验证死灵法师从动作到魔法阵再到骷髅的完整流程。
# 数据是咋流动的（数据流向）：真实战场与角色 → 动画帧 → 特效完成 → 单位位置和战场登记检查。
# 为啥这么写（选型决策）：使用真实场景与动画完成信号检查容器，避免帧率影响固定帧等待。
# 性能咋样（复杂度）：仅在手动测试时运行，正常游戏不加载。
extends Node

var spawned_positions: Dictionary = {}


# 作用：Godot 入树后延迟启动测试；没有参数，没有返回值。
func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


# 作用：运行召唤时序、死亡与阶段中断检查；没有参数，没有返回值。
func _run() -> void:
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 冻结其它单位，保证断言只观察本次召唤造成的变化。
	for unit in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	var team: Node2D = battle.get_node("Entities/TeamB")
	team.child_entered_tree.connect(_freeze_created_unit)
	var caster: UnitBase = load("res://scenes/units/necromancer.tscn").instantiate()
	caster.position = team.to_local(Vector2(1000, 500))
	team.add_child(caster)
	caster.set_physics_process(false)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var manager = caster.skill_manager
	var skill: SkillBase = caster.unit_data.skills[0]
	assert(manager.pick_skill() and manager.current_skill == skill, "召唤必须优先于普攻")
	caster.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	assert(caster.animated_sprite_2d.animation == &"summon")
	# 自身是召唤目标，战斗每帧检查也不能把死灵法师转向右边。
	caster.animated_sprite_2d.flip_h = true
	manager.check_attack()
	assert(caster.animated_sprite_2d.flip_h, "召唤期间应保留原来的朝向")
	var before := team.get_child_count()
	assert(_find_effect(team) == null, "动作开始时不能提前生成魔法阵")
	# 手动推进真实精灵的帧，验证场景信号确实通向技能管理器。
	caster.animated_sprite_2d.frame = 5
	var effect := _find_effect(team)
	assert(effect != null, "第六帧必须出现魔法阵")
	var point: Vector2 = caster.get_node("SummonPoint").global_position
	assert(effect.global_position.is_equal_approx(point))
	assert(team.get_child_count() == before + 1, "此时只有魔法阵，还没有骷髅")
	# 移动施法者后，魔法阵仍要留在原来的世界坐标。
	caster.position += Vector2(30, 40)
	await effect.animation_finished
	await get_tree().process_frame
	assert(not is_instance_valid(effect), "动画播完必须清除魔法阵")
	var summon_scene := skill.get("summon_scene") as PackedScene
	var summoned: UnitBase
	for child in team.get_children():
		if child.scene_file_path == summon_scene.resource_path:
			summoned = child
	assert(summoned != null, "特效完成后必须生成技能当前配置的怪物")
	var initial_position: Vector2 = spawned_positions[summoned.get_instance_id()]
	assert(initial_position.is_equal_approx(point), "怪物必须出现在固定的魔法阵落点")
	assert(summoned.is_in_group("team_b") and battle.card_runtime.states.has(summoned.get_instance_id()))
	assert(not manager.is_casting, "召唤动作结束必须解除施法锁")
	assert(manager.get_cooldown_left(skill) > 0.0, "召唤必须消耗冷却")
	summoned.set_physics_process(false)
	# 强化攻击资源使用 green_bombing 动画，检查命中后真实特效可见且能清理。
	var victim: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	battle.get_node("Entities/TeamA").add_child(victim)
	victim.set_physics_process(false)
	victim.position = caster.position + Vector2(-80, 0)
	var power: SkillBase = caster.unit_data.skills[2]
	manager.current_skill = power
	manager.current_target = victim
	caster.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	var victim_health: int = victim.current_health
	caster.animated_sprite_2d.frame = power.hit_frame[0]
	var hit_effect := team.get_node_or_null("HurtEffect") as AnimatedSprite2D
	assert(victim.current_health < victim_health, "强化攻击的命中帧应造成伤害")
	assert(hit_effect != null and hit_effect.animation == &"green_bombing" and hit_effect.is_playing(), "强化攻击应播放 green_bombing 命中特效")
	await hit_effect.animation_finished
	await get_tree().process_frame
	assert(not is_instance_valid(hit_effect), "命中特效播完应清理")

	# 回合切换立刻取消，重新进入战斗也不能让旧魔法阵补出骷髅。
	skill.execute(caster)
	effect = _find_effect(team)
	assert(effect != null)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not is_instance_valid(effect))
	assert(team.get_child_count() == before + 1)

	# 召唤师死亡时立即取消，不能等到尸体移除才让魔法阵失效。
	skill.execute(caster)
	effect = _find_effect(team)
	assert(effect != null)
	caster.die()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not is_instance_valid(effect))
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle.queue_free()
	await get_tree().process_frame
	print("SUMMON_SKILL_TEST_OK")
	get_tree().quit()


# 作用：查找本次测试中的魔法阵；team 是队伍容器，返回特效或空。
func _find_effect(team: Node) -> AnimatedSprite2D:
	for child in team.get_children():
		if child is AnimatedSprite2D and child.has_method("configure"):
			return child
	return null


# 作用：新单位入树时冻结自主移动，避免生成坐标被后续寻路改变；unit 是新节点，没有返回值。
func _freeze_created_unit(unit: Node) -> void:
	if unit is UnitBase:
		spawned_positions[unit.get_instance_id()] = unit.global_position
		unit.set_physics_process(false)
