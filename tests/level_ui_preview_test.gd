extends SceneTree

const PreviewVisibility = preload("res://addons/level_ui_preview/preview_visibility.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node2D.new()
	scene.name = "Battle"
	viewport.add_child(scene)
	var level := Node2D.new()
	level.name = "Level"
	scene.add_child(level)
	level.owner = scene
	_rect(level, scene, Color.BLUE, Vector2.ZERO, Vector2(64, 64))
	var card_ui := CanvasLayer.new()
	card_ui.name = "CardUI"
	scene.add_child(card_ui)
	card_ui.owner = scene
	var red := _rect(card_ui, scene, Color.RED, Vector2.ZERO, Vector2(32, 32))
	var invisible := _rect(card_ui, scene, Color.YELLOW, Vector2(32, 32), Vector2(32, 32))
	invisible.hide()
	var game_over := CanvasLayer.new()
	game_over.name = "GameOver"
	scene.add_child(game_over)
	game_over.owner = scene
	_rect(game_over, scene, Color.GREEN, Vector2(32, 0), Vector2(32, 32))
	var preview := PreviewVisibility.new()
	var packed := PackedScene.new()
	var path := "res://.maintenance/level-ui-preview/saved-preview.tscn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(packed.pack(scene) == OK and ResourceSaver.save(packed, path) == OK, "保存原始场景")
	var original := FileAccess.get_file_as_string(path)
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture:
		await _pixel_check(viewport, Vector2i(16, 16), Color.RED, "原始卡牌 UI 可见")
	preview.set_scene(scene)
	check(preview.items.size() == 3, "只选择 UI 分支，不隐藏地图")
	check(card_ui.visible and game_over.visible and red.visible and not invisible.visible, "隐藏预览不修改原有显隐属性")
	check(packed.pack(scene) == OK and ResourceSaver.save(packed, path) == OK, "隐藏期间仍可保存")
	check(FileAccess.get_file_as_string(path) == original, "隐藏前后保存的场景内容完全一致")
	var runtime := (load(path) as PackedScene).instantiate()
	check(runtime.get_node("CardUI").visible and runtime.get_node("GameOver").visible, "重新实例化时运行 UI 保持原始可见状态")
	runtime.free()
	if capture:
		await _pixel_check(viewport, Vector2i(16, 16), Color.BLUE, "卡牌 UI 隐藏后露出地图")
		await _pixel_check(viewport, Vector2i(48, 16), Color.BLUE, "结算 UI 同时隐藏")
	preview.set_hidden(false)
	if capture:
		await _pixel_check(viewport, Vector2i(16, 16), Color.RED, "恢复卡牌 UI")
		await _pixel_check(viewport, Vector2i(48, 48), Color.BLUE, "原本隐藏的控件仍保持隐藏")
	red.hide()
	preview.set_hidden(true)
	preview.set_hidden(false)
	check(not red.visible and not invisible.visible, "切换开关尊重后来修改的控件可见状态")
	red.show()
	preview.set_hidden(true)
	preview.set_scene(null)
	if capture:
		await _pixel_check(viewport, Vector2i(16, 16), Color.RED, "离开场景时恢复绘制")
	preview.set_scene(card_ui)
	check(preview.items.is_empty(), "单独编辑 UI 场景不隐藏")
	for scene_path in ["res://scenes/battle/battle_scene.tscn", "res://scenes/levels/templates/battle_template.tscn", "res://scenes/levels/battles/battle_001.tscn"]:
		var battle := (load(scene_path) as PackedScene).instantiate()
		preview.set_scene(battle)
		check(not preview.items.is_empty(), "战斗本体、模板和继承关卡识别正确：" + scene_path)
		preview.set_scene(null)
		battle.free()
	viewport.free()
	print("LEVEL_UI_PREVIEW_TEST: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)


func _rect(parent: Node, owner_node: Node, color: Color, position_value: Vector2, size_value: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = position_value
	rect.size = size_value
	parent.add_child(rect)
	rect.owner = owner_node
	return rect


func _pixel_check(viewport: SubViewport, position_value: Vector2i, expected: Color, message: String) -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.get_pixelv(position_value).is_equal_approx(expected), message)
