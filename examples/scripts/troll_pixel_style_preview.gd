# 巨魔画风试做：原版/2像素/4像素保持同体型、同动画、同一帧；下方放大检查轮廓。
# 只复制动画显示，不创建战斗单位，不写回原图和正式场景。
extends Node2D

const STYLE_SHADER := preload("res://shaders/unit_pixel_style.gdshader")
const TROLL_SCENE := preload("res://scenes/units/troll.tscn")
const ORC_SCENE := preload("res://scenes/units/orc.tscn")
const TROLL_PALETTE := preload("res://data/visuals/enemy_pack/troll.tres")
const PIXEL_STEPS := [1, 2, 4]

var troll_clock: AnimatedSprite2D
var orc_clock: AnimatedSprite2D
var troll_views: Array[Sprite2D] = []
var troll_details: Array[Sprite2D] = []
var orc_views: Array[Sprite2D] = []
var orc_details: Array[Sprite2D] = []
var style_materials: Array[ShaderMaterial] = []
var palette: ImageTexture
var source_palette: ImageTexture
var palette_toggle: CheckButton
var pause_button: Button
var frame_slider: HSlider
var frame_label: Label
var status_label: Label
var paused := false
var selected_animation: StringName = &"idle"
var rate := 1.0
var _syncing_slider := false


func _ready() -> void:
	# 与正式巨魔共享同一份色板，原版列仍直接显示原始纹理。
	palette = TROLL_PALETTE.target_texture()
	source_palette = TROLL_PALETTE.source_texture()
	_build_ui()
	_build_sprites()
	_play(&"idle")
	if "--troll-style-capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _clock(scene: PackedScene, id: String) -> AnimatedSprite2D:
	var unit := scene.instantiate()
	var source := unit.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var clock := AnimatedSprite2D.new()
	clock.name = id
	clock.sprite_frames = source.sprite_frames
	clock.visible = false
	clock.animation = &"idle"
	add_child(clock)
	preload("res://scripts/combat/fixed_sprite_clock.gd").attach(clock)
	unit.free()
	clock.animation_finished.connect(_finished.bind(clock))
	return clock


func _view(parent: Node, point: Vector2, magnification: float, effect_material: Material = null) -> Sprite2D:
	var view := Sprite2D.new()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.position = point
	view.scale = Vector2.ONE * magnification
	view.material = effect_material
	parent.add_child(view)
	return view


func _build_sprites() -> void:
	troll_clock = _clock(TROLL_SCENE, "TrollClock")
	orc_clock = _clock(ORC_SCENE, "OrcClock")
	for index in PIXEL_STEPS.size():
		var left := 40.0 + index * 620.0
		var effect_material: ShaderMaterial
		if index > 0:
			effect_material = ShaderMaterial.new()
			effect_material.shader = STYLE_SHADER
			effect_material.set_shader_parameter("pixel_step", float(PIXEL_STEPS[index]))
			effect_material.set_shader_parameter("palette_texture", palette)
			effect_material.set_shader_parameter("source_palette_texture", source_palette)
			effect_material.set_shader_parameter("palette_count", TROLL_PALETTE.source_colors.size())
			effect_material.set_shader_parameter("match_palette", palette_toggle.button_pressed)
		style_materials.append(effect_material)
		# 与游戏中的精灵缩放/脚底位置一致，三种处理不改变巨魔的体型。
		troll_views.append(_view(self, Vector2(left + 390, 438), 1.0, effect_material))
		orc_views.append(_view(self, Vector2(left + 123, 519), 4.0))
		var clip := Control.new()
		clip.position = Vector2(left + 20, 690)
		clip.size = Vector2(560, 282)
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(clip)
		# 放大后的挥棒可能横跨整格；分开裁剪，避免盖住旧角色参照。
		var reference_clip := Control.new()
		reference_clip.size = Vector2(235, 282)
		reference_clip.clip_contents = true
		reference_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(reference_clip)
		var troll_clip := Control.new()
		troll_clip.position = Vector2(245, 0)
		troll_clip.size = Vector2(315, 282)
		troll_clip.clip_contents = true
		troll_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(troll_clip)
		troll_details.append(_view(troll_clip, Vector2(105, 230), 2.0, effect_material))
		orc_details.append(_view(reference_clip, Vector2(100, 180), 8.0))
	troll_clock.frame_changed.connect(_sync_troll)
	troll_clock.animation_changed.connect(_sync_troll)
	orc_clock.frame_changed.connect(_sync_orc)
	orc_clock.animation_changed.connect(_sync_orc)
	_sync_troll()
	_sync_orc()


