# 这玩意儿是干嘛的（核心逻辑）：
# 保存这一局的血量、金币、卡牌、遗物、药水和地图配置、进度，切换战斗时不会丢失。
#
# 数据是咋流动的（数据流向）：
# 主菜单导入路线 → 开始游戏冻结本局配置并清空进度 → 地图记录进入哪个战斗 →
# 战斗胜利记录完成 → 返回地图恢复插旗和路线；实际抽牌持续累计遗物进度。
#
# 为啥这么写（选型决策）：
# 自动加载节点不会随着普通场景切换被删除，
# 适合保管跨场景数据，不保存旧地图节点引用。
#
# 性能咋样（复杂度）：
# 只在开始游戏、进入战斗和完成地点时更新少量数据。

extends Node

signal stats_changed
signal deck_changed
signal progress_changed
signal items_changed

const SHOP_SESSION = preload("res://scripts/shop/shop_session.gd")
var shop_visits: Dictionary = {}
var shop_removal_count := 0
var shop_error := ""

func begin_shop(node_id: String, catalog_path: String = "res://data/shops/caravan.json") -> RefCounted:
	if shop_visits.has(node_id):
		return shop_visits[node_id]
	var result: Dictionary = SHOP_SESSION.CATALOG.read_catalog(catalog_path)
	shop_error = str(result.get("error", ""))
	if not shop_error.is_empty():
		return null
	var visit := SHOP_SESSION.new()
	var room: Dictionary = route_location(node_id)
	visit.initialize(self, node_id, result.data, int(room.get("room_seed", 0)))
	shop_visits[node_id] = visit
	return visit

# 所有遗物和未使用药水都随本局保留，只有开新局才清空。
var relics: Array[RelicDefinition] = []
var potions: Array[PotionDefinition] = []
var relic_draw_counts: Dictionary = {}
var base_defence: int = 0
var bonus_energy_max: int = 0
var item_battle: Node
var relic_battle: Node
var discovered_relics: Dictionary = {}
var potion_use_counts: Dictionary = {}
var _triggering_fairy := false
var potion_capacity := 3
var pending_potions: Array[PotionDefinition] = []
var potion_overflow_panel: CanvasLayer
var starting_reward_pending := false


func _show_potion_overflow() -> void:
	if pending_potions.is_empty() or is_instance_valid(potion_overflow_panel):
		return
	potion_overflow_panel = preload("res://scripts/ui/potion_overflow_panel.gd").new()
	add_child(potion_overflow_panel)
	potion_overflow_panel.open(self)


## replacement -1 表示放弃新瓶；旧瓶只在玩家明确选择时移除。
func resolve_potion_overflow(replacement: int) -> bool:
	if pending_potions.is_empty() or replacement < -1 or replacement >= potions.size():
		return false
	var incoming := pending_potions.pop_front() as PotionDefinition
	if replacement >= 0:
		potions[replacement] = incoming
	items_changed.emit()
	return true


func discard_potion(potion: PotionDefinition) -> bool:
	if not potions.has(potion):
		return false
	if is_instance_valid(item_battle):
		if item_battle.aiming_potion == potion:
			item_battle._cancel_aim()
		elif item_battle.potion == potion and not item_battle.committed:
			item_battle.clear_effect()
	potions.erase(potion)
	items_changed.emit()
	return true


func expand_potion_belt(slots: int = 1) -> void:
	potion_capacity = clampi(potion_capacity + maxi(0, slots), 3, 5)
	items_changed.emit()


func starting_relic_options() -> Array[Resource]:
	var result: Array[Resource] = []
	for name in ["scout_horn", "war_banner", "tactical_map"]:
		result.append(load("res://data/relics/" + name + ".tres"))
	return result


func claim_starting_relic(index: int) -> bool:
	var options := starting_relic_options()
	if not starting_reward_pending or index < 0 or index >= options.size():
		return false
	if not add_relic(options[index]):
		return false
	starting_reward_pending = false
	var pool := preload("res://scripts/items/potion_catalog.gd").all_potions().filter(func(p: PotionDefinition): return p.rarity == PotionDefinition.Rarity.COMMON and p.min_act <= 1)
	if not pool.is_empty():
		add_potion(pool.pick_random())
	capture_location_checkpoint()
	return true


