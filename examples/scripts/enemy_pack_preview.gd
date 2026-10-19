# F6 浏览所有新怪物；攻击按钮只触发一套动作，各自播完后回待机，不使用统一重播间隔。
extends Node2D

const IDS := ["orc", "bear", "bomb_fish", "bumblebee", "giant_bat", "gnoll", "gnome",
	"harpoon_shark", "hex_shaman", "imp", "lizard", "minotaur", "paddle_shark", "panda",
	"skull", "slingshot_gnome", "snake", "spear_goblin", "spider", "thief", "torch_goblin",
	"troll", "turtle", "pig_rider"]
var units: Array[UnitBase] = []


func _ready() -> void:
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_label("Tiny Swords · 怪物预览", Vector2(40, 20), 32)
	_label("23 种新怪物 · 2 像素 + 旧角色配色     ·     左上为原兽人体型参照", Vector2(42, 66), 19)
	for index in IDS.size():
		var column := index % 6
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		var row := index / 6
		var preview := load("res://scenes/units/%s.tscn" % IDS[index]).instantiate() as UnitBase
		_label(preview.unit_data.unit_name, Vector2(40 + column * 310, 290 + row * 230), 22)
		_label(IDS[index], Vector2(40 + column * 310, 318 + row * 230), 15, Color("8faab4"))
		preview.free()
	var actions := [["待机", &"idle"], ["移动", &"walk"], ["攻击", &"attack_01"]]
	for index in actions.size():
		var button := _button(actions[index][0], Vector2(1010 + index * 150, 32))
		button.pressed.connect(_animate.bind(actions[index][1]))
	_button("白烟退场", Vector2(1470, 32)).pressed.connect(_die_all)
	_button("重新生成", Vector2(1640, 32)).pressed.connect(_spawn_all)
	var style_button := _button("巨魔画风", Vector2(1788, 32))
	style_button.size.x = 120
	style_button.pressed.connect(func(): get_tree().change_scene_to_file("res://examples/scenes/troll_pixel_style_preview.tscn"))
	_spawn_all()
	if "--enemy-pack-capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	elif "--enemy-pack-attack-capture" in OS.get_cmdline_user_args():
		_capture_attack.call_deferred()
	elif "--enemy-pack-style-capture" in OS.get_cmdline_user_args():
		_capture_style.call_deferred()


func _label(text: String, point: Vector2, font_size: int, tint: Color = Color("e6f0ef")) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = tint
	add_child(label)


func _button(text: String, point: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = point
	button.size = Vector2(135, 48)
	button.add_theme_font_size_override("font_size", 21)
	add_child(button)
	return button


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("15272e"))
	for index in IDS.size():
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		var cell := Rect2(24 + index % 6 * 310, 110 + index / 6 * 230, 292, 224)
		draw_rect(cell, Color("20393f"))
		draw_line(cell.position + Vector2(20, 168), cell.position + Vector2(272, 168), Color("375458"), 2)


func _spawn_all() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.free()
	units.clear()
	for index in IDS.size():
		var unit := load("res://scenes/units/%s.tscn" % IDS[index]).instantiate() as UnitBase
		add_child(unit)
		unit.set_physics_process(false)
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		unit.position = Vector2(170 + index % 6 * 310, 275 + index / 6 * 230)
		unit.scale = Vector2.ONE * (0.7 if IDS[index] == "troll" else 0.85)
		unit.animated_sprite_2d.flip_h = false
		unit.animated_sprite_2d.animation_finished.connect(_on_animation_finished.bind(unit))
		units.append(unit)
	_animate(&"idle")


func _animate(animation: StringName) -> void:
	for unit in units:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEATH:
			# 再次点击攻击从第一帧重播；每只单位自行播完一轮，不设统一重播时钟。
			if animation == &"attack_01":
				unit.animated_sprite_2d.stop()
			unit.animated_sprite_2d.play(animation)


func _die_all() -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.die()


func _on_animation_finished(unit: UnitBase) -> void:
	if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEATH \
		and unit.animated_sprite_2d.animation == &"attack_01":
		unit.animated_sprite_2d.play(&"idle")


