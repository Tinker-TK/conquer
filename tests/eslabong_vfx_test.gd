extends SceneTree

const Library = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var items: Array = Library.catalog().items
	var ids: Dictionary = {}
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effect/eslabong_vfx/source_manifest.json"))
	for path: String in manifest.files:
		if path.ends_with(".gd"):
			var script := load("res://assets/effect/eslabong_vfx/source/" + path) as Script
			if script == null or not script.can_instantiate():
				failures.append("Cannot compile " + path)
	for item: Dictionary in items:
		checks += 1
		if ids.has(item.id):
			failures.append("Duplicate ID " + str(item.id))
		ids[item.id] = true
		var effect := Library.spawn_item(stage, item, Vector2(300, 300))
		if effect == null:
			failures.append("Cannot instantiate " + str(item.path))
		else:
			_validate_scripts(effect, str(item.id))
		await process_frame
		await process_frame
		if effect != null and is_instance_valid(effect):
			effect.queue_free()
		await process_frame
	await create_timer(2.0).timeout
	stage.queue_free()
	await process_frame
	print("ESLABONG_VFX_TEST: ", checks, " items; failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _validate_scripts(node: Node, effect_id: String) -> void:
	var script := node.get_script() as Script
	if script != null and not script.can_instantiate():
		failures.append("Invalid script for " + effect_id + ": " + script.resource_path)
	for child in node.get_children():
		_validate_scripts(child, effect_id)
