extends SceneTree

const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
const OUT := "res://outputs/eslabong-skill-review-20261017/scale/"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var demo := Demo.instantiate()
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.loop_enabled = false
	demo.zoom = 3.0
	for skill_id: String in ["blessed_shield", "mini_shield", "rock_throw", "fireball", "ice_wave", "fire_wave", "flamethrower"]:
		var found := false
		for index in demo.items.size():
			if demo.items[index].id == skill_id:
				demo.show_item(index)
				found = true
				break
		if not found:
			failures.append("Missing skill: " + skill_id)
			continue
		var sample_time := .85
		if "shield" in skill_id: sample_time = 1.25
		if "wave" in skill_id: sample_time = .98
		await create_timer(sample_time).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + skill_id + ".png"))
		if "shield" in skill_id:
			demo.cells[0].viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + skill_id + "_stage.png"))
		print("ESLABONG_SCALE_PREVIEW: ", skill_id)
	demo.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_SCALE_PREVIEW: failures=", failures)
	quit(0 if failures.is_empty() else 1)
