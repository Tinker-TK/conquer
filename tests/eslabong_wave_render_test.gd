extends SceneTree

const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const OUT := "res://outputs/eslabong-skill-review-20261017/waves/"
var cells: Array[Control] = []
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Wave render test requires a graphics device")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--wave-ui" in OS.get_cmdline_user_args():
		await _interface()
		print("ESLABONG_WAVE_RENDER: failures=", failures)
		quit(0 if failures.is_empty() else 1)
		return
	var ui := GridContainer.new()
	ui.columns = 3
	root.add_child(ui)
	current_scene = ui
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fire: Dictionary = Skills.find("fire_wave").duplicate(true)
	var no_heat: Dictionary = fire.duplicate(true)
	no_heat.actions = no_heat.actions.filter(func(action: Dictionary) -> bool: return action.get("effect") != "scenes_vfx_heattrailvfx")
	var overlap: Dictionary = fire.duplicate(true)
	overlap.actions = [{"kind": "wave", "effect": "scenes_vfx_heattrailvfx", "count": 9, "interval": .06, "duration": 1.2}]
	var cases: Array = [fire, no_heat, overlap, Library.find("HeatTrailVFX"), Library.find("FireWaveSpike"), Skills.find("ice_wave")]
	for entry: Dictionary in cases:
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(620, 500)
		ui.add_child(cell)
		cell.looping = false
		cell.set_zoom(1.6)
		cell.set_item(entry)
		cells.append(cell)
	var previous := 0.0
	var maximum_black: Array[float] = [0, 0, 0, 0, 0, 0]
	var maximum_warm: Array[int] = [0, 0, 0, 0, 0, 0]
	var maximum_cyan: Array[int] = [0, 0, 0, 0, 0, 0]
	for time: float in [.12, .72, .9, 1.1, 1.4]:
		await create_timer(time - previous).timeout
		previous = time
		await RenderingServer.frame_post_draw
		for i in cells.size():
			var stats := _pixels(cells[i].viewport.get_texture().get_image())
			maximum_black[i] = maxf(maximum_black[i], stats.black_fraction)
			maximum_warm[i] = maxi(maximum_warm[i], stats.warm)
			maximum_cyan[i] = maxi(maximum_cyan[i], stats.cyan)
			samples.append(stats.merged({"case": i, "time": time}))
		var prefix := "baseline_" if "--baseline" in OS.get_cmdline_user_args() else "fixed_"
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + prefix + str(time) + ".png"))
	for i in cases.size():
		if maximum_black[i] > .005:
			failures.append("Black framebuffer in case %d: %.3f" % [i, maximum_black[i]])
	if maximum_warm[0] < 80 or maximum_warm[1] < 80 or maximum_warm[0] < maximum_cyan[0] * 3:
		failures.append("Fire wave is missing warm flame pixels")
	if maximum_cyan[5] < 80:
		failures.append("Ice wave lost its blue/white visual")
	var report := {"failures": failures, "maximum_black_fraction": maximum_black, "maximum_warm_pixels": maximum_warm, "maximum_cyan_pixels": maximum_cyan, "samples": samples}
	var suffix := "baseline" if "--baseline" in OS.get_cmdline_user_args() else "fixed"
	var file := FileAccess.open(OUT + suffix + "_pixels.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	ui.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_WAVE_RENDER: failures=", failures)
	quit(0 if failures.is_empty() or "--baseline" in OS.get_cmdline_user_args() else 1)

func _interface() -> void:
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.loop_enabled = false
	for i in demo.categories.item_count:
		if demo.categories.get_item_metadata(i) == "地面范围":
			demo.categories.select(i)
	demo._filter()
	for skill_id: String in ["fire_wave", "ice_wave"]:
		for i in demo.items.size():
			if demo.items[i].id == skill_id:
				demo.show_item(i)
				break
		await create_timer(.98).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + skill_id + "_ui.png"))
		var stats := _pixels(demo.cells[0].viewport.get_texture().get_image())
		if stats.black_fraction > .005:
			failures.append("Black screen in full UI: " + skill_id)
		if skill_id == "fire_wave" and stats.warm < 80:
			failures.append("Missing fire color in full UI")
	demo.queue_free()
	await process_frame
	await create_timer(2).timeout

func _pixels(picture: Image) -> Dictionary:
	picture.convert(Image.FORMAT_RGBA8)
	var bytes := picture.get_data()
	var black := 0
	var warm := 0
	var cyan := 0
	var width := picture.get_width()
	var height := picture.get_height()
	for offset in range(0, bytes.size(), 4):
		var r := int(bytes[offset])
		var g := int(bytes[offset + 1])
		var b := int(bytes[offset + 2])
		if r < 4 and g < 4 and b < 4:
			black += 1
		# Measure the skill lane, excluding unit labels and HP bars so their
		# orange/blue UI cannot make a missing flame pass the color check.
		var x := (offset / 4) % width
		var y := (offset / 4) / width
		if x < width * .25 or x > width * .75 or y < height * .5 - 100 or y > height * .5 + 5:
			continue
		if r > 90 and g > 30 and r > g * 1.3 and g > b * 1.15:
			warm += 1
		if b > 100 and g > 80 and b > r * 1.6:
			cyan += 1
	return {"black_fraction": float(black) / (width * height), "warm": warm, "cyan": cyan}
