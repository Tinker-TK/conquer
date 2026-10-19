# 这玩意儿是干嘛的（核心逻辑）：复现骑士普攻中反击，并检查反击后能继续行动。
# 数据是咋流动的（数据流向）：真实单位动画 → 防守反击 → 检查伤害和施法锁。
# 为啥这么写（选型决策）：播放完整动画覆盖原先卡在最后一帧的问题，而不只手动解除状态。
# 性能咋样（复杂度）：仅回归测试运行，等待设置上限，失败不会无限挂起。
extends Node2D

# 作用：引擎创建测试后延迟开始；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()

# 作用：创建 path 对应的静止单位；返回用于控制动画的真实单位。
func _unit(path: String) -> UnitBase:
	var unit: UnitBase = load(path).instantiate()
	add_child(unit)
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 10000
	unit.current_health = 10000
	return unit

# 作用：等待 unit 反击结束；没有返回值，超过 300 帧仍未结束则测试失败。
func _wait_reaction(unit: UnitBase) -> void:
	for index in range(300):
		await get_tree().process_frame
		if not unit.skill_manager.is_reacting:
			break
	assert(not unit.skill_manager.is_reacting, "反击必须结束")
	assert(not unit.skill_manager.is_casting, "被打断的普攻不能留下施法锁")
	assert(unit.current_state == UnitBase.State.IDLE, "结束后回到待机")

# 作用：验证完整反击、无效命中帧、目标消失和战斗中断；没有参数，没有返回值。
func _run() -> void:
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var knight := _unit("res://scenes/units/knight.tscn")
	var target := _unit("res://scenes/units/orc.tscn")
	knight.set_floor(3)
	target.set_floor(1)
	target.unit_data.dodge_skill = null
	knight.unit_data.dodge_rate = 1.0
	var manager = knight.skill_manager
	var counter: SkillBase = knight.unit_data.dodge_skill.duplicate()
	knight.unit_data.dodge_skill = counter
	# 先进入真实普通攻击，再通过受击触发闪避，复现旧施法锁残留。
	var normal: SkillBase = knight.unit_data.skills[0]
	manager.current_skill = normal
	manager.current_target = target
	knight.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	assert(manager.is_casting)
	var before: int = target.current_health
	knight.get_hurt(10, target)
	assert(manager.is_reacting and not manager.is_casting)
	await _wait_reaction(knight)
	var expected := roundi(maxi(int(knight.unit_data.attack * counter.attack_rate) - target.unit_data.defence, 1) * 1.2) * counter.hit_frame.size()
	assert(before - target.current_health == expected, "跨层反击每帧仅命中一次并加20%伤害，不夹带原普攻")
	# 恢复之后再次完整播放普通攻击，证明技能可以重新发动并结束。
	manager.current_skill = normal
	manager.current_target = target
	knight.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	before = target.current_health
	for index in range(300):
		await get_tree().process_frame
		if not manager.is_casting:
			break
	assert(not manager.is_casting and target.current_health < before, "反击后可以继续攻击")
	# 即使命中帧配置超过动画长度，也应在动画结束时解锁。
	counter.hit_frame = [999]
	counter.execute(knight, target)
	await _wait_reaction(knight)
	counter.execute(knight, target)
	target.queue_free()
	await _wait_reaction(knight)
	target = _unit("res://scenes/units/orc.tscn")
	counter.execute(knight, target)
	Global.game_phase = Global.GamePhase.CARD_PLAY
	assert(not manager.is_reacting and not manager.is_casting)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	counter.execute(knight, target)
	knight.animated_sprite_2d.play("idle")
	assert(not manager.is_reacting, "外部切换动画也要解除反击锁")
	counter.execute(knight, target)
	var deaths: Array[int] = [0]
	var kills: Array[int] = [0]
	var death_finished: Array[bool] = [false]
	knight.unit_died.connect(func(_subject): deaths[0] += 1)
	knight.kill_confirmed.connect(func(_subject, _killer): kills[0] += 1)
	knight.animated_sprite_2d.animation_finished.connect(func(): death_finished[0] = true, CONNECT_ONE_SHOT)
	knight.animated_sprite_2d.sprite_frames.set_animation_loop(&"death", true)
	knight.die(target)
	assert(not manager.is_reacting and knight.current_state == UnitBase.State.DEATH)
	assert(deaths[0] == 1 and kills[0] == 1, "死亡与击杀通知不等待退场动画")
	assert(knight.animated_sprite_2d.animation == &"death" and knight.animated_sprite_2d.is_playing())
	assert(knight.animated_sprite_2d.frame == 0 and not knight.has_node("DeathSmoke"), "先从首帧播放死亡动作，不能提前起烟")
	assert(not knight.get_node("HealthBar").visible, "播放死亡动画时立即隐藏血条")
	knight.die(target)
	assert(deaths[0] == 1 and kills[0] == 1, "重复死亡不能重复通知或启动退场")
	# 真实无 death 的怪物直接使用白烟，仍保留烟遮住身体再隐藏的时序。
	var bear := _unit("res://scenes/units/bear.tscn")
	assert(not bear.animated_sprite_2d.sprite_frames.has_animation(&"death"))
	bear.die()
	assert(bear.has_node("DeathSmoke") and not bear.animated_sprite_2d.is_playing(), "没有死亡动作时立即起烟")
	assert(bear.animated_sprite_2d.visible, "烟覆盖身体前保留精灵")
	for index in range(300):
		await get_tree().process_frame
		if knight.has_node("DeathSmoke"):
			break
		assert(not death_finished[0] and knight.animated_sprite_2d.animation == &"death", "死亡动作结束前不能切回攻击或待机")
	assert(death_finished[0] and knight.has_node("DeathSmoke"), "死亡动作完整播完一次后才起烟，即使资源设置为循环")
	assert(not knight.animated_sprite_2d.is_playing(), "起烟后停在死亡动作末帧")
	var smoke := knight.get_node("DeathSmoke")
	for index in range(300):
		await get_tree().process_frame
		if not is_instance_valid(knight):
			break
		if smoke.elapsed >= 0.14:
			assert(not knight.animated_sprite_2d.visible, "白烟覆盖后隐藏身体")
	assert(not is_instance_valid(knight) and not is_instance_valid(bear), "两类怪物均在白烟结束后释放")
	print("COUNTER_ATTACK_PASS")
	get_tree().quit()