# 作用：奖励一件遗物；relic 是配置，返回是否首次获得。
func add_relic(relic: RelicDefinition) -> bool:
	if relic == null or relic.id == &"":
		return false
	# 主堡移除后旧城防遗物没有对象可保护，拒绝获得而不改变精确的回合扣血公式。
	if relic.kind == RelicDefinition.Kind.BASE_DEFENCE:
		return false
	for owned in relics:
		if owned.id == relic.id:
			return false
	relics.append(relic.duplicate(true))
	discovered_relics[String(relic.id)] = true
	var collection := ConfigFile.new()
	collection.set_value("collection", "relics", discovered_relics)
	collection.save("user://relic_collection.cfg")
	if preload("res://scripts/items/relic_catalog.gd").has_relic(relics, &"relic_hunter"):
		hp += 10
		var bus := get_node_or_null("/root/SignalBus")
		if bus != null:
			bus.relic_triggered.emit(&"relic_hunter", "遗物猎人")
	if relic.kind == RelicDefinition.Kind.BASE_HEALTH:
		max_hp += relic.amount
		hp += relic.amount
	elif relic.kind == RelicDefinition.Kind.MAX_ENERGY:
		bonus_energy_max += relic.amount
		stats_changed.emit()
	items_changed.emit()
	return true


func has_relic(id: StringName) -> bool:
	return preload("res://scripts/items/relic_catalog.gd").has_relic(relics, id)


# 作用：奖励独立药水；返回是否成功，同种可多瓶，限量药水遵守本局数量限制。
func add_potion(potion: PotionDefinition) -> bool:
	if potion != null and can_acquire_potion(potion):
		if potions.size() < potion_capacity:
			potions.append(potion.duplicate(true))
		else:
			pending_potions.append(potion.duplicate(true))
			_show_potion_overflow.call_deferred()
		items_changed.emit()
		return true
	return false


func can_acquire_potion(potion: PotionDefinition) -> bool:
	if potion == null:
		return false
	if potion.max_per_run <= 0:
		return true
	var total := int(potion_use_counts.get(potion.id, 0))
	for owned in potions + pending_potions:
		if owned.id == potion.id:
			total += 1
	return total < potion.max_per_run


func is_boss_battle() -> bool:
	return int(route_location(pending_battle_id).get("type", -1)) == 3


func is_elite_battle() -> bool:
	return int(route_location(pending_battle_id).get("type", -1)) == 6


# 作用：首次合法施放消耗指定瓶；potion 是背包中的实例，返回是否成功。
func consume_potion(potion: PotionDefinition) -> bool:
	if not potions.has(potion):
		return false
	potions.erase(potion)
	potion_use_counts[potion.id] = int(potion_use_counts.get(potion.id, 0)) + 1
	items_changed.emit()
	return true


# 作用：统计真实抽到的张数；count 为实际抽牌数，返回这次应增加的能量。
func record_draws(count: int) -> int:
	var energy := 0
	for relic in relics:
		if relic.kind != RelicDefinition.Kind.DRAW_ENERGY:
			continue
		var total: int = int(relic_draw_counts.get(relic.id, 0)) + maxi(count, 0)
		var threshold := maxi(relic.draw_threshold, 1)
		@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
		energy += int(total / threshold) * relic.amount
		relic_draw_counts[relic.id] = total % threshold
	items_changed.emit()
	return energy

const REQUIRED_LOCATIONS := 10
const START_DATA_PATH := "res://data/run/run_start_data.tres"
const FixedMapConfig = preload("res://scripts/map/fixed_map_config.gd")
const IMPORTED_MAP_PATH := "user://imported_fixed_map.json"
const ROUTE_RULES = preload("res://scripts/map/route_generation_config.gd")
const MAP_GENERATOR = preload("res://scripts/map/procedural_map_generator.gd")
const UNKNOWN_ROOMS = preload("res://scripts/map/unknown_room_resolver.gd")
var generation_config_path := ROUTE_RULES.PATH
var map_seed := ""
var map_generator_version := 0
var map_config_version := 0
var map_difficulty := ""
var resolved_rooms: Dictionary = {}
var unknown_room_odds: Dictionary = {}

