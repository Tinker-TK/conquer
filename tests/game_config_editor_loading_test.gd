# 验证配置面板首次显示时自动读取，以及未载入和读取失败时的操作保护。
# 读取真实配置但不应用修改；恢复文件仅使用测试专用路径。
extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		push_error(text)

func _run() -> void:
	var panel = load("res://addons/game_config_editor/editor.gd").new()
	panel.doc.recovery_path = "user://game_config_editor_loading_test_recovery.json"
	panel.hide()
	root.add_child(panel)
	await process_frame
	check(not panel.bridge.is_busy(), "隐藏面板不抢在编辑器初始化和资源扫描期间读取")
	check(panel.toolbar.filter(func(button: Button): return button.text == "校验")[0].disabled, "未载入时禁止校验空文档")
	for title in ["导出 HTML / JSON…", "+ 新增配置行", "+ 新增字段列", "修改清单"]:
		check(panel.toolbar.filter(func(button: Button): return button.text == title)[0].disabled, "未载入时禁止操作：" + title)
	for title in ["重读", "导入合集…", "工具设置…"]:
		check(not panel.toolbar.filter(func(button: Button): return button.text == title)[0].disabled, "未载入时仍可恢复：" + title)
	check(panel.heading.text.contains("尚未载入"), "未载入状态与有效的空表区分显示")
	# 旧版本在这里已启动后台读取，先结束，避免对同一桥接重复执行任务。
	if panel.bridge.is_busy():
		panel.shutdown()
	panel._check()
	check(not panel.bridge.is_busy() and panel.status.text.contains("尚未载入"), "直接调用校验也不会把空字典送到后端")
	panel.message.hide()
	panel.show()
	await process_frame
	var deadline := Time.get_ticks_msec() + 15000
	while panel.bridge.is_busy() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not panel.bridge.is_busy() and panel.doc.data.get("records", []).size() > 100, "首次显示自动读取实际游戏配置")
	if panel.doc.data.is_empty():
		panel.shutdown()
		panel.free()
		quit(1)
		return
	await process_frame
	check(not panel.visible_rows.is_empty(), "自动读取后表格显示实际配置行")
	check(not panel.toolbar.filter(func(button: Button): return button.text == "校验")[0].disabled, "载入成功后恢复校验操作")
	var original: Dictionary = panel.doc.data.duplicate(true)
	# 已有草稿时切换页签不得自动重读并丢失修改。
	var card: Dictionary = panel.doc.record("res://data/cards/copy_ally.tres")
	panel.doc.set_value(str(card.id), "card_cost", int(panel.doc.value(card, "card_cost")) + 1)
	var draft: Dictionary = panel.doc.data.duplicate(true)
	panel.hide()
	panel.show()
	await process_frame
	check(not panel.bridge.is_busy() and panel.doc.data == draft and panel.doc.is_dirty(), "切换页签保留已载入文档，不重复读取或覆盖草稿")
	panel.operation = "editor-read"
	panel._finish_tool({"ok": true, "data": {}, "message": "不应显示的成功提示"})
	check(panel.doc.data == draft, "无效读取结果保留已有草稿")
	check(panel.status.text.contains("文件不是受支持") and panel.message.visible, "无效读取结果显示文档错误，不谎报读取成功")
	panel.message.hide()
	check(not panel._finish_tool({"ok": true, "message": "不应显示的成功提示"}) and panel.doc.data == draft, "缺少配置数据的成功响应同样被拒绝并保留草稿")
	panel.message.hide()
	panel.doc.open(original)
	panel.doc.discard_recovery()
	await process_frame
	panel.doc.data.clear()
	panel._finish_tool({"ok": false, "error": "模拟首次读取失败"})
	check(panel.status.text == "模拟首次读取失败", "首次读取失败保留具体原因")
	panel.message.hide()
	panel.hide()
	panel.show()
	await process_frame
	deadline = Time.get_ticks_msec() + 15000
	while panel.bridge.is_busy() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(not panel.bridge.is_busy() and panel.doc.data.get("records", []).size() > 100, "首次读取失败后重新打开页签可以自动恢复")
	panel.doc.discard_recovery()
	panel.shutdown()
	panel.free()
	await process_frame
	print("GAME_CONFIG_EDITOR_LOADING_TEST: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
