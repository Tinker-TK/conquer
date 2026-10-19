extends SceneTree
## Render each library item in isolation. PNG alpha/energy bounds are measured
## offline, so transparent sprite-sheet margins and UI labels do not count.

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
var phase := "authored"
var zoom := 1.0
var viewports: Array[SubViewport] = []
var worlds: Array[Node2D] = []
var records: Array[Dictionary] = []
var output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scale-phase="): phase = arg.trim_prefix("--scale-phase=")
		if arg.begins_with("--measure-zoom="): zoom = float(arg.trim_prefix("--measure-zoom="))
	output = "res://.maintenance/eslabong/scale/" + phase + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	RenderingServer.set_default_clear_color(Color(.04, .05, .06))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(grid)
	current_scene = grid
	for i in 16:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(512, 512)
		viewport.world_2d = World2D.new()
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := Node2D.new()
		world.position = Vector2(256, 256)
		world.scale = Vector2.ONE * zoom
		viewport.add_child(world)
		worlds.append(world)
		viewports.append(viewport)
		var preview := TextureRect.new()
		preview.texture = viewport.get_texture()
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(preview)
	var items: Array = Library.catalog().items
	var selection_path := "res://.maintenance/eslabong/scale/selection.json"
	if phase in ["detail", "wide", "recheck"] and FileAccess.file_exists(selection_path):
		var selected: Array = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
		items = items.filter(func(item: Dictionary) -> bool: return item.id in selected)
		var prior_path := output + "frames.json"
		var fitted_path := "res://.maintenance/eslabong/scale/fitted/frames.json"
		if phase == "recheck" and FileAccess.file_exists(prior_path) and FileAccess.get_modified_time(prior_path) >= FileAccess.get_modified_time(fitted_path):
			for record: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(prior_path)):
				if record.id not in selected: records.append(record)
	Engine.time_scale = 1
	for batch in ceili(float(items.size()) / 16.0):
		for i in 16:
			for child in worlds[i].get_children():
				worlds[i].remove_child(child)
				child.queue_free()
			var index := batch * 16 + i
			if index < items.size():
				Library.spawn_item(worlds[i], items[index], Vector2.ZERO, {
					"scale_mode": "authored" if phase in ["authored", "detail", "wide"] else "unit",
					"controlled_flight": items[index].original_name != "HookProjectile",
				"max_lifetime": 0.0,
			})
		var previous := 0.0
		for time: float in [.02, .06, .14, .32, .7, 1.2]:
			await create_timer(time - previous).timeout
			previous = time
			await RenderingServer.frame_post_draw
			for i in 16:
				var index := batch * 16 + i
				if index >= items.size(): break
				var filename := "%s_%.2f.png" % [items[index].id, time]
				viewports[i].get_texture().get_image().save_png(ProjectSettings.globalize_path(output + filename))
				records.append({"id": items[index].id, "name": items[index].original_name, "file": filename, "time": time, "zoom": zoom})
		print("ESLABONG_SCALE_BATCH: ", phase, " ", batch + 1, "/", ceili(float(items.size()) / 16.0))
	var report := FileAccess.open(output + "frames.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(records, "\t"))
	report.close()
	for viewport in viewports: viewport.queue_free()
	grid.queue_free()
	await process_frame
	Engine.time_scale = 1
	await create_timer(2).timeout
	print("ESLABONG_SCALE_MEASURE: ", phase, " ", items.size(), " items; complete")
	quit()