# selected_map 是下局选择；active_map 是本局副本，避免战斗返回时读到另一份路线。
var selected_map: Dictionary = {}
var active_map: Dictionary = {}
var selected_act_maps: Array[Dictionary] = []
var active_act_maps: Array[Dictionary] = []
var current_act := 1
var run_cleared := false
var map_load_error := ""
var map_terminal_ids: Array[String] = []
# 正式路线在项目内随发行打包；仅路径可由隔离回归替换。
var project_map_paths: Array[String] = FixedMapConfig.game_map_paths()
var project_map_path: String:
	get: return project_map_paths[0]
	set(value): project_map_paths[0] = value

# 修改运行中的数值会自动通知 HUD，不需要每帧查一次。
var max_hp: int = RunStartData.DEFAULT_MAX_HP:
	set(value):
		max_hp = maxi(1, value)
		hp = mini(hp, max_hp)
		stats_changed.emit()
var hp: int = RunStartData.DEFAULT_MAX_HP:
	set(value):
		if value <= 0 and hp > 0 and not _triggering_fairy:
			for potion in potions:
				if potion.target_mode != PotionDefinition.TargetMode.PASSIVE or (potion.max_per_run > 0 and int(potion_use_counts.get(potion.id, 0)) >= potion.max_per_run):
					continue
				for effect in potion.effects:
					if effect.kind == PotionEffect.Kind.FAIRY:
						_triggering_fairy = true
						consume_potion(potion)
						value = maxi(1, ceili(max_hp * effect.amount / 100.0))
						_triggering_fairy = false
						break
				if value > 0:
					break
		hp = clampi(value, 0, max_hp)
		stats_changed.emit()
var gold: int = 99:
	set(value):
		gold = maxi(0, value)
		stats_changed.emit()

# 这是“拥有的全部牌”，不是抽牌堆。上场、弃牌都不删除这里的牌。
var deck: Array[CardInstance] = []
var chapter_cleared := false


# 主菜单自行读取路线，点击开始才建新局；F6 和脚本入口保留独立初始化。
func _ready() -> void:
	var collection := ConfigFile.new()
	if collection.load("user://relic_collection.cfg") == OK:
		discovered_relics = collection.get_value("collection", "relics", {})
	var arguments := OS.get_cmdline_args()
	var startup_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	for argument in arguments:
		if argument.ends_with(".tscn"):
			startup_scene = argument
	if startup_scene == "res://scenes/ui/main_ui.tscn" and not "--script" in arguments and not "-s" in arguments:
		return
	reload_map_selection()
	start_new_run()

# 作用：读取地图工坊应用的正式路线，兼容旧的玩家导入；不修改进行中的本局和存档。
func reload_map_selection() -> String:
	var revision := FixedMapConfig.ConfigCache.refresh()
	# 工坊独立路径和手动导入仍可运行固定路线；正式征途默认从随机规则建局。
	if not generation_config_path.is_empty() and project_map_paths == FixedMapConfig.game_map_paths():
		var generated: Dictionary = ROUTE_RULES.read_file(generation_config_path)
		if generated.has("error"):
			map_load_error = str(generated.error)
			return map_load_error
		if generated.data.enabled:
			selected_map = {"mode": "procedural", "rules": generated.data, "encounters": generated.encounters}
			selected_act_maps.clear()
			map_load_error = ""
			return ""
	var maps: Array[Dictionary] = []
	var has_project_map := false
	for index in FixedMapConfig.ACT_COUNT:
		var act_path := project_map_paths[index]
		if not FileAccess.file_exists(act_path):
			maps.append({})
			continue
		has_project_map = true
		var act_result := FixedMapConfig.read_file(act_path, revision)
		if act_result.has("error"):
			map_load_error = "第%d幕路线无法读取：%s\n%s" % [index + 1, act_path, act_result.error]
			return map_load_error
		maps.append(act_result.data)
	if has_project_map:
		if maps[0].is_empty():
			map_load_error = "第一幕尚未配置，请在地图工坊选择“应用到第1幕”并应用路线。"
			return map_load_error
		selected_act_maps = maps
		selected_map = maps[0].duplicate(true)
		map_load_error = ""
		return ""
	var path := IMPORTED_MAP_PATH
	if not FileAccess.file_exists(path):
		selected_map = {}
		selected_act_maps.clear()
		map_load_error = ""
		return ""
	var result := FixedMapConfig.read_file(path, revision)
	if result.has("error"):
		map_load_error = "地图路线无法读取：%s\n%s" % [path, result.error]
		return map_load_error
	selected_map = result.data
	selected_act_maps.clear()
	map_load_error = ""
	return ""

