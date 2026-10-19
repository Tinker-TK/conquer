extends SceneTree

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Pool = preload("res://assets/effect/eslabong_vfx/runtime/pool.gd")
const Cell = preload("res://assets/effect/eslabong_vfx/demo/preview_cell.gd")
var failures: Array[String] = []
var ready_records: Array[Dictionary] = []
var checks := 0

func _initialize() -> void:
	node_added.connect(_watch_ready)
	call_deferred("_run")

func _watch_ready(node: Node) -> void:
	if node is Node2D and not node.scene_file_path.is_empty():
		node.ready.connect(func() -> void:
			ready_records.append({"file": node.scene_file_path.get_file(), "position": node.global_position})
		, CONNECT_ONE_SHOT)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var world := Node2D.new()
	world.position = Vector2(430, 260)
	root.add_child(world)
	current_scene = world
	var at := Vector2(135, -10)
	for zoom: float in [1.0, 2.0, 3.0]:
		world.scale = Vector2.ONE * zoom
		world.rotation = .2
		for ability_id: String in ["infernus", "infernusblue", "apocalypse"]:
			ready_records.clear()
			var body := world.to_global(at)
			var ground := world.to_global(at + Vector2(0, 10))
			var holder := Library.spawn(world, "InfernusImpactVFX", at, {"ground_position": ground, "properties": {"ability_vfx_id": StringName(ability_id)}})
			var burst_seen := false
			var puff_seen := false
			for record in ready_records:
				if record.file in ["InfernusBurstSpriteVFX.tscn", "InfernusPuffVFX.tscn"]:
					check(Vector2(record.position).distance_to(body) < .01, "Detached explosion component in " + ability_id + ": " + str(record.file))
					burst_seen = burst_seen or record.file == "InfernusBurstSpriteVFX.tscn"
					puff_seen = puff_seen or record.file == "InfernusPuffVFX.tscn"
				if record.file == "InfernusGroundDecal.tscn":
					check(Vector2(record.position).distance_to(ground) < .01, "Scorch decal is not at target feet")
			check(burst_seen and puff_seen, "Infernus explosion lost a visual layer")
			holder.queue_free()
			await process_frame
		# Other multipart bursts must initialize their decals at the same feet.
		for effect_name: String in ["IceBombImpactVFX", "LightningBombImpactVFX", "HammerOfHeavenImpactVFX", "MegaMeteorImpactVFX", "FireballImpactVFX"]:
			ready_records.clear()
			var ground := world.to_global(at + Vector2(0, 10))
			var holder := Library.spawn(world, effect_name, at, {"ground_position": ground})
			await create_timer(.06).timeout
			for record in ready_records:
				if "Decal" in str(record.file):
					check(Vector2(record.position).distance_to(ground) < .01, "Decal initialized away from impact: " + effect_name)
			holder.queue_free()
			await process_frame
	# Offset/non-uniform hosts must not add their transform a second time.
	world.rotation = -.35
	world.scale = Vector2(2.1, 1.4)
	var owner := Node2D.new()
	world.add_child(owner)
	var fragment := Node2D.new()
	var point := Vector2(800, 320)
	Pool.attach_for(owner, fragment, point, world)
	check(fragment.global_position.distance_to(point) < .01, "Shared visual attachment applied the parent transform twice")
	fragment.queue_free()
	owner.queue_free()
	# Check every distinct contact recipe, not only the named Infernus examples.
	var seen := {}
	for skill: Dictionary in Skills.catalog().items:
		for action: Dictionary in skill.actions:
			for entry: Dictionary in action.get("on_hit", []):
				var item := Library.find(str(entry.effect))
				if str(Library.UnitScale.profile(item).role) not in ["impact", "heavy_impact", "large_area"]: continue
				var key := JSON.stringify(entry)
				if seen.has(key): continue
				seen[key] = true
				var contact := Skills.Player.new()
				world.add_child(contact)
				contact.destination = at
				contact._options = {"ground_offset": Vector2(0, 10)}
				var hit := entry.duplicate(true)
				hit.erase("delay")
				contact._contact({"on_hit": [hit]}, at)
				for child in contact.get_children():
					if child.has_meta("effect_id"):
						check(child.global_position.distance_to(world.to_global(at + Vector2(0, float(hit.get("offset_y", 0))))) < .01, "Contact effect is not centered on unit: " + str(skill.id))
				contact.queue_free()
				await process_frame
	world.queue_free()
	await process_frame
	var cell := Cell.new()
	cell.size = Vector2(650, 360)
	root.add_child(cell)
	await process_frame
	cell.looping = false
	cell.set_item(Library.find("Projectile_Infernus"))
	check(is_instance_valid(cell.sequence) and cell.sequence._flights.size() == 1, "Raw projectile is not target-driven")
	cell.sequence.set_process(false)
	cell.sequence._process(.8)
	check(cell.sequence.hit_count == 1, "Raw projectile failed to hit the unit")
	for child in cell.sequence.get_children():
		if child.has_meta("effect_id"):
			check(child.global_position.distance_to(cell.world.to_global(cell.target.body_position())) < .01, "Raw projectile exploded past the target")
	cell.queue_free()
	await process_frame
	await create_timer(2).timeout
	print("ESLABONG_IMPACT_ALIGNMENT_TEST: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