func _label(text: String, point: Vector2, font_size: int, tint: Color = Color("e4eeec")) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.modulate = tint
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


func _button(text: String, point: Vector2, callback: Callable, width := 140.0) -> Button:
	var button := Button.new()
	button.text = text
	button.position = point
	button.size = Vector2(width, 46)
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(callback)
	add_child(button)
	return button


func _build_ui() -> void:
	_label("巨魔 · 像素风试做", Vector2(40, 24), 34)
	_label("同体型 · 同动画 · 同一帧对照    /    每组左侧为现有 Orc，右侧为巨魔", Vector2(42, 75), 20, Color("a5bbc0"))
	_button("待机", Vector2(40, 118), _play.bind(&"idle"))
	_button("移动", Vector2(190, 118), _play.bind(&"walk"))
	_button("攻击一次", Vector2(340, 118), _play.bind(&"attack_01"), 165)
	pause_button = _button("暂停", Vector2(515, 118), _toggle_pause)
	_button("逐帧 →", Vector2(665, 118), _step_frame)
	_button("转身", Vector2(815, 118), _flip, 110)
	var slow := CheckButton.new()
	slow.text = "半速播放"
	slow.position = Vector2(950, 117)
	slow.add_theme_font_size_override("font_size", 21)
	slow.toggled.connect(_set_slow)
	add_child(slow)
	palette_toggle = CheckButton.new()
	palette_toggle.text = "2 / 4 像素匹配旧角色色板"
	palette_toggle.position = Vector2(1190, 117)
	palette_toggle.add_theme_font_size_override("font_size", 21)
	palette_toggle.button_pressed = true
	palette_toggle.toggled.connect(_set_palette)
	add_child(palette_toggle)
	_button("返回怪物预览", Vector2(1670, 118), func(): get_tree().change_scene_to_file("res://examples/scenes/enemy_pack_preview.tscn"), 200)
	var titles := ["原版", "2 像素 · 折中", "4 像素 · 接近旧角色颗粒"]
	var hints := ["保留原始细节与颜色", "保留较多面部、木棒细节", "颗粒更粗，重点观察轮廓与细小部位"]
	for index in 3:
		var x := 64.0 + index * 620.0
		_label(titles[index], Vector2(x, 210), 26)
		_label(hints[index], Vector2(x, 253), 18, Color("9fb7bd"))
		_label("旧 Orc", Vector2(x + 50, 566), 19, Color("a5bbc0"))
		_label("巨魔 · 原体型", Vector2(x + 270, 566), 19, Color("a5bbc0"))
		_label("2× 细节对照", Vector2(x, 643), 21)
	frame_slider = HSlider.new()
	frame_slider.position = Vector2(50, 1000)
	frame_slider.size = Vector2(1350, 32)
	frame_slider.step = 1.0
	frame_slider.value_changed.connect(_seek)
	add_child(frame_slider)
	frame_label = _label("", Vector2(1450, 996), 21)
	status_label = _label("", Vector2(50, 1045), 18, Color("9fb7bd"))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("14262d"))
	for index in 3:
		var x := 40.0 + index * 620.0
		draw_rect(Rect2(x, 190, 600, 420), Color("203940"))
		draw_line(Vector2(x + 25, 535), Vector2(x + 575, 535), Color("4c6264"), 2)
		draw_rect(Rect2(x, 630, 600, 352), Color("1c333a"))
		draw_rect(Rect2(x + 20, 690, 560, 282), Color("244249"))
		draw_line(Vector2(x + 260, 700), Vector2(x + 260, 962), Color("34535a"), 1)


func _play(animation: StringName) -> void:
	selected_animation = animation
	paused = false
	pause_button.text = "暂停"
	for clock in [troll_clock, orc_clock]:
		clock.stop()
		clock.speed_scale = rate
		clock.play(animation)
	frame_slider.max_value = troll_clock.sprite_frames.get_frame_count(animation) - 1
	_sync_troll()
	_sync_orc()


