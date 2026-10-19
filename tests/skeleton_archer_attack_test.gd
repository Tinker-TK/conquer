# 这玩意儿是干嘛的（核心逻辑）：验证骷髅弓箭手完成攻击动作时真的射出箭。
# 数据是咋流动的（数据流向）：真实攻击动画 → 第六帧信号 → 箭矢生成 → 敌人受伤。
# 为啥这么写（选型决策）：播放完整动画能发现单位场景漏接帧变化信号。
# 性能咋样（复杂度）：只在回归测试里等待最多 180 帧，不影响游戏。
extends Node2D

var fired_arrow: Projectile

# 作用：Godot 加入测试场景时监听箭矢；没有参数，没有返回值。
func _ready() -> void:
	child_entered_tree.connect(_on_child_entered_tree)
	_run.call_deferred()

# 作用：记录新加入的 child 是否是箭矢；没有返回值。
func _on_child_entered_tree(child: Node) -> void:
	if child is Projectile:
		fired_arrow = child

# 作用：检查攻击动画是否发箭并命中；没有参数，没有返回值。
func _run() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var archer: UnitBase = load("res://scenes/units/skeleton_archer.tscn").instantiate()
	var victim: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	add_child(archer)
	add_child(victim)
	archer.set_physics_process(false)
	victim.set_physics_process(false)
	archer.global_position = Vector2(500, 400)
	victim.global_position = Vector2(250, 400)
	archer.animated_sprite_2d.flip_h = true
	victim.unit_data.max_hp = 10000
	victim.current_health = 10000
	victim.unit_data.dodge_skill = null
	var skill: SkillBase = archer.unit_data.skills[0]
	assert(archer.animated_sprite_2d.sprite_frames.get_frame_count(skill.cast_animation) > skill.hit_frame[0])
	archer.skill_manager.current_skill = skill
	archer.skill_manager.current_target = victim
	archer.switch_state(UnitBase.State.ATTACK)
	archer.skill_manager.attack()
	# 让 Godot 自然播放动画，避免手动跳帧掩盖信号断线。
	for frame in 180:
		await get_tree().process_frame
		if is_instance_valid(fired_arrow):
			break
	assert(is_instance_valid(fired_arrow), "攻击动作到命中帧时应射出箭矢")
	assert(fired_arrow.get_node_or_null("Sprite2D") != null, "箭矢必须可见")
	for frame in 180:
		await get_tree().process_frame
		if victim.current_health < 10000:
			break
	assert(victim.current_health < 10000, "箭矢飞到目标后应造成伤害")
	print("SKELETON_ARCHER_ATTACK_PASS")
	get_tree().quit()
