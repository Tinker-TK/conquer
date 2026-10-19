extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	RunManager.start_new_run(RunStartData.new())
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	var unit: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	if "--missing-sprite" in OS.get_cmdline_user_args():
		unit.get_node("AnimatedSprite2D").free()
	else:
		unit.unit_data = null
	battle.get_node("Entities/TeamA").add_child(unit)
	print("UNIT_REJECTION_PROBE: rejected=%s; registered=%s; alive=%s" % [
		unit.is_initialization_rejected(), battle.card_runtime.states.has(unit.get_instance_id()), unit.is_alive()])
	for frame in 8:
		await get_tree().process_frame
	print("UNIT_REJECTION_CLEANUP: freed=", not is_instance_valid(unit))
	get_tree().quit(1)
