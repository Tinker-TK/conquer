# 独立地图随机流：随机游走 → 强制行/配额 → 类型序列剪枝/修复 → 绑定遭遇 → 固定地图快照。
# 逻辑列与显示坐标分开；邻接表始终按编号排序，不依赖哈希枚举顺序。
@tool
extends RefCounted

const VERSION := 1
const BATTLE := 0
const EVENT := 1
const REST := 2
const BOSS := 3
const TREASURE := 4
const SHOP := 5
const ELITE := 6
const UNKNOWN := 7
const CATALOG = preload("res://scripts/map/encounter_catalog.gd")
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const TITLES := ["普通战斗", "旅途奇遇", "篝火", "幕终首领", "遗物宝箱", "旅途商队", "精英战斗", "随机事件"]
const ROOT_ID := "_origin"
const SEGMENT_LIMIT := 30000

var graph: Dictionary = {}
var rng := RandomNumberGenerator.new()
var rooms := 15
var width := 7
var quotas: Dictionary = {}
var pruned_nodes := 0
var prune_steps := 0
var segment_budget := 0
var bound_events: Dictionary = {}

static func seed_for(seed_text: String, stream: String) -> int:
	return (seed_text + ":" + stream).sha256_text().substr(0, 15).hex_to_int()

func _shuffle(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var target := rng.randi_range(0, index)
		var value: Variant = items[index]
		items[index] = items[target]
		items[target] = value

func _point(row: int, column: int) -> Dictionary:
	var id := "floor_%02d_%02d" % [row, column + 1]
	if not graph.has(id):
		graph[id] = {"id": id, "floor": row, "column": column, "type": -1, "parents": [], "next": [], "locked": false}
	return graph[id]

func _link(from: Dictionary, to: Dictionary) -> void:
	if not from.next.has(to.id):
		from.next.append(to.id)
		from.next.sort()
		to.parents.append(from.id)
		to.parents.sort()

func _unlink(from: Dictionary, to: Dictionary) -> void:
	from.next.erase(to.id)
	to.parents.erase(from.id)

func _points() -> Array:
	var ids := graph.keys()
	ids.sort()
	return ids.map(func(id): return graph[id])

func _row(row: int) -> Array:
	return _points().filter(func(p): return int(p.floor) == row)

func _crosses(point: Dictionary, column: int) -> bool:
	if column == int(point.column):
		return false
	var other_id := "floor_%02d_%02d" % [int(point.floor), column + 1]
	if not graph.has(other_id):
		return false
	for child_id in graph[other_id].next:
		if int(graph[child_id].column) == int(point.column):
			return true
	return false

func _carve(paths: int) -> void:
	graph[ROOT_ID] = {"id": ROOT_ID, "floor": 0, "column": width / 2.0, "type": EVENT, "parents": [], "next": [], "locked": true}
	var starts: Array = []
	for path in paths:
		var column := rng.randi_range(0, width - 1)
		if path == 1:
			while starts.has(column):
				column = rng.randi_range(0, width - 1)
		starts.append(column)
		var point := _point(1, column)
		_link(graph[ROOT_ID], point)
		for row in range(2, rooms + 1):
			var directions: Array = [-1, 0, 1]
			_shuffle(directions)
			for direction in directions:
				var target := clampi(int(point.column) + int(direction), 0, width - 1)
				if not _crosses(point, target):
					var next := _point(row, target)
					_link(point, next)
					point = next
					break
	var boss := _point(rooms + 1, int(width / 2.0))
	boss.type = BOSS
	boss.locked = true
	for point: Dictionary in _row(rooms):
		_link(point, boss)

func _valid(kind: int, point: Dictionary) -> bool:
	if kind in [REST, ELITE] and int(point.floor) < 6:
		return false
	if kind == REST and int(point.floor) >= rooms - 2:
		return false
	if kind in [ELITE, REST, TREASURE, SHOP]:
		for id in point.parents + point.next:
			if int(graph[id].type) == kind:
				return false
	if kind in [REST, BATTLE, UNKNOWN, ELITE, SHOP]:
		for parent_id in point.parents:
			for id in graph[parent_id].next:
				if id != point.id and int(graph[id].type) == kind:
					return false
	return true

func _assign() -> void:
	for pair in [[rooms, REST], [rooms - 6, TREASURE], [1, BATTLE]]:
		for point: Dictionary in _row(int(pair[0])):
			point.type = int(pair[1])
			point.locked = true
	var queue: Array = []
	for kind in [REST, SHOP, ELITE, UNKNOWN]:
		for unused in int(quotas[kind]):
			queue.append(kind)
	for pass_index in 3:
		var candidates := _points().filter(func(p): return int(p.type) == -1)
		_shuffle(candidates)
		for point: Dictionary in candidates:
			for unused in queue.size():
				var kind: int = queue.pop_front()
				if _valid(kind, point):
					point.type = kind
					break
				queue.append(kind)
	for point: Dictionary in _points():
		if int(point.type) == -1:
			point.type = BATTLE

func _count(kind: int) -> int:
	return _points().filter(func(p): return p.id != ROOT_ID and int(p.type) == kind).size()

func _repair() -> bool:
	var changed := false
	for kind in [SHOP, ELITE, REST, UNKNOWN]:
		var need := int(quotas[kind]) - _count(kind)
		if need <= 0:
			continue
		var candidates := _points().filter(func(p): return int(p.type) == BATTLE and not p.locked)
		_shuffle(candidates)
		for point: Dictionary in candidates:
			if need <= 0:
				break
			if _valid(kind, point):
				point.type = kind
				need -= 1
				changed = true
	return changed

# 只比较同一分叉点到同一汇合点的类型序列；预算限制避免可配置长图造成路径爆炸。
func _segments(path: Array, sequence: String, groups: Dictionary) -> void:
	segment_budget -= 1
	if segment_budget < 0:
		return
	var point: Dictionary = graph[path.back()]
	if path.size() > 1 and point.parents.size() > 1:
		if path.size() > 2:
			var key := str(path[0]) + ":" + str(point.id) + ":" + sequence
			if not groups.has(key):
				groups[key] = []
			groups[key].append(path.duplicate())
		# 首次汇合后的公共尾部对选择无影响，由后续分叉各自检查。
		return
	for child_id in point.next:
		_segments(path + [child_id], sequence + "," + str(graph[child_id].type), groups)

func _reachable(id: String, direction: String) -> Dictionary:
	var result: Dictionary = {}
	var pending: Array = [id]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if result.has(current):
			continue
		result[current] = true
		pending.append_array(graph[current][direction])
	return result

func _remove(id: String) -> void:
	var point: Dictionary = graph[id]
	for parent_id in point.parents.duplicate():
		_unlink(graph[parent_id], point)
	for child_id in point.next.duplicate():
		_unlink(point, graph[child_id])
	graph.erase(id)
	pruned_nodes += 1

func _cleanup() -> void:
	var reachable := _reachable(ROOT_ID, "next")
	var boss_id := str(_row(rooms + 1)[0].id)
	var to_boss := _reachable(boss_id, "parents")
	for id in graph.keys():
		if not reachable.has(id) or not to_boss.has(id):
			_remove(id)

func _prune_once() -> bool:
	var groups: Dictionary = {}
	segment_budget = SEGMENT_LIMIT
	for point: Dictionary in _points():
		if point.next.size() > 1:
			_segments([point.id], str(point.type), groups)
		if segment_budget < 0:
			break
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var matches: Array = groups[key]
		if matches.size() < 2:
			continue
		_shuffle(matches)
		var keep: Array = matches.back()
		for index in range(matches.size() - 1):
			var path: Array = matches[index]
			# 仅删除独立走廊里的节点，不切掉仍承载其他分叉的共享入口。
			for inner in range(1, path.size() - 1):
				var id: String = path[inner]
				var point: Dictionary = graph[id]
				if not keep.has(id) and not point.locked and point.parents.size() == 1 and point.next.size() == 1:
					_remove(id)
					_cleanup()
					return true
	return false

func _prune(limit: int) -> void:
	for pass_index in 3:
		for iteration in limit:
			if not _prune_once():
				break
			prune_steps += 1
		if not _repair():
			break

func _bind(kind: int, floor_number: int, act: int, rules: Dictionary, difficulty: String, encounters: Dictionary, content_rng: RandomNumberGenerator) -> Dictionary:
	var result := {"type": kind, "event_id": "", "title": TITLES[kind]}
	if kind in [BATTLE, ELITE, BOSS]:
		result.merge(CATALOG.pick(encounters, act, floor_number, rooms, "elite" if kind == ELITE else "boss" if kind == BOSS else "normal", difficulty, content_rng), true)
	elif kind == EVENT:
		result.event_pool = rules.event_pools[act - 1]
		result.event_pool_floor = clampi(roundi(1.0 + float(floor_number - 1) / float(rooms - 1) * 8.0), 2, 9)
		result.event_scope = "act"
	elif kind == REST:
		result.event_id = "campfire"
		if not bound_events.has("campfire"):
			bound_events.campfire = CONFIG.default_event("campfire")
		result.event = bound_events.campfire.duplicate(true)
	elif kind == SHOP:
		result.shop_catalog = rules.shop_catalog
	return result

func generate(seed_text: String, act: int, rules: Dictionary, difficulty: String, encounters: Dictionary, bind_content: bool = true) -> Dictionary:
	graph.clear()
	bound_events.clear()
	pruned_nodes = 0
	prune_steps = 0
	rooms = int(rules.rooms)
	width = int(rules.columns)
	rng.seed = seed_for(seed_text, "act_%d_map_v%d" % [act, VERSION])
	var tier: Dictionary = rules.difficulties[difficulty]
	quotas = {REST: rng.randi_range(int(rules.rest_quota[0]), int(rules.rest_quota[1])), SHOP: int(rules.shops), ELITE: int(tier.elites), UNKNOWN: rng.randi_range(int(rules.unknown_quota[0]), int(rules.unknown_quota[1]))}
	_carve(int(rules.paths))
	_assign()
	_prune(int(rules.max_prune_iterations))
	var content_rng := RandomNumberGenerator.new()
	content_rng.seed = seed_for(seed_text, "act_%d_encounters_v%d" % [act, VERSION])
	var locations: Array = []
	for point: Dictionary in _points():
		if point.id == ROOT_ID:
			continue
		var kind := int(point.type)
		var location: Dictionary = _bind(kind, int(point.floor), act, rules, difficulty, encounters, content_rng) if bind_content else {"type": kind, "title": TITLES[kind], "event_id": ""}
		if kind == UNKNOWN and bind_content:
			location.unknown_options = {}
			for option in [BATTLE, EVENT, TREASURE, SHOP, ELITE]:
				location.unknown_options[str(option)] = _bind(option, int(point.floor), act, rules, difficulty, encounters, content_rng)
		location.merge({"id": point.id, "floor": int(point.floor), "column": int(point.column), "map_pos": {"x": 0.1 + float(point.column) / float(width - 1) * 0.8, "y": 0.93 - float(point.floor - 1) / float(rooms) * 0.86}, "next": point.next.duplicate(), "generation_locked": point.locked}, true)
		locations.append(location)
	var deficits: Dictionary = {}
	for kind in quotas:
		if _count(kind) < int(quotas[kind]):
			deficits[str(kind)] = int(quotas[kind]) - _count(kind)
	var result := {"schema_version": 1, "mode": "fixed", "name": rules.act_names[act - 1], "floors": rooms + 1, "starting_ids": graph[ROOT_ID].next.duplicate(), "locations": locations,
		"generation": {"seed": seed_text, "generator_version": VERSION, "config_version": int(rules.config_version), "encounter_config_version": int(encounters.config_version), "act": act, "difficulty": difficulty, "rooms": rooms, "pruned_nodes": pruned_nodes, "prune_steps": prune_steps, "quota_shortfalls": deficits, "unknown_base_odds": rules.unknown_base_odds.duplicate(true)}}
	return result