func _save_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _capture() -> void:
	for _index in 12:
		await get_tree().physics_frame
	await _save_frame("res://.maintenance/enemy_pack/gallery.png")
	_die_all()
	for _index in 7:
		await get_tree().physics_frame
	await _save_frame("res://.maintenance/enemy_pack/death-smoke.png")
	for _index in 13:
		await get_tree().physics_frame
	await _save_frame("res://.maintenance/enemy_pack/death-smoke-dispersing.png")
	for _index in 60:
		await get_tree().physics_frame
	await _save_frame("res://.maintenance/enemy_pack/death-smoke-cleared.png")
	print("ENEMY_PACK_CAPTURE_PASS")
	get_tree().quit()


func _capture_attack() -> void:
	_animate(&"attack_01")
	for step in 301:
		await get_tree().physics_frame
		if step in [48, 105, 180, 285]:
			await _save_frame("res://.maintenance/enemy_pack/rhythm/attack_%03d.png" % step)
	print("ENEMY_PACK_ATTACK_CAPTURE_PASS")
	get_tree().quit()


# 用实际战斗单位截取所有新材质的待机、移动、连击、受击和白烟，不另建一套显示实现。
func _capture_style() -> void:
	var folder := "res://.maintenance/enemy_pack/style/"
	DirAccess.make_dir_recursive_absolute(folder)
	for _index in 12:
		await get_tree().physics_frame
	await _save_frame(folder + "idle.png")
	for unit in units:
		if unit.unit_data.unit_english_name != "orc":
			unit.animated_sprite_2d.material.set_shader_parameter("pixel_step", 1.0)
			unit.animated_sprite_2d.material.set_shader_parameter("match_palette", false)
	await _save_frame(folder + "original.png")
	for unit in units:
		if unit.unit_data.unit_english_name != "orc":
			unit.animated_sprite_2d.material.set_shader_parameter("pixel_step", 2.0)
			unit.animated_sprite_2d.material.set_shader_parameter("match_palette", true)
	_animate(&"walk")
	for _index in 20:
		await get_tree().physics_frame
	await _save_frame(folder + "walk.png")
	_animate(&"attack_01")
	for step in 301:
		await get_tree().physics_frame
		if step in [48, 105, 180, 285]:
			await _save_frame(folder + "attack-%03d.png" % step)
	for unit in units:
		unit.animated_sprite_2d.material.set_shader_parameter("flash_intensity", 0.8)
	await _save_frame(folder + "hurt.png")
	for unit in units:
		unit.animated_sprite_2d.material.set_shader_parameter("flash_intensity", 0.0)
	_die_all()
	for step in 70:
		await get_tree().physics_frame
		if step in [6, 19, 65]:
			await _save_frame(folder + "smoke-%02d.png" % step)
	await _capture_projectiles(folder)
	print("ENEMY_PACK_STYLE_CAPTURE_PASS")
	get_tree().quit()


func _capture_projectiles(folder: String) -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var background := ColorRect.new()
	background.color = Color("15272e")
	background.size = Vector2(1920, 1080)
	overlay.add_child(background)
	var title := Label.new()
	title.text = "专属投射物与命中特效 · 2 像素 + 旧角色配色（4× 放大检查）"
	title.position = Vector2(80, 100)
	title.add_theme_font_size_override("font_size", 32)
	overlay.add_child(title)
	var ranged := ["bomb_fish", "gnoll", "harpoon_shark", "hex_shaman", "slingshot_gnome"]
	for index in ranged.size():
		var projectile: Node2D = load("res://scenes/projectiles/%s_projectile.tscn" % ranged[index]).instantiate()
		overlay.add_child(projectile)
		projectile.set_physics_process(false)
		projectile.position = Vector2(240 + index * 350, 430)
		projectile.scale = Vector2.ONE * 4.0
		var caption := Label.new()
		caption.text = ranged[index]
		caption.position = Vector2(120 + index * 350, 550)
		caption.add_theme_font_size_override("font_size", 22)
		overlay.add_child(caption)
	var impact: AnimatedSprite2D = load("res://scenes/effects/hex_shaman_hit.tscn").instantiate()
	overlay.add_child(impact)
	impact.position = Vector2(960, 850)
	impact.scale = Vector2.ONE * 4.0
	for _index in 20:
		await get_tree().physics_frame
	await _save_frame(folder + "projectiles.png")
