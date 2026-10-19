extends RefCounted
const REWARDS = preload("res://scripts/events/event_rewards.gd")
const ROUTE = preload("res://scripts/events/route_effects.gd")
const CAPS := {"relic": 1, "duplicate": 1, "remove": 2}

static func fallback() -> Dictionary:
	return {"id": "abandoned_camp", "title": "遗弃兵营", "description": "空荡的营帐里留着一箱补给。\n\n你收拢散落的绷带和零钱，稍作休整。", "illustration": "res://assets/ui/events/illustrations/abandoned-camp.png", "choices": [{"text": "收拢补给", "gold": 25, "heal": 6}, {"text": "离开", "leave": true}]}

static func snapshot(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary or not data.get("entries") is Array:
		return {"entries": []}
	var frozen: Dictionary = data.duplicate(true)
	var events: Dictionary = {}
	for event in REWARDS.catalog():
		events[str(event.id)] = event.to_content()
	for entry in frozen.entries:
		entry.content = events.get(str(entry.get("event", "")), {}).duplicate(true)
	return frozen

static func eligible(content: Dictionary, run: Object) -> bool:
	for requirement in content.get("requires", []):
		match str(requirement):
			"trainable":
				if ROUTE.candidates(run.deck, "train_unit").is_empty():
					return false
			"removable":
				if run.deck.size() <= 1:
					return false
			"enhanceable":
				if ROUTE.candidates(run.deck, "enhance_card").is_empty():
					return false
			"two_recruits":
				if ROUTE.candidates(run.deck, "duplicate_card", "recruit").size() < 2:
					return false
	return true

static func draw(pool: Dictionary, floor_number: int, run: Object, rng: RandomNumberGenerator, excluded: Variant = null) -> Dictionary:
	var entries: Array = []
	var seen: Array = run.seen_events if excluded == null else excluded
	var total := 0.0
	var caps: Dictionary = pool.get("tag_caps", CAPS) if pool.get("tag_caps", CAPS) is Dictionary else CAPS
	for entry: Dictionary in pool.get("entries", []):
		var content: Dictionary = entry.get("content", {})
		var id := str(entry.get("event", ""))
		if content.is_empty() or seen.has(id) or floor_number < int(entry.get("min_floor", content.get("min_floor", 2))) or floor_number > int(entry.get("max_floor", content.get("max_floor", 9))):
			continue
		var allowed := eligible(content, run)
		for tag in content.get("tags", []):
			if caps.has(tag) and int(run.event_tag_counts.get(tag, 0)) >= int(caps[tag]):
				allowed = false
		if not allowed or not load("res://scripts/map/fixed_map_config.gd").event_error(content).is_empty():
			continue
		var weight := maxf(0.0, float(entry.get("weight", {"common": 10, "rare": 4, "gamble": 3, "story": 2}.get(str(content.get("rarity", "common")), 10))))
		if weight > 0:
			entries.append({"entry": entry, "weight": weight})
			total += weight
	var chosen := fallback()
	if total > 0:
		var roll := rng.randf() * total
		for item in entries:
			roll -= float(item.weight)
			if roll <= 0:
				chosen = item.entry.content.duplicate(true)
				break
	return chosen
