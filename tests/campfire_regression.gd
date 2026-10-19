# 篝火真实会话、界面和战场回归：百分比回血、单牌升级、能力点分配与跨场保留。
extends Node
var root: Window
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const SESSION = preload("res://scripts/events/event_session.gd")
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var run := root.get_node("RunManager")
	var soldier: UnitData = load("res://data/units/soldier.tres").duplicate()
	soldier.upgrade_ability_points = 4
	soldier.max_upgrade_count = 2
	var effect_card: CardDefinition = load("res://data/cards/power_enhance.tres").duplicate(true)
	effect_card.max_upgrade_count = 2
	effect_card.effects[0].upgrade_amount = 2
	var base_amount := effect_card.effects[0].amount
	var start := RunStartData.new()
	start.max_hp = 83
	start.starting_hp = 10
	start.cards.assign([soldier, soldier, effect_card, effect_card])
	run.selected_map = {}
	run.start_new_run(start)
	var card: CardInstance = run.deck[0]
	var peer: CardInstance = run.deck[1]
	var spell: CardInstance = run.deck[2]
	var spell_peer: CardInstance = run.deck[3]
	var event: Dictionary = CONFIG.default_event("campfire")
	check(event.choices.size() == 4 and event.choices[0].text == "休憩整备", "篝火提供休憩、训练、强化和离开")
	check(CONFIG.event_error(event).is_empty(), "篝火配置有效")
	event.choices[0].heal_percent = 25.5
	var session = SESSION.new()
	session.configure(event, run)
	session.choose(0)
	session.claim()
	check(run.hp == 32, "按最大血量计算百分比并向上取整")
	check(session.claim().has("error") and run.hp == 32, "休憩不能重复回血")
	run.hp = 82
	session = SESSION.new()
	session.configure(event, run)
	session.choose(0)
	session.claim()
	check(run.hp == 83, "回血不超过最大生命")
	for invalid in [-1, 101, "30", NAN, INF]:
		var bad: Dictionary = event.duplicate(true)
		bad.choices[0].heal_percent = invalid
		check(not CONFIG.event_error(bad).is_empty(), "无效回复百分比被拒绝：" + str(invalid))
	session = SESSION.new()
	session.configure(event, run)
	var offer: Dictionary = session.choose(1)
	check(offer.candidates == [card, peer], "训练只从已有己方兵种牌选择")
	check(session.choose(1).candidates[0] == card, "查看后返回保留具体卡牌候选")
	check(session.claim([-1], Vector2i(4, 0)).has("error"), "无选择时不能升级")
	check(session.claim([0], Vector2i(5, 0)).has("error"), "不能超额分配能力点")
	check(session.claim([0], Vector2i(-1, 5)).has("error"), "不能分配负能力点")
	check(session.claim([0], Vector2i(1, 1)).has("error"), "分配未完成不能消耗训练机会")
	check(card.upgrade_count == 0 and card.attack_points == 0, "失败确认不修改卡牌")
	check(not session.claim([0], Vector2i(1, 3), "missile").has("error"), "训练成功并自主分配攻击和防御、选择飞弹")
	check(card.upgrade_count == 1 and card.attack_points == 1 and card.defence_points == 3, "训练次数和分配记录准确")
	check(peer.upgrade_count == 0 and peer.attack_points == 0 and soldier.attack == peer.unit_data.attack, "同名兵种牌与配置资源互不影响")
	check(session.claim([0], Vector2i(4, 0)).has("error") and card.upgrade_count == 1, "训练重复确认不重复升级")
	check(session.choose(2).has("error"), "训练后不能再选择强化")
	var panel = load("res://scripts/map/event_panel.gd").new()
	panel.size = Vector2(1920, 1080)
	root.add_child(panel)
	panel.open_content(event, run)
	panel._choose(1)
	check(panel.cards_box.visible and panel.confirm_button.disabled, "训练选牌界面未选择时禁用确认")
	panel._select_upgrade(0)
	check(panel.confirm_button.disabled, "未分配能力点时禁用确认")
	panel.attack_input.value = 3
	check(panel.confirm_button.disabled and panel.defence_input.max_value == 1, "属性分配受总点数约束")
	panel.defence_input.value = 1
	check(not panel.confirm_button.disabled, "全部点数分配完成可确认")
	panel.hide()
	panel.show()
	check(panel.selected[0] == 0 and panel.attack_input.value == 3, "查看地图返回保留选牌和分配")
	panel._claim()
	panel._claim()
	check(card.upgrade_count == 2 and card.attack_points == 4 and card.defence_points == 4, "UI 确认只训练一次并累计属性")
	check(not card.can_upgrade(true), "可强化次数达到上限")
	var resolutions: Array[int] = []
	panel.resolved.connect(func(index): resolutions.append(index))
	panel._finish()
	check(resolutions == [1], "训练作为选项 1 正常结算，继续才推进")
	panel.open_content(event, run)
	panel._choose(2)
	check(panel.session.prepared.candidates == [spell, spell_peer], "强化只选择已有非兵种卡")
	panel._select_upgrade(0)
	panel._claim()
	check(spell.upgrade_count == 1 and spell.definition.effects[0].amount == base_amount + 2, "非兵种强化按配置增量修改效果")
	check(spell_peer.definition.effects[0].amount == base_amount and effect_card.effects[0].amount == base_amount, "同名效果卡与共享资源互不影响")
	panel._finish()
	panel.open_content(event, run, true)
	panel._choose(2)
	panel._select_upgrade(0)
	panel._claim()
	check(spell.upgrade_count == 1 and spell.definition.effects[0].amount == base_amount + 2, "试玩强化不改变本局原卡")
	panel.open_content(event, run, true)
	panel._choose(1)
	panel._select_upgrade(0)
	panel.attack_input.value = 4
	panel.soldier_choice.select_branch("slash")
	panel._claim()
	check(peer.upgrade_count == 0, "试玩训练不改变本局原卡")
	panel.open_content(event, run)
	panel._choose(3)
	check(not panel.visible and panel.session.claimed, "四选项篝火的离开正常关闭")
	session = SESSION.new()
	session.configure(event, run)
	session.choose(2)
	session.claim([0])
	check(spell.upgrade_count == 2 and not spell.enhance(), "非兵种卡强化上限生效")
	spell_peer.definition = spell_peer.definition.duplicate(true)
	spell_peer.definition.max_upgrade_count = 0
	check(not spell_peer.can_upgrade(false), "可强化次数为零禁用强化")
	peer.unit_data = peer.unit_data.duplicate()
	peer.unit_data.max_upgrade_count = 0
	session = SESSION.new()
	session.configure(event, run)
	check(session.choose(1).has("error"), "没有符合条件的兵种牌时提示并允许返回")
	session.choose(3)
	check(not session.claim().has("error"), "没有可升级卡仍可离开")
	# 两个真实战场：训练属性出场生效，跨战斗不丢失，不与永久增益重复累加。
	for battle_index in 2:
		var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
		var config := BattleLevelConfig.new()
		config.cards_per_round = 0
		battle.configure_level(config)
		root.add_child(battle)
		await get_tree().physics_frame
		await get_tree().physics_frame
		battle.hand_manager.draw_pile.erase(card)
		battle.hand_manager.hand.append(card)
		battle.hand_manager.draw_pile.erase(spell)
		battle.hand_manager.hand.append(spell)
		battle.battle_round_manager.current_energy = 99
		check(battle.card_runtime.try_play(card, Vector2(450, 450)), "真实战场可部署已训练兵种")
		var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
		unit.set_physics_process(false)
		check(unit.unit_data.attack == soldier.attack + 4 and unit.unit_data.defence == soldier.defence + 4, "训练属性在第 %d 场正确生效且不重复累加" % (battle_index + 1))
		check(battle.card_runtime.try_play(spell, unit.global_position), "真实战场可施放强化后的效果牌")
		check(unit.unit_data.attack == soldier.attack + 4 + int(base_amount + 4), "强化效果以升级后的数值结算")
		battle.queue_free()
		await get_tree().process_frame
	check(card.upgrade_count == 2 and spell.upgrade_count == 2, "跨战斗保留升级次数")
	run.start_new_run(start)
	check(run.deck[0].upgrade_count == 0 and run.deck[0].attack_points == 0 and run.deck[2].definition.effects[0].amount == base_amount, "新局清空强化次数、分配与效果增量")
	var editor = load("res://addons/event_editor/editor.gd").new()
	root.add_child(editor)
	editor.doc.new_event(3)
	editor.rest_percent_input.value = 42.5
	editor.apply_inputs()
	check(editor.doc.event.rest_heal_percent == 42.5 and editor.doc.event.to_content().choices[0].heal_percent == 42.5, "事件工坊可配置回复百分比")
	check(editor.doc.event.validate().is_empty(), "新建篝火配方通过验证")
	var map_doc = load("res://addons/map_editor/document.gd").new()
	map_doc.new_map(true)
	check(map_doc.draft_error(map_doc.data).is_empty(), "原生地图草稿支持四选项篝火")
	var labels = load("res://addons/game_config_editor/labels.gd")
	check(labels.KEYS.allies.has("upgrade_ability_points") and labels.KEYS.allies.has("max_upgrade_count"), "己方单位特性显示升级能力点数及可强化次数")
	check(labels.KEYS.cards.has("max_upgrade_count"), "卡牌效果显示可强化次数")
	if OS.get_cmdline_user_args().has("--capture"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.maintenance/campfire"))
		editor.hide()
		panel.open_content(event, run)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/campfire/story.png")
		panel._choose(1)
		panel._select_upgrade(0)
		panel.attack_input.value = 2
		panel.defence_input.value = 2
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/campfire/training.png")
	panel.queue_free()
	editor.queue_free()
	await get_tree().process_frame
	print("CAMPFIRE_TEST: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
