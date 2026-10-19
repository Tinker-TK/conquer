# 将 demo 的原生粒子渲染成战斗帧动画，避免运行时创建粒子消耗玩法的全局随机数。
extends SceneTree

const VFX = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const OUT := "res://assets/effect/eslabong_vfx/combat_baked/"
const SIZE := 192
const FRAMES := 30
const FPS := 30.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for id in ["BloodImpactVFX", "FireSparks"]:
		seed(9137)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(SIZE, SIZE)
		viewport.transparent_bg = true
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var stage := Node2D.new()
		viewport.add_child(stage)
		VFX.spawn(stage, id, Vector2.ONE * SIZE * 0.5, {"scale_mode": "authored", "max_lifetime": 2.0})
		var atlas := Image.create(SIZE * 6, SIZE * 5, false, Image.FORMAT_RGBA8)
		for frame in FRAMES:
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			atlas.blit_rect(viewport.get_texture().get_image(), Rect2i(0, 0, SIZE, SIZE), Vector2i((frame % 6) * SIZE, (frame / 6) * SIZE))
		atlas.save_png(OUT + id + ".png")
		var texture := ImageTexture.create_from_image(atlas)
		var frames := SpriteFrames.new()
		frames.set_animation_loop(&"default", false)
		frames.set_animation_speed(&"default", FPS)
		for frame in FRAMES:
			var region := AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2((frame % 6) * SIZE, (frame / 6) * SIZE, SIZE, SIZE)
			frames.add_frame(&"default", region)
		check_save(ResourceSaver.save(frames, OUT + id + ".res", ResourceSaver.FLAG_COMPRESS))
		viewport.free()
		print("BAKED: ", id)
	quit()


func check_save(error: Error) -> void:
	if error != OK:
		push_error("无法保存烘焙帧资源")
		quit(1)
