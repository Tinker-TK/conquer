# 通用驻场光环的显式测试配置；圣殿骑士正式技能已由嘲讽替换，临时加成仍须隔离。
extends Node

var battle: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _create_battle() -> void:
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	for unit: UnitBase in battle.card_runtime.living_units():
		unit.set_physics_process(false)


func _deploy(card: CardInstance, point: Vector2) -> UnitBase:
	var hand = battle.hand_manager
	hand.draw_pile.erase(card)
	hand.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, point), "通过正式出牌部署单位")
	var unit := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	unit.set_physics_process(false)
	return unit


func _effect(kind: CardEffect.Kind, target: UnitBase, amount: float = 1.0) -> void:
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	var definition := CardDefinition.new()
	definition.effects.assign([effect])
	definition.target = CardDefinition.Target.ALLY
	var card := CardInstance.new(definition)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(battle.card_runtime.try_play(card, target.global_position), "通过真实效果牌验证光环组合")


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	var source := load("res://data/units/knight_templar.tres").duplicate() as UnitData
	var source_attack := source.attack
	var skill := load("res://data/skills/knight_templar_protection_aura.tres") as SkillBase
	source.skills.assign([load("res://data/skills/knight_templar_attack.tres"), skill])
	check(skill.is_passive() and skill.aura_radius == 200.0 and skill.aura_attack_bonus == 2, "默认驻场光环半径200、攻击+2")
	check(skill.aura_effect.resource_path == "res://assets/effect/godot_vfx_library/effects/magic/magic_aura.tscn", "使用截图特效演示中的魔法光环")
	var start := RunStartData.new()
	start.cards.assign([source, source, load("res://data/units/soldier.tres")])
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	var normal: CardInstance = RunManager.deck[0]
	var trained: CardInstance = RunManager.deck[1]
	check(trained.train(source.upgrade_ability_points, 0), "原训练入口解锁光环")
	check(not normal.get_summon_data().skills.has(skill) and trained.get_summon_data().skills.has(skill), "光环按本张卡的精确强化等级解锁")
	check(not normal.get_description().contains("庇护") and trained.get_description().contains("半径200") and trained.get_description().contains("攻击力提升2"), "强化卡面说明跟随当前光环配置")
	_create_battle()
	var caster := _deploy(trained, Vector2(450, 450))
	var normal_caster := _deploy(normal, Vector2(350, 750))
	var ally := _deploy(RunManager.deck[2], Vector2(650, 450))
	var base_attack := ally.unit_data.attack
	var aura = caster.skill_manager.get_node("ProtectionAura")
	check(caster.skill_manager.group_skills.has(skill) and not caster.skill_manager._skill_time_cd.has(skill), "驻场技能显示在技能栏且不创建攻击冷却")
	check(normal_caster.skill_manager.get_node_or_null("ProtectionAura") == null, "未强化圣殿骑士没有光环")
	await _settle()
	check(ally.unit_data.attack == base_attack + 2 and ally.protection_attack_bonus == 2, "半径边界内友军获得攻击+2")
	check(caster.unit_data.attack == source.attack + source.upgrade_ability_points + 2, "默认光环也庇护圣殿骑士自身")
	check(normal_caster.protection_attack_bonus == 0, "范围外友军不受影响")
	check(aura.visual is GPUParticles2D and aura.visual.process_material.emission_ring_radius == 200.0 and aura.visual.local_coords, "粒子范围与配置一致且跟随施放者")
	var visual_preview := skill.aura_effect.instantiate() as GPUParticles2D
	check(aura.visual.process_material != visual_preview.process_material, "每个光环使用独立粒子材质")
	visual_preview.free()
	var status = ally.get_node("HealthBar/StatusDisplay")
	check(status.statuses.any(func(entry: Dictionary): return entry.icon == "protection" and entry.tooltip.contains("提升2")), "友军状态显示庇护及真实加成")
	var enemy := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	battle.get_node("Entities/TeamB").add_child(enemy)
	enemy.global_position = Vector2(500, 450)
	enemy.set_physics_process(false)
	await _settle()
	check(enemy.protection_attack_bonus == 0, "光环不加成敌军")
	check(caster.skill_manager.pick_skill() and not caster.skill_manager.current_skill.is_passive(), "驻场光环不抢占主动技能选择")
	caster.set_stunned(true)
	await _settle()
	check(ally.protection_attack_bonus == 2, "来源仍存活时眩晕不撤销光环")
	caster.set_stunned(false)
	enemy.unit_data.defence = 0
	enemy.unit_data.dodge_skill = null
	enemy.current_health = 10000
	var health_before := int(enemy.current_health)
	var attack: SkillBase = caster.unit_data.skills[0]
	var manager = caster.skill_manager
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	manager.current_skill = attack
	manager.current_target = enemy
	caster.switch_state(UnitBase.State.ATTACK)
	manager.attack()
	for frame in 180:
		await get_tree().physics_frame
		if not manager.is_casting:
			break
	check(not manager.is_casting and health_before - int(enemy.current_health) == int(caster.unit_data.attack * attack.attack_rate) * attack.hit_frame.size(), "原攻击动画正常结束，真实伤害包含庇护加成")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	ally.global_position.x = 650.1
	await _settle()
	check(ally.unit_data.attack == base_attack and ally.protection_attack_bonus == 0, "移出范围立即撤销庇护")
	ally.global_position.x = 650.0
	await _settle()
	for frame in 20:
		await get_tree().physics_frame
	check(ally.unit_data.attack == base_attack + 2, "进入范围及持续刷新不反复叠加")
	var peer_card := CardInstance.new(source)
	check(peer_card.train(source.upgrade_ability_points, 0), "第二张圣殿骑士卡独立强化")
	var peer := _deploy(peer_card, Vector2(480, 450))
	await _settle()
	check(ally.unit_data.attack == base_attack + 2, "两个同类光环重叠仍为+2")
	caster.die()
	check(ally.protection_attack_bonus == 2 and not aura.visual.visible, "来源死亡立即隐藏特效，另一个光环继续庇护")
	peer.global_position = Vector2(350, 750)
	await _settle()
	check(ally.unit_data.attack == base_attack, "最后一个光环移走后恢复基础攻击")
	peer.global_position = Vector2(480, 450)
	await _settle()
	_effect(CardEffect.Kind.FRENZY, ally, 20.0)
	check(ally.unit_data.attack == roundi((base_attack + 2) * 0.7), "狂化按含光环加法的攻击计算百分比")
	peer.global_position = Vector2(350, 750)
	await _settle()
	check(ally.unit_data.attack == roundi(base_attack * 0.7), "离开光环时正确重算狂化，不残留乘数贡献")
	peer.global_position = Vector2(480, 450)
	await _settle()
	ally.global_position = Vector2(650, 450)
	_effect(CardEffect.Kind.COPY_ALLY, ally)
	var copied := battle.get_node("Entities/TeamA").get_children().back() as UnitBase
	copied.set_physics_process(false)
	await _settle()
	check(copied.unit_data.attack == base_attack, "范围外复制品不烘焙原单位的庇护或狂化加成")
	copied.global_position = Vector2(600, 450)
	await _settle()
	check(copied.unit_data.attack == base_attack + 2, "复制品进入范围后单独获得一次庇护")
	_effect(CardEffect.Kind.RECALL_ALLY, peer)
	check(copied.unit_data.attack == base_attack and ally.unit_data.attack == roundi(base_attack * 0.7), "收回光环来源立即撤销所有临时加成")
	await _settle()
	var configured_source := source.duplicate() as UnitData
	var configured_skill := skill.duplicate(true) as SkillBase
	configured_skill.aura_radius = 75.0
	configured_skill.aura_attack_bonus = 4
	configured_skill.aura_include_caster = false
	configured_source.skills = [configured_skill]
	var configured_card := CardInstance.new(configured_source)
	check(configured_card.train(source.upgrade_ability_points, 0), "配置变体仍通过原训练解锁")
	var configured := _deploy(configured_card, Vector2(530, 450))
	await _settle()
	check(configured.protection_attack_bonus == 0 and configured.unit_data.attack == source.attack + source.upgrade_ability_points, "可配置排除施放者自身")
	check(copied.protection_attack_bonus == 4 and ally.protection_attack_bonus == 0, "自定义75半径与攻击+4均实际生效")
	var configured_aura = configured.skill_manager.get_node("ProtectionAura")
	check(configured_aura.visual.process_material.emission_ring_radius == 75.0 and skill.aura_radius == 200.0, "自定义视觉半径不修改原技能配置")
	configured_skill.aura_radius = 150.0
	await _settle()
	check(ally.protection_attack_bonus == 4 and configured_aura.visual.process_material.emission_ring_radius == 150.0, "半径变化同步更新作用范围和视觉")
	configured.unit_data.card_upgrade_level = 0
	await _settle()
	check(ally.protection_attack_bonus == 0 and copied.protection_attack_bonus == 0, "技能等级不再匹配时移除光环")
	check(source.attack == source_attack and source.card_upgrade_level == 0 and trained.permanent_buffs.is_empty(), "驻场庇护不写进原牌或共享资源")
	battle.queue_free()
	await get_tree().process_frame
	check(RunManager.save_run().is_empty(), "保存圣殿骑士卡强化记录")
	check(RunManager.load_saved_run().is_empty(), "恢复圣殿骑士强化存档")
	_create_battle()
	var restored := _deploy(RunManager.deck[1], Vector2(450, 450))
	await _settle()
	check(restored.protection_attack_bonus == 2 and restored.skill_manager.get_node_or_null("ProtectionAura") != null, "存档继续后重新建立光环，不丢失强化")
	battle.queue_free()
	await get_tree().process_frame
	await _monster_test()
	print("PROTECTION_AURA_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _monster_test() -> void:
	var arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	var caster: UnitBase = arena.spawn_unit(load("res://scenes/units/knight_templar.tscn"), "team_a", 1)
	# 测试独立场中的通用光环接入，不恢复正式圣殿骑士已移除的技能。
	var aura_skill := load("res://data/skills/knight_templar_protection_aura.tres") as SkillBase
	caster.unit_data.skills.append(aura_skill)
	var aura_skills: Array[SkillBase] = [aura_skill]
	caster.skill_manager.setup(aura_skills)
	var ally: UnitBase = arena.spawn_unit(load("res://scenes/units/soldier.tscn"), "team_a")
	var base_attack := ally.unit_data.attack
	caster.global_position = Vector2(680, 500)
	ally.global_position = Vector2(820, 500)
	await _settle()
	check(ally.protection_attack_bonus == 2 and ally.unit_data.attack == base_attack + 2, "怪物测试场强化按钮生成的单位也提供真实光环")
	check(ally.get_node("HealthBar/StatusDisplay").statuses.any(func(entry: Dictionary): return entry.icon == "protection"), "独立测试场同样显示庇护状态")
	if "--protection-aura-preview" in OS.get_cmdline_user_args():
		var normal: UnitBase = arena.spawn_unit(load("res://scenes/units/knight_templar.tscn"), "team_a")
		normal.global_position = Vector2(440, 280)
		var enemy: UnitBase = arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b")
		enemy.global_position = Vector2(1250, 500)
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/protection-aura-preview.png")
	arena.clear_arena()
	await _settle()
	check(arena.team_a.get_child_count() == 0 and arena.team_b.get_child_count() == 0, "清空测试场同时移除光环和庇护单位")
	arena.queue_free()
	await get_tree().process_frame
