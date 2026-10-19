extends Node
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.maintenance/balance-v1/screenshots")
	get_viewport().get_texture().get_image().save_png("res://.maintenance/balance-v1/screenshots/" + name + ".png")

func click(button: Button) -> void:
	await get_tree().process_frame
	var point := button.get_global_transform() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func _run() -> void:
	RunManager.selected_map = {}
	RunManager.start_new_run(load("res://data/run/run_start_data.tres"))
	RunManager.starting_reward_pending = true
	var game: Node = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var picker := game.find_child("StartingRelicChoice", true, false) as Control
	check(picker != null and picker.visible, "新征途打开开局遗物三选一")
	await shot("starting-relic-choice")
	var options: Array[Node] = picker.find_children("*", "Button", true, false)
	check(options.size() == 4 and not options.back().visible, "三件固定遗物，必须选择后开始")
	await click(options[0])
	check(RunManager.relics.size() == 1 and RunManager.potions.size() == 1 and not RunManager.starting_reward_pending, "真实鼠标领取遗物与普通药水")
	var fire := load("res://data/potions/fire.tres") as PotionDefinition
	RunManager.add_potion(fire)
	RunManager.add_potion(fire)
	var incoming := load("res://data/potions/lightning.tres") as PotionDefinition
	RunManager.add_potion(incoming)
	await get_tree().process_frame
	await get_tree().process_frame
	var overflow: CanvasLayer = RunManager.potion_overflow_panel
	check(is_instance_valid(overflow) and get_tree().paused and RunManager.potions.size() == 3, "满格弹窗暂停游戏并保留三瓶")
	await shot("potion-belt-replace")
	await click(overflow.column.get_child(2))
	check(RunManager.potions[0].id == incoming.id and RunManager.pending_potions.is_empty() and not get_tree().paused, "真实鼠标替换并恢复游戏")
	RunManager.add_potion(fire)
	await get_tree().process_frame
	await get_tree().process_frame
	overflow = RunManager.potion_overflow_panel
	await click(overflow.column.get_child(overflow.column.get_child_count()-1))
	check(RunManager.potions[0].id == incoming.id and RunManager.pending_potions.is_empty(), "真实鼠标放弃新瓶不覆盖原瓶")
	game.queue_free()
	await get_tree().process_frame
	print("BALANCE_UI_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
