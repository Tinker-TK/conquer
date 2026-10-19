# 验证可配置药水特效在真实战场中的播放、暂停、移动与清理；所有配置只用于测试实例。
extends Node

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


# 两个不同循环设置的动画用于验证运行时隔离，场景自身还带有缩放和绘制偏移。
func make_visual_scene(selected: StringName = &"scene_default", empty_current := false) -> PackedScene:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for animation_name in [&"scene_default", &"chosen"]:
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, 5.0)
		frames.set_animation_loop(animation_name, animation_name == &"scene_default")
		for index in 3:
			frames.add_frame(animation_name, texture)
	if empty_current:
		frames.add_animation(&"empty")
	var visual := AnimatedSprite2D.new()
	visual.sprite_frames = frames
	visual.animation = selected
	visual.scale = Vector2(2, 3)
	visual.offset = Vector2(0, -6)
	var packed := PackedScene.new()
	assert(packed.pack(visual) == OK)
	visual.free()
	return packed


func add_potion(kind: PotionDefinition.Kind, scene: PackedScene) -> PotionDefinition:
	var recipe := PotionDefinition.new()
	recipe.id = &"visual_test"
	recipe.display_name = "特效测试药水"
	recipe.kind = kind
	recipe.casts = 1
	recipe.cast_delay = 0.1
	recipe.duration = 0.3
	recipe.effect_scene = scene
	recipe.effect_scale = Vector2(0.5, 2)
	recipe.effect_offset = Vector2(17, -9)
	RunManager.add_potion(recipe)
	return RunManager.potions.back()


