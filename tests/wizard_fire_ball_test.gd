# 这玩意儿是干嘛的（核心逻辑）：验证巫师的火球飞到敌人时才播放命中特效。
# 数据是咋流动的（数据流向）：真实施法动画 → 火球投射物 → 目标受伤 → 特效出现并清理。
# 为啥这么写（选型决策）：使用真实场景和飞行过程，能发现技能资源没有传给投射物的问题。
# 性能咋样（复杂度）：仅回归测试运行，最多等待 180 帧命中。
extends Node2D

var created_effect: AnimatedSprite2D

# 作用：Godot 把测试加入场景时开始监听新特效；没有参数，没有返回值。
func _ready() -> void:
	child_entered_tree.connect(_on_child_entered_tree)
	_run.call_deferred()

# 作用：记录 child 中的火球命中特效；没有返回值。
func _on_child_entered_tree(child: Node) -> void:
	if child is AnimatedSprite2D and child.name == "WizardFireBallEffect":
		created_effect = child

# 作用：测试实际命中时机、伤害和特效清理；没有参数，没有返回值。
func _run() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var wizard: UnitBase = load("res://scenes/units/wizard.tscn").instantiate()
	var victim: UnitBase = load("res://scenes/units/orc.tscn").instantiate()
	add_child(wizard)
	add_child(victim)
	wizard.set_physics_process(false)
	victim.set_physics_process(false)
	wizard.global_position = Vector2(300, 400)
	victim.global_position = Vector2(550, 400)
	victim.unit_data.max_hp = 10000
	victim.current_health = 10000
	victim.unit_data.dodge_skill = null
	var skill: SkillBase = wizard.unit_data.skills[0]
	assert(skill.on_hit_effect != null)
	wizard.skill_manager.current_skill = skill
	wizard.skill_manager.current_target = victim
	wizard.switch_state(UnitBase.State.ATTACK)
	wizard.skill_manager.attack()
	assert(wizard.skill_manager.is_chanting, "火球先咏唱0.5秒")
	for frame in 31:
		await get_tree().physics_frame
	wizard.animated_sprite_2d.frame = skill.hit_frame[0]
	assert(created_effect == null, "火球离开法师时还未命中，不能提前播放特效")
	for frame in 180:
		await get_tree().process_frame
		if is_instance_valid(created_effect):
			break
	assert(is_instance_valid(created_effect), "火球命中时应创建 wizard_fire_ball_effect")
	assert(created_effect.animation == &"effect" and created_effect.is_playing())
	assert(created_effect.global_position.is_equal_approx(victim.global_position), "特效应出现在受击位置")
	assert(victim.current_health < 10000, "火球命中时必须造成伤害")
	for frame in 60:
		await get_tree().process_frame
	assert(not is_instance_valid(created_effect), "特效播完后应自动清理")
	print("WIZARD_FIRE_BALL_PASS")
	get_tree().quit()
