# 检查缓存命中、同秒文件修改、依赖更新与本局快照隔离。
extends SceneTree

const Cache = preload("res://scripts/run/game_config_cache.gd")
const MapConfig = preload("res://scripts/map/fixed_map_config.gd")
const ROUTE := "user://cache_route_test.json"
var child_path := ""
var parent_path := ""
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _write_route(data: Dictionary) -> void:
	var file := FileAccess.open(ROUTE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _run() -> void:
	# 奖励脚本依赖全局兵种枚举，等待 autoload 注册后再加载。
	var Rewards: Script = load("res://scripts/events/event_rewards.gd")
	var run := root.get_node("RunManager")
	var data := {"schema_version": 1, "mode": "fixed", "name": "缓存路线 A", "floors": 2,
		"starting_ids": ["entry"], "locations": [
			{"id": "entry", "title": "出发", "type": 1, "floor": 1, "event_id": "", "next": ["boss"], "map_pos": {"x": 0.5, "y": 0.9},
				"event": {"description": "测试事件", "choices": [{"text": "领取", "heal": 0, "gold": 11}, {"text": "离开", "heal": 0, "gold": 0}]}},
			{"id": "boss", "title": "终点", "type": 3, "floor": 2, "event_id": "level_001", "next": [], "map_pos": {"x": 0.5, "y": 0.1},
				"battle_rewards": {"gold": 31, "potion_chance": 0.0, "relic_chance": 0.0}}]}
	_write_route(data)
	var first := MapConfig.read_file(ROUTE)
	check(first.has("data"), "有效路线可读取")
	first.data.name = "调用方修改"
	check(MapConfig.read_file(ROUTE).data.name == data.name, "缓存返回独立字典")
	var invalid := data.duplicate(true)
	invalid.schema_version = 2
	_write_route(invalid)
	check(MapConfig.read_file(ROUTE).has("error"), "同秒损坏配置使旧校验结果失效")
	_write_route(data)
	check(MapConfig.read_file(ROUTE).has("data"), "同秒修复后重新校验")
	run.selected_map = data.duplicate(true)
	run.selected_act_maps.clear()
	run.start_new_run()
	data.name = "缓存路线 B"
	data.locations[0].event.choices[0].gold = 77
	_write_route(data)
	run.selected_map = MapConfig.read_file(ROUTE).data
	check(run.active_map.name == "缓存路线 A" and run.active_map.locations[0].event.choices[0].gold == 11, "新选择不修改正在进行的本局")
	run.start_new_run()
	check(run.active_map.name == "缓存路线 B" and run.active_map.locations[0].event.choices[0].gold == 77, "下一局采用更新后的路线")
	# 测试专用配置位于监控目录，不覆盖任何正式文件，结束时删除。
	child_path = "res://data/run/cache_probe_%d.tres" % Time.get_ticks_usec()
	var level_id := "level_cache_probe_%d" % Time.get_ticks_usec()
	parent_path = MapConfig.level_path(level_id)
	var reward := BattleRewardConfig.new()
	reward.gold = 31
	check(ResourceSaver.save(reward, child_path) == OK, "依赖配置可创建")
	var parent := BattleLevelConfig.new()
	parent.victory_rewards = load(child_path)
	parent.waves.assign([load("res://scenes/levels/waves/wave_01.tscn")])
	check(ResourceSaver.save(parent, parent_path) == OK, "包含外部依赖的关卡可创建")
	Cache.refresh()
	var old_level := Cache.resource(parent_path) as BattleLevelConfig
	check(old_level == Cache.resource(parent_path), "未变化的关卡资源复用引用")
	var next_reward := BattleRewardConfig.new()
	next_reward.gold = 93
	check(ResourceSaver.save(next_reward, child_path) == OK, "同秒修改外部依赖")
	Cache.refresh()
	var new_level := Cache.resource(parent_path) as BattleLevelConfig
	check(new_level.victory_rewards.gold == 93 and old_level.victory_rewards.gold == 31, "依赖更新生效且不改旧资源")
	var game: Node = load("res://scripts/app/game_session.gd").new()
	check(game.resolve_level(level_id) == new_level, "实际战斗入口使用已更新的关卡配置")
	game.free()
	var pool: Array[Resource] = Rewards.pool([], "potion")
	var size := pool.size()
	pool.clear()
	check(Rewards.pool([], "potion").size() == size and size > 0, "调用方修改奖励数组不污染缓存")
	check(Rewards.validate_pool(["res://data/potions/fire.tres", "res://data/potions/fire.tres"], "potion", 1).is_empty(), "奖励池兼容重复路径并去重")
	check(not Rewards.validate_pool(["res://data/potions/fire.tres"], "relic", 1).is_empty(), "缓存仍阻止奖励资源类型错误")
	for path in [ROUTE, parent_path, child_path]:
		DirAccess.remove_absolute(path)
	Cache.refresh()
	print("GAME_CONFIG_CACHE_TEST: %d checks; failures=%s" % [checks, str(failures)])
	quit(0 if failures.is_empty() else 1)
