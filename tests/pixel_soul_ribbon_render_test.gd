extends Node
## 真实 GPU 检查曲线光带、低分辨率显示、尾迹吸收及预览控件。

const Ribbon := preload("res://scripts/effects/pixel_soul_ribbon.gd")
const EFFECT := preload("res://scenes/effects/pixel_soul_ribbon.tscn")
const DEMO := preload("res://examples/scenes/pixel_soul_ribbon_demo.tscn")
var failures: Array[String] = []
var checks := 0
var view: SubViewport
var ribbon: Ribbon
var arrivals := 0
var completions := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SOUL_RIBBON_CHECK: " + message)


func _capture(time: float) -> Image:
	ribbon.seek(time)
	await get_tree().process_frame
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
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.025)
	return count


func _palette_counts(img: Image) -> PackedInt32Array:
	var colors := ribbon.get_palette()
	var counts := PackedInt32Array([0, 0, 0])
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.9:
				continue
			for i in 3:
				var distance := absf(c.r - colors[i].r) + absf(c.g - colors[i].g) + absf(c.b - colors[i].b)
				if distance < 0.07:
					counts[i] += 1
	return counts


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PIXEL_SOUL_RIBBON_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-soul-ribbon")
	view = SubViewport.new()
	view.size = Vector2i(860, 450)
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	ribbon = EFFECT.instantiate() as Ribbon
	ribbon.autoplay = false
	ribbon.position = Vector2(50, 385)
	view.add_child(ribbon)
	_check(_opaque_count(await _capture(0.0)) == 0, "effect must begin with a fully transparent frame")
	var early := await _capture(ribbon.flight_duration * 0.5)
	var late := await _capture(ribbon.flight_duration * 0.96)
	var at_target := await _capture(ribbon.flight_duration)
	var absorbed := await _capture(ribbon.flight_duration + ribbon.trail_delay * 0.55)
	early.save_png("res://.maintenance/pixel-soul-ribbon/early.png")
	late.save_png("res://.maintenance/pixel-soul-ribbon/flight.png")
	absorbed.save_png("res://.maintenance/pixel-soul-ribbon/absorb.png")
	var early_count := _opaque_count(early)
	var late_count := _opaque_count(late)
	var arrival_count := _opaque_count(at_target)
	var absorbed_count := _opaque_count(absorbed)
	_check(early_count > 100 and late_count > early_count * 2, "the accelerating head must create a longer visible ribbon")
	_check(_difference(early, late) > 1000, "the ribbon must visibly advance along the curve")
	var colors := _palette_counts(late)
	_check(colors[0] > 20 and colors[1] > 100 and colors[2] > 100, "all three palette bands must be visible")
	_check(late.get_pixel(0, 0).a == 0.0 and late.get_pixel(859, 449).a == 0.0, "outside the ribbon must remain transparent")
	_check(absorbed_count > 0 and absorbed_count < arrival_count * 0.6, "tail absorption must shrink the visible ribbon after arrival")
	_check(_opaque_count(await _capture(ribbon.get_duration())) == 0, "the entire ribbon must disappear when absorption finishes")
	_check(ribbon.get_head_progress() == 1.0 and ribbon.get_tail_progress() == 1.0, "both ends must finish at the destination")
	var paused_a := await _capture(1.1)
	var paused_b := await _capture(1.1)
	_check(paused_a.get_data() == paused_b.get_data(), "seeking the same time must reproduce the exact pixels")
	ribbon.pixel_size = 1
	var smooth_image := await _capture(1.1)
	var full_size: Vector2i = ribbon.get_node("LowResolution").size
	ribbon.pixel_size = 4
	var pixel_image := await _capture(1.1)
	var small_size: Vector2i = ribbon.get_node("LowResolution").size
	_check(small_size.x < full_size.x * 0.3 and small_size.y < full_size.y * 0.3, "pixel size must actually lower render resolution")
	_check(_difference(smooth_image, pixel_image) > 100, "pixel size must visibly change the rasterized silhouette")
	ribbon.pixel_size = 3
	var another := EFFECT.instantiate() as Ribbon
	another.autoplay = false
	another.palette_preset = 2
	another.hide()
	view.add_child(another)
	_check(ribbon.get_node("Display").texture != another.get_node("Display").texture, "instances must have independent viewport textures")
	ribbon.palette_preset = 1
	var golden := await _capture(1.1)
	_check(_difference(paused_a, golden) > 500, "palette changes must recolor the visible ribbon")
	_check(another.palette_preset == 2 and another.get_palette()[1] == Ribbon.PALETTES[2][1], "recoloring an instance must preserve other instances")
	ribbon.glow_enabled = true
	_check(_difference(golden, await _capture(1.1)) > 100, "optional glow must add visible pixels")
	ribbon.glow_enabled = false
	# Completion signals are tied to normal playback, never to scrubbing.
	ribbon.arrived.connect(func(): arrivals += 1)
	ribbon.finished.connect(func(): completions += 1)
	ribbon.seek(ribbon.get_duration())
	_check(arrivals == 0 and completions == 0, "seeking must not emit arrival or completion")
	ribbon.restart()
	ribbon._process(ribbon.flight_duration)
	_check(arrivals == 1 and completions == 0 and ribbon.playing, "arrival must occur before the tail completes")
	ribbon._process(ribbon.trail_delay + 0.001)
	ribbon._process(1.0)
	_check(completions == 1 and arrivals == 1 and not ribbon.playing, "one-shot playback must stop and finish exactly once")
	ribbon.set_path(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_check(_opaque_count(await _capture(0.7)) == 0, "a zero-length path must not create a stray head or invalid polygon")
	ribbon.set_path(Vector2(-300, 100), Vector2(-450, -200), Vector2(-20, -50))
	await _capture(0.9)
	var internal: Image = ribbon.get_node("LowResolution").get_texture().get_image()
	_check(_opaque_count(internal) > 50, "negative local path coordinates must remain inside the effect viewport")
	# Scan the whole life cycle, including sub-frame startup/absorption degeneracy.
	ribbon.set_path(Vector2.ZERO, Vector2(20, -300), Vector2(760, -40))
	for seconds in [0.00001, 0.001, 0.005, 0.01, 0.02, 0.03, 0.04,
		ribbon.get_duration() - 0.03, ribbon.get_duration() - 0.01, ribbon.get_duration() - 0.001]:
		await _capture(seconds)
	for frame in 121:
		await _capture(ribbon.get_duration() * float(frame) / 120.0)
	_check(_opaque_count(await _capture(ribbon.get_duration())) == 0, "full-frame lifecycle sweep must end fully transparent")
	ribbon.set_path(Vector2.ZERO, Vector2(0, -200), Vector2.ZERO)
	await _capture(ribbon.flight_duration * 0.95)
	_check(_opaque_count(view.get_texture().get_image()) > 0, "a curve that doubles back must still render safely")
	# Card casts use a fast half orbit and inward absorption.
	ribbon.flight_duration = 0.5
	ribbon.trail_delay = 0.15
	ribbon.acceleration = 1.15
	ribbon.curve_samples = 128
	for preset in [1, 2]:
		ribbon.palette_preset = preset
		ribbon.set_orbit_path(Vector2(20, -25), Vector2(460, -170), 72.0)
		var orbit_image := await _capture(ribbon.flight_duration * 0.70)
		var orbit_colors := _palette_counts(orbit_image)
		_check(orbit_colors[1] > 100 and orbit_colors[2] > 50, "gold and purple orbits must render visible body and head bands")
		orbit_image.save_png("res://.maintenance/pixel-soul-ribbon/orbit-%d.png" % preset)
		for frame in 61:
			await _capture(ribbon.get_duration() * float(frame) / 60.0)
		_check(_opaque_count(await _capture(ribbon.get_duration())) == 0, "orbit absorption must finish fully transparent")
	ribbon.set_orbit_path(Vector2(460, -170), Vector2(460, -170), 72.0)
	_check(_opaque_count(await _capture(ribbon.flight_duration * 0.70)) > 100, "a card released directly over its target must still make a visible orbit")
	ribbon.move_orbit_target(Vector2(520, -200))
	_check(ribbon.point_at(1.0) == Vector2(520, -200) and ribbon.point_at(0.0) == Vector2(460, -170), "tracking must preserve the card origin while updating the absorption point")
	await _capture(ribbon.flight_duration * 0.95)
	ribbon.set_path(Vector2.ZERO, Vector2(20, -300), Vector2(760, -40))
	_check(ribbon.point_at(0.5) == Vector2(200, -160), "ordinary Bezier playback must reset the orbit mode")
	# Exercise the actual preview controls and GUI drag events.
	var demo := DEMO.instantiate()
	add_child(demo)
	await get_tree().process_frame
	(demo._sliders["head_width"] as HSlider).value = 32
	_check(demo._hero.effect.head_width == 32 and demo._phase_stages[1].effect.head_width == 32, "sliders must update the main and phase previews")
	demo._timeline.value = 0.75
	_check(not demo._hero.effect.playing and is_equal_approx(demo._hero.effect._elapsed, demo._hero.effect.get_duration() * 0.75), "timeline scrubbing must pause at the selected time")
	demo._palette_buttons[2].pressed.emit()
	_check(demo._hero.effect.palette_preset == 2 and demo._phase_stages[0].effect.palette_preset == 2, "palette buttons must update all previews")
	demo._guide_check.button_pressed = true
	var stage: Control = demo._hero
	var original_bend: Vector2 = demo._hero.effect.control_point
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = demo._hero._screen_point(original_bend)
	stage._gui_input(click)
	var drag := InputEventMouseMotion.new()
	drag.position = click.position + Vector2(35, 20)
	stage._gui_input(drag)
	click.pressed = false
	stage._gui_input(click)
	_check(demo._hero.effect.control_point != original_bend and demo._phase_stages[0].effect.control_point == demo._hero.effect.control_point, "dragging the bend must change every preview path")
	demo._reset()
	_check(demo._hero.effect.playing and demo._hero.effect.head_width == 20 and demo._hero.effect.control_point == Vector2(20, -300), "reset must restore playback, shape and path")
	demo._palette_buttons[0].grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(not demo._hero.effect.playing, "space must pause even when a button has keyboard focus")
	print("SOUL_RIBBON_METRICS: early=", early_count, "; flight=", late_count, "; arrival=", arrival_count, "; absorbed=", absorbed_count, "; palette=", colors)
	print("PIXEL_SOUL_RIBBON_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
