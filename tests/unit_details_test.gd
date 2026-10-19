# 用实际卡牌、技能 Timer、鼠标与滚动验证详情；--capture 可导出实机面板和遮罩。
extends Node

var checks := 0
var failures: Array[String] = []
var battle
var runtime
var inspector
var ally: UnitBase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func _play(kind: CardEffect.Kind, amount: int, label: String, lifetime: CardEffect.Lifetime = CardEffect.Lifetime.BATTLE) -> void:
	var effect := CardEffect.new()
	effect.kind = kind
	effect.amount = amount
	effect.lifetime = lifetime
	effect.lasting_rounds = 1
	effect.radius = 70
	var definition := CardDefinition.new()
	definition.card_name = label
	definition.target = CardDefinition.Target.POSITION if kind == CardEffect.Kind.MUD_ZONE else CardDefinition.Target.ALLY
	definition.effects.append(effect)
	var card := CardInstance.new(definition)
	battle.hand_manager.hand.append(card)
	battle.battle_round_manager.current_energy = 99
	check(runtime.try_play(card, ally.global_position), "状态必须由真实出牌入口生效")


func _hover(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame
	inspector.update_hover(point)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var start := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	start.starting_relics.clear()
	start.starting_potions.clear()
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	runtime = battle.card_runtime
	runtime.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var recruit := CardInstance.new(load("res://data/units/soldier.tres"))
	# 明确使用斩击分支：两项独立冷却技能，无基础剑矢常驻状态。
	recruit.upgrade_count = 1
	recruit.soldier_specialization = "slash"
	battle.hand_manager.hand.append(recruit)
	battle.battle_round_manager.current_energy = 99
	check(runtime.try_play(recruit, Vector2(650, 500)), "召唤测试单位")
	ally = battle.get_node("Entities/TeamA").get_children().back()
	for unit in runtime.living_units():
		unit.set_physics_process(false)
	_play(CardEffect.Kind.ATTACK_UP, 5, "磨刀", CardEffect.Lifetime.ROUNDS)
	_play(CardEffect.Kind.ATTACK_UP, 7, "战斗磨刀")
	_play(CardEffect.Kind.DEFENCE_UP, 3, "护甲", CardEffect.Lifetime.RUN)
	_play(CardEffect.Kind.POISON_ON_HIT, 3, "毒刃")
	_play(CardEffect.Kind.DEATH_EXPLOSION, 20, "爆炸")
	_play(CardEffect.Kind.MAX_HP_UP, 10, "强健")
	_play(CardEffect.Kind.MUD_ZONE, 20, "泥沼", CardEffect.Lifetime.ROUNDS)
	runtime.states[ally.get_instance_id()].poison = 2
	runtime._refresh_unit_status(ally)
	ally.current_health = 85
	inspector = battle.card_ui.get_node("UnitInspector")
	inspector.open_unit(ally)
	await get_tree().process_frame
	await get_tree().process_frame
	check(inspector.health_text.text == "85 / 110" and inspector.health_bar.value == 85, "生命条和数值来自实时生命")
	check(inspector.stat_labels.attack.get_parsed_text().contains("22 (+12)"), "同类强化汇总进攻击括号")
	check(inspector.stat_labels.attack.text.contains("color=246746"), "增加数值使用适合浅色底板的深绿色")
	check(inspector.stat_labels.speed.get_parsed_text().contains("120.0 (-30.0)"), "泥沼按实际速度差显示减少")
	check(inspector.stat_labels.speed.text.contains("color=a73538"), "减少数值使用适合浅色底板的深红色")
	check(inspector.status_cells.size() == 7, "全部强化、地形和毒共用状态栏")
	check(inspector.status_cells.explosion.badge.text == "1", "爆炸图标角标为实际效果数量")
	check(inspector.status_cells.poison.badge.text == "2" and inspector.status_cells.poison_on_hit.badge.text == "3", "毒与附毒分别显示实际层数")
	check(inspector.status_cells.attack.duration.text == "多种期限", "详情图标下保留独立的期限角标")
	var attack_cell: Dictionary = inspector.status_cells.attack
	var icon_point: Vector2 = attack_cell.icon.get_global_rect().get_center()
	await _hover(icon_point)
	check(inspector.status_tooltip.visible and inspector.status_text.text.contains("+12"), "真实鼠标移到面板图标显示说明")
	check(inspector.status_text.text == "攻击力提升：+12", "Buff 提示只显示当前汇总加成，不附加来源或期限")
	check(inspector.status_tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "说明框不阻挡图标或关闭按钮")
	var camera := battle.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.8
	camera.global_position = Vector2(800, 550)
	camera.force_update_scroll()
	await _hover(inspector.status_cells.poison.icon.get_global_rect().get_center())
	check(inspector.status_tooltip.visible and inspector.status_text.text.contains("2 点无视防御"), "换行图标在相机缩放后仍显示正确说明")
	check(inspector.status_cells.poison.root.position.y > inspector.status_cells.attack.root.position.y, "第七个状态换行")
	await _hover(inspector.close_button.get_global_rect().get_center())
	check(not inspector.status_tooltip.visible, "离开状态图标即隐藏说明")
	var skill: SkillBase = inspector.skill_cells[0].skill
	var timer: Timer = ally.skill_manager._skill_time_cd[skill]
	var skill_icon: Control = inspector.skill_cells[0].icon
	check(skill_icon.cooldown_fraction == 0.0, "就绪时技能图标完整显示")
	timer.start(3.0)
	inspector._refresh_cooldowns()
	check(is_equal_approx(skill_icon.cooldown_fraction, 1.0), "使用实际 3 秒冷却而非配置的基础 CD")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await get_tree().create_timer(0.6).timeout
	check(skill_icon.cooldown_fraction > 0.7 and skill_icon.cooldown_fraction < 0.9, "交锋时冷却遮罩逐帧推进")
	var ready_description: String = inspector.skill_cells[0].description.get_parsed_text()
	check((ready_description.contains("100%") if skill.description.is_empty() else ready_description.contains(skill.description)) and inspector.skill_cells[1].description.get_parsed_text().contains("130%"), "已填写攻击文案按配置显示，未填写时显示实际倍率")
	check(inspector.skill_cells[1].icon.cooldown_fraction == 0.0, "不同技能的冷却遮罩相互独立")
	check(not inspector.skill_cells[0].parameters.text.contains("已就绪") and not inspector.skill_cells[0].parameters.text.contains("冷却 3"), "技能没有已删除的就绪和剩余冷却标签")
	get_tree().paused = true
	var left := timer.time_left
	await get_tree().create_timer(0.2, true).timeout
	check(is_equal_approx(timer.time_left, left), "暂停期间真实技能计时停止")
	check(not inspector.panel.visible and not inspector.status_tooltip.visible, "暂停清理详情与提示")
	get_tree().paused = false
	inspector.open_unit(ally)
	check(inspector.skill_cells[0].icon.cooldown_fraction > 0.0, "重新打开从当前冷却继续显示")
	timer.stop()
	inspector._process(0.01)
	check(inspector.skill_cells[0].icon.cooldown_fraction == 0.0, "冷却结束或停止立即撤销遮罩")
	timer.start(0.08)
	await get_tree().create_timer(0.12).timeout
	check(inspector.skill_cells[0].icon.cooldown_fraction == 0.0, "自然冷却结束也恢复完整图标")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	battle.battle_round_manager.battle_state = BattleRoundManager.BattleState.PLAYER_PHASE
	# 打开悬停后，在静止鼠标下撤销一层强化；图标保持位置，说明与括号同步更新。
	await get_tree().process_frame
	await _hover(inspector.status_cells.attack.icon.get_global_rect().get_center())
	var existing_icon = inspector.status_cells.attack.icon
	runtime._tick_buffs()
	runtime._tick_zones()
	await get_tree().create_timer(0.15).timeout
	check(inspector.status_cells.attack.icon == existing_icon, "叠层更新不重建悬停图标")
	check(inspector.stat_labels.attack.get_parsed_text().contains("17 (+7)"), "强化到期更新属性括号")
	check(inspector.status_tooltip.visible and inspector.status_text.text == "攻击力提升：+7", "静止鼠标下到期立即更新当前汇总加成")
	check(not inspector.status_cells.has("mud") and not inspector.stat_labels.speed.get_parsed_text().contains("(-"), "减速到期移除图标和减少数值")
	# 滚轮走原生容器，不穿透到战场相机；滚动后命中取当前图标位置。
	inspector.panel.offset_bottom = 620
	await get_tree().process_frame
	await _hover(inspector.scroll.get_global_rect().get_center())
	for down in [true, false]:
		var wheel := InputEventMouseButton.new()
		wheel.position = inspector.scroll.get_global_rect().get_center()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = down
		get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	check(inspector.scroll.scroll_vertical > 0, "面板内容可用鼠标滚轮浏览")
	var old_scroll: int = inspector.scroll.scroll_vertical
	inspector.refresh_details()
	check(inspector.scroll.scroll_vertical == old_scroll, "实时属性刷新保留滚动位置")
	inspector.scroll.scroll_vertical = 0
	inspector.panel.offset_bottom = 920
	await get_tree().process_frame
	await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args():
		_play(CardEffect.Kind.ATTACK_UP, 5, "磨刀", CardEffect.Lifetime.ROUNDS)
		_play(CardEffect.Kind.MUD_ZONE, 20, "泥沼", CardEffect.Lifetime.ROUNDS)
		await get_tree().create_timer(3.0).timeout
		inspector.set_process(false)
		var icon: Control = inspector.skill_cells[0].icon
		icon.cooldown_fraction = 0.5
		await _hover(inspector.status_cells.attack.icon.get_global_rect().get_center())
		await _capture("res://.maintenance/unit-details-panel.png")
		await _hover(Vector2(800, 700))
		var samples: Array[Image] = []
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			icon.cooldown_fraction = fraction
			await _capture("res://.maintenance/unit-details-cd-%d.png" % int(fraction * 100))
			samples.append(get_viewport().get_texture().get_image())
		# 检查实际渲染像素：剩余四分之一在左上，二分之一在左侧，完整冷却覆盖四象限。
		var rect: Rect2 = icon.get_global_rect()
		var points := [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.75, 0.75), Vector2(0.25, 0.75)]
		for frame in 4:
			for quadrant in 4:
				var point := Vector2i(rect.position + rect.size * points[quadrant])
				var clear := samples[0].get_pixelv(point)
				var shaded := samples[frame + 1].get_pixelv(point)
				var expected := quadrant == 0 or (frame >= 1 and quadrant == 3) or (frame >= 2 and quadrant == 2) or frame == 3
				check((shaded.get_luminance() < clear.get_luminance() * 0.6) if expected else is_equal_approx(shaded.get_luminance(), clear.get_luminance()), "冷却 %d%% 象限 %d 遮罩正确" % [(frame + 1) * 25, quadrant])
		inspector.set_process(true)
	# 清空状态时，悬停框也必须消失；死亡和结算沿用双击面板的关闭规则。
	await _hover(inspector.status_cells.attack.icon.get_global_rect().get_center())
	runtime.clear_battle_buffs()
	await get_tree().create_timer(0.15).timeout
	check(inspector.status_cells.is_empty() and inspector.no_status.visible, "无状态时显示空态")
	check(not inspector.status_tooltip.visible, "状态消失后立即隐藏说明")
	ally.current_state = UnitBase.State.DEATH
	inspector._process(0.1)
	check(not inspector.panel.visible and inspector.inspected == null, "死亡单位详情关闭")
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	print("UNIT_DETAILS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
