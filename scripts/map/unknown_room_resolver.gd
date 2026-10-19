# 问号房使用内容随机流，首次结果与概率一起进存档；地图种子不控制本阶段的事件/商品随机。
extends RefCounted

const BASE_ODDS := {"battle": 0.10, "shop": 0.03, "treasure": 0.02, "elite": 0.0}
const TYPES := {"battle": 0, "shop": 5, "treasure": 4, "elite": 6}

static func resolve(location: Dictionary, run: Node) -> Dictionary:
	var key := "%d:%s" % [run.current_act, location.id]
	if run.resolved_rooms.has(key):
		return run.resolved_rooms[key].duplicate(true)
	var base: Dictionary = run.active_map.get("generation", {}).get("unknown_base_odds", BASE_ODDS)
	var odds: Dictionary = run.unknown_room_odds.get(str(run.current_act), base).duplicate(true)
	var allow_shop := true
	var previous: Dictionary = run.route_location(run.current_id)
	if not previous.is_empty() and int(previous.type) == 5:
		allow_shop = false
	if not location.next.is_empty():
		var all_shops := true
		for id in location.next:
			if int(run.route_location(str(id)).get("type", -1)) != 5:
				all_shops = false
		if all_shops:
			allow_shop = false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weights: Dictionary = {}
	var total := 0.0
	for kind in TYPES:
		var weight := float(odds.get(kind, base[kind])) if kind != "shop" or allow_shop else 0.0
		weights[kind] = weight
		total += weight
	# 未知房访问多次后，累积概率可能超过 1；此时按非事件候选的比例归一化。
	var roll := rng.randf() * maxf(1.0, total)
	var selected := "event"
	for kind in TYPES:
		roll -= float(weights[kind])
		if roll < 0.0:
			selected = kind
			break
	for kind in TYPES:
		odds[kind] = float(base[kind]) if selected == kind else minf(1.0, float(odds.get(kind, base[kind])) + float(base[kind]))
	var result := location.duplicate(true)
	var actual_type := int(TYPES.get(selected, 1))
	result.merge(location.unknown_options[str(actual_type)].duplicate(true), true)
	# JSON 候选的 type 会回读为 float；统一为运行时枚举整数后再分发。
	result.type = actual_type
	result.erase("unknown_options")
	result.source_type = 7
	result.room_seed = int(rng.randi()) + 1
	run.unknown_room_odds[str(run.current_act)] = odds
	run.resolved_rooms[key] = result.duplicate(true)
	run.pending_route_node = str(location.id)
	# 在打开战斗/商店/事件前提交抽签结果；重新载入不会再掷一次或切换分支。
	run.capture_location_checkpoint()
	run.save_run(true)
	return result
