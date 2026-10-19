extends SceneTree

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
var output_dir := "res://.maintenance/eslabong/render_audit/"
var cells: Array[Control] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--audit-focus" in OS.get_cmdline_user_args():
		output_dir = "res://.maintenance/eslabong/render_focus/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var ui := GridContainer.new()
	ui.columns = 4
	ui.add_theme_constant_override("h_separation", 0)
	ui.add_theme_constant_override("v_separation", 0)
	root.add_child(ui)
	current_scene = ui
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(16):
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(400, 220)
		ui.add_child(cell)
		cell.set_zoom(1.0)
		cell.looping = false
		cell.character_visible = false
		cell.backdrop.show_grid = false
		cell.set_background(Color("0a0d12"))
		cells.append(cell)
	var items: Array = Library.catalog().items
	if "--audit-focus" in OS.get_cmdline_user_args():
		items = items.filter(func(item: Dictionary) -> bool: return item.original_name in ["AssassinImpactVFX", "BlazingDashTrailSparks", "SpellbladeDashTrailSparks", "HeatTrailVFX"])
		Engine.time_scale = 0.25
		for cell in cells:
			cell.set_zoom(4.0)
			cell.backdrop.show_grid = true
			cell.backdrop.queue_redraw()
	var batches: Array = []
	for batch in range(ceili(float(items.size()) / 16.0)):
		var records: Array = []
		for index in range(16):
			var item_index := batch * 16 + index
			cells[index].clear_effects()
			cells[index].item = {}
			if item_index < items.size():
				cells[index].set_item(items[item_index])
				records.append({"index": item_index, "id": items[item_index].id, "name": items[item_index].original_name})
		var previous := 0.0
		var sample := 0
		for time: float in [0.05, 0.2, 0.6, 1.2]:
			await create_timer(time - previous).timeout
			previous = time
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir + "%02d_%d.png" % [batch, sample]))
			sample += 1
		batches.append(records)
		print("ESLABONG_RENDER_BATCH: ", batch + 1, "/", ceili(float(items.size()) / 16.0))
	var report := FileAccess.open(output_dir + "batches.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(batches, "\t"))
	ui.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	await create_timer(12.0).timeout
	print("ESLABONG_RENDER_AUDIT: ", items.size(), " entries; complete")
	quit()
