extends Node
## GPU 验证四层、透明边界、周期重现、循环接缝、材质隔离与预览交互。

const EFFECT := preload("res://scenes/effects/pixel_portal.tscn")
const DEMO := preload("res://examples/scenes/pixel_portal_demo.tscn")
var view: SubViewport
var portal: PixelPortal
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PIXEL_PORTAL_CHECK: " + message)


func _capture(seconds: float) -> Image:
	portal.seek(seconds)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _coverage(img: Image) -> int:
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
		push_error("PIXEL_PORTAL_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-portal")
	view = SubViewport.new()
	view.size = Vector2i(80, 112)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	portal = EFFECT.instantiate() as PixelPortal
	portal.playing = false
	portal.scale = Vector2(2, 2)
	portal.position = Vector2(40, 96)
	view.add_child(portal)
	var initial := await _capture(0)
	var later := await _capture(2.4)
	initial.save_png("res://.maintenance/pixel-portal/frame-00.png")
	later.save_png("res://.maintenance/pixel-portal/frame-24.png")
	var coverage := _coverage(later)
	_check(coverage > 1400 and coverage < 4500, "visible oval must occupy a bounded part of the canvas")
	_check(later.get_pixel(0, 0).a == 0 and later.get_pixel(79, 100).a == 0 and later.get_pixel(40, 111).a == 0, "outside the effect must remain transparent")
	_check(_difference(initial, later) > 200, "the ring, vortex, fragments and light must animate")
	_check((await _capture(6)).get_data() == initial.get_data(), "six-second cycle must reproduce its first frame")
	_check((await _capture(8.4)).get_data() == later.get_data(), "any frame must repeat exactly one cycle later")
	_check((await _capture(2.4)).get_data() == later.get_data(), "paused seeking must be deterministic")
	for duration in [3.0, 12.0, 5.3]:
		portal.loop_duration = duration
		var start := await _capture(0)
		_check((await _capture(duration)).get_data() == start.get_data(), "integer-frame clock must loop for duration %.1f" % duration)
	portal.loop_duration = 6
	var first := await _capture(0)
	var seam := _difference(await _capture(6.0 - 1.0 / 14.0), first)
	var largest_step := 0
	for i in 12:
		var t := i * 0.5
		largest_step = maxi(largest_step, _difference(await _capture(t), await _capture(t + 1.0 / 14.0)))
	_check(seam <= largest_step * 1.5, "loop seam must be comparable to ordinary adjacent animation frames")
	for key in ["ring_enabled", "interior_enabled", "fragments_enabled", "ground_enabled"]:
		portal.set(key, false)
		var removed := await _capture(2.4)
		_check(_difference(removed, later) > 0, "%s must control a visible independent layer" % key)
		portal.set(key, true)
	portal.brightness = 0
	_check(_coverage(await _capture(2.4)) == 0, "zero brightness must hide the complete effect")
	portal.brightness = 1
	var other := EFFECT.instantiate() as PixelPortal
	other.palette_preset = 3
	other.playing = false
	other.hide()
	view.add_child(other)
	_check(portal.get_node("Portal").material != other.get_node("Portal").material, "instances must own separate materials")
	var other_material := other.get_node("Portal").material as ShaderMaterial
	var original: Color = other_material.get_shader_parameter("color_3")
	portal.palette_preset = 1
	_check(_difference(await _capture(2.4), later) > 1000 and other_material.get_shader_parameter("color_3") == original, "palette changes must recolor only the intended instance")
	_check(original == other.get_palette()[3], "pre-ready palette must reach the shader")
	portal.playing = true
	portal.playback_speed = 0
	var frozen := await _capture(2.4)
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	_check(view.get_texture().get_image().get_data() == frozen.get_data(), "zero playback speed must freeze every layer")
	portal.playing = false
	if "--capture-portal-loop" in OS.get_cmdline_user_args():
		portal.palette_preset = 0
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-portal/loop")
		for i in 84:
			var img := await _capture(float(i) / 14.0)
			img.save_png("res://.maintenance/pixel-portal/loop/%03d.png" % i)
	var demo := DEMO.instantiate()
	add_child(demo)
	await get_tree().process_frame
	(demo._sliders["ring_width"] as HSlider).value = 3.1
	_check(is_equal_approx(demo._primary[0].ring_width, 3.1) and is_equal_approx(demo._all[-1].ring_width, 3.1), "sliders must update the main views and decomposition")
	(demo._checks["ring_enabled"] as CheckButton).button_pressed = false
	_check(not demo._primary[0].ring_enabled and demo._stages[2].effects[0].ring_enabled, "main layer switches must preserve decomposition cards")
	demo._duration_buttons[0].pressed.emit()
	_check(demo._all[0].loop_duration == 3 and demo._all[-1].loop_duration == 3, "duration buttons must update every view")
	demo._palette_buttons[2].pressed.emit()
	_check(demo._all[0].palette_preset == 2 and demo._all[-1].palette_preset == 2, "palette buttons must update every view")
	demo._timeline.value = 0.5
	_check(not demo._primary[0].playing and is_equal_approx(demo._primary[0].get_cycle_position(), 0.5), "scrubbing must seek and pause all effects")
	demo._pause_button.pressed.emit()
	_check(demo._all[0].playing and demo._all[-1].playing, "resume button must restart playback without resetting the clock")
	demo._reset()
	_check(demo._primary[0].ring_enabled and demo._primary[0].playing and demo._primary[0].loop_duration == 6 and demo._primary[0].palette_preset == 0, "reset must restore default layers, palette and playback")
	demo._palette_buttons[0].grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(not demo._primary[0].playing, "space must pause even when a button holds keyboard focus")
	_check(demo.find_children("*", "UnitBase", true, false).is_empty(), "standalone preview must not instantiate gameplay units")
	print("PIXEL_PORTAL_METRICS: coverage=", coverage, "; seam_changed=", seam, "; largest_step=", largest_step)
	print("PIXEL_PORTAL_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
