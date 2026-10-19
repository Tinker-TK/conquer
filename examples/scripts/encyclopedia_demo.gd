extends Control
## 与正式设置共用图鉴，只读预览不开始征途。

func _ready() -> void:
	get_window().title = "冒险图鉴 · 书本预览"
	var pause := preload("res://scripts/ui/pause_menu.gd").new()
	add_child(pause)
	pause.open()
	pause.show_encyclopedia()
	print("ENCYCLOPEDIA_DEMO_READY")
	if "--capture-encyclopedia" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/encyclopedia")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/encyclopedia/demo.png")
		get_tree().quit()
