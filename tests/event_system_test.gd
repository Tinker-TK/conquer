extends SceneTree
var REWARDS
var SESSION
var CONFIG
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	REWARDS = load("res://scripts/events/event_rewards.gd")
	SESSION = load("res://scripts/events/event_session.gd")
	CONFIG = load("res://scripts/map/fixed_map_config.gd")
	var run := root.get_node("RunManager")
	run.selected_map = {}
	run.start_new_run()
	var startup_offer: Dictionary = REWARDS.prepare(REWARDS.content("forgotten_reliquary").choices[0], run.relics, RandomNumberGenerator.new())
	check(startup_offer.has("reward"), "默认开局仍有可以获得的新遗物")
	run.relics.clear()
	var events: Array = REWARDS.catalog()
	check(events.size() >= 3, "三类事件资源可加载")
	for event in events:
		check(event.validate().is_empty(), "事件模板校验：" + event.id)
		check(event.illustration != null and event.illustration.get_width() > 0, "每个正式事件都有可加载的独立插画：" + event.id)
	check(load("res://data/events/campfire.tres").illustration != load("res://data/events/crossroads_recruitment.tres").illustration,
		"篝火与援军不再共用插画")
	var relic_event: Resource = load("res://data/events/forgotten_reliquary.tres")
	var session = SESSION.new()
	session.configure(relic_event.to_content(), run)
	var offer: Dictionary = session.choose(0)
	check(offer.has("reward"), "生成可用随机遗物")
	var before: int = run.relics.size()
	var chosen: Array[int] = [0]
	check(not session.claim(chosen).has("error") and run.relics.size() == before + 1, "遗物选择后加入本局")
	check(session.claim().has("error") and run.relics.size() == before + 1, "重复点击不能重复发奖")
	var filtered: Dictionary = relic_event.to_content()
	filtered.choices[0].effect.pool = [offer.reward.resource_path]
	session = SESSION.new()
	session.configure(filtered, run)
	check(session.choose(0).has("error"), "排除已拥有遗物且允许离开")
	session.choose(1)
	session.claim()
	check(run.relics.size() == before + 1, "离开没有额外奖励")
	var potion_event: Resource = load("res://data/events/wandering_alchemist.tres")
	session = SESSION.new()
	session.configure(potion_event.to_content(), run)
	session.choose(0)
	before = run.potions.size()
	session.claim()
	check(run.potions.size() == before + 1, "药水加入本局")
	# 旧的两组五选一仍须兼容；正式援军现已改成教学单组三选一。
	var cards_event: Resource = load("res://data/events/crossroads_recruitment.tres").duplicate(false)
	# 旧的两组五选一契约；避免 SceneTree 启动前静态加载领域类。
	cards_event.template = 2 # EventDefinition.Template.CHOOSE_CARDS
	session = SESSION.new()
	session.configure(cards_event.to_content(), run)
	offer = session.choose(0)
	check(offer.units.size() == 5 and offer.effects.size() == 5, "兵种与效果各五张")
	var unique: Dictionary = {}
	for card in offer.units + offer.effects:
		unique[card.resource_path] = true
		check(not card.card_name.is_empty() and card.card_image != null, "候选必须有名称和卡面")
	check(unique.size() == 10, "十张候选不重复")
	check(session.choose(0) == offer, "反复打开不重抽候选")
	before = run.deck.size()
	check(session.claim(selection(0, -1)).has("error") and run.deck.size() == before, "未选满两组不领奖")
	check(not session.claim(selection(2, 4)).has("error") and run.deck.size() == before + 2, "选择两组后获得两张永久牌")
	check(run.deck[-2].unit_data != null and run.deck[-1].definition.category != 0, "一张兵种和一张效果牌")
	var bad: Dictionary = cards_event.to_content()
	bad.choices[0].effect.unit_pool = ["res://data/units/soldier.tres"]
	check(not CONFIG.event_error(bad).is_empty(), "不足五种的池被拒绝")
	bad = cards_event.to_content()
	bad.choices[0].effect.type = "future_unknown"
	check(not CONFIG.event_error(bad).is_empty(), "未知效果不能静默发奖")
	check(CONFIG.event_content({"event_source": "catalog", "event_id": cards_event.id}).title == cards_event.title, "地图按编号读取工坊事件")
	var panel = load("res://scripts/map/event_panel.gd").new()
	panel.size = Vector2(1920, 1080)
	root.add_child(panel)
	# 老存档可能冻结着旧 SVG 路径；打开时选择对应主题，不改变原奖励或自定义插图。
	var old_camp: Dictionary = CONFIG.default_event("campfire").duplicate(true)
	old_camp.illustration = "res://assets/ui/events/recruit_camp.svg"
	panel.open_content(old_camp, run)
	check(panel.art.texture == load("res://data/events/campfire.tres").illustration, "旧版篝火快照展示新的休憩插画")
	var old_recruits: Dictionary = cards_event.to_content().duplicate(true)
	old_recruits.illustration = "res://assets/ui/events/recruit_camp.svg"
	panel.open_content(old_recruits, run)
	check(panel.art.texture == cards_event.illustration, "同一旧 SVG 路径的援军快照仍展示援军插画")
	var supplies: Dictionary = CONFIG.default_event("abandoned_camp")
	panel.open_content(supplies, run)
	check(panel.art.texture.resource_path == supplies.illustration, "遗弃兵营补给事件有专用插画")
	var custom_art: Dictionary = cards_event.to_content().duplicate(true)
	custom_art.illustration = "res://assets/ui/comic_menu/fantasy-battle.png"
	panel.open_content(custom_art, run)
	check(panel.art.texture.resource_path == custom_art.illustration, "工坊显式指定的自定义插图保持有效")
	panel.open_content({"title": "字面文案", "description": "[b]未经格式化的文案[/b]", "choices": supplies.choices}, run)
	check(panel.description_label.get_parsed_text() == "[b]未经格式化的文案[/b]", "自动高亮不会把事件正文中的方括号解释为标记")
	panel.open_content(cards_event.to_content(), run)
	check(panel.choice_1.get_node("ChoiceCaption").mouse_filter == Control.MOUSE_FILTER_IGNORE, "双行选项装饰不拦截真实按钮点击")
	panel._choose(0)
	check(panel.confirm_button.disabled, "未选择时禁用确认")
	panel._select_card(0, 0)
	check(panel.confirm_button.disabled, "只选兵种不能确认")
	panel.hide()
	panel.show()
	check(panel.selected[0] == 0, "查看地图再返回保留选择")
	panel._select_card(1, 1)
	check(not panel.confirm_button.disabled, "两组完成才允许确认")
	before = run.deck.size()
	panel._claim()
	panel._claim()
	check(run.deck.size() == before + 2, "界面连续确认只发一次奖励")
	var resolutions: Array[int] = []
	panel.resolved.connect(func(index): resolutions.append(index))
	panel._finish()
	panel._finish()
	check(resolutions.size() == 1, "继续只完成一次地图节点")
	panel.open_content(cards_event.to_content(), run, true)
	panel._choose(0)
	panel._select_card(0, 0)
	panel._select_card(1, 0)
	before = run.deck.size()
	panel._claim()
	check(run.deck.size() == before, "编辑器试玩不改变正式牌组")
	var editor = load("res://addons/event_editor/editor.gd").new()
	root.add_child(editor)
	await process_frame
	check(editor.doc.event != null and editor.preview.visible, "事件工坊表单和预览初始化")
	editor.doc.new_event(2)
	editor.inputs.title.text = "测试新事件"
	editor.apply_inputs()
	check(editor.doc.event.title == "测试新事件", "表单提交到草稿")
	editor.doc.undo()
	check(editor.doc.event.title != "测试新事件", "事件编辑可撤销")
	editor.doc.redo()
	check(editor.doc.event.title == "测试新事件", "事件编辑可重做")
	check(editor.doc.event.validate().is_empty(), "草稿模板保留合法奖励池")
	var recovery_before: String = editor.doc.fingerprint()
	check(editor.doc.recover_save(), "事件草稿可保存")
	check(editor.doc.recover() and editor.doc.fingerprint() == recovery_before, "恢复草稿不丢失文案和效果")
	# 正式保存器的往返与外部修改保护；只创建测试专用编号。
	editor.doc.event.id = "event_test_" + str(Time.get_ticks_usec())
	var test_path: String = "res://data/events/" + editor.doc.event.id + ".tres"
	editor.doc.event.unit_pool.assign(REWARDS.pool([], "unit").slice(0, 5))
	editor.doc.event.effect_pool.assign(REWARDS.pool([], "effect").slice(0, 5))
	check(editor.doc.save(test_path), "新事件资源可原子保存")
	var saved_event: Resource = ResourceLoader.load(test_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved_event != null and saved_event.to_content() == editor.doc.event.to_content(), "保存后插图和两个奖励池无损回读")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("external test change")
	file.close()
	check(not editor.doc.save(test_path), "磁盘外部修改被保护")
	DirAccess.remove_absolute(test_path)
	# 真实游戏外壳：领取后继续才完成地点，查看地图/卡组保留事件会话。
	var game = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var map = game.map_view
	run.complete_location("battle_a")
	map.resume_after_battle()
	map._on_node_selection_started(map.node_views.event_a)
	map._on_node_enter_requested(map.node_views.event_a)
	before = run.potions.size()
	map.event_panel._choose(0)
	check(run.potions.size() == before + 1 and not run.completed_ids.has("event_a"), "领取奖励后等待继续再完成地图")
	game._on_map_pressed()
	check(not map.event_panel.visible and map.view_only, "事件中查看地图")
	game._on_map_pressed()
	check(map.event_panel.visible and map.event_panel.session.claimed, "返回时保留已领取的事件状态")
	game._on_deck_pressed()
	game._close_deck()
	check(map.event_panel.visible and not paused, "事件中查看卡组并恢复")
	map.event_panel._finish()
	check(run.completed_ids.has("event_a") and map.pending_id.is_empty() and map.locked_node_id.is_empty(), "继续后解锁下个地图节点")
	game.queue_free()
	var legacy: Dictionary = CONFIG.default_event("campfire")
	run.hp = 10
	session = SESSION.new()
	session.configure(legacy, run)
	session.choose(0)
	session.claim()
	var expected_hp := mini(run.max_hp, 10 + int(ceil(run.max_hp * float(legacy.choices[0].heal_percent) / 100.0)))
	check(run.hp == expected_hp, "篝火按最大生命的百分比回复")
	editor.queue_free()
	panel.queue_free()
	await process_frame
	print("EVENT_SYSTEM_TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func selection(unit: int, effect: int) -> Array[int]:
	return [unit, effect]
