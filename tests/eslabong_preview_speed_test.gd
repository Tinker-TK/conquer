extends SceneTree

const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const Clock = preload("res://assets/effect/eslabong_vfx/runtime/clock.gd")
var failures: Array[String] = []
var checks := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func frames(count: int) -> void:
	for i in count: await process_frame

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await frames(4)

func _run() -> void:
	var initial_scale := Engine.time_scale
	var battle_controller: Node = root.get_node("BattleSpeed")
	var battle_was_processing := battle_controller.is_processing()
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await frames(4)
	check(demo.speed_buttons.size() == 4, "Missing playback buttons")
	for index in 4:
		var speed: float = [.25, .5, 1.0, 2.0][index]
		await click(demo.speed_buttons[index])
		check(is_equal_approx(Engine.time_scale, speed), "Button was overridden back to normal speed: " + str(speed))
		check(demo.speed_buttons[index].button_pressed, "Selected speed has no visible state")
		demo.cells[0].replay()
		var sequence: Node = demo.cells[0].sequence
		Clock.ticks_for(sequence)
		await frames(2)
		var sequence_before: float = sequence.elapsed
		var clock_before := Clock.ticks_for(sequence)
		await frames(12)
		var advance: float = sequence.elapsed - sequence_before
		var clock_advance := float(Clock.ticks_for(sequence) - clock_before) / 1000.0
		check(absf(advance - speed * 12.0 / 60.0) < .015, "Actual skill playback does not match selected speed")
		check(absf(clock_advance - advance) < .004, "Recovered visual timers do not follow playback speed")
		measurements.append({"speed": speed, "skill_seconds_in_12_frames": advance, "visual_clock_seconds": clock_advance})
	demo._toggle_pause()
	var paused_at: float = demo.cells[0].sequence.elapsed
	await click(demo.speed_buttons[0])
	await frames(6)
	check(is_equal_approx(demo.cells[0].sequence.elapsed, paused_at), "Changing speed resumed a paused effect")
	demo._toggle_pause()
	await frames(4)
	check(is_equal_approx(Engine.time_scale, .25) and demo.cells[0].sequence.elapsed > paused_at, "Resume lost the selected playback speed")
	demo._replay()
	await frames(3)
	check(is_equal_approx(Engine.time_scale, .25), "Replay reset selected speed")
	demo.queue_free()
	await frames(3)
	check(battle_controller.is_processing() == battle_was_processing, "Leaving preview did not restore battle speed control")
	check(is_equal_approx(Engine.time_scale, initial_scale), "Leaving preview did not restore engine speed")
	if DisplayServer.get_name() != "headless":
		var preview := Demo.instantiate()
		root.add_child(preview)
		current_scene = preview
		await frames(3)
		await click(preview.speed_buttons[0])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://outputs/eslabong-skill-review-20261017/impact_alignment/playback_speed_ui.png"))
		preview.queue_free()
		await frames(3)
	var folder := "res://outputs/eslabong-skill-review-20261017/impact_alignment/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := FileAccess.open(folder + "playback_speed.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"measurements": measurements, "failures": failures}, "\t"))
	report.close()
	await create_timer(2).timeout
	print("ESLABONG_PREVIEW_SPEED_TEST: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
