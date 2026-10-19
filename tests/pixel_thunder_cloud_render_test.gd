extends Node
## 真实 GPU 检查乌云轮廓、翻滚、分层、闪光同步和原落雷实例隔离。

const EFFECT := preload("res://scenes/effects/pixel_thunder_cloud.tscn")
const ORIGINAL_LIGHTNING := preload("res://scenes/effects/pixel_lightning.tscn")
const DEMO := preload("res://examples/scenes/pixel_thunder_cloud_demo.tscn")
const CLOUD_REGION := Rect2i(80, 28, 160, 100)
const BOLT_REGION := Rect2i(50, 135, 220, 121)
var effect: PixelThunderCloud
var view: SubViewport
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PIXEL_THUNDER_CLOUD_CHECK: " + message)


func _capture(seconds: float) -> Image:
	effect.seek(seconds)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _visible(img: Image, region := Rect2i(0, 0, 320, 256)) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			count += int(img.get_pixel(x, y).a > 0.05)
	return count


func _difference(a: Image, b: Image, region := Rect2i(0, 0, 320, 256)) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.025)
	return count


func _cyan_count(img: Image) -> int:
	var count := 0
	for y in range(CLOUD_REGION.position.y, CLOUD_REGION.end.y):
		for x in range(CLOUD_REGION.position.x, CLOUD_REGION.end.x):
			var color := img.get_pixel(x, y)
			count += int(color.a > 0.5 and color.g > 0.48 and color.g > color.r * 1.15)
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PIXEL_THUNDER_CLOUD_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-thunder-cloud")
	view = SubViewport.new()
	view.size = Vector2i(320, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	effect = EFFECT.instantiate() as PixelThunderCloud
	effect.position = Vector2(160, 240)
	effect.playing = false
	effect.loop = false
	view.add_child(effect)
	var idle := await _capture(0.20)
	var coverage := _visible(idle, CLOUD_REGION)
	idle.save_png("res://.maintenance/pixel-thunder-cloud/idle.png")
	_check(coverage > 2000 and coverage < 5500, "cloud must have a bounded layered silhouette")
	_check(idle.get_pixel(0, 0).a == 0 and idle.get_pixel(319, 255).a == 0, "outside cloud and bolt must remain transparent")
	_check(_visible(idle, BOLT_REGION) == 0, "idle cloud must not show a bolt")
	var colors: Dictionary = {}
	for y in range(CLOUD_REGION.position.y, CLOUD_REGION.end.y):
		for x in range(CLOUD_REGION.position.x, CLOUD_REGION.end.x):
			var color := idle.get_pixel(x, y)
			if color.a > 0.95:
				colors[color.to_html(false)] = true
	_check(colors.size() >= 3 and colors.size() <= 6, "idle cloud must use discrete dark, body and light bands")
	var rolling := await _capture(2.0)
	_check(_difference(idle, rolling, CLOUD_REGION) > 250, "cloud outline and shading must visibly roll over time")
	_check((await _capture(2.0)).get_data() == rolling.get_data(), "fixed-time seeking must exactly reproduce the cloud")
	effect.roll_speed = 0
	effect.flash_enabled = false
	effect.lightning_enabled = false
	var frozen_a := await _capture(0.2)
	var frozen_b := await _capture(2.0)
	_check(frozen_a.get_data() == frozen_b.get_data(), "zero roll speed must freeze all cloud noise and billows")
	effect.roll_speed = 0.65
	effect.flash_enabled = true
	effect.lightning_enabled = true
	var charge := await _capture(effect.strike_delay - 0.03)
	_check(_cyan_count(charge) > 20 and _visible(charge, BOLT_REGION) == 0, "cloud must charge before the bolt appears")
	var peak_time := effect.strike_delay + 0.075
	var peak := await _capture(peak_time)
	peak.save_png("res://.maintenance/pixel-thunder-cloud/discharge.png")
	_check(_cyan_count(peak) > 100 and _visible(peak, BOLT_REGION) > 90, "cloud internal flash and ground bolt must appear together")
	var lightning := effect.get_lightning()
	_check(lightning.scene_file_path == "res://scenes/effects/pixel_lightning.tscn" and not lightning.playing, "combination must reuse the original scene with a separate driven clock")
	var actual_source := lightning.position + Vector2(0, -lightning.bolt_height).rotated(lightning.rotation)
	_check(actual_source.distance_to(effect.get_discharge_position()) < 0.001, "bolt source must align with the chosen cloud discharge point")
	_check(lightning.position == Vector2.ZERO, "main bolt endpoint must stay at the component origin")
	effect.flash_enabled = false
	var without_flash := await _capture(peak_time)
	_check(_difference(peak, without_flash, CLOUD_REGION) > 200 and _cyan_count(without_flash) == 0, "flash switch must only remove the internal cloud light")
	_check(_difference(peak, without_flash, BOLT_REGION) == 0, "cloud flash switch must preserve the original bolt image")
	effect.flash_enabled = true
	effect.lightning_enabled = false
	var cloud_only := await _capture(peak_time)
	_check(_visible(cloud_only, BOLT_REGION) == 0 and _cyan_count(cloud_only) > 100, "cloud-only mode must preserve internal discharge while hiding lightning")
	effect.lightning_enabled = true
	var restored := await _capture(effect.get_strike_end() + 0.2)
	_check(_visible(restored, CLOUD_REGION) > 2000 and _visible(restored, BOLT_REGION) == 0 and _cyan_count(restored) == 0, "after discharge the cloud must remain while bolt and inner flash disappear")
	effect.lightning_type = 1
	var tree := await _capture(peak_time)
	_check(_visible(tree, BOLT_REGION) > _visible(peak, BOLT_REGION) + 80, "tree mode must add visible branches without editing the base effect")
	effect.debug_view = 1
	var structure := await _capture(peak_time)
	_check(_difference(tree, structure, CLOUD_REGION) > 500 and _visible(structure, BOLT_REGION) == 0, "structure mode must expose ellipse layout and hide the bolt")
	effect.debug_view = 2
	var mask := await _capture(peak_time)
	_check(_visible(mask, CLOUD_REGION) > 2000 and _difference(mask, peak, CLOUD_REGION) > 1000, "mask mode must show an opaque cloud silhouette")
	effect.debug_view = 0
	var companion := EFFECT.instantiate() as PixelThunderCloud
	companion.playing = false
	companion.hide()
	view.add_child(companion)
	var original_color := companion.body_color
	_check(effect.get_node("Cloud").material != companion.get_node("Cloud").material and effect.get_lightning() != companion.get_lightning(), "instances must own isolated cloud materials and lightning nodes")
	effect.body_color = Color("7d4a55")
	_check(companion.body_color == original_color and _difference(restored, await _capture(effect.get_strike_end() + 0.2), CLOUD_REGION) > 500, "editing one palette must not recolor another cloud")
	var original := ORIGINAL_LIGHTNING.instantiate() as PixelLightning
	original.playing = false
	original.hide()
	view.add_child(original)
	_check(original.bolt_height == 136 and original.core_color == Color("e5e5d5") and original.lightning_type == 1, "original scene defaults must remain intact")
	var first_source := effect.get_discharge_position()
	var changed := false
	for i in 5:
		effect.trigger()
		changed = changed or effect.get_discharge_position().distance_to(first_source) > 1
		_check(effect.get_lightning().position == Vector2.ZERO, "random discharge must preserve the fixed ground endpoint")
	_check(changed, "new strikes must vary the cloud source")
	# 单次播放信号与无自动击发的待机行为。
	var hits: Array[int] = []
	var completions: Array[int] = []
	effect.struck.connect(func(): hits.append(1))
	effect.finished.connect(func(): completions.append(1))
	effect.loop = false
	effect.playing = true
	effect.restart()
	effect.set_process(false)
	effect._process(effect.strike_delay + effect.get_lightning().strike_duration + 0.001)
	effect._process(1.0)
	effect._process(1.0)
	_check(hits.size() == 1 and completions.size() == 1, "one-shot mode must emit one impact and one completion")
	effect.playing = false
	var demo := DEMO.instantiate()
	add_child(demo)
	await get_tree().process_frame
	demo._set_paused(true)
	(demo._sliders["cloud_width"] as HSlider).value = 130
	_check(demo._stages[0].effect.cloud_size.x == 130 and demo._stages[1].effect.cloud_size.x == 130, "cloud slider must update both main previews")
	demo._time_slider.value = 0.725
	_check(demo._paused and is_equal_approx(demo._stages[1].effect.get_elapsed(), 0.725), "time-axis scrubbing must pause and synchronize the views")
	(demo._checks["lightning_enabled"] as CheckButton).button_pressed = false
	_check(not demo._stages[1].effect.get_lightning().visible and demo._stages[0].effect.flash_enabled, "lightning switch must leave clouds and internal flashes available")
	demo._lightning_picker.item_selected.emit(1)
	_check(demo._stages[1].effect.lightning_type == 1, "mode picker must select tree lightning")
	demo._step()
	_check(is_equal_approx(demo._clock, 0.725 + 1.0 / 60.0), "single-frame control must advance exactly one frame")
	(demo._checks["dummy"] as CheckButton).button_pressed = false
	_check(not demo._stages[1].skeleton.visible, "dummy toggle must hide the reference sprite")
	demo._reset()
	_check(not demo._paused and demo._looping and demo._stages[1].effect.lightning_enabled and demo._stages[1].effect.lightning_type == 0 and demo._stages[0].effect.cloud_size.x == 112, "reset must restore preview defaults")
	demo._pause_button.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(demo._paused, "space must pause once with a focused button")
	_check(demo.find_children("*", "UnitBase", true, false).is_empty(), "preview must not instantiate gameplay units")
	print("PIXEL_THUNDER_CLOUD_METRICS: cloud=", coverage, "; flash=", _cyan_count(peak), "; bolt=", _visible(peak, BOLT_REGION), "; colors=", colors.size())
	print("PIXEL_THUNDER_CLOUD_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