func _finished(clock: AnimatedSprite2D) -> void:
	if clock.animation == &"attack_01":
		clock.play(&"idle")
		if clock == troll_clock:
			selected_animation = &"idle"
			frame_slider.max_value = clock.sprite_frames.get_frame_count(&"idle") - 1


func _sync_troll() -> void:
	if troll_clock == null or troll_views.is_empty():
		return
	var texture := troll_clock.sprite_frames.get_frame_texture(troll_clock.animation, troll_clock.frame)
	for index in troll_views.size():
		troll_views[index].texture = texture
		troll_details[index].texture = texture
		troll_views[index].flip_h = troll_clock.flip_h
		troll_details[index].flip_h = troll_clock.flip_h
		if style_materials[index] != null and texture is AtlasTexture:
			style_materials[index].set_shader_parameter("frame_origin", texture.region.position)
			style_materials[index].set_shader_parameter("frame_size", texture.region.size)
	_syncing_slider = true
	frame_slider.value = troll_clock.frame
	_syncing_slider = false
	frame_label.text = "%s  %d / %d" % [troll_clock.animation, troll_clock.frame + 1, troll_clock.sprite_frames.get_frame_count(troll_clock.animation)]
	status_label.text = "攻击播完各自回待机；空格暂停 / 继续，拖动滑条检查动作细节。色板：%s" % ("旧角色配色" if palette_toggle.button_pressed else "巨魔原配色")


func _sync_orc() -> void:
	if orc_clock == null:
		return
	var texture := orc_clock.sprite_frames.get_frame_texture(orc_clock.animation, orc_clock.frame)
	for index in orc_views.size():
		orc_views[index].texture = texture
		orc_details[index].texture = texture
		orc_views[index].flip_h = orc_clock.flip_h
		orc_details[index].flip_h = orc_clock.flip_h


func _set_palette(enabled: bool) -> void:
	palette_toggle.set_pressed_no_signal(enabled)
	for effect_material in style_materials:
		if effect_material != null:
			effect_material.set_shader_parameter("match_palette", enabled)
	_sync_troll()


func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "继续" if paused else "暂停"
	for clock in [troll_clock, orc_clock]:
		if paused:
			clock.pause()
		else:
			clock.play()


func _set_slow(enabled: bool) -> void:
	rate = 0.5 if enabled else 1.0
	troll_clock.speed_scale = rate
	orc_clock.speed_scale = rate


func _seek(value: float) -> void:
	if _syncing_slider or troll_clock == null:
		return
	paused = true
	pause_button.text = "继续"
	troll_clock.pause()
	orc_clock.pause()
	troll_clock.set_frame_and_progress(int(value), 0.0)
	_sync_troll()


func _step_frame() -> void:
	_seek(float((troll_clock.frame + 1) % troll_clock.sprite_frames.get_frame_count(troll_clock.animation)))


func _flip() -> void:
	troll_clock.flip_h = not troll_clock.flip_h
	orc_clock.flip_h = troll_clock.flip_h
	_sync_troll()
	_sync_orc()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _capture() -> void:
	for _index in 8:
		await get_tree().physics_frame
	paused = true
	pause_button.text = "继续"
	troll_clock.pause()
	orc_clock.pause()
	await _save("res://.maintenance/troll_style/idle-palette.png")
	_set_palette(false)
	await _save("res://.maintenance/troll_style/idle-original-colors.png")
	_set_palette(true)
	_play(&"attack_01")
	for step in 275:
		await get_tree().physics_frame
		if step in [48, 93, 141, 215]:
			await _save("res://.maintenance/troll_style/attack-%03d.png" % step)
	assert(troll_clock.animation == &"idle", "完整攻击仅播一次，结束回待机")
	_play(&"walk")
	for _index in 20:
		await get_tree().physics_frame
	_toggle_pause()
	var before := troll_clock.frame
	for _index in 8:
		await get_tree().physics_frame
	assert(troll_clock.frame == before, "暂停冻结动画")
	_step_frame()
	assert(troll_clock.frame == (before + 1) % troll_clock.sprite_frames.get_frame_count(&"walk"), "逐帧前进")
	_flip()
	await _save("res://.maintenance/troll_style/walk-flipped.png")
	print("TROLL_STYLE_CAPTURE_PASS: synchronized original/2px/4px, palette toggle, full attack, pause, step, flip")
	get_tree().quit()
