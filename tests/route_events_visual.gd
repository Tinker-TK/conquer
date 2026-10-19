# 在真实渲染器中保存事件、单组选牌、牌组操作和结算画面，检查边界与文字裁切。
extends SceneTree
const OUTPUT := "res://outputs/route_events_20261018/screenshots"
var panel: Control
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	var controls: Array = panel.choices_box.get_children() if panel.choices_box.is_visible_in_tree() else []
	for button: Control in controls:
		if button.get_global_rect().end.y > root.size.y:
			failures.append(name + " 选项超出窗口")
		var caption = button.get_node_or_null("ChoiceCaption")
		if caption != null and caption.get_content_height() > caption.size.y + 1:
			failures.append(name + " 选项文案被裁切")
	if panel.cards_box.visible and panel.confirm_button.get_global_rect().end.y > root.size.y:
		failures.append(name + " 确认按钮超出窗口")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var run := root.get_node("RunManager")
	run.selected_map = {}
	run.start_new_run()
	run.hp = 44
	panel = load("res://scripts/map/event_panel.gd").new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rewards = load("res://scripts/events/event_rewards.gd")
	for id in ["act1_broken_standard", "act1_golden_idol", "act1_caravan_wreck", "act1_goblin_arena", "act1_undead_whisper"]:
		panel.open_content(rewards.content(id),run)
		await capture(id)
	panel.open_content(rewards.content("crossroads_recruitment"),run)
	panel._choose(0)
	await capture("single-card-choice")
	panel.open_content(rewards.content("act1_blood_pact"),run)
	panel._choose(0)
	await capture("two-card-groups")
	panel.open_content(rewards.content("act1_silent_altar"),run)
	panel._choose(0)
	await capture("remove-card")
	panel.open_content(rewards.content("act1_caravan_wreck"),run)
	panel._choose(1)
	await capture("resource-result")
	print("ROUTE_EVENTS_VISUAL: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
