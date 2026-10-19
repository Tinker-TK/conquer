extends SceneTree

const DEMO = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
var demo: Control
var failures: Array[String] = []
const OUT := "res://.maintenance/eslabong/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	demo = DEMO.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.set_catalog_mode(1)
	demo.search.text = "Burn"
	demo._filter()
	if demo.filtered.is_empty(): failures.append("Search did not find Burn")
	demo.search.text = "__nothing_matches__"
	demo._filter()
	if not demo.cells.is_empty(): failures.append("Empty search retained previews")
	demo.search.text = ""
	demo._filter()
	demo._toggle_pause()
	if not paused: failures.append("Pause failed")
	demo._toggle_pause()
	var curated: Array[int] = []
	for name in ["FireballImpactVFX", "IceBoltImpactVFX", "LightningBoltVFX_Premium", "ShieldBubbleVFX", "BurnVFX", "HolyWrathBeamVFX", "GlacialPrisonVFX", "PortalEffect", "FlameThrowerVFX"]:
		for i in demo.items.size():
			if demo.items[i].original_name == name:
				curated.append(i)
				break
	if curated.size() != 9: failures.append("Curated gallery missing entries")
	demo.filtered = curated
	demo.list.clear()
	for index in curated:
		demo.list.add_item(demo.items[index].name)
	demo.status.text = "9 项代表效果 / %d 项" % demo.items.size()
	demo.show_item(curated[0])
	demo.current = curated[0]
	demo.gallery = true
	demo.page = 0
	demo._rebuild_stage()
	await create_timer(0.16).timeout
	demo.cells[2].replay()
	await _capture("gallery.png")
	demo.gallery = false
	demo._filter()
	demo.show_item(curated[3])
	await create_timer(0.7).timeout
	await _capture("shield.png")
	demo.show_item(curated[5])
	await create_timer(0.4).timeout
	await _capture("holy_wrath.png")
	demo.queue_free()
	await process_frame
	await create_timer(12.0).timeout
	print("ESLABONG_PREVIEW_TEST: failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + filename))
	if error != OK:
		failures.append("Cannot save " + filename)