func _run() -> void:
	var initial = load("res://data/run/run_start_data.tres").duplicate(true)
	initial.starting_relics.clear()
	initial.starting_potions.clear()
	RunManager.start_new_run(initial)
	# 保存重读检查使用已有美术场景，但不写入正式药水资源。
	var saved := PotionDefinition.new()
	saved.effect_scene = load("res://scenes/effects/potion_effect.tscn")
	saved.effect_scale = Vector2(2, 0.5)
	saved.effect_offset = Vector2(4, -7)
	var fixture_path := "user://potion_visual_fixture.tres"
	check(ResourceSaver.save(saved, fixture_path) == OK, "特效配置可以保存")
	var restored := ResourceLoader.load(fixture_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PotionDefinition
	check(restored != null and restored.effect_scene != null and restored.effect_scene.resource_path == saved.effect_scene.resource_path, "特效场景保存重读，无需额外动画名")
	check(restored.effect_scale == saved.effect_scale and restored.effect_offset == saved.effect_offset, "缩放与偏移保存重读")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))

	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	var items = battle.get_node("BattleItems")
	items.set_physics_process(false)
	# 让测试手动推进药水状态，动画仍由引擎正常播放；冻结单位以避免交锋提前结束。
	for unit in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	var enemy: UnitBase = battle.get_node("Entities/TeamB").get_child(0)
	enemy.current_health = 1000
	var point := Vector2(800, 500)
	enemy.global_position = point
	items.position = Vector2(37, 23)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var scene := make_visual_scene()
	var recipe := add_potion(PotionDefinition.Kind.LIGHTNING, scene)
	check(items.select_potion(recipe), "可选择带特效的闪电药水")
	check(not items.try_cast(Vector2(-999, -999)) and items._flash_visuals.is_empty() and RunManager.potions.size() == 1, "无效落点不生成特效或扣瓶")
	check(items.try_cast(point), "合法落点成功施放")
	var flash: AnimatedSprite2D = items._flash_visuals[0]
	check(flash.animation == &"scene_default" and flash.is_playing(), "只配置场景即可使用当前动画")
	check(flash.global_position.is_equal_approx(point + recipe.effect_offset), "父节点有偏移时仍按世界坐标放置")
	check(flash.scale.is_equal_approx(Vector2(1, 6)) and flash.offset == Vector2(0, -6), "倍率叠加场景原缩放并保留绘制偏移")
	check(not flash.sprite_frames.get_animation_loop(flash.animation), "闪电实例改为单次播放")
	check(enemy.current_health == 992 and RunManager.potions.is_empty(), "特效缩放偏移不改变伤害中心与消耗")
	var source := scene.instantiate() as AnimatedSprite2D
	check(source.sprite_frames.get_animation_loop(&"scene_default"), "单次播放不污染原场景循环设置")
	source.free()
	items._physics_process(0.11)
	check(items.potion == null and is_instance_valid(flash) and not flash.is_queued_for_deletion(), "释放间隔结束不截断闪电动画")

	get_tree().paused = true
	var before_frame := flash.frame
	var before_progress := flash.frame_progress
	await get_tree().create_timer(0.15, true).timeout
	check(flash.frame == before_frame and is_equal_approx(flash.frame_progress, before_progress), "闪电残影在战斗暂停时停止播放")
	get_tree().paused = false

	var chosen_scene := make_visual_scene(&"chosen")
	recipe = add_potion(PotionDefinition.Kind.FIRE, chosen_scene)
	check(items.select_potion(recipe) and items.try_cast(point), "闪电残影存在时仍可使用下一瓶")
	var fire: AnimatedSprite2D = items._persistent_visual
	check(fire.animation == &"chosen" and fire.sprite_frames.get_animation_loop(&"chosen"), "火焰自动使用新场景当前动画并循环播放")
	source = chosen_scene.instantiate() as AnimatedSprite2D
	check(not source.sprite_frames.get_animation_loop(&"chosen"), "循环播放不污染原场景设置")
	source.free()
	check(fire.sprite_frames != flash.sprite_frames, "不同实例的 SpriteFrames 独立")
	var fire_point := fire.global_position
	items._physics_process(0.5)
	check(fire.global_position == fire_point and enemy.current_health == 976, "火焰固定在落点并保持周期伤害")
	await get_tree().create_timer(0.8).timeout
	await get_tree().process_frame
	check(not is_instance_valid(flash) and items._flash_visuals.is_empty(), "闪电由真实动画完成信号自动清理")
	check(is_instance_valid(fire) and fire.is_playing(), "持续特效跨动画周期保持播放")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	check(fire.is_queued_for_deletion() and items._persistent_visual == null, "交锋结束立即清理火焰")
	await get_tree().process_frame

	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	recipe = add_potion(PotionDefinition.Kind.TORNADO, chosen_scene)
	check(items.select_potion(recipe) and items.try_cast(point), "龙卷风成功施放")
	var tornado: AnimatedSprite2D = items._persistent_visual
	items._physics_process(0.1)
	check(items.effect_position != point and tornado.global_position.is_equal_approx(items.effect_position + recipe.effect_offset), "龙卷风视觉跟随伤害中心移动")
	get_tree().paused = true
	var paused_point := tornado.global_position
	items._physics_process(1.0)
	check(tornado.global_position == paused_point and items.potion != null, "暂停不会推进龙卷风位置或持续时间")
	get_tree().paused = false
	items._physics_process(0.21)
	check(items.potion == null and tornado.is_queued_for_deletion(), "龙卷风到期清理持续特效")
	await get_tree().process_frame

	# 配置错误仅回退显示，不影响合法施放、伤害和扣瓶。
	var empty_visual := AnimatedSprite2D.new()
	empty_visual.sprite_frames = SpriteFrames.new()
	var empty_scene := PackedScene.new()
	empty_scene.pack(empty_visual)
	empty_visual.free()
	recipe = add_potion(PotionDefinition.Kind.LIGHTNING, empty_scene)
	check(items.select_potion(recipe) and items.try_cast(point), "无动画帧的场景仍能施放")
	check(not items._cast_has_visual and items._flash_visuals.is_empty() and RunManager.potions.is_empty(), "无动画帧回退到占位显示")
	items._physics_process(0.11)
	recipe = add_potion(PotionDefinition.Kind.LIGHTNING, make_visual_scene(&"empty", true))
	check(items.select_potion(recipe) and items.try_cast(point) and items._cast_has_visual, "场景当前动画为空时自动选择有帧的动画")
	var auto_flash: AnimatedSprite2D = items._flash_visuals.back()
	check(auto_flash.animation != &"empty" and auto_flash.is_playing(), "自动选择的动画正常播放")
	items._physics_process(0.11)
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	await get_tree().process_frame
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var wrong_root := Node2D.new()
	var wrong_scene := PackedScene.new()
	wrong_scene.pack(wrong_root)
	wrong_root.free()
	recipe = add_potion(PotionDefinition.Kind.LIGHTNING, wrong_scene)
	check(items.select_potion(recipe) and items.try_cast(point) and not items._cast_has_visual, "错误场景根节点回退且不阻止施放")
	items._physics_process(0.11)
	recipe = add_potion(PotionDefinition.Kind.LIGHTNING, null)
	check(items.select_potion(recipe) and items.try_cast(point) and not items._cast_has_visual, "旧药水无配置时保持原有行为")
	items._physics_process(0.11)

	recipe = add_potion(PotionDefinition.Kind.LIGHTNING, scene)
	recipe.casts = 2
	check(items.select_potion(recipe) and items.try_cast(point), "多次闪电首发成功")
	items._physics_process(0.11)
	var second_point := point + Vector2(100, 0)
	check(items.try_cast(second_point) and items._flash_visuals.size() == 2, "每次有效点击生成独立闪电动画")
	var flashes: Array = items._flash_visuals.duplicate()
	check(flashes[0].global_position.is_equal_approx(point + recipe.effect_offset) and flashes[1].global_position.is_equal_approx(second_point + recipe.effect_offset), "后续闪电不会移动上一发视觉")
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	check(items._flash_visuals.is_empty() and flashes[0].is_queued_for_deletion() and flashes[1].is_queued_for_deletion(), "离开交锋清理所有未播完闪电")
	await get_tree().process_frame

	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	# 使用磁盘上实际配置的闪电药水，防止测试夹具通过而正式配置仍回退。
	var configured := load("res://data/potions/lightning.tres") as PotionDefinition
	RunManager.add_potion(configured)
	var owned: PotionDefinition = RunManager.potions.back()
	check(owned.effect_scene != null and items.select_potion(owned), "正式闪电药水保留配置的特效场景")
	var configured_source := owned.effect_scene.instantiate() as AnimatedSprite2D
	var configured_animation := configured_source.animation
	check(configured_source.sprite_frames.has_animation(configured_animation), "正式闪电自动读取场景当前动画")
	var expected_texture := configured_source.sprite_frames.get_frame_texture(configured_animation, 0)
	for index in owned.casts:
		check(items.try_cast(point) and items._cast_has_visual, "正式闪电第%d次施放使用配置特效" % (index + 1))
		var configured_flash: AnimatedSprite2D = items._flash_visuals.back()
		check(configured_flash.is_playing() and configured_flash.animation == configured_animation and configured_flash.sprite_frames.get_frame_texture(configured_animation, 0) == expected_texture, "正式闪电第%d次播放所选场景的真实帧" % (index + 1))
		items._physics_process(owned.cast_delay + 0.01)
	configured_source.free()
	check(items.potion == null and items._flash_visuals.size() == owned.casts, "正式闪电全部施放后残影独立保留")
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	await get_tree().process_frame

	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	recipe = add_potion(PotionDefinition.Kind.FIRE, scene)
	enemy.current_health = 1
	enemy.unit_died.connect(func(_unit): Global.game_phase = Global.GamePhase.ROUND_RESOLVE, CONNECT_ONE_SHOT)
	check(items.select_potion(recipe) and items.try_cast(point), "造成致死伤害的施放仍成功")
	check(items.potion == null and items._persistent_visual == null and not items._cast_has_visual, "伤害同步切换阶段不会遗留刚生成的视觉")
	battle.battle_finished = true
	battle.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(items), "销毁战场释放药水运行器及其视觉子节点")
	print("POTION_VISUALS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
