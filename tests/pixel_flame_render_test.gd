extends Node
## 实际 GPU 验证透明轮廓、上升动画、调色隔离、暂停和预览控件。

const EFFECT := preload("res://scenes/effects/pixel_flame.tscn")
const DEMO := preload("res://examples/scenes/pixel_flame_demo.tscn")
var failures: Array[String] = []
var checks := 0
var view: SubViewport
var flame: PixelFlame


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PIXEL_FLAME_CHECK: " + message)


func _capture(time: float) -> Image:
	flame.seek(time)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _opaque_count(img: Image) -> int:
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			count += int(img.get_pixel(x, y).a > 0.1)
	return count


func _difference(a: Image, b: Image) -> int:
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			changed += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.025)
	return changed


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PIXEL_FLAME_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-flame")
	view = SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	flame = EFFECT.instantiate() as PixelFlame
	flame.playing = false
	flame.embers_enabled = false
	flame.position = Vector2(64, 120)
	view.add_child(flame)
	var initial := await _capture(0.0)
	var later := await _capture(2.4)
	initial.save_png("res://.maintenance/pixel-flame/frame-00.png")
	later.save_png("res://.maintenance/pixel-flame/frame-24.png")
	var coverage := _opaque_count(later)
	var movement := _difference(initial, later)
	_check(coverage > 200 and coverage < 2000, "flame must have a bounded visible silhouette")
	_check(later.get_pixel(0, 0).a == 0.0 and later.get_pixel(64, 127).a == 0.0, "outside the flame must stay transparent")
	_check(movement > 80, "noise must visibly animate both contour and palette")
	var paused := await _capture(2.4)
	_check(paused.get_data() == later.get_data(), "seeking the same time must reproduce the exact frame")
	flame.flow_speed = 0.0
	var stopped_a := await _capture(1.0)
	var stopped_b := await _capture(4.0)
	_check(stopped_a.get_data() == stopped_b.get_data(), "zero flow speed must freeze the entire shader")
	flame.flow_speed = 1.0
	flame.intensity = 0.0
	_check(_opaque_count(await _capture(2.4)) == 0, "zero intensity must hide every pixel")
	flame.intensity = 1.0
	var other := EFFECT.instantiate() as PixelFlame
	other.palette_preset = 3
	other.playing = false
	other.hide()
	view.add_child(other)
	_check(flame.get_node("Flame").material != other.get_node("Flame").material, "instances must own separate materials")
	var other_material := other.get_node("Flame").material as ShaderMaterial
	var original_palette: Color = other_material.get_shader_parameter("color_2")
	flame.palette_preset = 1
	var orange := await _capture(2.4)
	_check(_difference(later, orange) > 200, "changing palette must visibly recolor the fire")
	_check(other_material.get_shader_parameter("color_2") == original_palette, "recoloring one instance must not alter another")
	_check(original_palette == other.get_palette()[2], "preset set before ready must reach the shader")
	flame.shape = 1
	var tall := await _capture(2.4)
	_check(_opaque_count(tall) != coverage and _difference(orange, tall) > 80, "the tall shape must visibly change the silhouette")
	flame.embers_enabled = true
	_check(_difference(tall, await _capture(2.4)) > 0, "embers toggle must add visible sparks")
	flame.embers_enabled = false
	flame.debug_view = 1
	var mask := await _capture(2.4)
	_check(_difference(tall, mask) > 200, "mask view must replace the palette")
	flame.debug_view = 0
	flame.glow_enabled = true
	var with_halo := await _capture(2.4)
	_check(_opaque_count(with_halo) >= _opaque_count(tall) and _difference(tall, with_halo) > 0, "optional halo must visibly add light while preserving the main flame")
	# Controls are exercised through their actual Godot signals.
	var demo := DEMO.instantiate()
	add_child(demo)
	await get_tree().process_frame
	(demo._sliders["wind"] as HSlider).value = 0.65
	_check(is_equal_approx(demo._stages[0].effect.wind, 0.65) and is_equal_approx(demo._stages[1].effect.wind, 0.65), "slider must change both primary previews")
	demo._palette_buttons[2].pressed.emit()
	_check(demo._stages[0].effect.palette_preset == 2 and demo._variants[1].effect.palette_preset == 1, "preset buttons must preserve comparison cards")
	demo._pause_button.pressed.emit()
	_check(not demo._stages[0].effect.playing and not demo._variants[0].effect.playing, "pause must stop all displayed flames")
	demo._reset()
	_check(demo._stages[0].effect.playing and demo._stages[0].effect.wind == 0.0 and demo._stages[0].effect.palette_preset == 0, "reset must restore preview defaults")
	demo._palette_buttons[0].grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(not demo._stages[0].effect.playing, "space must pause even when a preset button has keyboard focus")
	var reset_key := InputEventKey.new()
	reset_key.keycode = KEY_R
	reset_key.pressed = true
	Input.parse_input_event(reset_key)
	await get_tree().process_frame
	_check(demo._stages[0].effect.playing, "R key must restore playback")
	_check(demo.find_children("*", "UnitBase", true, false).is_empty(), "preview must not instantiate gameplay units")
	print("PIXEL_FLAME_METRICS: visible=", coverage, "; changed=", movement)
	print("PIXEL_FLAME_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