var current_id: String = ""
var completed_ids: Array[String] = []

var pending_battle_id: String = ""
var pending_event_id: String = ""
var pending_battle_rewards: Dictionary = {}
var run_serial := 0

var map_scroll: int = 0
const SAVE_DATA = preload("res://scripts/run/run_save_data.gd")
const SAVE_PATH := "user://saved_run.tres"
const SAVE_KEYS := ["max_hp", "hp", "gold", "active_map", "map_terminal_ids", "current_id", "completed_ids", "chapter_cleared", "map_scroll", "relic_draw_counts", "base_defence", "bonus_energy_max", "shop_removal_count"]
const ACT_SAVE_KEYS := ["active_act_maps", "current_act", "run_cleared"]
const EVENT_SAVE_KEYS := ["event_visits", "seen_events", "completed_events", "event_tag_counts", "event_history", "pending_route_node"]
const MAP_SAVE_KEYS := ["map_seed", "map_generator_version", "map_config_version", "map_difficulty", "resolved_rooms", "unknown_room_odds"]
const EVENT_POOL = preload("res://scripts/events/event_pool.gd")
var event_visits: Dictionary = {}
var seen_events: Array[String] = []
var completed_events: Array[String] = []
var event_tag_counts: Dictionary = {}
var event_history: Array[Dictionary] = []
var pending_route_node := ""
var location_checkpoint: Resource
var save_error := ""


# 每个未完成地点从进入前重开；快照包含独立牌配方和强化，避免领取一半的奖励重复发放。
func capture_location_checkpoint() -> void:
	location_checkpoint = create_save_data()


