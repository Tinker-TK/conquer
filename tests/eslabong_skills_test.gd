extends SceneTree

const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Demo = preload("res://assets/effect/eslabong_vfx/demo/eslabong_vfx_demo.tscn")
var failures: Array[String] = []
var hits: Array[Vector2] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	current_scene = host
	var seen := {}
	for skill: Dictionary in Skills.catalog().items:
		check(not seen.has(skill.id), "Duplicate skill ID: " + str(skill.id))
		seen[skill.id] = true
		for entry: Dictionary in skill.windup + skill.release + skill.actions:
			if entry.has("effect"):
				check(not Library.find(entry.effect).is_empty(), "Missing visual in " + str(skill.id))
			for hit: Dictionary in entry.get("on_hit", []):
				check(not Library.find(hit.effect).is_empty(), "Missing contact visual in " + str(skill.id))
	var stone := Skills.play(host, "rock_throw", Vector2(-120, 25), Vector2(160, 25), {"auto_free": false})
	stone.set_process(false)
	stone.target_hit.connect(func(at: Vector2) -> void: hits.append(at))
	check(stone._flights.is_empty(), "Stone launched before windup")
	stone._process(.4)
	check(stone._flights.size() == 1, "Stone was not emitted from left unit")
	check(hits.is_empty(), "Contact preceded flight")
	stone._process(.15)
	check(stone._flights.size() == 1 and hits.is_empty(), "Stone hit before arrival")
	if not stone._flights.is_empty():
		var flight: Dictionary = stone._flights[0]
		check(flight.holder.position.x > -120 and flight.holder.position.x < 160, "Stone did not travel between units")
		check(flight.holder.position.y < 25, "Stone lost authored arc presentation")
		check(flight.root.get_meta("sequence_driven", false), "Original independent projectile movement still active")
	stone._process(.26)
	check(hits.size() == 1 and hits[0].is_equal_approx(Vector2(160, 25)), "Stone impact did not use target position")
	check(stone._flights.is_empty(), "Projectile remained after impact")
	check(stone.phase == "持续效果", "Stun was not attached after impact")
	stone.clear()
	check(stone.get_child_count() == 0, "Clear retained skill children")
	stone.queue_free()
	await process_frame
	var fire_wave := Skills.play(host, "fire_wave", Vector2(-135, 0), Vector2(135, 0), {"auto_free": false})
	fire_wave.set_process(false)
	fire_wave._process(.61)
	check(fire_wave.hit_count == 0, "Fire wave hit before reaching target")
	fire_wave._process(.5)
	check(fire_wave.hit_count == 1, "Fire wave did not hit once at its endpoint")
	check(fire_wave.phase == "持续效果", "Fire wave did not apply burning after contact")
	check(not fire_wave.skill.actions.any(func(action: Dictionary) -> bool: return action.get("effect") == "scenes_vfx_heattrailvfx"), "Unused refraction export was treated as a fire wave stage")
	fire_wave.clear()
	fire_wave.queue_free()
	await process_frame
	# Exercise every authored combination, including delayed and multishot actions.
	for skill: Dictionary in Skills.catalog().items:
		var player := Skills.Player.new()
		host.add_child(player)
		player.play(skill, Vector2(-135, 0), Vector2(135, 0), {"auto_free": false})
		player.set_process(false)
		for i in 60:
			player._process(.25)
		check(not player.playing, "Skill did not finish: " + str(skill.id))
		player.clear()
		player.queue_free()
		await process_frame
	var demo := Demo.instantiate()
	host.add_child(demo)
	await process_frame
	check(demo.items.size() == Skills.catalog().items.size(), "Demo did not default to skills")
	check(demo.cells.size() == 1 and demo.cells[0].sequence != null, "Demo did not create skill player")
	check(demo.cells[0].character.position.x < demo.cells[0].target.position.x, "Demo endpoints reversed")
	var cell: Control = demo.cells[0]
	for scale_factor: float in [1.0, 2.0, 4.0]:
		cell.set_zoom(scale_factor)
		for unit: Node2D in [cell.character, cell.target]:
			unit.reset()
			var frame_width: int = unit.sprite.texture.get_width() / unit.sprite.hframes
			var frame_image: Image = unit.sprite.texture.get_image().get_region(Rect2i(0, 0, frame_width, unit.sprite.texture.get_height()))
			var boot_row: int = frame_image.get_used_rect().end.y
			var actual_feet: Vector2 = unit.sprite.to_global(unit.sprite.get_rect().position + Vector2(frame_width * .5, boot_row))
			check(actual_feet.distance_to(unit.global_position) < .1, "Unit boots float above ground anchor at zoom " + str(scale_factor))
		check(cell.character.global_position.y == cell.target.global_position.y, "Units do not stand on the same baseline")
	cell.set_zoom(2)
	cell.replay()
	cell.sequence.set_process(false)
	cell.sequence._process(.4)
	check(cell.sequence.source.is_equal_approx(cell.character.body_position()), "Cast effect does not follow caster body")
	check(cell.sequence.destination.is_equal_approx(cell.target.body_position()), "Target endpoint does not follow target body")
	if not cell.sequence._flights.is_empty():
		check(cell.sequence._flights[0].holder.position.is_equal_approx(cell.character.cast_position()), "Projectile did not start at caster's hand")
	else:
		check(false, "Alignment test did not emit the stone")
	cell.replay()
	demo._toggle_pause()
	var paused_time: float = demo.cells[0].sequence.elapsed
	await process_frame
	await process_frame
	check(is_equal_approx(demo.cells[0].sequence.elapsed, paused_time), "Skill advanced while paused")
	demo._toggle_pause()
	demo.search.text = "投石"
	demo._filter()
	check(demo.filtered.size() == 1, "Chinese skill search failed")
	demo.set_catalog_mode(1)
	check(demo.items.size() == Library.catalog().items.size(), "Raw material mode lost original catalog")
	demo.set_catalog_mode(0)
	demo._toggle_gallery()
	check(demo.cells.size() == 9, "Skill gallery did not create nine sequences")
	demo.queue_free()
	host.queue_free()
	await process_frame
	await create_timer(3.0).timeout
	print("ESLABONG_SKILLS_TEST: ", Skills.catalog().items.size(), " skills; failures=", failures)
	quit(0 if failures.is_empty() else 1)
