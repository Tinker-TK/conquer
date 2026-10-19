extends Node
## 实际 GPU 画面、真实鼠标/键盘输入、提交/取消与边界检查。

const DEMO := preload("res://examples/scenes/book_flip_demo.tscn")
var demo: Control
var book: PixelBook
var checks := 0
var failures: Array[String] = []
var _mouse_position := Vector2.ZERO


class LeafProbe extends Node2D:

	var book: PixelBook
	var amount := 0.2
	var layer := 0

	func _draw() -> void:
		book._draw_leaf(self, amount, layer, book._page_points(amount, layer))


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("BOOK_FLIP_CHECK: " + message)


func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture() -> Image:
	await _frame()
	return book._view.get_texture().get_image()


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) + absf(ca.a - cb.a) > 0.04)
	return count


func _ink_pixels(img: Image) -> int:
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.a < 0.5:
				continue
			count += int((color.g > color.r * 1.5 and color.g > color.b * 1.5) or (color.r > color.g * 1.5 and color.b > color.g * 1.5))
	return count


func _check_blank_transition_pages() -> void:
	# 使用醒目的页面内容标记，直接检查中间纸面的 GPU 像素是否仍带图案。
	var original_textures := book.page_textures
	var textures: Array[Texture2D] = []
	for color in [Color("19e438"), Color("19e438"), Color("ed17b7"), Color("ed17b7")]:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(color)
		textures.append(ImageTexture.create_from_image(img))
	book.page_textures = textures
	var view := SubViewport.new()
	view.size = Vector2i(PixelBook.CANVAS)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var probe := LeafProbe.new()
	probe.book = book
	view.add_child(probe)
	for side in [1, -1]:
		book.spread_index = 0 if side > 0 else 1
		book.direction = side
		for sample in [[3, 0, 0.2, true], [3, 0, 0.8, false], [3, 1, 0.2, false], [3, 1, 0.8, false], [3, 2, 0.2, false], [3, 2, 0.8, true], [1, 0, 0.2, true], [1, 0, 0.8, true]]:
			book.leaf_count = sample[0]
			probe.layer = sample[1]
			probe.amount = sample[2]
			probe.queue_redraw()
			await _frame()
			var ink := _ink_pixels(view.get_texture().get_image())
			_check(ink > 15000 if sample[3] else ink == 0, "direction %d, %d sheets, sheet %d phase %.1f must %s" % [side, sample[0], sample[1], sample[2], "retain outer content" if sample[3] else "remain blank"])
	book.page_textures = original_textures
	demo._reset()
	view.queue_free()


func _cover_bounds(img: Image) -> Rect2i:
	var minimum := Vector2i(img.get_width(), img.get_height())
	var maximum := Vector2i.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.a > 0.8 and color.b > color.r * 1.2 and color.b > color.g * 1.5:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _check_body_motion() -> void:
	var rest := await _capture()
	var resting_cover := _cover_bounds(rest)
	book.preview_turn(1)
	book.seek_turn(0.46)
	var compressed := await _capture()
	compressed.save_png("res://.maintenance/book-flip/book-squash.png")
	var compressed_cover := _cover_bounds(compressed)
	_check(compressed_cover.size.x < resting_cover.size.x * 0.75, "the entire cover must visibly squeeze horizontally during a turn")
	_check(compressed_cover.size.y < resting_cover.size.y * 0.92, "uniform zoom must change the cover height as well as its width")
	_check(compressed_cover.get_center().x < resting_cover.get_center().x - 20, "forward turns must translate the whole book in the flip direction")
	_check((await _capture()).get_data() == compressed.get_data(), "paused body motion must remain deterministic")
	demo.motion_button.button_pressed = false
	_check(_cover_bounds(await _capture()) == resting_cover, "motion toggle must restore the stationary cover while preserving the bent paper")
	demo.motion_button.button_pressed = true
	demo.squash_slider.value = 0
	_check(_cover_bounds(await _capture()).size.x > compressed_cover.size.x * 1.3, "squash slider must alter the actual cover width")
	demo.squash_slider.value = 0.30
	demo.travel_slider.value = 0
	_check(absi(_cover_bounds(await _capture()).get_center().x - resting_cover.get_center().x) <= 1, "zero travel must keep the book horizontally centered")
	demo.travel_slider.value = 32
	demo.zoom_slider.value = 0
	_check(_cover_bounds(await _capture()).size.y > compressed_cover.size.y * 1.1, "zoom slider must independently control the complete book scale")
	demo.squash_slider.value = 0
	demo.travel_slider.value = 0
	_check(_cover_bounds(await _capture()) == resting_cover, "zeroing all three motion amplitudes must leave the cover stationary")
	demo.squash_slider.value = 0.30
	demo.travel_slider.value = 32
	demo.zoom_slider.value = 0.18
	book.seek_turn(0.72)
	var rebound := await _capture()
	rebound.save_png("res://.maintenance/book-flip/book-rebound.png")
	_check(_cover_bounds(rebound).size.x > resting_cover.size.x * 1.15, "the release must expand past the resting size before settling")
	book.seek_turn(0)
	_check(_difference(rest, await _capture()) <= 16, "seeking back to the beginning must reset every body transformation")
	book.seek_turn(1)
	var before_commit := await _capture()
	book.finish_turn(true)
	await _settle()
	_check(_difference(before_commit, await _capture()) <= 16, "body position and scale must settle without a landing jump")
	book.preview_turn(-1)
	book.seek_turn(0.46)
	var backwards_cover := _cover_bounds(await _capture())
	_check(backwards_cover.get_center().x > resting_cover.get_center().x + 20 and backwards_cover.size == compressed_cover.size, "reverse motion must mirror translation while keeping the same squeeze and zoom")
	demo._reset()
	_check(book.get_motion_transform() == Transform2D.IDENTITY, "reset must restore the original book position and scale")
	# 最大面板参数也必须留在扩展透明画布中，不能裁掉弯曲纸页。
	var inside := true
	book.squash_amount = 0.45
	book.travel_distance = 48
	book.zoom_amount = 0.30
	for side in [1, -1]:
		book.spread_index = 0 if side > 0 else 1
		book.preview_turn(side)
		for i in 41:
			book.seek_turn(float(i) / 40.0)
			var motion := book.get_motion_transform()
			for layer in 5:
				var amount := clampf(book.progress * 1.56 - layer * 0.14, 0.0, 1.0)
				for point in book._page_points(amount, layer):
					inside = inside and Rect2(Vector2.ONE, Vector2(book._view.size) - Vector2.ONE * 2).has_point(motion * point + PixelBook.OVERSCAN)
		book.reset()
	_check(inside, "maximum body motion must keep every moving page inside the overscan canvas")
	# 外部参数也恢复，避免污染后续捕获。
	book.squash_amount = 0.30
	book.travel_distance = 32
	book.zoom_amount = 0.18
	demo._reset()


