extends SceneTree

const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const OUT := "res://outputs/eslabong-skill-review-20261017/"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--all-skills" in OS.get_cmdline_user_args():
		await _audit()
	else:
		await _interface()
	print("ESLABONG_SKILLS_PREVIEW: failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _interface() -> void:
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.loop_enabled = false
	demo.search.text = "投石"
	demo._filter()
	await create_timer(.18).timeout
	await capture("stone_cast.png")
	await create_timer(.36).timeout
	if demo.cells[0].sequence.hit_count != 0:
		failures.append("Native impact occurred before stone arrived")
	await capture("stone_flight.png")
	await create_timer(.28).timeout
	if demo.cells[0].sequence.hit_count != 1:
		failures.append("Native stone did not impact target exactly once")
	await capture("stone_impact.png")
	await create_timer(.4).timeout
	await capture("stone_stun.png")
	demo.search.text = ""
	demo._filter()
	var curated: Array[int] = []
	for id in ["rock_throw", "fireball", "ice_bolt", "chain_lightning", "burning_arrow", "flamethrower", "mini_shield", "earth_spike", "holy_wrath"]:
		for i in demo.items.size():
			if demo.items[i].id == id:
				curated.append(i)
				break
	if curated.size() != 9:
		failures.append("Missing curated skills")
	demo.filtered = curated
	demo.list.clear()
	for index in curated:
		demo.list.add_item(demo.items[index].name)
	demo.current = curated[0]
	demo.gallery = true
	demo.page = 0
	demo.status.text = "9 套代表技能 / %d 套" % demo.items.size()
	demo._rebuild_stage()
	await create_timer(.6).timeout
	await capture("skill_gallery.png")
	demo.queue_free()
	await process_frame
	await create_timer(3).timeout

func _audit() -> void:
	var ui := GridContainer.new()
	ui.columns = 4
	root.add_child(ui)
	current_scene = ui
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cells: Array[Control] = []
	for i in 16:
		var cell := Cell.new()
		cell.custom_minimum_size = Vector2(470, 250)
		ui.add_child(cell)
		cell.set_zoom(1)
		cell.looping = false
		cells.append(cell)
	Engine.time_scale = 2
	var items: Array = Skills.catalog().items
	if "--dense-skills" in OS.get_cmdline_user_args():
		items = items.filter(func(item: Dictionary) -> bool: return item.id in ["pewpewpew", "plasma_bolt", "rain_of_arrows", "shotgun", "blizzard", "everwinter", "ice_storm", "rock_throw", "multishot"])
	for batch in ceili(float(items.size()) / 16):
		for i in 16:
			cells[i].clear_effects()
			cells[i].item = {}
			if batch * 16 + i < items.size():
				cells[i].set_item(items[batch * 16 + i])
		var previous := 0.0
		var sample := 0
		for time: float in [.2, .8, 1.8, 3.5, 6.0]:
			await create_timer(time - previous).timeout
			previous = time
			await capture(("dense/" if "--dense-skills" in OS.get_cmdline_user_args() else "audit/") + "%02d_%d.png" % [batch, sample])
			sample += 1
		print("ESLABONG_SKILL_BATCH: ", batch + 1, "/", ceili(float(items.size()) / 16))
	ui.queue_free()
	await process_frame
	Engine.time_scale = 1
	await create_timer(4).timeout
	print("ESLABONG_SKILLS_RENDER: ", items.size(), " skills; complete")

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + filename)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if root.get_texture().get_image().save_png(path) != OK:
		failures.append("Cannot save " + filename)
