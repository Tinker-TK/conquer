extends Node
## 真实草地纹理上的 GPU 检查：融合、人物层级、粒子、独立实例、暂停和 RNG 隔离。

const EFFECT := preload("res://scenes/effects/pixel_burned_ground.tscn")
const GRASS := preload("res://assets/tilemap/field_128_128.png")
const SPARK_SOURCE := preload("res://assets/effect/eslabong_vfx/source/Scenes/VFX/BurnGroundVFX.tscn")
const OUT := "res://.maintenance/burned-ground/"
var view: SubViewport
var burn: Node2D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("BURNED_GROUND_CHECK: " + message)


func capture() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			count += int(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.025)
	return count


func fire_mask(frame: Image, background: Image) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(frame.get_width() * frame.get_height())
	for y in frame.get_height():
		for x in frame.get_width():
			var color := frame.get_pixel(x, y)
			mask[y * frame.get_width() + x] = int(color.r - background.get_pixel(x, y).r > 0.08 and color.r > color.g * 1.2)
	return mask


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BURNED_GROUND_RENDER_TEST requires a graphical renderer")
		get_tree().quit(2)
		return
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	view = SubViewport.new()
	view.size = Vector2i(384, 384)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var ground := TextureRect.new()
	ground.texture = ImageTexture.create_from_image(GRASS.get_image().get_region(Rect2i(128, 128, 128, 128)))
	ground.stretch_mode = TextureRect.STRETCH_TILE
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.size = Vector2(384, 384)
	ground.z_index = -20
	view.add_child(ground)
	burn = EFFECT.instantiate()
	burn.position = Vector2(192, 192)
	burn.radius = 144.0
	burn.spark_density = 0.0
	burn.flame_density = 0.0
	burn.playing = false
	burn.process_mode = Node.PROCESS_MODE_PAUSABLE
	view.add_child(burn)
	burn.hide()
	var grass := await capture()
	grass.save_png(OUT + "grass-before.png")
	burn.show()
	burn.seek(2.4)
	var scorched := await capture()
	var outside := 0
	var before_sum := 0.0
	var after_sum := 0.0
	for y in 384:
		for x in 384:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(192, 192))
			if d > 145.0:
				outside += int(grass.get_pixel(x, y) != scorched.get_pixel(x, y))
			elif d < 65.0:
				before_sum += grass.get_pixel(x, y).g
				after_sum += scorched.get_pixel(x, y).g
	check(outside == 0, "ground outside the damage radius must remain unchanged")
	check(after_sum < before_sum * 0.78 and after_sum > before_sum * 0.25, "central grass should be charred while retaining visible ground detail")
	var detailed := 0
	var preserved := 0
	for gy in range(-25, 25):
		for gx in range(-25, 25):
			var x := 192 + gx * 2
			var y := 192 + gy * 2
			var before_delta := grass.get_pixel(x, y).g - grass.get_pixel(x + 1, y).g
			if absf(before_delta) > 0.025:
				detailed += 1
				var after_delta := scorched.get_pixel(x, y).g - scorched.get_pixel(x + 1, y).g
				preserved += int(before_delta * after_delta > 0.0)
	check(detailed > 30 and preserved > detailed * 0.95, "original grass blade contrast must survive the scorch shader")
	burn.burn_amount = 0.0
	check((await capture()).get_data() == grass.get_data(), "zero burn must reproduce the original ground exactly")
	burn.burn_amount = 0.86
	burn.spark_density = 1.0
	var particles := burn.get_node("Sparks/Particles") as CPUParticles2D
	var authored := SPARK_SOURCE.instantiate()
	var source := authored.get_node("Particles") as CPUParticles2D
	check(particles.amount == source.amount and particles.lifetime == source.lifetime
		and particles.gravity == source.gravity and particles.randomness == source.randomness
		and particles.initial_velocity_min == source.initial_velocity_min and particles.initial_velocity_max == source.initial_velocity_max
		and particles.scale_amount_min == source.scale_amount_min and particles.scale_amount_max == source.scale_amount_max
		and particles.scale_amount_curve == source.scale_amount_curve and particles.color_ramp == source.color_ramp,
		"sparks must use the laboratory particle settings and shared original curves")
	authored.free()
	burn.seek(2.4)
	var with_sparks := await capture()
	with_sparks.save_png(OUT + "burned-grass.png")
	check(difference(scorched, with_sparks) > 40, "original ember particles must be visible above the charred grass")
	burn.seek(3.1)
	check(difference(with_sparks, await capture()) > 100, "sparks should rise and expire over time")
	burn.seek(2.4)
	check((await capture()).get_data() == with_sparks.get_data(), "seeking must exactly reproduce the original particles and shader")
	burn.flame_density = 0.85
	burn.seek(2.4)
	var burning := await capture()
	burning.save_png(OUT + "burned-grass.png")
	check(difference(with_sparks, burning) > 500, "orange-red burning patches must be clearly visible above the scorched grass")
	# Inspect rendered combustion, independently of how many nodes draw it.
	burn.get_node("Sparks").hide()
	var previous := PackedByteArray()
	var ignited := 0
	var extinguished := 0
	for sample in 9:
		burn.seek(sample * 0.5)
		var image := await capture()
		var mask := fire_mask(image, scorched)
		var hot_pixels := mask.count(1)
		check(hot_pixels > 300 and hot_pixels < PI * 144.0 * 144.0 * 0.60,
			"surface fire should stay visible while leaving exposed scorched grass")
		for index in mask.size():
			if not previous.is_empty():
				ignited += int(mask[index] == 1 and previous[index] == 0)
				extinguished += int(mask[index] == 0 and previous[index] == 1)
		previous = mask
		var outside_changed := 0
		for y in 384:
			for x in 384:
				if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(192, 192)) > 145.0:
					outside_changed += int(image.get_pixel(x, y) != grass.get_pixel(x, y))
		check(outside_changed == 0, "surface fire must stay inside the terrain radius")
	check(ignited > 500 and extinguished > 500, "burning fronts must ignite new pixels and extinguish old ones")
	burn.get_node("Sparks").show()
	burn.seek(2.4)
	check((await capture()).get_data() == burning.get_data(), "burning patches must reproduce exactly when seeking")
	var unit_marker := ColorRect.new()
	unit_marker.position = Vector2(184, 180)
	unit_marker.size = Vector2(16, 24)
	unit_marker.color = Color("a6b8ce")
	unit_marker.z_index = 0
	view.add_child(unit_marker)
	var marked := await capture()
	check(marked.get_pixel(190, 190).is_equal_approx(unit_marker.color), "scorch pass must stay below units")
	unit_marker.hide()
	# Godot's native particle constructor draws one initial seed. Playback and
	# seeking must not consume anything beyond constructing that source node.
	seed(371)
	var reference_particle := CPUParticles2D.new()
	var expected := randi()
	reference_particle.free()
	seed(371)
	var other := EFFECT.instantiate() as Node2D
	other.playing = false
	other.hide()
	view.add_child(other)
	other.seek(8.0)
	check(randi() == expected, "particle playback must not consume extra gameplay randomness")
	var material := burn.get_node("ScorchedGrass").material as ShaderMaterial
	var other_material := other.get_node("ScorchedGrass").material as ShaderMaterial
	check(material != other_material, "overlapping areas need independent materials")
	var flame_material := burn.get_node("BurningFlames/BurningSurface").material as ShaderMaterial
	var other_flame_material := other.get_node("BurningFlames/BurningSurface").material as ShaderMaterial
	check(flame_material != other_flame_material, "surface combustion needs independent materials per terrain area")
	burn.burn_amount = 0.7
	check(other_material.get_shader_parameter("burn_amount") == 0.86, "editing one burn area must not change another")
	burn.burn_amount = 0.86
	burn.playing = true
	await get_tree().physics_frame
	get_tree().paused = true
	var paused_time: float = material.get_shader_parameter("clock_time")
	var paused := await capture()
	await get_tree().create_timer(0.15, true).timeout
	check(is_equal_approx(material.get_shader_parameter("clock_time"), paused_time), "scorch clock must stop during pause")
	check((await capture()).get_data() == paused.get_data(), "burning patches, laboratory sparks and embers must stop during pause")
	get_tree().paused = false
	burn.playing = false
	for frame in 16:
		burn.seek(frame * 0.2)
		(await capture()).save_png(OUT + "loop-%02d.png" % frame)
	print("BURNED_GROUND_RENDER_TEST: %d checks; failures=%s; grass detail=%d/%d" % [checks, failures, preserved, detailed])
	get_tree().quit(0 if failures.is_empty() else 1)
