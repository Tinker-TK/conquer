extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var script = load("res://addons/package_tool/panel.gd")
	check(script != null and script.can_instantiate(), "打包面板脚本可以实例化")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var panel = script.new()
	root.add_child(panel)
	await process_frame
	if "--capture-package-tool" in OS.get_cmdline_user_args():
		panel.popup_centered(Vector2i(720, 460))
		for frame in range(8):
			await process_frame
		var image := root.get_texture().get_image()
		check(image.save_png("res://.maintenance/packaging/package-panel.png") == OK, "保存打包面板截图")
	check(panel.platform_choice.item_count == 3, "提供 Windows、Mac 和两个平台三种选择")
	check(not panel.is_busy() and not panel.start_button.disabled, "初始界面可开始打包")
	panel.output_edit.text = ""
	panel._start_build()
	check(not panel.is_busy() and panel.status_label.text.contains("保存位置"), "空输出目录不会启动任务")
	panel._set_busy(true)
	check(panel.platform_choice.disabled and panel.start_button.disabled and not panel.output_edit.editable, "任务期间锁定平台和输出目录")
	panel._finish({"code": 1, "output": "failure log"}, {"ok": false, "error": "模板缺失", "packages": []})
	check(not panel.start_button.disabled and panel.status_label.text.contains("模板缺失"), "失败后恢复按钮并显示原因")
	panel._finish({"code": 0, "output": ""}, {"ok": true, "packages": ["C:/test/Windows.zip", "C:/test/Mac.zip"], "folder": ""})
	check(panel.package_list.text.contains("Windows.zip") and panel.package_list.text.contains("Mac.zip"), "成功后显示两个可分享包")
	if "--package-tool-integration" in OS.get_cmdline_user_args():
		panel.platform_choice.select(0)
		panel.output_edit.text = ProjectSettings.globalize_path("res://builds")
		panel._start_build()
		check(panel.is_busy(), "通过界面启动真实 Windows 打包任务")
		var deadline := Time.get_ticks_msec() + 180000
		while panel.is_busy() and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		check(not panel.is_busy(), "后台任务结束并恢复界面")
		check(panel.status_label.text.contains("打包完成"), "真实任务在界面显示完成")
		var result: Dictionary = panel._read_result()
		check(result.get("ok", false) and result.get("packages", []).size() == 1, "仅生成所选的 Windows 包")
		check(panel.package_list.text.contains("Windows-x64.zip") and not panel.package_list.text.contains("macOS"), "界面结果对应所选平台")
		var report := FileAccess.open("res://.maintenance/packaging/ui-integration-result.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(result, "\t"))
		report.close()
	panel.shutdown()
	panel.free()
	print("PACKAGE_TOOL_TEST: failures=", failures)
	quit(0 if failures.is_empty() else 1)
