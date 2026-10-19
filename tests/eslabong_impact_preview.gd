extends SceneTree

const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const OUT := "res://outputs/eslabong-skill-review-20261017/impact_alignment/"
const CASES := ["InfernusImpactVFX", "IceBombImpactVFX", "LightningBombImpactVFX", "HammerOfHeavenImpactVFX", "TheOneImpactVFX", "MegaMeteorImpactVFX", "FireballImpactVFX", "ArcaneTorpedoImpactVFX", "InfernusPuffVFX"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var folder := OUT + ("before/" if "--before" in OS.get_cmdline_user_args() else "after/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(grid)
	current_scene = grid
	var cells: Array[Control] = []
	for effect_name: String in CASES:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(box)
		var label := Label.new()
		label.text = effect_name
		box.add_child(label)
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(630, 310)
		cell.looping = false
		box.add_child(cell)
		cell.set_zoom(2)
		cells.append(cell)
	await process_frame
	for i in CASES.size(): cells[i].set_item(Library.find(CASES[i]))
	var previous := 0.0
	for time: float in [.04, .12, .28, .48]:
		await create_timer(time - previous).timeout
		previous = time
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder + "grid_%.2f.png" % time))
	grid.queue_free()
	await process_frame
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.loop_enabled = false
	for skill_id: String in ["infernus", "infernusblue", "ice_bomb", "apocalypse"]:
		for i in demo.items.size():
			if demo.items[i].id == skill_id:
				demo.show_item(i)
				break
		var sequence: Node = demo.cells[0].sequence
		var action: Dictionary = sequence.skill.actions[0]
		var arrival := float(sequence.skill.cast_seconds) + float(action.get("start", 0)) + maxf(.25, sequence.launch_position().distance_to(sequence.destination) / maxf(50, float(action.get("speed", 600))))
		await create_timer(arrival + .1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder + skill_id + "_ui.png"))
	demo.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_IMPACT_PREVIEW: complete")
	quit()
