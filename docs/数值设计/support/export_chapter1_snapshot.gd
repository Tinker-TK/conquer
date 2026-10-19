extends SceneTree
var result: Dictionary = {"date": "2026-10-09", "units": [], "skills": [], "cards": [], "relics": [], "potions": [], "levels": []}
func _initialize() -> void:
	run.call_deferred()
func fields(r: Resource) -> Dictionary:
	var o: Dictionary = {"path": r.resource_path, "script_path": r.get_script().resource_path if r.get_script() != null else ""}
	for p in r.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			var v: Variant = r.get(p.name)
			if v is Resource:
				o[p.name] = v.resource_path
			elif v is Array:
				var a: Array = []
				for x in v:
					if x is Resource:
						a.append(fields(x) if x.resource_path.contains("::") else x.resource_path)
					else:
						a.append(x)
				o[p.name] = a
			elif v == null or v is String or v is StringName or v is int or v is float or v is bool or v is Dictionary:
				o[p.name] = v
	return o
func unit_snapshot(u: Node) -> Dictionary:
	var o: Dictionary = {"name": u.name, "position": [u.position.x, u.position.y], "unit": fields(u.unit_data), "growth": u.get_meta("wave_cycle_effects", {})}
	var sprite = u.get_node_or_null("AnimatedSprite2D")
	o.animations = {}
	if sprite != null and sprite.sprite_frames != null:
		for a in sprite.sprite_frames.get_animation_names():
			var duration: float = 0.0
			for i in sprite.sprite_frames.get_frame_count(a):
				duration += sprite.sprite_frames.get_frame_duration(a, i) / sprite.sprite_frames.get_animation_speed(a)
			o.animations[a] = {"duration": duration, "frames": sprite.sprite_frames.get_frame_count(a), "loop": sprite.sprite_frames.get_animation_loop(a)}
	return o
func run() -> void:
	await process_frame
	for category in ["units", "skills", "cards", "relics", "potions", "levels"]:
		for filename in DirAccess.get_files_at("res://data/" + category):
			if not filename.ends_with(".tres"):
				continue
			var r = load("res://data/" + category + "/" + filename)
			var o = fields(r)
			if category == "levels":
				o.waves = []
				for wave in r.waves:
					var w: Dictionary = {"units": []}
					if wave != null:
						var scene = wave.instantiate()
						for unit in scene.get_children():
							if unit.get("unit_data") != null:
								w.units.append(unit_snapshot(unit))
						scene.free()
					o.waves.append(w)
			result[category].append(o)
	result.unit_scenes = []
	for filename in DirAccess.get_files_at("res://scenes/units"):
		if filename.ends_with(".tscn"):
			var scene = load("res://scenes/units/" + filename).instantiate()
			if scene.get("unit_data") != null:
				var o = unit_snapshot(scene)
				o.scene_path = "res://scenes/units/" + filename
				result.unit_scenes.append(o)
			scene.free()
	result.run_start = fields(load("res://data/run/run_start_data.tres"))
	var manager = root.get_node("RunManager")
	result.run_effective = {"hp": manager.hp, "max_hp": manager.max_hp, "gold": manager.gold, "relic_count": manager.relics.size(), "potions": manager.potions.size()}
	var f = FileAccess.open("res://docs/数值设计/support/chapter1_runtime_snapshot.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("NUMERIC_SNAPSHOT units=", result.units.size(), " skills=", result.skills.size(), " cards=", result.cards.size(), " levels=", result.levels.size(), " run=", result.run_effective)
	quit()

