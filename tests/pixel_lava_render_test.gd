extends Node
## 真实 GPU 验证熔岩轮廓、像素网格、动画、暂停、尺寸和材质隔离。

const EFFECT := preload("res://scenes/effects/pixel_lava.tscn")
const OUT := "res://.maintenance/pixel-lava/"
var failures: Array[String] = []
var checks := 0
var view: SubViewport
var lava: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PIXEL_LAVA_CHECK: " + message)


func _frame() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _at(seconds: float) -> Image:
	lava.seek(seconds)
	return await _frame()


func _coverage(img: Image) -> int:
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			count += int(img.get_pixel(x, y).a > 0.5)
	return count


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.03)
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PIXEL_LAVA_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	view = SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	lava = EFFECT.instantiate()
	lava.radius = 96.0
	lava.position = Vector2(128, 128)
	lava.playing = false
	lava.process_mode = Node.PROCESS_MODE_PAUSABLE
	view.add_child(lava)
	var initial := await _at(0.0)
	var later := await _at(2.4)
	initial.save_png(OUT + "frame-00.png")
	later.save_png(OUT + "frame-24.png")
	var coverage := _coverage(later)
	_check(coverage > 22000 and coverage < 29000, "pool must have a bounded circular footprint")
	var outside := 0
	var hot := 0
	var crust := 0
	for y in later.get_height():
		for x in later.get_width():
			var color := later.get_pixel(x, y)
			if color.a > 0.5:
				outside += int(Vector2(x + 0.5, y + 0.5).distance_to(Vector2(128, 128)) > 96.0)
				hot += int(color.r > 0.7 and color.g > 0.2)
				crust += int(color.r < 0.45)
	_check(outside == 0 and later.get_pixel(0, 0).a == 0.0, "no shader pixels may escape the damage radius")
	_check(hot > 2000 and crust > 6000, "both molten channels and dark basalt must be visible")
	_check(_difference(initial, later) > 2000, "lava must visibly flow over time")
	_check((await _at(2.4)).get_data() == later.get_data(), "seeking the same time must exactly reproduce the image")
	var mismatches := 0
	for gy in range(-20, 20):
		for gx in range(-20, 20):
			var x := 128 + gx * 3
			var y := 128 + gy * 3
			mismatches += int(later.get_pixel(x, y) != later.get_pixel(x + 1, y + 1))
	_check(mismatches == 0, "neighboring samples within a pixel block must be identical")
	lava.flow_speed = 0.0
	var stopped := await _at(0.5)
	_check((await _at(8.1)).get_data() == stopped.get_data(), "zero flow speed must freeze channels and bubbles")
	lava.flow_speed = 1.0
	var other := EFFECT.instantiate() as Node2D
	other.playing = false
	other.hide()
	view.add_child(other)
	var material := lava.get_node("LavaSurface").material as ShaderMaterial
	var other_material := other.get_node("LavaSurface").material as ShaderMaterial
	_check(material != other_material, "instances must own independent materials")
	lava.pattern_seed = 8.0
	_check(other_material.get_shader_parameter("pattern_seed") == 1.0, "changing one pattern must not modify another instance")
	_check(_difference(later, await _at(2.4)) > 3000, "pattern seed must produce a visibly different pool")
	lava.pattern_seed = 1.0
	lava.radius = 48.0
	_check(_coverage(await _at(2.4)) < coverage * 0.30, "halving the radius must reduce the rendered area")
	lava.radius = 96.0
	lava.playing = true
	await get_tree().physics_frame
	get_tree().paused = true
	var paused_time: float = material.get_shader_parameter("clock_time")
	var paused := await _frame()
	await get_tree().create_timer(0.15, true).timeout
	_check(is_equal_approx(material.get_shader_parameter("clock_time"), paused_time), "shader clock must stop while the game is paused")
	_check((await _frame()).get_data() == paused.get_data(), "paused GPU output must stay unchanged")
	get_tree().paused = false
	lava.playing = false
	# Export deterministic frames for a compact animated review artifact.
	for frame in 16:
		(await _at(frame * 0.2)).save_png(OUT + "loop-%02d.png" % frame)
	print("PIXEL_LAVA_RENDER_TEST: %d checks; failures=%s; coverage=%d; hot=%d; crust=%d" % [checks, failures, coverage, hot, crust])
	get_tree().quit(0 if failures.is_empty() else 1)
