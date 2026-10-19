# 现有篝火训练 → 原士兵卡强化 → 正式征召与完整攻击动画；覆盖冷却、再次出场和存档。
extends Node

var battle: Node2D
var hand: Node2D
var runtime: Node2D
var checks := 0
var failures: Array[String] = []
var arrows := 0
var arrow_texture: Texture2D
var shooting_unit: UnitBase
var arrow_frames: Array[int] = []
var arrow_animations: Array[StringName] = []


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _create_battle() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	runtime.set_physics_process(false)
	runtime.tactics.set_physics_process(false)
	battle.get_node("Entities/TeamA").child_entered_tree.connect(_projectile_entered)


func _recruit(card: CardInstance, point: Vector2) -> UnitBase:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	hand.draw_pile.erase(card)
	hand.discard_pile.erase(card)
	if not hand.hand.has(card):
		hand.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(runtime.try_play(card, point), "通过原征召牌部署士兵")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _play_existing(resource_name: String, target: UnitBase) -> bool:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % resource_name))
	hand.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	var marker := target.get_node_or_null("CastTargetCenter") as Node2D
	return runtime.try_play(card, marker.global_position if marker != null else target.global_position)


func _projectile_entered(child: Node) -> void:
	if child is Projectile:
		arrows += 1
		arrow_texture = child.get_node("Sprite2D").texture
		if is_instance_valid(shooting_unit):
			arrow_frames.append(shooting_unit.animated_sprite_2d.frame)
			arrow_animations.append(shooting_unit.animated_sprite_2d.animation)


func _cast(unit: UnitBase) -> void:
	unit.skill_manager.check_attack()
	check(unit.current_state == UnitBase.State.ATTACK, "有效射程内可以攻击")
	shooting_unit = unit
	var skill: SkillBase = unit.skill_manager.current_skill
	var expected_animation := &"attack_03" if unit.global_position.distance_to(unit.skill_manager.current_target.global_position) > skill.cast_range else StringName(skill.cast_animation)
	unit.skill_manager.attack()
	check(unit.animated_sprite_2d.animation == expected_animation, "远程使用attack_03，近战沿用原攻击动画")
	for frame in 180:
		await get_tree().physics_frame
		if not unit.skill_manager.is_casting:
			break
	check(not unit.skill_manager.is_casting, "完整攻击动画正常结束")
	for frame in 60:
		await get_tree().physics_frame
		var has_arrow := false
		for child in battle.get_node("Entities/TeamA").get_children():
			has_arrow = has_arrow or child is Projectile
		if not has_arrow:
			break


