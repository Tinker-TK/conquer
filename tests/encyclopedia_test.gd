extends SceneTree
## 三条/页、不重复、原生文字与条目滚动、真实纸面点击、暂停与只读检查。

var CATALOG: Script
var REWARDS: Script
const OUT := "res://.maintenance/encyclopedia"
var checks := 0
var failures: Array[String] = []
var game: Node
var atlas: Control
var run: Node


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("ENCYCLOPEDIA_CHECK: " + message)


func frames() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw


func click(control: Control) -> void:
	await click_point(control.get_global_rect().get_center())


func click_point(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame


func paper_point(side: int, point: Vector2 = Vector2(0.5, 0.45)) -> Vector2:
	var canvas := Vector2(60 + side * 180, 66) + point * Vector2(180, 230)
	return atlas.book.get_global_transform_with_canvas() * atlas.book.get_layout_transform() * canvas


func wheel(point: Vector2, down: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = point
	root.push_input(event, true)
	await frames()


func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func settle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while atlas.book.turning and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not atlas.book.turning, "图鉴翻页必须结束")
	await frames()


func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await frames()
		root.get_texture().get_image().save_png(OUT + "/" + name + ".png")


func snapshot() -> Array:
	return [run.hp, run.gold, run.current_id, run.deck.duplicate(), run.relics.duplicate(), run.potions.duplicate(), run.seen_events.duplicate(), run.discovered_relics.duplicate()]


func _run() -> void:
	CATALOG = load("res://scripts/ui/encyclopedia_catalog.gd")
	REWARDS = load("res://scripts/events/event_rewards.gd")
	create_timer(80).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	run = root.get_node("RunManager")
	root.get_node("GameSettings").set_audio("master_volume", 0.0)
	run.use_default_map()
	run.start_new_run()
	run.starting_reward_pending = false
	game = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var hud := get_first_node_in_group("run_items_hud")
	check(hud != null and not hud.has_node("Hint"), "主界面移除药水带提示文字")
	check(hud.find_children("*", "Button", true, false).all(func(button): return button.text != "遗物图鉴"), "主界面移除旧遗物图鉴入口")
	await capture("map-clean")
	var before := snapshot()
	await click(game.get_node("HUDLayer/RunHUD/TopButtons/Setting"))
	check(game.pause_menu.opened and paused, "实际顶部设置按钮打开暂停菜单")
	check(game.pause_menu.buttons.map(func(button): return button.text) == ["继续", "设置", "图鉴", "保存并退出"], "设置菜单加入图鉴按钮")
	await capture("pause-with-encyclopedia")
	await click(game.pause_menu.buttons[2])
	atlas = game.pause_menu.encyclopedia
	check(atlas != null and atlas.visible and paused and not game.pause_menu.menu.visible, "真实图鉴按钮打开书本并保持暂停")
	var book_bounds: Rect2 = atlas.book.get_global_transform_with_canvas() * atlas.book.get_layout_transform() * Rect2(43, 55, 394, 254)
	check(book_bounds.size.x > root.size.x * 0.94 and book_bounds.size.y > root.size.y * 0.74, "书本铺满页头下方主要区域")
	check(atlas.book._view.size.x > 2500 and atlas.book._view.size.y > 1500, "提高书本文字绘制分辨率")
	check(atlas.previous.get_parent() == atlas.bookmark_root and atlas.next.get_parent() == atlas.bookmark_root, "上下页按钮移入书页")
	check(not atlas.find_children("*", "Label", true, false).any(func(label): return label.text.contains("跨页") or label.text.contains("Esc 返回设置")), "移除书外底部页码与说明")
	var data: Dictionary = atlas.catalog
	check(data.relics.size() == REWARDS.pool([], "relic").size(), "遗物图鉴覆盖全部有效遗物")
	check(data.potions.size() == REWARDS.pool([], "potion").size(), "药水图鉴覆盖全部有效药水")
	check(data.events.size() == REWARDS.catalog().size(), "事件图鉴覆盖全部事件配方")
	var counts := {}
	for category in CATALOG.KEYS:
		counts[category] = data[category].size()
		check(not data[category].is_empty(), category + " 分类必须有内容")
		var ids := {}
		var models: Array = CATALOG.spreads(data[category])
		var displayed_ids: Array = []
		for model: Dictionary in models:
			check(model.entries.size() <= 6, "每个展开页最多六个词条：" + category)
			for entry: Dictionary in model.entries: displayed_ids.append(entry.id)
		check(displayed_ids.size() == data[category].size(), "三个词条一页的排版保留全部条目：" + category)
		for entry: Dictionary in data[category]:
			check(not ids.has(entry.id), category + " 条目不重复：" + entry.id)
			ids[entry.id] = true
			if category in ["allies", "enemies"]:
				check(entry.source.unit_team == ("team_a" if category == "allies" else "team_b"), "单位按真实阵营分类：" + entry.title)
			check(displayed_ids.count(entry.id) == 1, "词条在整本分类内只出现一次：" + entry.title)
		check(CATALOG.spreads(data[category] + data[category])[0].entries.size() == 6, "输入重复条目时仍去重")
	check(data.allies.any(func(entry): return entry.source.resource_path.begins_with("res://data/event_recruits/")), "己方图鉴包含事件征召兵种")
	var troll: Dictionary = data.enemies.filter(func(entry): return entry.source.unit_english_name == "troll")[0]
	check(CATALOG.icon_for(troll) != null, "无卡面的敌军从只读场景取得肖像")
	check(root.find_children("*", "UnitBase", true, false).is_empty(), "读图鉴不创建战斗单位")
	for category in CATALOG.KEYS.size():
		await click(atlas.bookmarks[category])
		await settle()
		check(atlas.category == category and atlas.current_index == 0, "真实书签切换分类并回到首页：" + CATALOG.NAMES[category])
		check(not atlas.book.show_bookmark and atlas.bookmarks.size() == 5, "使用五枚分类书签")
		check(atlas.previous.disabled and not atlas.next.disabled, "首跨页边界与翻页按钮")
		var pair: Array = atlas.page_cache[0]
		for side in 2:
			var sheet: Control = pair[side].get_child(0)
			check(sheet.entries.size() == 3 and sheet.readers.size() == 3, "左右每张纸各展示三个完整词条")
			check(pair[side].size == Vector2i(840, 740), "纸面使用原生清晰文字分辨率")
			for i in sheet.readers.size():
				var entry: Dictionary = sheet.entries[i]
				var expected := ""
				for section: Dictionary in entry.sections: expected += str(section.title) + str(section.text)
				var actual: String = sheet.readers[i].get_parsed_text()
				check(actual.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "") == expected.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", ""), "同一词条保留完整技能与说明：" + entry.title)
				check(sheet.readers[i].get_theme_font_size("normal_font_size") >= 20, "说明使用清晰的正文字号")
		await capture(CATALOG.KEYS[category])
		var original_index: int = atlas.current_index
		await click_point(paper_point(1))
		check(atlas.book.turning and atlas.book.direction == 1 and atlas.search.editable == false, "点击右侧说明文字直接向后翻页并锁定筛选")
		atlas.book.seek_turn(0.43)
		await capture(CATALOG.KEYS[category] + "-turn")
		if category == 1:
			var stays_in_frame := true
			for step in 21:
				atlas.book.seek_turn(float(step) / 20)
				var motion: Transform2D = atlas.book.get_motion_transform()
				var frame: Rect2 = atlas.book.fitting_rect.grow(0.1)
				stays_in_frame = stays_in_frame and frame.encloses(motion * atlas.book.fitting_rect)
				for layer in atlas.book.leaf_count:
					var amount := clampf(atlas.book.progress * (1.0 + 0.14 * (atlas.book.leaf_count - 1)) - layer * 0.14, 0.0, 1.0)
					for point in atlas.book._page_points(amount, layer): stays_in_frame = stays_in_frame and frame.has_point(motion * point)
			check(stays_in_frame, "满版书本的弯曲纸面与回弹不遮住页头或裁掉书签")
			atlas.book.seek_turn(0.72)
			await capture("allies-landing")
		atlas.book.finish_turn(true)
		await settle()
		check(atlas.current_index == original_index + 1 and atlas.search.editable, "落页只推进一个跨页并恢复控件")
		await click_point(paper_point(0))
		check(atlas.book.turning and atlas.book.direction == -1, "点击左侧说明文字直接向前翻页")
		await settle()
		check(atlas.current_index == original_index, "反向翻页回到原跨页")
		check(atlas.page_cache.size() <= 3 and atlas.get_children().filter(func(child): return child is SubViewport).size() <= 6, "纸面视口缓存数量有界")
	# 搜索、无结果与目录直达；目录跳转同样使用书本翻页。
	var wanted: String = data.events[-1].title
	atlas.search.text = wanted
	atlas._filter()
	await frames()
	check(atlas.spreads.any(func(model): return model.entries.any(func(entry): return entry.title == wanted)), "搜索当前分类的标题与说明")
	atlas.search.text = "没有这个图鉴条目_zzzz"
	atlas._filter()
	await frames()
	check(atlas.spreads.size() == 1 and atlas.spreads[0].entries.is_empty() and atlas.previous.disabled and atlas.next.disabled, "无搜索结果有空白说明且禁止翻页")
	atlas.search.text = ""
	atlas._filter()
	await frames()
	var popup: PopupMenu = atlas.directory.get_popup()
	await click(atlas.directory)
	check(popup.visible, "真实目录按钮打开条目菜单")
	await key(KEY_ESCAPE)
	check(atlas.visible and not popup.visible and paused, "Esc 先关闭目录而不退出图鉴")
	var target_entry: int = popup.get_item_id(popup.item_count - 1)
	@warning_ignore("integer_division")
	var target: int = target_entry / 6
	popup.id_pressed.emit(target_entry)
	check(atlas.book.turning, "目录选择也播放翻页动画")
	await settle()
	check(atlas.current_index == target, "目录定位到条目首个跨页")
	# 实际纸面内的按钮与长技能滚动；同一单位不会为说明续页复制图文。
	atlas.select_category(1)
	await settle()
	atlas.search.text = "熊人"
	atlas._filter()
	await frames()
	check(atlas.spreads.size() == 1 and atlas.spreads[0].entries.size() == 1, "长技能单位仅占一个词条，不重复到其他页")
	var bear_sheet: Control = atlas.page_cache[0][0].get_child(0)
	var reader: RichTextLabel = bear_sheet.readers[0]
	var scroll := reader.get_v_scroll_bar()
	check(scroll.max_value > scroll.page, "长技能保留可滚动的完整正文")
	var scroll_before := scroll.value
	for i in 5:
		await wheel(paper_point(0, Vector2(0.65, 0.23)))
	check(scroll.value > scroll_before and not atlas.book.turning, "纸面内滚轮阅读说明，不触发翻页")
	await capture("unit-description")
	scroll.value = 0
	var thumb: Vector2 = scroll.get_global_rect().position + Vector2(scroll.size.x * 0.5, 8)
	var thumb_point := paper_point(0, thumb / Vector2(840, 740))
	var press := InputEventMouseButton.new()
	press.position = thumb_point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	check(atlas.scroll_side == 0 and not atlas.book.turning, "点击条目滚动条不会误翻书")
	var drag := InputEventMouseMotion.new()
	drag.position = thumb_point + Vector2(0, 50)
	drag.relative = Vector2(0, 50)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	await frames()
	press.pressed = false
	press.position = drag.position
	root.push_input(press, true)
	await frames()
	check(scroll.value > 0 and atlas.scroll_side == -1 and not atlas.book.turning, "条目滚动条支持拖动并正确释放鼠标")
	atlas.search.text = ""
	atlas._filter()
	await frames()
	await click(atlas.next)
	await settle()
	check(atlas.current_index == 1, "书页内下一页按钮可用")
	await click(atlas.previous)
	await settle()
	check(atlas.current_index == 0, "书页内上一页按钮可用")
	# 动画中 Esc 返回菜单必须清理临时纸面，不能解开外层暂停。
	atlas.select_category(0)
	check(atlas.book.turning, "退出检查前存在正在翻动的分类页")
	await key(KEY_ESCAPE)
	check(not atlas.visible and game.pause_menu.menu.visible and paused and not atlas.book.turning and atlas.pending.is_empty(), "图鉴 Esc 返回设置菜单并取消未完成翻页")
	await click(game.pause_menu.buttons[2])
	await frames()
	check(atlas.visible and atlas.book.spread_index == atlas.current_index, "再次打开不会留下错误页码或旧分类纹理")
	await click(atlas.close_button)
	check(game.pause_menu.menu.visible and paused, "返回设置按钮不恢复战斗")
	await key(KEY_ESCAPE)
	check(not game.pause_menu.opened and not paused, "关闭外层设置才恢复原暂停状态")
	game._on_deck_pressed()
	check(paused and game.deck_open, "打开卡组形成已有暂停")
	game._on_settings_pressed()
	game.pause_menu.show_encyclopedia()
	await frames()
	game.pause_menu.show_menu()
	game.pause_menu.close()
	check(paused and game.deck_open, "嵌套图鉴关闭后保持卡组暂停")
	game._close_deck()
	check(snapshot() == before, "浏览所有分类不改变生命、金币、库存、牌组、事件或发现记录")
	game.queue_free()
	await frames()
	await frames()
	print("ENCYCLOPEDIA_COUNTS: ", counts)
	print("ENCYCLOPEDIA_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