func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while book.turning and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not book.turning, "animation must settle without leaving an active turn")


func _canvas_point(point: Vector2) -> Vector2:
	var zoom := minf(book.size.x / PixelBook.CANVAS.x, book.size.y / PixelBook.CANVAS.y)
	return book.get_global_transform_with_canvas() * ((book.size - PixelBook.CANVAS * zoom) * 0.5 + point * zoom)


func _mouse(point: Vector2, pressed: bool) -> void:
	_mouse_position = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame


func _drag(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _mouse_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_mouse_position = point
	Input.parse_input_event(event)
	await get_tree().process_frame


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BOOK_FLIP_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(50).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute("res://.maintenance/book-flip")
	demo = DEMO.instantiate()
	add_child(demo)
	await _frame()
	book = demo.book
	_check(book.get_spread_count() == 4 and book.spread_index == 0, "demo must expose four independent spreads")
	_check(not book.turn_previous() and not book.turning, "first spread must reject backwards turns")
	_check(demo.previous.disabled and not demo.next.disabled, "first-spread controls must reflect boundaries")
	var initial := await _capture()
	initial.save_png("res://.maintenance/book-flip/book-rest.png")
	_check(initial.get_pixel(0, 0).a == 0 and initial.get_pixel(initial.get_width() - 1, initial.get_height() - 1).a == 0, "component canvas must remain transparent outside the book")
	var padding := Vector2i(PixelBook.OVERSCAN)
	_check(initial.get_pixelv(Vector2i(100, 180) + padding).a > 0.99 and initial.get_pixelv(Vector2i(360, 180) + padding).a > 0.99, "both page textures must render on the GPU")
	book.preview_turn(1)
	book.seek_turn(0)
	_check(_difference(initial, await _capture()) <= 16, "blank transition sheets must not obscure the initial outer page")
	demo.timeline.value = 0.43
	_check(book.turning and book.paused and is_equal_approx(book.progress, 0.43), "timeline must begin a turn and pause at the selected phase")
	var bent := await _capture()
	bent.save_png("res://.maintenance/book-flip/book-turn.png")
	_check(_difference(initial, bent) > 14000, "turning pages must visibly bend and reveal the next spread")
	_check((await _capture()).get_data() == bent.get_data(), "paused geometry, textures and shadows must remain deterministic")
	book.shadows_enabled = false
	_check(_difference(bent, await _capture()) > 200, "shadow control must alter actual rendered pixels")
	book.shadows_enabled = true
	book.curl_strength = 0
	_check(_difference(bent, await _capture()) > 1000, "curl control must deform actual page geometry")
	book.curl_strength = 0.8
	book.leaf_count = 1
	_check(_difference(bent, await _capture()) > 1000, "multiple sheets must render independently")
	book.leaf_count = 3
	book.seek_turn(1)
	var landed := await _capture()
	_check(book.spread_index == 0, "scrubbing alone must never commit a spread")
	book.turn_duration = 0.2
	book.finish_turn(true)
	await _settle()
	var committed := await _capture()
	_check(book.spread_index == 1, "a completed forward turn must commit exactly one spread")
	var seam := _difference(landed, committed)
	_check(seam <= 16, "landing must preserve front/back orientation and match the resting page textures")
	_check(not book.turning and not demo.next.disabled and not demo.previous.disabled, "controls must unlock after completing a turn")
	_check(book.turn_previous(), "reverse turn must start")
	_check(not book.turn_next(), "repeated input during a turn must not start a second animation")
	book.seek_turn(0.57)
	var reverse := await _capture()
	reverse.save_png("res://.maintenance/book-flip/book-reverse.png")
	_check(_difference(reverse, committed) > 14000, "reverse pages must also bend and reveal their back faces")
	book.seek_turn(1)
	var reverse_landed := await _capture()
	book.finish_turn(true)
	await _settle()
	_check(book.spread_index == 0 and _difference(reverse_landed, await _capture()) <= 16, "reverse landing must restore the original spread without mirrored content")
	# 通过真实 GUI 输入验证点击、拖动和小幅拖动回弹。
	await _mouse(_canvas_point(Vector2(401, 180)), true)
	_check(book.dragging, "pressing the right paper must capture a drag")
	await _drag(_canvas_point(Vector2(374, 180)))
	_check(book.progress > 0.05 and book.progress < 0.22, "paper must follow a short drag before release")
	var drag_phase := book.progress
	await _frame()
	await _drag(_canvas_point(Vector2(374, 180)))
	_check(is_equal_approx(book.progress, drag_phase), "body translation and scale must not feed back into a stationary mouse drag")
	await _mouse(_canvas_point(Vector2(374, 180)), false)
	await _settle()
	_check(book.spread_index == 0, "an incomplete drag must spring back without changing pages")
	await _mouse(_canvas_point(Vector2(401, 180)), true)
	await _drag(_canvas_point(Vector2(120, 180)))
	await _mouse(_canvas_point(Vector2(120, 180)), false)
	await _settle()
	_check(book.spread_index == 1, "a complete right-to-left drag must commit the next spread")
	await _mouse(_canvas_point(Vector2(80, 180)), true)
	await _drag(_canvas_point(Vector2(365, 180)))
	await _mouse(_canvas_point(Vector2(365, 180)), false)
	await _settle()
	_check(book.spread_index == 0, "left-to-right drag must commit the previous spread")
	await _mouse(demo.next.get_global_rect().get_center(), true)
	await _mouse(demo.next.get_global_rect().get_center(), false)
	_check(book.turning, "the actual next button must start animation")
	demo.pause.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await get_tree().process_frame
	_check(book.paused, "space must pause once even when a button has keyboard focus")
	var frozen := book.progress
	await get_tree().create_timer(0.15).timeout
	_check(is_equal_approx(book.progress, frozen), "pause must freeze the animation clock")
	demo._toggle_pause()
	await _settle()
	_check(book.spread_index == 1, "resume must complete the interrupted turn")
	for i in 2:
		book.turn_next()
		await _settle()
	_check(book.spread_index == 3 and not book.turn_next() and demo.next.disabled, "last spread must reject further forward turns")
	demo.timeline.value = 0.35
	_check(book.direction == -1 and book.paused, "timeline at the last spread must preview a valid backwards turn")
	book.finish_turn(false)
	await _settle()
	_check(book.spread_index == 3, "cancelling a scrub must keep the current spread")
	demo._auto_direction = 1
	demo.auto_button.button_pressed = true
	demo._auto_wait = 1.7
	await get_tree().process_frame
	await get_tree().process_frame
	_check(book.turning and book.direction == -1, "autoplay must reverse at the end of the book")
	demo._reset()
	_check(book.spread_index == 0 and not book.turning and not demo.auto_button.button_pressed and book.leaf_count == 3, "reset must cancel active animation and restore the defaults")
	await _mouse(_canvas_point(Vector2(400, 180)), true)
	await _drag(_canvas_point(Vector2(240, 180)))
	book.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await _mouse(_canvas_point(Vector2(240, 180)), false)
	await _settle()
	_check(book.spread_index == 0 and not book.dragging, "losing focus must safely cancel a captured drag")
	var points_inside := true
	for side in [1, -1]:
		book.direction = side
		for curl in [0.0, 0.8, 1.4]:
			book.curl_strength = curl
			for i in 41:
				for point in book._page_points(float(i) / 40.0, 4):
					points_inside = points_inside and Rect2(1, 1, 478, 338).has_point(point)
	_check(points_inside, "all allowed curl/leaf settings and both directions must stay inside the transparent canvas")
	demo._reset()
	book.curl_strength = 0.8
	_check(demo.find_children("*", "UnitBase", true, false).is_empty(), "preview must not instantiate gameplay units")
	await _check_blank_transition_pages()
	await _check_body_motion()
	if "--capture-book-loop" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://.maintenance/book-flip/loop")
		for side in [1, -1]:
			book.preview_turn(side)
			for i in 24:
				book.seek_turn(float(i) / 23.0)
				var img := await _capture()
				img.save_png("res://.maintenance/book-flip/loop/%03d.png" % (i + (24 if side < 0 else 0)))
			book.finish_turn(true)
			await _settle()
	await _frame()
	get_viewport().get_texture().get_image().save_png("res://.maintenance/book-flip/test-demo.png")
	print("BOOK_FLIP_METRICS: landing_changed_pixels=", seam)
	print("BOOK_FLIP_RENDER_TEST: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