func _run() -> void:
	var source := load("res://data/units/soldier.tres").duplicate() as UnitData
	source.skills = source.skills.duplicate()
	source.skills[0] = source.skills[0].duplicate() as SkillBase
	source.skills[0].cooldown = 3.0
	var start := RunStartData.new()
	start.cards.assign([source, source, load("res://data/units/archer.tres")])
	RunManager.start_new_run(start)
	var original: CardInstance = RunManager.deck[0]
	var peer: CardInstance = RunManager.deck[1]
	check(original.get_summon_data().has_sword_arrow(), "未强化士兵已有远近普攻")
	var session = load("res://scripts/events/event_session.gd").new()
	session.configure(load("res://scripts/map/fixed_map_config.gd").default_event("campfire"), RunManager)
	var offer: Dictionary = session.choose(1)
	check(offer.candidates[0] == original, "原有篝火训练选择现有士兵卡")
	var selection: Array[int] = [0]
	check(not session.claim(selection, Vector2i(source.upgrade_ability_points, 0), "missile").has("error"), "通过原有强化入口完成士兵卡训练")
	check(original.upgrade_count == 1 and original.get_summon_data().has_sword_arrow(), "飞弹分支保留剑矢")
	check(peer.upgrade_count == 0 and peer.get_summon_data().has_sword_arrow(), "同名未强化士兵不受影响")
	check(original.upgrade_summary().contains("剑矢"), "原牌强化摘要显示剑矢")
	check(source.card_upgrade_level == 0 and source.has_sword_arrow(), "共享士兵配置不被强化")
	check(original.permanent_buffs.is_empty(), "效果由强化次数决定，不写入额外卡牌增益")
	check(not FileAccess.file_exists("res://data/cards/sword_arrow.tres"), "没有独立剑矢牌")
	var archer_card: CardInstance = RunManager.deck[2]
	check(archer_card.train(archer_card.unit_data.upgrade_ability_points, 0), "其他兵种仍可按原系统强化")
	check(not archer_card.get_summon_data().has_sword_arrow(), "强化弓箭手不获得士兵效果")
	var enemy_data := original.get_summon_data()
	enemy_data.unit_team = "team_b"
	check(not enemy_data.has_sword_arrow(), "敌方士兵不启用己方强化效果")
	_create_battle()
	var soldier := _recruit(original, Vector2(450, 450))
	var ordinary := _recruit(peer, Vector2(450, 750))
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	enemy.position = Vector2(800, 450)
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.set_physics_process(false)
	enemy.unit_data.defence = 0
	enemy.unit_data.dodge_skill = null
	enemy.unit_data.max_hp = 10000
	enemy.current_health = 10000
	var manager := soldier.skill_manager
	var basic: SkillBase = soldier.unit_data.skills[0]
	var special: SkillBase = soldier.unit_data.skills[1]
	manager._skill_time_cd[special].start(99.0)
	check(soldier.unit_data.card_upgrade_level == 1 and manager.get_attack_range(basic) == 300.0, "原强化士兵出场即可远程普攻")
	check(ordinary.skill_manager.get_attack_range(ordinary.unit_data.skills[0]) == 300.0, "未强化士兵已有远近普攻")
	check(basic.cast_range == 80.0 and load("res://data/skills/normal_attack.tres").cooldown == 1.0, "共享普通攻击数值保持原配置")
	check(manager._skill_time_cd.size() == 2, "剑矢没有额外冷却计时器")
	var legacy_basic := basic.duplicate() as SkillBase
	legacy_basic.is_basic_attack = false
	check(manager.get_attack_range(legacy_basic) == 300.0, "兼容旧存档未保存普攻标记的快照")
	var inspector: Control = battle.card_ui.get_node("UnitInspector")
	inspector.open_unit(soldier)
	check(inspector.status_cells.has("sword_arrow") and inspector.skill_cells[0].parameters.text.contains("300"), "单位详情显示强化效果和实际射程")
	inspector.open_card(original, inspector)
	check(inspector.status_cells.has("sword_arrow") and inspector.skill_cells[0].parameters.text.contains("300"), "强化士兵牌预览显示远程普攻")
	inspector.open_card(peer, inspector)
	check(inspector.status_cells.has("sword_arrow"), "未强化同名牌预览也显示剑矢")
	inspector.close_details()
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	enemy.global_position = soldier.global_position + Vector2(301, 0)
	manager.check_attack()
	check(soldier.current_state != UnitBase.State.ATTACK, "301距离不能开始攻击")
	enemy.global_position = soldier.global_position + Vector2(300, 0)
	manager.check_attack()
	check(manager.current_skill == basic, "300距离使用远程普攻")
	var before := int(enemy.current_health)
	await _cast(soldier)
	check(arrows == 1 and before - int(enemy.current_health) == soldier.unit_data.attack, "真实动画发箭，伤害含原训练属性")
	check(arrow_frames == [7] and arrow_animations == [&"attack_03"], "attack_03播放到第7帧时发射唯一箭矢")
	var arrow_scene: PackedScene = load("res://data/skills/archer_arrow_attack.tres").projectile_scene
	var reference_arrow := arrow_scene.instantiate()
	check(arrow_texture == reference_arrow.get_node("Sprite2D").texture, "箭矢使用弓箭手相同素材")
	reference_arrow.free()
	check(manager.get_cooldown_left(basic) > 0.0, "远程消耗原普攻冷却")
	manager._skill_time_cd[special].start(99.0)
	enemy.global_position = soldier.global_position + Vector2(80, 0)
	manager.check_attack()
	check(soldier.current_state != UnitBase.State.ATTACK, "远程攻击后近身不能绕过冷却")
	var remaining: float = manager.get_cooldown_left(basic)
	manager.set_cooldown_multiplier(0.5)
	check(is_equal_approx(manager.get_cooldown_left(basic), remaining * 0.5), "强化士兵仍按同一计时器调整冷却")
	manager.set_cooldown_multiplier(1.0)
	manager._skill_time_cd[basic].stop()
	before = int(enemy.current_health)
	await _cast(soldier)
	check(arrows == 1 and before - int(enemy.current_health) == soldier.unit_data.attack, "80距离的近战边界使用近战普攻")
	enemy.global_position = soldier.global_position + Vector2(250, 0)
	manager.check_attack()
	check(soldier.current_state != UnitBase.State.ATTACK, "近战攻击后远离不能绕过冷却")
	manager._skill_time_cd[basic].stop()
	manager.check_attack()
	manager.attack()
	check(soldier.animated_sprite_2d.animation == &"attack_03", "远程攻击开始时播放attack_03")
	enemy.global_position = soldier.global_position + Vector2(60, 0)
	before = int(enemy.current_health)
	for frame in 180:
		await get_tree().physics_frame
		if not manager.is_casting:
			break
	check(arrows == 1 and before - int(enemy.current_health) == soldier.unit_data.attack, "出箭帧之前近身则改用近战")
	manager._skill_time_cd[special].stop()
	check(manager.pick_skill() and manager.current_skill == special, "飞弹技能保留高于普攻的优先级")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	runtime._tick_buffs()
	runtime._clear_unit_buffs(soldier)
	check(manager.get_attack_range(basic) == 300.0, "回合和临时增益清理不撤销卡牌强化")
	check(_play_existing("copy_ally", soldier), "原有复制牌可复制强化士兵")
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	check(copied.unit_data.card_upgrade_level == 1 and copied.skill_manager.has_sword_arrow(), "复制品继承原单位强化等级")
	check(_play_existing("recall_ally", soldier), "通过原有撤回牌收回强化士兵")
	check(hand.hand.has(original), "撤回返回同一张士兵原牌")
	await get_tree().process_frame
	var redeployed := _recruit(original, Vector2(330, 550))
	check(redeployed.skill_manager.has_sword_arrow() and original.upgrade_count == 1, "同一强化牌重新出场保留剑矢")
	battle.queue_free()
	await get_tree().process_frame
	check(RunManager.save_run().is_empty(), "保存现有士兵牌强化记录")
	RunManager.start_new_run(start)
	check(RunManager.deck[0].get_summon_data().has_sword_arrow() and RunManager.deck[0].upgrade_count == 0, "新局清空强化并保留基础远近普攻")
	check(RunManager.load_saved_run().is_empty(), "恢复已强化士兵的存档")
	var restored: CardInstance = RunManager.deck[0]
	check(restored.upgrade_count == 1 and restored.get_summon_data().has_sword_arrow(), "读取存档按原强化次数恢复剑矢")
	check(RunManager.deck[1].upgrade_count == 0 and RunManager.deck[1].soldier_specialization.is_empty(), "存档保留同名未强化牌的独立状态")
	_create_battle()
	var restored_unit := _recruit(restored, Vector2(450, 450))
	check(restored_unit.skill_manager.has_sword_arrow(), "存档继续后的另一战场自动启用剑矢")
	battle.queue_free()
	await get_tree().process_frame
	print("SWORD_ARROW_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