func create_save_data() -> Resource:
	var data := SAVE_DATA.new()
	data.version = 2
	data.state["potion_use_counts"] = potion_use_counts.duplicate(true)
	data.state["potion_capacity"] = potion_capacity
	data.state["pending_potions"] = pending_potions.duplicate(true)
	data.state["starting_reward_pending"] = starting_reward_pending
	for key in SAVE_KEYS + ACT_SAVE_KEYS + EVENT_SAVE_KEYS + MAP_SAVE_KEYS:
		var value: Variant = get(key)
		data.state[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	for card: CardInstance in deck:
		if not CardInstance.is_player_card_data(card.definition):
			continue
		data.card_definitions.append(card.persistent_definition().duplicate(true))
		var upgrades := card.persistent_upgrade_state()
		upgrades.permanent_buffs = card.permanent_buffs.duplicate(true)
		data.card_states.append(upgrades)
	for relic in relics:
		data.relics.append(relic.duplicate(true))
	for potion in potions:
		data.potions.append(potion.duplicate(true))
	return data


func save_run(restart_location: bool = false) -> String:
	var data: Resource = location_checkpoint if restart_location and location_checkpoint != null else create_save_data()
	var temporary := "user://saved_run.tmp.tres"
	var error := ResourceSaver.save(data, temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, SAVE_PATH)
	save_error = "存档保存失败：" + error_string(error) if error != OK else ""
	return save_error


func has_saved_run() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_saved_run() -> String:
	var data := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if data == null or data.get_script() != SAVE_DATA or data.version not in [1, 2] or data.card_definitions.is_empty() or data.card_definitions.size() != data.card_states.size():
		return "存档无法读取，请检查存档文件。"
	var state: Dictionary = data.state.duplicate(true)
	var saved_capacity: Variant = state.get("potion_capacity", 3)
	if not saved_capacity is int or saved_capacity < 3 or saved_capacity > 5:
		return "存档药水带容量无效。"
	var saved_pending: Variant = state.get("pending_potions", [])
	if not saved_pending is Array or not saved_pending.all(func(p): return p is PotionDefinition and p.id != &""):
		return "存档待选药水无效。"
	if not state.get("starting_reward_pending", false) is bool:
		return "存档开局奖励状态无效。"
	# 路线事件字段为可选扩展，旧存档沿用已有内容。
	for key in EVENT_SAVE_KEYS:
		var fallback: Variant = "" if key == "pending_route_node" else [] if key in ["seen_events", "completed_events", "event_history"] else {}
		if typeof(state.get(key, fallback)) != typeof(fallback):
			return "存档事件字段格式错误：" + key
		state[key] = state.get(key, fallback)
	# 新增元数据可选，旧存档保持原地图；恢复过程中不会调用随机生成器。
	for key in MAP_SAVE_KEYS:
		var fallback: Variant = {} if key in ["resolved_rooms", "unknown_room_odds"] else 0 if key in ["map_generator_version", "map_config_version"] else ""
		if typeof(state.get(key, fallback)) != typeof(fallback):
			return "存档随机地图字段格式错误：" + key
		state[key] = state.get(key, fallback)
	for key in SAVE_KEYS:
		if not state.has(key):
			return "存档缺少征途数据：" + key
		if typeof(state[key]) != typeof(get(key)):
			return "存档数据格式错误：" + key
	# 旧的单幕存档保持原有路线和进度，不把新的项目配置插进旧局。
	if data.version == 1 and not state.has("active_act_maps") and not state.has("current_act") and not state.has("run_cleared"):
		state["active_act_maps"] = [state.get("active_map", {}).duplicate(true)]
		state["current_act"] = 1
		state["run_cleared"] = state.get("chapter_cleared", false)
	for key in ACT_SAVE_KEYS:
		if not state.has(key):
			return "存档缺少征途数据：" + key
		if typeof(state[key]) != typeof(get(key)):
			return "存档数据格式错误：" + key
	if state.active_act_maps.size() not in [1, FixedMapConfig.ACT_COUNT] or state.current_act < 1 or state.current_act > state.active_act_maps.size():
		return "存档幕数或当前幕编号无效。"
	for map in state.active_act_maps:
		if not map is Dictionary:
			return "存档中的幕路线格式错误。"
	for definition in data.card_definitions:
		if definition == null:
			return "存档中的卡牌配置损坏。"
	# 完成验证后才替换当前局；不调用 add_relic，避免生命和能量加成重复累加。
	run_serial += 1
	shop_visits.clear()
	location_checkpoint = null
	for key in SAVE_KEYS + ACT_SAVE_KEYS + EVENT_SAVE_KEYS + MAP_SAVE_KEYS:
		if key in ["map_terminal_ids", "completed_ids", "active_act_maps", "seen_events", "completed_events", "event_history"]:
			get(key).assign(state[key])
		else:
			set(key, state[key])
	relics.assign(data.relics)
	potions.assign(data.potions)
	potion_capacity = clampi(int(state.get("potion_capacity", 3)), 3, 5)
	pending_potions.assign(state.get("pending_potions", []))
	starting_reward_pending = bool(state.get("starting_reward_pending", false))
	_show_potion_overflow.call_deferred()
	potion_use_counts = state.get("potion_use_counts", {}).duplicate(true)
	deck.clear()
	for index in data.card_definitions.size():
		# 兼容曾把敌军奖励成卡牌的旧存档；按原索引读取合法牌状态，保留训练与进度。
		if not CardInstance.is_player_card_data(data.card_definitions[index]):
			continue
		var card := CardInstance.new(data.card_definitions[index])
		for key in ["upgrade_count", "ability_points", "attack_points", "defence_points"]:
			card.set(key, int(data.card_states[index].get(key, 0)))
		card.soldier_specialization = str(data.card_states[index].get("soldier_specialization", ""))
		card.permanent_buffs.assign(data.card_states[index].get("permanent_buffs", []))
		deck.append(card)
	pending_battle_id = ""
	pending_event_id = ""
	pending_battle_rewards = {}
	item_battle = null
	stats_changed.emit()
	deck_changed.emit()
	items_changed.emit()
	progress_changed.emit()
	return ""


# 作用：开始全新的一局，清空上一次冒险的进度。
# 参数 configuration：初始配置；seed_text/difficulty 可覆盖随机路线默认种子与难度。
# 返回值：空串表示成功；失败返回原因，并保留原有征途。
func start_new_run(configuration: RunStartData = null, seed_text: String = "", difficulty: String = "") -> String:
	# 先完整生成与验证，再替换本局，配置有误时保留现有征途。
	var maps: Array = selected_act_maps if not selected_act_maps.is_empty() and selected_act_maps[0] == selected_map else [selected_map]
	var next_seed := ""
	var next_difficulty := ""
	var next_config_version := 0
	var next_generator_version := 0
	if selected_map.get("mode", "") == "procedural":
		var rules: Dictionary = selected_map.rules
		next_seed = (seed_text if not seed_text.strip_edges().is_empty() else str(rules.get("seed", ""))).strip_edges().to_upper()
		if next_seed.length() > 64:
			return "地图种子最多 64 字。"
		if next_seed.is_empty():
			var seed_rng := RandomNumberGenerator.new()
			seed_rng.randomize()
			next_seed = "%08X%08X" % [seed_rng.randi(), seed_rng.randi()]
		next_difficulty = difficulty if not difficulty.is_empty() else str(rules.difficulty)
		if not rules.difficulties.has(next_difficulty):
			return "未配置的地图难度：" + next_difficulty
		maps = []
		for act in range(1, FixedMapConfig.ACT_COUNT + 1):
			var generated: Dictionary = MAP_GENERATOR.new().generate(next_seed, act, rules, next_difficulty, selected_map.encounters)
			var issue := FixedMapConfig.validate(generated)
			if not issue.is_empty():
				return "第%d幕随机路线生成失败：%s" % [act, issue]
			maps.append(generated)
		next_config_version = int(rules.config_version)
		next_generator_version = MAP_GENERATOR.VERSION
	elif selected_map.get("generation") is Dictionary:
		# 工坊导出的随机地图作为固定路线试玩时，仍保留它原本的生成来源。
		var metadata: Dictionary = selected_map.generation
		next_seed = str(metadata.get("seed", ""))
		next_difficulty = str(metadata.get("difficulty", ""))
		next_config_version = int(metadata.get("config_version", 0))
		next_generator_version = int(metadata.get("generator_version", 0))
	map_seed = next_seed
	map_difficulty = next_difficulty
	map_config_version = next_config_version
	map_generator_version = next_generator_version
	resolved_rooms.clear()
	unknown_room_odds.clear()
	pending_route_node = ""
	event_visits.clear()
	seen_events.clear()
	completed_events.clear()
	event_tag_counts.clear()
	event_history.clear()
	run_serial += 1
	location_checkpoint = null
	shop_visits.clear()
	shop_removal_count = 0
	shop_error = ""
	active_act_maps.clear()
	# 手动单路线试玩和旧版导入仍是独立的一幕；正式项目路线固定为三幕。
	for map: Dictionary in maps:
		active_act_maps.append(_snapshot_map(map))
	current_act = 1
	run_cleared = false
	_activate_act_map()
	# 等全局脚本初始化后再读取资源，避免 UnitData 依赖全局枚举时循环预加载。
	var start_data: Resource = configuration if configuration != null else FixedMapConfig.ConfigCache.resource(START_DATA_PATH)
	relics.clear()
	potions.clear()
	pending_potions.clear()
	if is_instance_valid(potion_overflow_panel):
		get_tree().paused = potion_overflow_panel.was_paused
		potion_overflow_panel.queue_free()
		potion_overflow_panel = null
	potion_capacity = 3
	starting_reward_pending = configuration == null
	potion_use_counts.clear()
	relic_draw_counts.clear()
	base_defence = 0
	bonus_energy_max = start_data.bonus_energy_max
	max_hp = start_data.max_hp
	hp = start_data.starting_hp
	gold = start_data.starting_gold
	for relic in start_data.starting_relics:
		add_relic(relic)
	for potion in start_data.starting_potions:
		add_potion(potion)
	items_changed.emit()
	chapter_cleared = false
	# 每局新建具体卡牌，重复的士兵牌也是不同的实例。
	deck.clear()
	for data: Resource in start_data.cards:
		if CardInstance.is_player_card_data(data):
			deck.append(CardInstance.new(data))
		else:
			push_warning("初始牌组跳过敌方单位或无效资源，请使用己方征召牌或效果牌。")
	current_id = ""
	completed_ids.clear()
	pending_battle_id = ""
	pending_event_id = ""
	pending_battle_rewards = {}
	map_scroll = 0
	deck_changed.emit()
	progress_changed.emit()
	return ""

# 冻结每幕的事件与战斗奖励，存档和跨幕不依赖后续编辑器修改。
func _snapshot_map(map: Dictionary) -> Dictionary:
	var snapshot := map.duplicate(true)
	var pools: Dictionary = {}
	for location in snapshot.get("locations", []):
		_snapshot_location(location, pools)
	return snapshot

func _snapshot_location(location: Dictionary, pools: Dictionary) -> void:
	if int(location.type) == 7:
		for option: Dictionary in location.unknown_options.values():
			_snapshot_location(option, pools)
	elif int(location.type) in [0, 3, 6]:
		location.battle_rewards = FixedMapConfig.battle_reward_content(location)
	elif int(location.type) in [1, 2, 4]:
		if not str(location.get("event_pool", "")).is_empty():
			var path := str(location.event_pool)
			if not pools.has(path):
				pools[path] = EVENT_POOL.snapshot(path)
			location.pool_snapshot = pools[path].duplicate(true)
		location.event = FixedMapConfig.event_content(location).duplicate(true)
		location.erase("event_source")

# 查询已揭晓房间不消耗随机数；地图显示、商店和图例共用此结果。
func route_location(node_id: String) -> Dictionary:
	var key := "%d:%s" % [current_act, node_id]
	if resolved_rooms.has(key):
		return resolved_rooms[key]
	for location: Dictionary in active_map.get("locations", []):
		if str(location.id) == node_id:
			return location
	return {}

func resolve_map_location(location: Dictionary) -> Dictionary:
	return UNKNOWN_ROOMS.resolve(location, self) if int(location.type) == 7 else location

# 节点首次进入时固定事件与随机种子；地点检查点也包含抽签结果。
func resolve_route_event(location: Dictionary) -> Dictionary:
	var key := "%d:%s" % [current_act, str(location.id)]
	if event_visits.has(key):
		return event_visits[key].duplicate(true)
	var content: Dictionary
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not str(location.get("event_pool", "")).is_empty():
		var excluded: Array = seen_events
		if location.get("event_scope", "run") == "act":
			excluded = []
			for visit_key in event_visits:
				if str(visit_key).begins_with("%d:" % current_act):
					excluded.append(str(event_visits[visit_key].get("id", "")))
		content = EVENT_POOL.draw(location.get("pool_snapshot", {"entries": []}), int(location.get("event_pool_floor", location.floor)), self, rng, excluded)
	else:
		content = FixedMapConfig.event_content(location).duplicate(true)
		content.id = content.get("id", str(location.get("event_id", "")))
	content._seed = rng.randi()
	content._node_id = str(location.id)
	content._floor = int(location.floor)
	event_visits[key] = content.duplicate(true)
	pending_route_node = str(location.id)
	if int(location.type) == 1:
		var id := str(content.get("id", ""))
		if not seen_events.has(id):
			seen_events.append(id)
		for tag in content.get("tags", []):
			event_tag_counts[tag] = int(event_tag_counts.get(tag, 0)) + 1
	capture_location_checkpoint()
	save_run(true)
	return content

func record_event_choice(content: Dictionary, choice: int, before: Dictionary, elapsed_ms: int) -> void:
	var id := str(content.get("id", ""))
	if not completed_events.has(id):
		completed_events.append(id)
	event_history.append({"event": id, "title": content.get("title", "旅途奇遇"), "act": current_act, "floor": content.get("_floor", 0), "node": content.get("_node_id", ""), "choice": choice, "text": content.choices[choice].text, "leave": content.choices[choice].get("leave", false), "before": before, "after": {"hp": hp, "max_hp": max_hp, "gold": gold, "cards": deck.size()}, "elapsed_ms": elapsed_ms})

func _activate_act_map() -> void:
	active_map = active_act_maps[current_act - 1].duplicate(true)
	map_terminal_ids.clear()
	for location in active_map.get("locations", []):
		if location.next.is_empty():
			map_terminal_ids.append(location.id)

# 只切换幕和路线，不重新开局、不重置玩家资源或永久强化。
func advance_act() -> String:
	if not chapter_cleared or run_cleared or current_act >= active_act_maps.size():
		return "当前幕尚未完成，或征途已经通关。"
	if active_act_maps[current_act].is_empty():
		# 已配置的幕始终使用本局快照；尚未配置的下一幕可在工坊补齐后重试。
		var path := project_map_paths[current_act]
		if not FileAccess.file_exists(path):
			return "第%d幕尚未配置。请在地图工坊应用对应幕的路线后重试。" % (current_act + 1)
		var result := FixedMapConfig.read_file(path)
		if result.has("error"):
			return "第%d幕路线无法读取：%s" % [current_act + 1, result.error]
		active_act_maps[current_act] = _snapshot_map(result.data)
	current_act += 1
	_activate_act_map()
	chapter_cleared = false
	pending_route_node = ""
	current_id = ""
	completed_ids.clear()
	pending_battle_id = ""
	pending_event_id = ""
	pending_battle_rewards = {}
	map_scroll = 0
	shop_visits.clear()
	shop_error = ""
	location_checkpoint = null
	reset_battle_card_costs()
	progress_changed.emit()
	return ""


# 作用：记录玩家即将进入的战斗。
# 参数 node_id：地图地点编号；event_id：战斗内容编号。
# 返回值：没有返回值。
func begin_battle(node_id: String, event_id: String, rewards: Dictionary = {}) -> void:
	pending_battle_id = node_id
	pending_event_id = event_id
	pending_battle_rewards = rewards.duplicate(true)


# 作用：完成一个地点，供普通事件和战斗共同使用。
# 参数 node_id：已经完成的地图地点编号。
# 返回值：没有返回值。
func complete_location(node_id: String) -> void:
	if pending_route_node == node_id:
		pending_route_node = ""
	if node_id.is_empty():
		return

	current_id = node_id
	location_checkpoint = null
	if not completed_ids.has(node_id):
		completed_ids.append(node_id)
	# 自定义路线可能跨层或少于十站，必须完成终点 Boss 才算通关。
	chapter_cleared = map_terminal_ids.has(node_id) if not active_map.is_empty() else completed_ids.size() >= REQUIRED_LOCATIONS
	run_cleared = chapter_cleared and current_act == active_act_maps.size()
	progress_changed.emit()


# 作用：导入并记住下局地图；path 是玩家所选路径，返回空串代表成功，否则返回错误原因。
func import_fixed_map(path: String) -> String:
	var result := FixedMapConfig.read_file(path)
	if result.has("error"):
		return result.error
	# 先写入临时文件再替换，磁盘写入失败不会毁掉之前可用的配置。
	var temporary := IMPORTED_MAP_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法保存导入路线：%s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(result.data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "路线保存失败：%s" % error_string(write_error)
	var rename_error := DirAccess.rename_absolute(temporary, IMPORTED_MAP_PATH)
	if rename_error != OK:
		return "无法替换上次路线：%s" % error_string(rename_error)
	selected_map = result.data
	selected_act_maps.clear()
	map_load_error = ""
	return ""


# 作用：让下局使用原来的十层地图；没有参数，返回空串表示成功，否则返回删除失败原因。
func use_default_map() -> String:
	if FileAccess.file_exists(IMPORTED_MAP_PATH):
		var error := DirAccess.remove_absolute(IMPORTED_MAP_PATH)
		if error != OK:
			return "无法清除上次路线：%s" % error_string(error)
	selected_map = {}
	selected_act_maps.clear()
	map_load_error = ""
	return ""


# 作用：清除本场临时加费并刷新卡组，保留原牌实例、训练和永久强化；没有参数，没有返回值。
func reset_battle_card_costs() -> void:
	var changed := false
	# 热更新或旧会话遗留的怪物牌，在真正创建下一场抽牌堆前清除。
	for index in range(deck.size() - 1, -1, -1):
		if not CardInstance.is_player_card_data(deck[index].definition):
			deck.remove_at(index)
			changed = true
	for card: CardInstance in deck:
		card.reset_battle_modifiers()
		if card.cost_increase != 0:
			card.cost_increase = 0
			changed = true
	if changed:
		deck_changed.emit()


# 作用：奖励一张永久加入本局的牌；data 为单位配置，返回新牌，没有数据时返回空。
func add_card(data: Resource) -> CardInstance:
	if not CardInstance.is_player_card_data(data):
		return null
	var card := CardInstance.new(data)
	deck.append(card)
	deck_changed.emit()
	return card


# 作用：战斗胜利后，完成之前记录的地图地点。
# 参数：没有参数。
# 返回值：没有返回值。
func complete_battle() -> void:
	complete_location(pending_battle_id)
	pending_battle_id = ""
	pending_event_id = ""
	pending_battle_rewards = {}
