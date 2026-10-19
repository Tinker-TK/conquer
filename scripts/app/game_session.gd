# 这玩意儿是干嘛的（核心逻辑）：本局游戏的外壳，保留顶部栏，用漫画幕布衔接地图、战斗和主菜单。
# 数据是咋流动的（数据流向）：地图关卡名 → 顶部标题去掉重复章节前缀；幕布合拢 → 配置战斗 → 结算后合拢并插旗 → 展开地图。
# 为啥这么写（选型决策）：战斗只在真正进入/结束时创建或销毁；查看地图仍保留手牌与单位。
# 性能咋样（复杂度）：只在切换时处理节点；同时只保留一场战斗和一张地图，加载层全局只建一份。
extends Node

const FixedMapConfig = preload("res://scripts/map/fixed_map_config.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const CompletionPanel = preload("res://scripts/ui/run_completion_panel.gd")
var pause_menu: CanvasLayer
var completion_panel: CanvasLayer
var saving_exit := false

@onready var content_root: Node = $ContentRoot
@onready var map_layer: CanvasLayer = $MapLayer
@onready var map_view: Control = $MapLayer/Map
@onready var map_button: Button = $HUDLayer/RunHUD/TopButtons/MapButton
@onready var deck_button: Button = $HUDLayer/RunHUD/TopButtons/CardButton
@onready var deck_view: Control = $DeckLayer/DeckView
var deck_open := false
var paused_before_deck := false

var current_battle: Node
var inspecting_map := false
var event_preview := false
var paused_before_map := false


# 作用：Godot 在进入本局时连接地图与顶部按钮；没有参数，没有返回值。
func _ready() -> void:
	completion_panel = CompletionPanel.new()
	add_child(completion_panel)
	completion_panel.retry_requested.connect(_retry_next_act)
	completion_panel.menu_requested.connect(_on_completion_menu)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	$HUDLayer/RunHUD/TopButtons/Setting.pressed.connect(_on_settings_pressed)
	pause_menu.save_exit_requested.connect(_on_save_exit)
	pause_menu.standalone_requested.connect(_open_standalone)
	GameAudio.set_context(self)
	SceneTransition.finished.connect(_on_save_transition_finished)
	map_view.battle_requested.connect(_on_battle_requested)
	map_button.pressed.connect(_on_map_pressed)
	map_view.set_view_only(false)
	map_button.tooltip_text = "战斗或事件中点击可查看地图，再次点击返回"
	deck_button.pressed.connect(_on_deck_pressed)
	deck_view.close_requested.connect(_close_deck)
	RunManager.stats_changed.connect(_refresh_run_hud)
	RunManager.progress_changed.connect(_refresh_run_hud)
	_refresh_run_hud()
	RunManager.capture_location_checkpoint()
	if RunManager.starting_reward_pending:
		_offer_starting_relic.call_deferred()
	if RunManager.chapter_cleared:
		_show_act_completion()
	if GameSettings.resume_settings_pending:
		GameSettings.resume_settings_pending = false
		_open_startup_settings.call_deferred()


func _offer_starting_relic() -> void:
	if SceneTransition.busy:
		await SceneTransition.finished
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var picker := preload("res://scripts/ui/relic_choice_panel.gd").new()
	picker.name = "StartingRelicChoice"
	layer.add_child(picker)
	picker.selected.connect(func(index: int):
		RunManager.claim_starting_relic(index)
		layer.queue_free())
	picker.open(RunManager.starting_relic_options(), false)


func _open_startup_settings() -> void:
	# 等幕布完成再暂停，否则切场会恢复其开始前的暂停状态。
	if SceneTransition.busy:
		await SceneTransition.finished
	pause_menu.open()
	pause_menu.show_settings()


func _open_standalone() -> void:
	RunManager.map_scroll = map_view.scroll_container.scroll_vertical
	GameSettings.open_standalone(true, is_instance_valid(current_battle) or not map_view.pending_id.is_empty())


func _on_settings_pressed() -> void:
	if SceneTransition.busy or get_viewport().gui_is_dragging() or saving_exit or completion_panel.visible:
		return
	if not map_view.locked_node_id.is_empty() and map_view.pending_id.is_empty():
		return
	pause_menu.open(is_instance_valid(current_battle) or not map_view.pending_id.is_empty())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not pause_menu.opened:
		_on_settings_pressed()
		get_viewport().set_input_as_handled()


func _on_save_exit() -> void:
	if saving_exit or SceneTransition.busy:
		return
	saving_exit = true
	RunManager.map_scroll = map_view.scroll_container.scroll_vertical
	var error := RunManager.save_run(is_instance_valid(current_battle) or not map_view.pending_id.is_empty())
	if not error.is_empty():
		pause_menu.message.text = error
		saving_exit = false
		return
	pause_menu.close()
	_close_deck()
	if inspecting_map:
		_set_battle_map_visible(false)
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/ui/main_ui.tscn", "征途已保存 / 返回主菜单")


func _on_save_transition_finished(success: bool) -> void:
	if saving_exit and not success:
		saving_exit = false
		pause_menu.open()
		pause_menu.message.text = SceneTransition.last_error


# 作用：把本局血量、金币和进度填入顶部栏；没有参数，没有返回值。
func _refresh_run_hud() -> void:
	$HUDLayer/RunHUD/BisicUI/Hp/Hp.text = "%d/%d" % [RunManager.hp, RunManager.max_hp]
	$HUDLayer/RunHUD/BisicUI/GlodCoin/GlodCoinNumber.text = str(RunManager.gold)
	# 幕编号来自本局进度；地图名称里的章节前缀只在显示时去掉。
	var map_title: String = map_view.map_name
	var prefix := RegEx.new()
	prefix.compile("^第(?:[一二三]|[123])[章幕]\\s*[·:：-]?\\s*")
	map_title = prefix.sub(map_title, "")
	$HUDLayer/RunHUD/BisicUI/ChapterBanner/Charpter.text = (
		"征途通关" if RunManager.run_cleared else "第%d幕-%s" % [RunManager.current_act, "已完成" if RunManager.chapter_cleared else map_title]
	)


# 作用：点击卡组按钮切换查看面板；没有参数，没有返回值。
func _on_deck_pressed() -> void:
	# 幕布期间不能另开暂停面板，否则会覆盖管理器记录的暂停状态。
	if SceneTransition.busy or completion_panel.visible:
		return
	if deck_open:
		_close_deck()
		return
	# 拖牌与画圈进行中暂不打开，避免进入一半的事件被模态界面挡住。
	if get_viewport().gui_is_dragging():
		return
	if not map_view.locked_node_id.is_empty() and map_view.pending_id.is_empty():
		return
	deck_open = true
	paused_before_deck = get_tree().paused
	get_tree().paused = true
	deck_view.open_deck()
	deck_button.text = "返回"


# 作用：关闭卡组并恢复打开前的暂停状态；没有参数，没有返回值。
func _close_deck() -> void:
	if not deck_open:
		return
	deck_open = false
	deck_view.hide()
	# 若从只读地图打开，原本就处于暂停，不能在此恢复战斗。
	get_tree().paused = paused_before_deck
	deck_button.text = "卡组"


# 作用：地图画圈完成后生成战斗；event_id 是关卡编号，没有返回值。
func _on_battle_requested(event_id: String) -> void:
	if SceneTransition.busy or is_instance_valid(current_battle):
		return
	# 当前外壳对应第一幕草原，进入战斗时沿用草原加载色系。
	SceneTransition.play_transition(_enter_battle.bind(event_id), "进入战场 / %s" % event_id, "grassland")


# 作用：幕布合拢后配置并创建战斗；event_id 是关卡编号，返回是否成功，失败时保留地图。
func _enter_battle(event_id: String) -> bool:
	if is_instance_valid(current_battle):
		return false
	# 直接指定的关卡必须存在，不能在拼错文件名时偷偷退回其他战斗。
	var direct_error := FixedMapConfig.level_error(event_id)
	if not direct_error.is_empty():
		map_view.cancel_pending_battle()
		map_view.status_label.text = direct_error
		return false
	# 从地图指定的资源读取参数，不再维护额外的节点绑定。
	var config := resolve_level(event_id)
	if config == null:
		push_error("地图指定的战斗资源无法加载。")
		map_view.cancel_pending_battle()
		return false
	var scene: PackedScene = config.battle_scene
	if scene == null:
		scene = load("res://scenes/battle/battle_scene.tscn") as PackedScene
	if scene == null:
		push_error("战斗场景无法加载，请检查地图指定的关卡资源。")
		map_view.cancel_pending_battle()
		return false

	current_battle = scene.instantiate()
	# 在 add_child 前注入，第一轮就使用本关配置。
	if not current_battle.has_method("configure_level"):
		push_error("关卡场景必须继承 battle_scene，并保留 configure_level 方法。")
		current_battle.free()
		current_battle = null
		map_view.cancel_pending_battle()
		return false
	current_battle.configure_level(config)
	var result_panel := current_battle.get_node_or_null("GameOver")
	if result_panel == null or not result_panel.has_signal("continue_requested"):
		push_error("战斗场景需要 GameOver 节点，并使用新的 game_over.gd。")
		current_battle.free()
		current_battle = null
		map_view.cancel_pending_battle()
		return false
	# 延迟处理结算，避免在按钮自己的信号回调里销毁它。
	result_panel.continue_requested.connect(_on_battle_continue, CONNECT_DEFERRED)
	content_root.add_child(current_battle)
	map_view.set_view_only(true)
	map_layer.hide()
	map_button.text = "地图"
	return true


# 作用：读取地图指定的战斗资源；level_id 为关卡文件名，返回配置或空。
func resolve_level(level_id: String) -> BattleLevelConfig:
	var path := FixedMapConfig.level_path(level_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return FixedMapConfig.ConfigCache.resource(path) as BattleLevelConfig


# 作用：点击常驻地图按钮时切换查看/返回；没有参数，没有返回值。
func _on_map_pressed() -> void:
	if SceneTransition.busy or completion_panel.visible:
		return
	if deck_open:
		_close_deck()
	# 拖牌或正在画圈时不切换页面，避免留下未完成的鼠标操作。
	if get_viewport().gui_is_dragging():
		return
	if not map_view.locked_node_id.is_empty() and map_view.pending_id.is_empty():
		return
	if is_instance_valid(current_battle):
		_set_battle_map_visible(not inspecting_map)
		return
	# 普通事件暂时仍在地图自己的面板里；查看时隐藏面板，但不结算事件。
	if not map_view.pending_id.is_empty():
		event_preview = not event_preview
		map_view.set_pending_panel_visible(not event_preview)
		map_view.set_view_only(event_preview)
		map_button.text = "返回" if event_preview else "地图"


# 作用：显示或关闭战斗中的只读地图；show_map 表示是否查看，没有返回值。
func _set_battle_map_visible(show_map: bool) -> void:
	inspecting_map = show_map
	if current_battle.has_method("set_round_damage_visible"):
		current_battle.set_round_damage_visible(not show_map)
	if show_map:
		# 暂停整棵场景树；GameSession 是 Always，ContentRoot 是 Pausable。
		# 因此战斗的计时器、移动、动画停住，地图和顶部按钮仍能操作。
		paused_before_map = get_tree().paused
		get_tree().paused = true
		map_view.set_view_only(true)
		map_layer.show()
	else:
		map_layer.hide()
		get_tree().paused = paused_before_map
	map_button.text = "返回" if show_map else "地图"


# 作用：玩家在战斗结算面板点击继续；won 表示是否胜利，没有返回值。
func _on_battle_continue(won: bool) -> void:
	if SceneTransition.busy or not is_instance_valid(current_battle):
		return
	# 结算离开战斗时先结束查看暂停，再让幕布记录状态；否则可能把“查看地图”的暂停带到下一张地图。
	_close_deck()
	if inspecting_map:
		_set_battle_map_visible(false)
	get_tree().paused = false
	if won:
		var title := "战斗胜利 / 继续征途"
		if RunManager.pending_battle_id in RunManager.map_terminal_ids:
			title = "征途通关" if RunManager.current_act == RunManager.active_act_maps.size() else "第%d幕完成 / 进入第%d幕" % [RunManager.current_act, RunManager.current_act + 1]
		SceneTransition.play_transition(_return_to_map, title, "grassland")
	else:
		SceneTransition.change_scene("res://scenes/ui/main_ui.tscn", "返回主菜单 / 再整旗鼓")


# 作用：胜利幕布合拢后清理战斗并解锁路线；没有参数，没有返回值。
func _return_to_map() -> void:
	if not is_instance_valid(current_battle):
		return
	_close_deck()
	if inspecting_map:
		_set_battle_map_visible(false)
	# 先移出树，再排队释放，防止旧战斗与新战斗同时响应全局信号。
	content_root.remove_child(current_battle)
	current_battle.queue_free()
	current_battle = null
	# 真正胜利才插旗；只查看地图绝不会走到这里。
	RunManager.complete_battle()
	if RunManager.chapter_cleared and not RunManager.run_cleared:
		_advance_to_next_act()
	else:
		map_view.resume_after_battle()
		if RunManager.run_cleared:
			_show_act_completion()
	map_layer.show()
	map_button.text = "地图"
	RunManager.capture_location_checkpoint()

# 在胜利奖励领取完后切换下一幕；旧地图移出树，重用整局资源与 HUD。
func _advance_to_next_act() -> bool:
	var error := RunManager.advance_act()
	if not error.is_empty():
		map_view.resume_after_battle()
		_show_act_completion(error)
		return false
	completion_panel.hide()
	var old_map := map_view
	map_layer.remove_child(old_map)
	old_map.queue_free()
	map_view = load("res://scenes/map/map.tscn").instantiate()
	map_view.name = "Map"
	map_layer.add_child(map_view)
	map_view.battle_requested.connect(_on_battle_requested)
	map_view.set_view_only(false)
	event_preview = false
	map_layer.show()
	map_button.text = "地图"
	_refresh_run_hud()
	RunManager.capture_location_checkpoint()
	return true

func _show_act_completion(error: String = "") -> void:
	if RunManager.run_cleared:
		var detail := "第一幕 → 第二幕 → 第三幕\n三幕全部完成，征途胜利！" if RunManager.active_act_maps.size() == 3 else "当前路线已完成，征途胜利！"
		completion_panel.open_summary("征途通关！", detail, true)
	else:
		var detail := error if not error.is_empty() else "第%d幕已完成，继续进入第%d幕。" % [RunManager.current_act, RunManager.current_act + 1]
		completion_panel.open_summary("第%d幕完成" % RunManager.current_act, detail, false)

func _retry_next_act() -> void:
	if SceneTransition.busy or RunManager.run_cleared or not RunManager.chapter_cleared:
		return
	SceneTransition.play_transition(_advance_to_next_act, "进入第%d幕" % (RunManager.current_act + 1), "grassland")

func _on_completion_menu(save_current: bool) -> void:
	if SceneTransition.busy:
		return
	if save_current:
		var error := RunManager.save_run()
		if not error.is_empty():
			completion_panel.description.text = error
			return
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/ui/main_ui.tscn", "返回主菜单")


# 作用：Godot 在外壳退出场景树时解除自己的查看暂停；没有参数，没有返回值。
func _exit_tree() -> void:
	BattleSpeed.reset()
	if deck_open:
		get_tree().paused = paused_before_deck
	if inspecting_map:
		get_tree().paused = paused_before_map
