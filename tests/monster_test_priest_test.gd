# 在真实 monster_test 中保持牧师自动行为开启，验证从选目标到动画命中的完整治疗。
extends Node

var checks := 0
var failures: Array[String] = []
var arena: Node2D


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _run() -> void:
	arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await get_tree().physics_frame
	await get_tree().physics_frame
	for level in [0, 1]:
		var priest: UnitBase = arena.spawn_unit(load("res://scenes/units/priest.tscn"), "team_a", level)
		var ally: UnitBase = arena.spawn_unit(load("res://scenes/units/soldier.tscn"), "team_a")
		var enemy: UnitBase = arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b")
		priest.global_position = Vector2(650, 500)
		ally.global_position = Vector2(850, 500)
		enemy.global_position = Vector2(1450, 800)
		ally.set_physics_process(false)
		enemy.set_physics_process(false)
		ally.current_health = 50
		var healing_seen := false
		var chant_seen := false
		var animation_seen := false
		arena.start_button.pressed.emit()
		for frame in 240:
			await get_tree().physics_frame
			chant_seen = chant_seen or priest.skill_manager.is_chanting
			animation_seen = animation_seen or priest.animated_sprite_2d.animation == &"heal_01"
			if ally.current_health > 50:
				healing_seen = true
				break
		check(chant_seen, "测试场普通/强化牧师自动开始治疗咏唱")
		check(animation_seen, "测试场咏唱完成后播放治疗动画")
		check(healing_seen, "测试场牧师全程自动行为开启时真实治疗友军")
		check(not priest.has_meta("battle_owner") and not ally.has_meta("battle_owner"), "使用没有正式战场标记的真实独立测试单位")
		ally.current_health = ally.unit_data.max_hp
		priest.current_health = 50
		var self_healed := false
		for frame in 300:
			await get_tree().physics_frame
			if priest.current_health > 50:
				self_healed = true
				break
		check(self_healed, "测试场普通与强化牧师均能自动治疗自身")
		priest.current_health = priest.unit_data.max_hp
		ally.unit_data.max_hp = 200
		ally.current_health = 200
		var heal: SkillBase = priest.unit_data.get_unlocked_skills()[1]
		if level == 0:
			check(priest.skill_manager.find_target_for_skill(heal) == null, "未强化牧师全员满血时没有治疗目标")
		else:
			var shield_seen := false
			for frame in 300:
				await get_tree().physics_frame
				if ally.shield_amount > 0:
					shield_seen = true
					break
			check(shield_seen and ally.current_health == 200, "强化牧师全员满血时自动给最高生命友军转盾")
			check(is_instance_valid(ally.shield_visual) and ally.shield_visual.get_meta("effect_id") == "scenes_vfx_statuseffects_shieldbubblevfx", "独立测试场同样显示实验室护盾罩")
		arena.clear_arena()
		await get_tree().process_frame
		await get_tree().process_frame
	print("MONSTER_TEST_PRIEST_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
