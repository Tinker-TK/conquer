# 独立窗口启动参数打开同一设置页，继续存档只消费一次。
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings := root.get_node("GameSettings")
	var run := root.get_node("RunManager")
	var transition := root.get_node("SceneTransition")
	transition.reduced_motion = true
	var resume := "--resume-settings" in OS.get_cmdline_user_args()
	if resume:
		run.use_default_map()
		run.start_new_run()
		run.gold = 345
		assert(run.save_run().is_empty())
		run.start_new_run()
	var main = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	while transition.busy:
		await process_frame
	for i in 5:
		await process_frame
	if resume:
		assert(current_scene.scene_file_path == "res://scenes/app/game_session.tscn")
		assert(run.gold == 345 and current_scene.pause_menu.settings.visible and paused)
		assert(not settings.resume_settings_pending)
	else:
		assert(main.panel_open == "settings" and main.settings_panel.visible)
	assert(not settings.consume_startup_settings())
	root.get_node("GameAudio").stop_all()
	paused = false
	current_scene.queue_free()
	await create_timer(.2).timeout
	print("SETTINGS_STARTUP_PASS: resume=%s" % resume)
	quit()
