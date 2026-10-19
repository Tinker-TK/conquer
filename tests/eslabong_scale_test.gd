extends SceneTree

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Sizing = preload("res://assets/effect/eslabong_vfx/runtime/unit_scale.gd")
var failures: Array[String] = []

class SizedUnit extends Node2D:
	func _smoke_body_rect() -> Rect2:
		return Rect2(-12, -36, 24, 36)

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	check(Sizing.Data.DATA.profiles.size() == Library.catalog().items.size(), "Not all VFX have size profiles")
	for item: Dictionary in Library.catalog().items:
		var profile := Sizing.profile(item)
		check(not profile.is_empty(), "Missing size profile: " + str(item.id))
		if profile.role != "screen":
			check(float(profile.min_units) > 0 and float(profile.max_units) >= float(profile.min_units), "Invalid body-size limits: " + str(item.id))
	# Inspect actual scene geometry: the bubble must hug the 18px body even if
	# source data requests a very large or tiny authored multiplier.
	for authored: float in [.02, 1.0, 8.0]:
		var shield := Library.spawn(world, "ShieldBubbleVFX", Vector2.ZERO, {"scale": authored})
		var visual: Node2D = shield.get_meta("visual_root")
		var rect: ColorRect = visual.get_node("ColorRect")
		var diameter := rect.size.y * shield.scale.y
		check(diameter >= 18 * 1.2 and diameter <= 18 * 1.6, "Shield does not fit the visible body")
		shield.queue_free()
	var large_unit := SizedUnit.new()
	world.add_child(large_unit)
	var large_shield := Library.spawn(large_unit, "ShieldBubbleVFX")
	var large_diameter := 68.0 * large_shield.scale.y
	check(large_diameter >= 36 * 1.2 and large_diameter <= 36 * 1.6, "Shield did not adapt to a larger battlefield unit")
	large_unit.scale = Vector2.ONE * 2
	var attached := Library.spawn(world, "ShieldBubbleVFX", Vector2.ZERO, {"unit": large_unit})
	check(68 * attached.scale.y >= 72 * 1.2 and 68 * attached.scale.y <= 72 * 1.6, "Cross-parent unit scale was lost")
	attached.queue_free()
	large_unit.queue_free()
	# Body scaling must not change the requested endpoints of beam geometry.
	world.scale = Vector2.ONE * 2.5
	var from := Vector2(10, 5)
	var to := Vector2(200, 25)
	for effect_name: String in ["PlasmaBeam", "ThinBeam", "LightningBoltVFX_Premium"]:
		var holder := Library.spawn(world, effect_name, from, {"destination": world.to_global(to)})
		check(holder != null, "Missing beam: " + effect_name)
		if holder == null: continue
		var effect: Node2D = holder.get_meta("visual_root")
		var end: Vector2
		if "_main_bolt" in effect:
			end = effect.to_global(effect.get("_main_bolt")[-1])
		elif "line" in effect:
			var line: Line2D = effect.get("line")
			end = line.to_global(line.get_point_position(line.get_point_count() - 1))
		else:
			end = effect.to_global(Vector2(float(effect.get("_beam_length")), 0))
		check(end.distance_to(world.to_global(to)) < .2, "Beam endpoint changed with body/camera scale: " + effect_name)
		holder.queue_free()
	world.scale = Vector2.ONE
	# Read the actual typeface at the skill's requested multiplier. The comic
	# lettering must survive small-character rendering rather than just fit bounds.
	var boo := Library.spawn(world, "BooCastVFX", Vector2.ZERO, {"scale": .55})
	var boo_root: Node2D = boo.get_meta("visual_root")
	var boo_label: Label = boo_root.get_node("BooLabel")
	await create_timer(.4).timeout
	check(float(boo_label.get_theme_font_size("font_size")) * boo_root.global_scale.y >= 16, "Boo letters are too small to read at unit scale")
	check(boo.position.y < -18, "Boo callout obscures the unit body")
	boo.queue_free()
	# Stream thickness follows the unit; its length follows the requested target.
	var stream := Skills.Player.new()
	world.add_child(stream)
	stream.play(Skills.find("flamethrower"), Vector2(10, 5), Vector2(210, 65), {"auto_free": false})
	stream._execute("beam", Skills.find("flamethrower").actions[0])
	for child in stream.get_children():
		if not child.has_meta("effect_id"): continue
		var profile := Sizing.profile(Library.find(str(child.get_meta("effect_id"))))
		if profile.role != "stream": continue
		var tip := float(profile.native_width) * .5 + float(profile.native_offset[0])
		check(child.to_global(Vector2(tip, 0)).distance_to(world.to_global(Vector2(210, 65))) < .2, "Flame stream ended before target")
	stream.queue_free()
	# Beam/muzzle origins must follow facing, including reverse and diagonal aim.
	for skill_id: String in ["flamethrower", "chain_lightning", "lightning_smite", "blood_thunder", "hammer_beam"]:
		for heading: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(1, 1).normalized()]:
			var data := Skills.find(skill_id).duplicate(true)
			data.cast_seconds = 0
			var caster_at := Vector2(20, 15)
			var target_at := caster_at + heading * 200
			var beam := Skills.play(world, skill_id, caster_at, target_at, {"auto_free": false})
			beam.play(data, caster_at, target_at, {"auto_free": false})
			beam.set_process(false)
			for child in beam.get_children():
				if not child.has_meta("effect_id"): continue
				var item := Library.find(str(child.get_meta("effect_id")))
				var role := str(Sizing.profile(item).role)
				if item.mode != "beam" and role != "stream": continue
				check(child.position.distance_to(caster_at + heading * 12) < .01, "Beam starts inside the unit: " + skill_id)
				var visual: Node2D = child.get_meta("visual_root")
				if "_local_target_pos" in visual:
					check(visual.to_global(visual.get("_local_target_pos")).distance_to(target_at) < .1, "Lightning endpoint moved: " + skill_id)
				elif "_beam_length" in visual:
					check(visual.to_global(Vector2(float(visual.get("_beam_length")), 0)).distance_to(target_at) < .1, "Beam endpoint moved: " + skill_id)
			beam.queue_free()
	# The release flash belongs at the same muzzle, while charging stays on body.
	check(Skills.find("chain_lightning").release[0].at == "muzzle", "Lightning flash still uses the body center")
	# Every skill uses the same bounds, including scaled missiles and status stages.
	for skill: Dictionary in Skills.catalog().items:
		for action: Dictionary in skill.actions + skill.windup + skill.release:
			var visuals: Array = [action] + action.get("on_hit", [])
			for visual: Dictionary in visuals:
				if not visual.has("effect"): continue
				var item := Library.find(visual.effect)
				var profile := Sizing.profile(item)
				var metric := float(profile.metric)
				if metric <= 0 or profile.role == "screen": continue
				var size := Sizing.factor(item, float(visual.get("scale", 1.0))) * metric / 18.0
				check(size >= float(profile.min_units) - .001 and size <= float(profile.max_units) + .001, "Skill bypassed calibrated scale: " + str(skill.id))
	world.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_SCALE_TEST: ", Library.catalog().items.size(), " profiles; failures=", failures)
	quit(0 if failures.is_empty() else 1)
