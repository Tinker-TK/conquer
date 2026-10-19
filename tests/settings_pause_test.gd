# 真实外壳验证暂停输入、设置应用/持久化及存档重开，图形运行可导出界面截图。
extends SceneTree
var checks := 0
var game: Node
var settings: Node
var run: Node
const OUT := "res://.maintenance/settings"

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("SETTINGS_TEST: " + message)
		quit(1)
		assert(condition, message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK, "截图保存")

func click_at(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	settings = root.get_node("GameSettings")
	run = root.get_node("RunManager")
	if "--verify-saved-run" in OS.get_cmdline_user_args():
		check(run.load_saved_run().is_empty(), "重启进程读取存档")
		check(run.hp == 103 and run.max_hp == 120 and run.gold == 333 and run.deck[0].attack_points == 3, "跨进程恢复数据")
		check(run.relics.size() == 1 and run.potions.size() == 1 and run.relic_draw_counts.get(&"draw_engine") == 7, "跨进程恢复物品和遗物进度")
		check(is_equal_approx(settings.audio.master_volume, 0.37) and settings.video.fps == 60, "重启自动恢复设置")
		print("SETTINGS_RESTART_PASS: %d checks" % checks)
		quit()
		return
	var transition := root.get_node("SceneTransition")
	transition.reduced_motion = true
	settings.reset_video()
	settings.set_video("resolution", Vector2i(1280, 720))
	settings.set_audio("mute_in_background", false)
	run.use_default_map()
	run.start_new_run()
	var main = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(0.3).timeout
	main._on_start_pressed()
	# 本项从完成开局奖励后的地图检查设置；三选一交互由 balance-ui 覆盖。
	run.starting_reward_pending = false
	while transition.busy:
		await process_frame
	game = current_scene
	await create_timer(0.3).timeout
	# 真实顶部按钮点击打开模态；背景按钮点不到，继续恢复原暂停状态。
	var top_button: Button = game.get_node("HUDLayer/RunHUD/TopButtons/Setting")
	await click_at(top_button.get_global_rect().get_center())
	check(game.pause_menu.opened and paused, "顶部设置暂停")
	check(game.pause_menu.buttons.size() == 4, "四个菜单按钮")
	check(game.pause_menu.buttons.map(func(button): return button.text) == ["继续", "设置", "图鉴", "保存并退出"], "菜单内容")
	await capture("pause")
	await click_at(game.deck_button.get_global_rect().get_center())
	check(not game.deck_open and game.pause_menu.opened, "模态拦截背景卡组")
	game.pause_menu.buttons[1].pressed.emit()
	var panel: Control = game.pause_menu.settings
	check(panel.visible and panel.tabs.size() == 2, "仅视频与音频两个页签")
	panel.controls.monitor.get_popup().popup()
	await process_frame
	await key(KEY_ESCAPE)
	check(panel.visible and not panel.controls.monitor.get_popup().visible and paused, "Esc优先关闭下拉列表")
	await capture("video")
	panel.controls.resizable.button_pressed = false
	check(not settings.video.resizable, "窗口缩放开关应用")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED), "窗口实际禁止缩放")
	panel._cycle("fps", 1)
	check(Engine.max_fps == 90, "帧数上限即时应用")
	panel._cycle("vsync", -1)
	check(settings.video.vsync == 1, "垂直同步切换")
	panel._cycle("msaa", 1)
	check(root.msaa_2d == Viewport.MSAA_4X, "MSAA即时应用")
	panel.controls.aspect.item_selected.emit(2)
	check(root.content_scale_size == Vector2i(1920, 1440), "宽高比改变渲染画布")
	await process_frame
	await capture("video_4_3")
	settings.reset_video()
	settings.set_video("resolution", Vector2i(1280, 720))
	check(settings.video.fps == 60 and settings.video.resizable and settings.video.msaa == 1, "视频重置默认")
	panel.select_tab(1)
	for pair in [["master_volume", 37], ["music_volume", 43], ["sfx_volume", 29], ["ambience_volume", 61]]:
		panel.controls[pair[0]].value = pair[1]
	for pair in [[&"Master", 0.37], [&"Music", 0.43], [&"SFX", 0.29], [&"Ambience", 0.61]]:
		check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(pair[0]))), pair[1]), "总线音量 " + str(pair[0]))
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"CombatSFX")) == &"SFX", "战斗音效接入音效音量")
	panel.controls.sfx_volume.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "零音量完全静音")
	panel.controls.sfx_volume.value = 29
	panel.controls.mute_in_background.button_pressed = true
	settings._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(AudioServer.is_bus_mute(0), "后台静音")
	settings._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not AudioServer.is_bus_mute(0), "返回窗口恢复音量")
	settings.set_audio("mute_in_background", false)
	settings.audio.master_volume = 1.0
	settings.video.fps = 240
	settings.load_settings()
	settings.apply_audio()
	settings.apply_video()
	check(is_equal_approx(settings.audio.master_volume, 0.37) and settings.video.fps == 60, "设置从磁盘恢复")
	await capture("audio")
	await key(KEY_ESCAPE)
	check(game.pause_menu.menu.visible and paused, "设置Esc返回暂停菜单")
	await key(KEY_ESCAPE)
	check(not game.pause_menu.opened and not paused, "菜单Esc继续")
	# 从已暂停的卡组再开菜单，关闭不能错误地恢复战斗。
	game._on_deck_pressed()
	check(paused, "卡组暂停")
	game._on_settings_pressed()
	game.pause_menu.close()
	check(paused and game.deck_open, "嵌套暂停恢复")
	game._close_deck()
	# 永久强化、重复牌独立性、遗物/药水及自定义路线均落盘。
	var trained = run.deck[0]
	run.add_relic(load("res://data/relics/draw_engine.tres"))
	run.add_potion(load("res://data/potions/lightning.tres"))
	run.relic_draw_counts[&"draw_engine"] = 7
	trained.attack_points = 3
	trained.defence_points = 2
	trained.upgrade_count = 1
	trained.permanent_buffs.assign([{"id": "saved_buff", "attack": 2}])
	var enhanced = null
	for card in run.deck:
		if not card.is_unit_card() and not card.definition.effects.is_empty():
			enhanced = card
			break
	check(enhanced != null, "强化卡牌样本")
	enhanced.definition = enhanced.definition.duplicate(true)
	enhanced.definition.effects[0].amount += 4
	var enhanced_amount: float = enhanced.definition.effects[0].amount
	run.max_hp = 120
	run.hp = 103
	run.gold = 333
	run.map_scroll = 150
	var card_count: int = run.deck.size()
	var relic_count: int = run.relics.size()
	var potion_count: int = run.potions.size()
	check(run.save_run().is_empty(), "保存征途")
	run.start_new_run()
	check(run.load_saved_run().is_empty(), "从磁盘继续征途")
	check(run.hp == 103 and run.max_hp == 120 and run.gold == 333, "恢复血量与金币")
	check(run.deck.size() == card_count and run.relics.size() == relic_count and run.potions.size() == potion_count, "恢复卡牌与物品")
	check(run.deck[0].attack_points == 3 and run.deck[0].defence_points == 2 and run.deck[0].upgrade_count == 1 and run.deck[0].permanent_buffs.size() == 1, "恢复独立训练状态")
	check(run.deck[1].attack_points == 0 and run.deck[1].permanent_buffs.is_empty(), "同名牌状态保持独立")
	for card in run.deck:
		if not card.is_unit_card() and not card.definition.effects.is_empty():
			check(card.definition.effects[0].amount == enhanced_amount, "恢复强化后的效果配方")
			break
	# 地点进入前快照阻止战斗药水/事件奖励在退出重开时重复获得。
	# 随机地图不再使用旧固定节点 battle_a；从当前可进入的普通战斗验证保存重开。
	var available_battles: Array = game.map_view.locations.filter(func(location):
		return int(location.type) == 0 and game.map_view.node_views[str(location.id)].can_enter)
	check(not available_battles.is_empty(), "地图提供可进入的战斗样本")
	game.map_view._on_node_enter_requested(game.map_view.node_views[str(available_battles[0].id)])
	while transition.busy:
		await process_frame
	check(is_instance_valid(game.current_battle), "真实进入战场")
	run.gold += 50
	run.hp -= 7
	run.deck[0].cost_increase = 4
	game._on_settings_pressed()
	check(paused, "真实战斗暂停")
	await capture("battle_pause")
	game.pause_menu.buttons[3].pressed.emit()
	while transition.busy:
		await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/ui/main_ui.tscn" and not paused, "保存并退出返回主菜单且解除暂停")
	check(current_scene.continue_button.visible, "主菜单显示继续征途")
	current_scene.continue_button.pressed.emit()
	while transition.busy:
		await process_frame
	check(current_scene.scene_file_path == "res://scenes/app/game_session.tscn", "主菜单继续存档")
	check(run.gold == 333 and run.hp == 103 and run.deck[0].cost_increase == 0, "未完成战斗恢复进入前数据")
	check(run.completed_ids.is_empty() and run.pending_battle_id.is_empty() and current_scene.map_layer.visible, "重开未完成节点不插旗")
	# 单独检查导入路线与已完成地点；之后还原用于跨进程检查的征途快照。
	var checkpoint: Resource = run.create_save_data()
	run.active_map = {"name": "存档测试路线", "locations": [{"id": "a", "next": ["boss"]}, {"id": "boss", "next": []}]}
	run.map_terminal_ids.assign(["boss"])
	run.completed_ids.assign(["a"])
	run.current_id = "a"
	check(run.save_run().is_empty(), "保存自定义路线与进度")
	run.active_map.clear()
	run.completed_ids.clear()
	check(run.load_saved_run().is_empty() and run.active_map.name == "存档测试路线" and run.completed_ids == ["a"] and run.current_id == "a" and run.map_terminal_ids == ["boss"], "恢复路线快照与完成旗帜")
	run.location_checkpoint = checkpoint
	check(run.save_run(true).is_empty(), "恢复跨进程测试存档")
	print("SETTINGS_PAUSE_PASS: %d checks" % checks)
	quit()
