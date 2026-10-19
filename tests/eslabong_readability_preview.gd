extends SceneTree

const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const OUT := "res://outputs/eslabong-skill-review-20261017/readability/"
const CASES := ["boo", "call_wild_boar", "call_armored_wild_boar", "call_barrel_wild_boar", "boar_mend", "flamethrower", "chain_lightning", "lightning_smite", "blood_thunder"]
var cells: Array[Control] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--readability-ui" in OS.get_cmdline_user_args():
		await _interface()
		print("ESLABONG_READABILITY_UI: failures=", failures)
		quit(0 if failures.is_empty() else 1)
		return
	var folder := OUT + ("before/" if "--before" in OS.get_cmdline_user_args() else "after/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(grid)
	current_scene = grid
	for skill_id: String in CASES:
		var panel := VBoxContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var label := Label.new()
		label.text = str(Skills.find(skill_id).name)
		panel.add_child(label)
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(630, 310)
		cell.looping = false
		panel.add_child(cell)
		cell.set_zoom(2)
		cells.append(cell)
	await process_frame
	for i in CASES.size():
		var skill: Dictionary = Skills.find(CASES[i]).duplicate(true)
		# Align release for comparisons; the real catalog retains its cast time.
		skill.cast_seconds = 0
		cells[i].set_item(skill)
	var previous := 0.0
	for time: float in [.08, .18, .32, .48, .7]:
		await create_timer(time - previous).timeout
		previous = time
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder + "grid_%.2f.png" % time))
		for i in CASES.size():
			cells[i].viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder + CASES[i] + "_%.2f.png" % time))
	if "--before" not in OS.get_cmdline_user_args():
		# Verify visible flame pixels, including particle tails, do not cover the
		# caster. Hide units so warm armor pixels cannot masquerade as flame.
		var flame: Control = cells[5]
		flame.character.visible = false
		flame.target.visible = false
		flame.character_visible = false
		await RenderingServer.frame_post_draw
		var pixels: Image = flame.viewport.get_texture().get_image()
		var origin: Vector2 = flame.world.to_global(flame.sequence.launch_position())
		var warm := 0
		var behind := 0
		for y in pixels.get_height():
			for x in pixels.get_width():
				var color := pixels.get_pixel(x, y)
				if color.r > .45 and color.g > .12 and color.r > color.g * 1.15 and color.r > color.b * 1.8:
					warm += 1
					if x < origin.x - 2: behind += 1
		if warm < 100: failures.append("Flame lost its visible body")
		if behind > 0: failures.append("Flame tails still cover the caster")
		var report := FileAccess.open(OUT + "flame_origin_pixels.json", FileAccess.WRITE)
		report.store_string(JSON.stringify({"warm_pixels": warm, "warm_pixels_behind_muzzle": behind, "muzzle_x": origin.x, "failures": failures}, "\t"))
		report.close()
	grid.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_READABILITY_PREVIEW: 9 skills; failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _interface() -> void:
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.loop_enabled = false
	for skill_id: String in ["boo", "call_wild_boar", "call_armored_wild_boar", "call_barrel_wild_boar", "flamethrower", "chain_lightning"]:
		for index in demo.items.size():
			if demo.items[index].id == skill_id:
				demo.show_item(index)
				break
		var release_time := .16 if "boar" in skill_id else .3 if skill_id == "boo" else .08 if skill_id == "chain_lightning" else .65
		await create_timer(float(Skills.find(skill_id).cast_seconds) + release_time).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + skill_id + "_ui.png"))
	demo.queue_free()
	await process_frame
	await create_timer(2).timeout
