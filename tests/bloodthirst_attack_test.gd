# 这玩意儿是干嘛的（核心逻辑）：验证嗜血攻击只回复真实伤害，并验证蝙蝠的动画帧能够触发。
# 数据是咋流动的（数据流向）：真实场景与技能资源 → 攻击结算 → 检查双方生命和施法配置。
# 为啥这么写（选型决策）：同时检查防御、闪避、溢出和满血，避免吸血按面板攻击力错误计算。
# 性能咋样（复杂度）：仅手动回归时运行，不参与游戏。
extends Node2D


# 作用：Godot 入树后延迟执行测试；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：实例化一个静止单位；path 为场景路径，返回已初始化的单位。
func _unit(path: String) -> UnitBase:
	var unit: UnitBase = load(path).instantiate()
	add_child(unit)
	unit.set_physics_process(false)
	unit.unit_data.max_hp = 100
	unit.current_health = 100
	unit.unit_data.dodge_skill = null
	return unit


# 作用：执行伤害回血及蝙蝠动画集成检查；没有参数，没有返回值。
func _run() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	var caster := _unit("res://scenes/units/orc.tscn")
	var target := _unit("res://scenes/units/soldier.tscn")
	var skill: SkillBase = load("res://data/skills/bloodthirst_attack.tres").duplicate()
	caster.unit_data.attack = 25
	caster.current_health = 40
	target.unit_data.defence = 5
	skill.execute(caster, target)
	assert(target.current_health == 80 and caster.current_health == 60, "扣防御后造成 20 伤害，只回复 20")
	caster.current_health = 95
	skill.execute(caster, target)
	assert(caster.current_health == 100, "回复不能超过最大生命")
	# 用空技能保证闪避判定发生，又不让反击动画干扰测试。
	target.unit_data.dodge_skill = SkillBase.new()
	target.unit_data.dodge_rate = 1.0
	caster.current_health = 40
	skill.execute(caster, target)
	assert(target.current_health == 60 and caster.current_health == 40, "闪避不扣血也不回血")
	target.unit_data.dodge_skill = null
	skill.attack_rate = 0
	skill.execute(caster, target)
	assert(target.current_health == 60 and caster.current_health == 40, "零倍率不造成伤害或治疗")
	skill.attack_rate = 1
	target.current_health = 3
	skill.execute(caster, target)
	assert(target.current_state == UnitBase.State.DEATH and caster.current_health == 43, "击杀只回复剩余 3 血")
	skill.execute(caster, target)
	assert(caster.current_health == 43, "尸体不能继续吸血")
	skill.execute(caster, null)
	skill.execute(caster, caster)
	assert(caster.current_health == 43)

	# 从真实蝙蝠技能列表选择，手动推进动画帧，确认不是只改了资源名字。
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var bat := _unit("res://scenes/units/bat.tscn")
	var victim := _unit("res://scenes/units/soldier.tscn")
	victim.unit_data.defence = 5
	bat.unit_data.attack = 10
	bat.current_health = 40
	var bat_skill: SkillBase = bat.unit_data.skills[1]
	# 策划可以调整技能倍率；按当前配置检查真实伤害与等量回血，不把旧数值写死。
	var bat_damage := maxi(int(bat.unit_data.attack * bat_skill.attack_rate) - victim.unit_data.defence, 1)
	assert(bat_skill.get_script() == skill.get_script())
	assert(bat.skill_manager.pick_skill() and bat.skill_manager.current_skill == bat_skill)
	bat.skill_manager.current_target = victim
	bat.switch_state(UnitBase.State.ATTACK)
	bat.skill_manager.attack()
	bat.animated_sprite_2d.frame = bat_skill.hit_frame[0]
	assert(victim.current_health == 100 - bat_damage and bat.current_health == 40 + bat_damage, "蝙蝠动画命中帧必须造成伤害并回血")
	# 已死亡的攻击者不能继续打人，也不能被嗜血复活。
	bat.current_state = UnitBase.State.DEATH
	bat_skill.execute(bat, victim)
	assert(victim.current_health == 100 - bat_damage and bat.current_health == 40 + bat_damage)
	queue_free()
	print("BLOODTHIRST_ATTACK_PASS")
	get_tree().quit()
