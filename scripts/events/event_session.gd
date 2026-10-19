# 候选固定、复合选择与原子结算；取消、查看地图和牌组不会重抽。
@tool
extends RefCounted
const REWARDS = preload("res://scripts/events/event_rewards.gd")
const ROUTE = preload("res://scripts/events/route_effects.gd")
const STATE = preload("res://scripts/events/event_state.gd")
var event: Dictionary
var run: Object
var preview := false
var claimed := false
var choice_index := -1
var prepared: Dictionary = {}
var cache: Dictionary = {}
var rng := RandomNumberGenerator.new()
var steps: Array = []
var decisions: Array[Dictionary] = []
var step_index := 0
var opened_at := 0

func configure(content: Dictionary, manager: Node, is_preview: bool = false) -> void:
	claimed = false
	choice_index = -1
	prepared = {}
	cache.clear()
	steps.clear()
	decisions.clear()
	step_index = 0
	event = content.duplicate(true)
	run = manager
	preview = is_preview
	if preview:
		run = STATE.new()
		run.capture(manager)
	rng.randomize()
	opened_at = Time.get_ticks_msec()

func option_error(index: int) -> String:
	if index < 0 or index >= event.choices.size():
		return "选项无效。"
	var choice: Dictionary = event.choices[index]
	var issue := ROUTE.cost_error(choice, run)
	if not issue.is_empty():
		return issue
	if run == null:
		return "事件没有绑定本局数据。"
	for effect: Dictionary in ROUTE.effects(choice):
		var kind := str(effect.get("type", ""))
		if kind in ["train_unit", "enhance_card", "remove_card", "duplicate_card", "enhance_random"]:
			var targets := ROUTE.candidates(run.deck, kind, effect.get("filter", "any"))
			if targets.size() < int(effect.get("count", 1)):
				return "没有足够的合法目标（训练 / 强化上限，或必须保留最后一张牌）。"
		if kind == "random_relic":
			var available := REWARDS.pool(effect.get("pool", []), "relic")
			for owned in run.relics:
				for item in available.duplicate():
					if owned.id == item.id:
						available.erase(item)
			if available.is_empty():
				return "本事件的遗物已经全部拥有。"
		if kind == "random_potion":
			var available := false
			for potion in REWARDS.pool(effect.get("pool", []), "potion"):
				if run.current_act >= potion.min_act and run.current_act <= potion.max_act and run.can_acquire_potion(potion):
					available = true
					break
			if not available:
				return "当前幕没有可获得的药水，或已达本局获取上限。"
	return ""

func choose(index: int) -> Dictionary:
	if claimed:
		return {"error": "事件已经结算。"}
	var issue := option_error(index)
	if not issue.is_empty():
		return {"error": issue, "code": "relic_pool_exhausted" if "遗物已经全部拥有" in issue else "unavailable"}
	decisions.clear()
	step_index = 0
	if not cache.has(index):
		if event.has("_seed"):
			rng.seed = hash(str(event._seed) + ":" + str(index))
		var prepared_steps: Array = []
		for effect: Dictionary in ROUTE.effects(event.choices[index]):
			var item := REWARDS.prepare({"effect": effect}, run.relics, rng, run.deck)
			if item.has("error"):
				return item
			prepared_steps.append(item)
		if prepared_steps.is_empty():
			prepared_steps.append({"type": "legacy"})
		# 熔炼必须保留可强化的另一张牌；仅剩一个强化目标时不能把它熔掉。
		for i in prepared_steps.size() - 1:
			if prepared_steps[i].type == "remove_card" and prepared_steps[i + 1].type == "enhance_card":
				if prepared_steps[i + 1].candidates.size() == 1:
					prepared_steps[i].candidates.erase(prepared_steps[i + 1].candidates[0])
				if prepared_steps[i].candidates.is_empty():
					return {"error": "没有能熔炼并强化另一张牌的组合。"}
		cache[index] = prepared_steps
	choice_index = index
	steps = cache[index]
	prepared = steps[0].duplicate()
	return prepared

func cancel() -> void:
	if not claimed:
		decisions.clear()
		step_index = 0
		choice_index = -1
		prepared = {}

func claim(selected: Array[int] = [], allocation: Vector2i = Vector2i.ZERO, branch: String = "") -> Dictionary:
	if claimed or choice_index < 0 or prepared.has("error"):
		return {"error": "事件无法重复结算。"}
	var issue := REWARDS.selection_error(prepared, run, selected, allocation, branch)
	if not issue.is_empty():
		return {"error": issue}
	decisions.append({"prepared": prepared, "selected": selected.duplicate(), "allocation": allocation, "branch": branch})
	if step_index + 1 < steps.size():
		step_index += 1
		prepared = steps[step_index].duplicate()
		if prepared.has("candidates"):
			prepared.candidates = prepared.candidates.duplicate()
			for decision in decisions:
				if decision.prepared.type == "remove_card":
					prepared.candidates.erase(decision.prepared.candidates[decision.selected[0]])
			if prepared.candidates.is_empty():
				cancel()
				return {"error": "熔炼后没有可强化的另一张牌，请取消并重新选择。"}
		return {"pending": true}
	issue = ROUTE.cost_error(event.choices[choice_index], run)
	if not issue.is_empty():
		decisions.pop_back()
		return {"error": issue}
	for decision in decisions:
		issue = REWARDS.selection_error(decision.prepared, run, decision.selected, decision.allocation, decision.branch)
		if not issue.is_empty():
			decisions.pop_back()
			return {"error": issue}
	var backup := STATE.new()
	backup.capture(run)
	var before := {"hp": run.hp, "max_hp": run.max_hp, "gold": run.gold, "cards": run.deck.size()}
	var choice: Dictionary = event.choices[choice_index]
	var cost: Dictionary = choice.get("cost", {})
	run.gold -= int(cost.get("gold", 0))
	run.hp -= int(cost.get("hp", 0))
	run.max_hp -= int(cost.get("max_hp", 0))
	var result: Dictionary = {"items": [], "cards": []}
	var messages: Array[String] = []
	for decision in decisions:
		var granted := REWARDS.grant(decision.prepared, run, decision.selected, decision.allocation, decision.branch)
		if granted.has("error"):
			backup.restore(run)
			decisions.pop_back()
			return granted
		result.items.append_array(granted.get("items", []))
		result.cards.append_array(granted.get("cards", []))
		if granted.has("message"):
			messages.append(granted.message)
		if not str(granted.get("result_text", "")).is_empty():
			result.result_text = granted.result_text
		if granted.has("upgraded"):
			result.upgraded = granted.upgraded
	run.hp += int(choice.get("heal", 0)) + ceili(run.max_hp * float(choice.get("heal_percent", 0.0)) / 100.0)
	run.gold += int(choice.get("gold", 0))
	var changes: Array[String] = []
	for key in ["max_hp", "hp", "gold"]:
		if before[key] != run.get(key):
			changes.append("%s %d → %d" % [{"max_hp": "最大生命", "hp": "生命", "gold": "金币"}[key], before[key], run.get(key)])
	messages.append(" · ".join(changes))
	result.message = "\n".join(messages).strip_edges()
	result.result_text = result.get("result_text", choice.get("result_text", event.get("result_text", "你收拾行囊，继续前进。")))
	claimed = true
	if not preview and run.has_method("record_event_choice"):
		run.record_event_choice(event, choice_index, before, Time.get_ticks_msec() - opened_at)
	return result
