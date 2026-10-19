# 这玩意儿是干嘛的（核心逻辑）：验证测试场两侧按钮、真实对战、清空和再次开战。
# 数据是咋流动的（数据流向）：真实 UI 信号 → 场景生成单位 → 自动战斗 → 命中与清理断言。
# 为啥这么写（选型决策）：实际点击按钮信号和运行寻路，避免界面存在却没有接通。
# 性能咋样（复杂度）：只在开发测试时运行，正式游戏不加载。
extends Node

var hits := 0
var ranged_unit: UnitBase
var arrows := 0
var arrow_frame := -1
var arrow_animation: StringName = &""


# 作用：Godot 入树后延迟启动测试；没有参数，没有返回值。
func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


# 作用：统计真实伤害命中；_unit 是受击者，_attacker 是攻击者，没有返回值。
func _on_hit(_unit: UnitBase, _attacker: UnitBase) -> void:
	hits += 1


func _on_projectile_added(child: Node) -> void:
	if child is Projectile and is_instance_valid(ranged_unit):
		arrows += 1
		arrow_frame = ranged_unit.animated_sprite_2d.frame
		arrow_animation = ranged_unit.animated_sprite_2d.animation


# 作用：完成场景集成检查，预览模式额外保存截图；没有参数，没有返回值。
func _run() -> void:
	var arena = load("res://scenes/testing/monster_test.tscn").instantiate()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	await get_tree().physics_frame
	await get_tree().physics_frame
	arena.start_button.pressed.emit()
	assert(not arena.running, "空场不能开始对战")
	for button in arena.spawn_buttons.values():
		button.pressed.emit()
	assert(arena.team_a.get_child_count() > 0 and arena.team_b.get_child_count() > 0)
	assert(arena.team_a.get_child_count() + arena.team_b.get_child_count() == arena.unit_scenes.size())
	for unit in arena.team_a.get_children():
		assert(unit.is_in_group("team_a") and unit.unit_data.unit_team == "team_a")
		assert(unit.unit_data.card_upgrade_level == 0, "普通添加按钮仍生成未强化单位")
	for unit in arena.team_b.get_children():
		assert(unit.is_in_group("team_b") and unit.unit_data.unit_team == "team_b")
	assert(Global.game_phase == Global.GamePhase.CARD_PLAY)
	assert(arena.upgrade_buttons.size() == arena.team_a.get_child_count(), "每个己方兵种都有独立强化等级列表")
	assert(not arena.upgrade_buttons.has("res://scenes/units/orc.tscn"), "敌方列表不显示己方卡牌强化按钮")
	for unit in arena.team_a.get_children():
		var levels: Dictionary = arena.upgrade_buttons[unit.scene_file_path]
		assert(levels.size() == maxi(0, unit.unit_data.max_upgrade_count), "强化按钮数量取自各兵种可强化次数")
		for level in range(1, unit.unit_data.max_upgrade_count + 1):
			var label := "飞弹%d次" if unit.unit_data.unit_english_name == "soldier" else "强化%d次"
			assert(levels.has(level) and levels[level].text == label % level)
			assert(levels[level].get_global_rect().end.x <= 295.0, "强化按钮完整显示在己方列表内")
	var deck_before: Array[CardInstance] = RunManager.deck.duplicate()
	arena.upgrade_buttons["res://scenes/units/soldier.tscn"][1].pressed.emit()
	var upgraded: UnitBase = arena.team_a.get_children().back()
	var soldier_data := load("res://data/units/soldier.tres") as UnitData
	assert(upgraded.unit_data.card_upgrade_level == 1 and upgraded.skill_manager.has_sword_arrow(), "强化按钮生成已强化士兵并启用剑矢")
	assert(upgraded.unit_data.attack == soldier_data.attack + soldier_data.upgrade_ability_points, "测试强化按原训练规则把能力点加到攻击")
	assert(soldier_data.card_upgrade_level == 0 and RunManager.deck == deck_before, "测试强化不修改共享单位资源或本局牌组")
	if "--monster-test-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/monster-test-preview.png")
	assert(arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b", 1) == null, "测试强化入口拒绝敌方单位")
	# 清空要同时移除根节点临时效果和队伍内召唤物。
	var temporary := Node2D.new()
	arena.add_child(temporary)
	arena.clear_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not is_instance_valid(temporary))
	assert(arena.team_a.get_child_count() == 0 and arena.team_b.get_child_count() == 0)
	# 测试场里的强化士兵必须真实播放指定动画并在第7帧发箭，随后仍可切回近战。
	arena.child_entered_tree.connect(_on_projectile_added)
	arena.upgrade_buttons["res://scenes/units/soldier.tscn"][1].pressed.emit()
	ranged_unit = arena.team_a.get_children().back()
	for skill: SkillBase in ranged_unit.skill_manager.group_skills:
		if not ranged_unit.unit_data.is_basic_attack(skill):
			ranged_unit.skill_manager._skill_time_cd[skill].start(99.0)
	var ranged_enemy: UnitBase = arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b")
	ranged_unit.global_position = Vector2(850, 500)
	ranged_enemy.global_position = Vector2(1100, 500)
	ranged_enemy.unit_data.defence = 0
	ranged_enemy.unit_data.dodge_skill = null
	ranged_enemy.current_health = 10000
	ranged_enemy.set_physics_process(false)
	var before := int(ranged_enemy.current_health)
	arena.start_button.pressed.emit()
	for frame in 180:
		await get_tree().physics_frame
		if ranged_enemy.current_health < before:
			break
	assert(arrows == 1 and arrow_animation == &"attack_03" and arrow_frame == 7, "强化士兵在attack_03第7帧发箭")
	assert(ranged_enemy.current_health == before - ranged_unit.unit_data.attack, "测试场里远程箭矢真实造成伤害")
	for skill: SkillBase in ranged_unit.skill_manager.group_skills:
		if not ranged_unit.unit_data.is_basic_attack(skill):
			ranged_unit.skill_manager._skill_time_cd[skill].start(99.0)
	ranged_enemy.global_position = ranged_unit.global_position + Vector2(60, 0)
	before = int(ranged_enemy.current_health)
	var melee_played := false
	for frame in 180:
		await get_tree().physics_frame
		melee_played = melee_played or ranged_unit.animated_sprite_2d.animation == &"attack_01"
		if ranged_enemy.current_health < before:
			break
	assert(melee_played and arrows == 1 and ranged_enemy.current_health < before, "强化士兵近身后使用近战普攻")
	arena.clear_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(arena.team_a.get_child_count() == 0 and arena.team_b.get_child_count() == 0, "强化单位和箭矢也可清空重置")
	ranged_unit = null
	var ally: UnitBase = arena.spawn_unit(load("res://scenes/units/soldier.tscn"), "team_a")
	var enemy: UnitBase = arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b")
	ally.global_position = Vector2(850, 500)
	enemy.global_position = Vector2(1050, 500)
	ally.hit_received.connect(_on_hit)
	enemy.hit_received.connect(_on_hit)
	arena.start_button.pressed.emit()
	assert(arena.running and Global.game_phase == Global.GamePhase.AUTO_BATTLE)
	for frame in range(600):
		await get_tree().physics_frame
		if hits > 0:
			break
	assert(hits > 0, "开始战斗后必须真正寻路并攻击")
	assert(arena.spawn_unit(load("res://scenes/units/bat.tscn"), "team_b") != null, "战斗中可以继续增兵")
	arena.upgrade_buttons["res://scenes/units/soldier.tscn"][1].pressed.emit()
	var reinforcement: UnitBase = arena.team_a.get_children().back()
	assert(reinforcement.skill_manager.has_sword_arrow(), "战斗中可继续添加强化士兵")
	arena.clear_arena()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not arena.running and not arena.start_button.disabled)
	assert(Global.game_phase == Global.GamePhase.CARD_PLAY)
	assert(arena.team_a.get_child_count() == 0 and arena.team_b.get_child_count() == 0)
	# 清空后的第二次开战不能被上一次的施法锁或按钮状态阻挡。
	arena.spawn_unit(load("res://scenes/units/soldier.tscn"), "team_a")
	arena.spawn_unit(load("res://scenes/units/orc.tscn"), "team_b")
	arena.start_button.pressed.emit()
	assert(arena.running and Global.game_phase == Global.GamePhase.AUTO_BATTLE)
	arena.clear_arena()
	arena.queue_free()
	await get_tree().process_frame
	await _test_upgrade_levels()
	print("MONSTER_TEST_SCENE_PASS")
	get_tree().quit()


