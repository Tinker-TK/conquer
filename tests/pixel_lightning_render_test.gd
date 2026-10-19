extends Node
## 使用真实渲染结果检查劈落、余光、分支、火花与独立预览控件。

const EFFECT := preload("res://scenes/effects/pixel_lightning.tscn")
const DEMO := preload("res://examples/scenes/pixel_lightning_demo.tscn")
var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var effect: PixelLightning


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PIXEL_LIGHTNING_CHECK: " + message)


func _capture(seconds: float) -> Image:
	effect.seek(seconds)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _visible_count(img: Image, region := Rect2i(0, 0, 240, 192)) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			count += int(img.get_pixel(x, y).a > 0.05)
	return count


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.025)
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PIXEL_LIGHTNING_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-lightning")
	viewport = SubViewport.new()
	viewport.size = Vector2i(240, 192)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	effect = EFFECT.instantiate() as PixelLightning
	effect.playing = false
	effect.auto_start = false
	effect.lightning_type = 0
	effect.position = Vector2(120, 172)
	viewport.add_child(effect)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(_visible_count(viewport.get_texture().get_image()) == 0, "auto_start disabled must keep an untriggered effect invisible")
	var descending := await _capture(effect.strike_duration * 0.5)
	var peak_time := effect.strike_duration + effect.flash_duration * 0.25
	var peak := await _capture(peak_time)
	peak.save_png("res://.maintenance/pixel-lightning/single-peak.png")
	var trunk_coverage := _visible_count(peak)
	_check(trunk_coverage > 100 and trunk_coverage < 500, "single bolt must have a thin visible silhouette")
	_check(_visible_count(descending) < trunk_coverage, "descent must reveal the trunk progressively")
	_check(_visible_count(descending, Rect2i(0, 110, 240, 82)) == 0, "descent must not appear below its moving tip")
	_check(peak.get_pixel(0, 0).a == 0.0 and peak.get_pixel(239, 191).a == 0.0, "outside the bolt must remain transparent")
	_check((await _capture(peak_time)).get_data() == peak.get_data(), "fixed-time seeking must reproduce exactly the same pixels")
	var residual := await _capture(effect.strike_duration + effect.flash_duration + 0.12)
	_check(_difference(peak, residual) > 100, "white flash must change into dim blue afterglow")
	_check(_visible_count(await _capture(effect.get_duration())) == 0, "effect must disappear entirely at its duration")
	effect.lightning_type = 1
	var tree := await _capture(peak_time)
	tree.save_png("res://.maintenance/pixel-lightning/tree-peak.png")
	_check(_visible_count(tree) > trunk_coverage + 120, "tree mode must visibly add branching channels")
	effect.debug_view = 3
	var branch_peak := await _capture(peak_time)
	var branch_end := await _capture(effect.strike_duration + effect.flash_duration + effect.afterglow_duration * 0.70)
	_check(_visible_count(branch_peak) > 100 and _visible_count(branch_end) == 0, "branches must disappear before the trunk")
	effect.debug_view = 2
	_check(_visible_count(await _capture(effect.strike_duration + effect.flash_duration + effect.afterglow_duration * 0.70)) > 50, "trunk must remain visible after branches have disappeared")
	effect.debug_view = 5
	var sparks := await _capture(peak_time)
	_check(_visible_count(sparks) > 0 and _visible_count(sparks, Rect2i(0, 0, 240, 145)) == 0, "sparks must appear only near ground endpoints")
	effect.sparks_enabled = false
	_check(_visible_count(await _capture(peak_time)) == 0, "disabling sparks must clear the spark layer")
	effect.debug_view = 4
	var glints := await _capture(peak_time)
	_check(_visible_count(glints) > 0, "peak must contain visible corner glints")
	effect.glints_enabled = false
	_check(_visible_count(await _capture(peak_time)) == 0, "disabling glints must clear their layer")
	effect.sparks_enabled = true
	effect.glints_enabled = true
	effect.debug_view = 0
	effect.trigger()
	var randomized := await _capture(peak_time)
	_check(_difference(tree, randomized) > 180, "new strikes must generate visibly different fixed paths")
	effect.reset_sequence()
	_check((await _capture(peak_time)).get_data() == tree.get_data(), "resetting sequence must restore the initial shape")
	var other := EFFECT.instantiate() as PixelLightning
	other.playing = false
	other.hide()
	viewport.add_child(other)
	var other_color := other.core_color
	effect.core_color = Color("ffbb66")
	_check(_difference(tree, await _capture(peak_time)) > 100 and other.core_color == other_color, "instance colors must be isolated")
	effect.restrike_enabled = true
	var second_peak := effect.strike_duration + effect.flash_duration + 0.065 + effect.strike_duration * 0.2 + 0.01
	_check(_visible_count(await _capture(second_peak)) > 100, "optional second flash must visibly re-illuminate the same channel")
	_check(_visible_count(await _capture(effect.get_duration() + 0.001)) == 0, "second flash must also finish completely")
	# 检查单次播放信号与暂停，防止未来调用时重复发送击中。
	var hits: Array[int] = []
	var completions: Array[int] = []
	effect.struck.connect(func(): hits.append(1))
	effect.finished.connect(func(): completions.append(1))
	effect.restrike_enabled = false
	effect.loop = false
	effect.playing = true
	effect.restart()
	effect.set_process(false)
	effect._process(effect.strike_duration + 0.001)
	effect._process(effect.get_duration())
	effect._process(1.0)
	_check(hits.size() == 1 and completions.size() == 1 and not effect.is_active(), "one-shot playback must emit one impact and one completion")
	effect.restart()
	effect.playing = false
	effect._process(0.5)
	_check(effect.get_elapsed() == 0.0, "paused effects must preserve their time")
	var demo := DEMO.instantiate()
	add_child(demo)
	await get_tree().process_frame
	demo._set_paused(true)
	(demo._sliders["lateral_spread"] as HSlider).value = 24
	_check(demo._stages[0].effect.lateral_spread == 24 and demo._stages[1].effect.lateral_spread == 24, "shape slider must update both previews")
	demo._time_slider.value = 0.07
	_check(demo._paused and is_equal_approx(demo._stages[1].effect.get_elapsed(), 0.07), "scrubbing must pause and seek both previews")
	demo._palette_buttons[1].pressed.emit()
	_check(demo._stages[0].effect.core_color == demo.PALETTES[1][0], "palette buttons must recolor the preview")
	demo._step()
	_check(is_equal_approx(demo._clock, 0.07 + 1.0 / 60.0), "single-frame stepping must advance the paused timeline")
	demo._dummy_check.button_pressed = false
	_check(not demo._stages[0].skeleton.visible and not demo._stages[1].skeleton.visible, "dummy toggle must hide both reference sprites")
	demo._loop_check.button_pressed = false
	demo._set_paused(false)
	demo._process(1.0)
	_check(demo._paused and is_equal_approx(demo._clock, demo._stages[0].effect.get_duration()), "non-looping preview must stop on completion")
	demo._reset()
	_check(not demo._paused and demo._looping and demo._stages[0].effect.lateral_spread == 11 and demo._stages[1].effect.lightning_type == 1, "reset must restore default parameters and preserve the comparison modes")
	demo._pause_button.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(demo._paused, "space must pause exactly once even with a focused button")
	_check(demo.find_children("*", "UnitBase", true, false).is_empty(), "demo must not instantiate gameplay units")
	print("PIXEL_LIGHTNING_METRICS: single=", trunk_coverage, "; tree=", _visible_count(tree))
	print("PIXEL_LIGHTNING_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