# 使用独立的双次强化/不可强化配置，检查按钮、属性累计及二级技能解锁，不修改正式资源。
func _test_upgrade_levels() -> void:
	var soldier_data := load("res://data/units/soldier.tres") as UnitData
	var deck_before: Array[CardInstance] = RunManager.deck.duplicate()
	for limit in [0, 2]:
		var preview := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
		var source := soldier_data.duplicate(true) as UnitData
		source.unit_name = "双次强化测试士兵" if limit == 2 else "不可强化测试士兵"
		source.max_upgrade_count = limit
		var basic := load("res://data/skills/normal_attack.tres").duplicate() as SkillBase
		basic.unlock_upgrade_levels = [0, 1, 2]
		var special := load("res://data/skills/soldier_power_attack.tres").duplicate() as SkillBase
		special.soldier_branch = ""
		special.unlock_upgrade_levels = [2]
		source.skills.assign([basic, special])
		preview.unit_data = source
		var fixture := PackedScene.new()
		assert(fixture.pack(preview) == OK)
		preview.free()
		var arena = load("res://scenes/testing/monster_test.tscn").instantiate()
		arena.unit_scenes.assign([fixture, load("res://scenes/units/orc.tscn")])
		get_tree().root.add_child(arena)
		get_tree().current_scene = arena
		await get_tree().physics_frame
		await get_tree().physics_frame
		var levels: Dictionary = arena.upgrade_buttons[fixture.resource_path]
		assert(levels.size() == limit, "零次与双次强化配置显示正确数量的按钮")
		arena.spawn_buttons[fixture.resource_path].pressed.emit()
		var normal: UnitBase = arena.team_a.get_children().back()
		assert(normal.unit_data.card_upgrade_level == 0 and normal.unit_data.attack == source.attack)
		assert(normal.skill_manager.group_skills.size() == 1, "普通单位不解锁二级技能")
		for level in range(1, limit + 1):
			var button: Button = levels[level]
			assert(button.text == "飞弹%d次" % level and not button.disabled)
			assert(button.get_global_rect().end.x <= 295.0, "多个等级按钮不超出列表宽度")
			button.pressed.emit()
			var unit: UnitBase = arena.team_a.get_children().back()
			assert(unit.unit_data.card_upgrade_level == level, "各强化按钮生成对应等级的单位")
			assert(unit.unit_data.attack == source.attack + level * source.upgrade_ability_points, "二次强化累计两次训练属性")
			assert(unit.skill_manager.has_sword_arrow(), "两种强化等级的士兵都获得剑矢")
			assert(unit.skill_manager.group_skills.size() == (2 if level == 2 else 1), "二级技能只在强化两次时实际安装")
			assert(arena.status_label.text.contains("强化%d次" % level), "状态提示显示实际强化次数")
		var count: int = arena.team_a.get_child_count()
		assert(arena.spawn_unit(fixture, "team_a", limit + 1) == null, "禁止超过单位配置的强化上限")
		assert(arena.spawn_unit(fixture, "team_a", -1) == null, "禁止负数强化次数")
		assert(arena.team_a.get_child_count() == count, "无效强化请求不添加单位")
		assert(source.card_upgrade_level == 0 and source.attack == soldier_data.attack and source.skills.size() == 2, "多个测试等级不修改共享源数据")
		assert(RunManager.deck == deck_before, "多次测试强化不修改本局牌组")
		if limit == 2 and "--monster-test-preview" in OS.get_cmdline_user_args():
			arena.upgrade_buttons[fixture.resource_path][2].pressed.emit()
			arena.spawn_buttons["res://scenes/units/orc.tscn"].pressed.emit()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://.maintenance/monster-test-upgrade-levels-preview.png")
		arena.clear_arena()
		arena.queue_free()
		await get_tree().process_frame
