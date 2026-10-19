extends RefCounted
## 图鉴只读取配置，不实例化战斗单位、不执行事件或物品效果。

const REWARDS := preload("res://scripts/events/event_rewards.gd")
const CACHE := preload("res://scripts/run/game_config_cache.gd")
const ROUTE := preload("res://scripts/events/route_effects.gd")
const ART := preload("res://scripts/events/event_illustrations.gd")
const KEYS := ["relics", "allies", "enemies", "potions", "events"]
const NAMES := ["遗物", "己方单位", "敌方单位", "药水", "事件"]
const ENTRIES_PER_PAGE := 3
const ENTRIES_PER_SPREAD := ENTRIES_PER_PAGE * 2


static func read() -> Dictionary:
	var result := {"relics": [], "allies": [], "enemies": [], "potions": [], "events": []}
	for item: RelicDefinition in REWARDS.pool([], "relic"):
		var facts := ["品质：" + item.rarity_name(), "流派：" + item.school_name()]
		var sections := [{"title": "遗物效果", "text": item.description}]
		var limits: Array[String] = []
		if item.max_per_battle > 0: limits.append("每场最多触发 %d 次" % item.max_per_battle)
		if item.max_per_round > 0: limits.append("每轮最多触发 %d 次" % item.max_per_round)
		if item.cooldown_seconds > 0: limits.append("触发间隔 %s 秒" % str(item.cooldown_seconds))
		if not limits.is_empty(): sections.append({"title": "触发规则", "text": "\n".join(limits)})
		result.relics.append(_entry(str(item.id), item.display_name, item.rarity_name() + "遗物", item.icon, facts, sections, item))
	var seen := {}
	for directory in ["res://data/units", "res://data/event_recruits"]:
		for path in REWARDS.resource_paths(directory):
			var unit := CACHE.resource(path) as UnitData
			if unit == null or unit.unit_team not in ["team_a", "team_b"]: continue
			var key := unit.unit_english_name + ":" + unit.unit_team
			if seen.has(key): continue
			seen[key] = true
			var ally := unit.unit_team == "team_a"
			var sections: Array = []
			# 征召卡文案包含技能摘要；图鉴只使用真实技能定义，避免摘要再重复一遍。
			if ally and unit.get_deployment_draw_count(0) > 0:
				sections.append({"title": "上场效果", "text": "成功出牌上场时抽 %d 张牌；强化后抽 %d 张牌。" % [unit.get_deployment_draw_count(0), unit.get_deployment_draw_count(1)]})
			if ally and unit.unit_english_name == "soldier":
				sections.append({"title": "剑矢", "text": UnitData.sword_arrow_description().trim_prefix("剑矢：")})
			var skills := unit.skills.duplicate()
			if unit.dodge_skill != null and not skills.has(unit.dodge_skill): skills.append(unit.dodge_skill)
			var listed: Array[SkillBase] = []
			for skill: SkillBase in skills:
				if skill == null or listed.has(skill): continue
				listed.append(skill)
				var levels: Array[String] = []
				for level in skill.unlock_upgrade_levels:
					levels.append("初始" if level == 0 else "强化%d" % level)
				var text := skill.effect_description().strip_edges()
				if not skill.skill_name.is_empty(): text = text.trim_prefix(skill.skill_name).trim_prefix("：").trim_prefix(":").strip_edges()
				if not skill.is_passive():
					text += "\n冷却 %s 秒 · 距离 %s" % [str(skill.cooldown), str(skill.cast_range)]
				var repeated_name: bool = skills.filter(func(candidate): return candidate != null and candidate.skill_name == skill.skill_name).size() > 1
				var level_text := " / ".join(levels) if not levels.is_empty() else "未启用"
				var heading := skill.skill_name + (" · 被动" if skill.is_passive() else "")
				if repeated_name: heading += " · " + level_text
				else: text += "\n生效：" + level_text
				sections.append({"title": heading, "text": text.strip_edges()})
			var facts := ["生命 %d   攻击 %d" % [unit.max_hp, unit.attack], "防御 %d   移速 %s" % [unit.defence, str(unit.speed)], "闪避 %d%%" % roundi(unit.dodge_rate * 100)]
			facts.append("征召费用 %d · 可强化 %d 次" % [unit.card_cost, unit.max_upgrade_count] if ally else "等级：" + ["普通", "精英", "首领", "传说"][unit.monster_rank])
			if unit.is_flying: facts.append("移动方式：飞行")
			var icon: Texture2D = unit.card_image_2 if unit.card_image_2 != null else unit.card_image
			var subtitle := "己方兵种" if ally else "敌方生物"
			if unit.is_flying: subtitle += " · 飞行"
			var entry := _entry(key, unit.unit_name, subtitle, icon, facts, sections, unit)
			if ally: result.allies.append(entry)
			else: result.enemies.append(entry)
	for item: PotionDefinition in REWARDS.pool([], "potion"):
		var target: String = ["选择落点", "选择敌人", "选择友军", "全体友军", "全体敌人", "阵亡友军", "随机友军", "自身", "被动触发"][item.target_mode]
		var rarity: String = ["普通", "稀有", "传说"][item.rarity]
		var facts := ["品质：" + rarity, "使用方式：" + target, "准备或交锋阶段" if item.prep_usable else "交锋阶段使用"]
		var rules := "被动触发时自动消耗。" if item.target_mode == PotionDefinition.TargetMode.PASSIVE else "成功使用才消耗一瓶，不消耗手牌能量。"
		if item.needs_aim(): rules += "选择药水后指定目标或落点；右键或 Esc 取消。"
		if item.max_per_run > 0: rules += "每局最多使用 %d 瓶。" % item.max_per_run
		var sections := [{"title": "药水效果", "text": item.description}, {"title": "使用规则", "text": rules}]
		result.potions.append(_entry(str(item.id), item.display_name, rarity + "药水", item.icon, facts, sections, item))
	for event: EventDefinition in REWARDS.catalog():
		var content := event.to_content()
		var sections := [{"title": "故事", "text": event.description}]
		for choice: Dictionary in content.get("choices", []):
			var text := ROUTE.summary(choice)
			if choice.get("leave", false): text = "离开此处，继续征途。"
			var outcome := str(choice.get("result_text", ""))
			if not outcome.is_empty(): text += "\n" + outcome
			sections.append({"title": str(choice.get("text", "选项")), "text": text})
		var act := "通用奇遇"
		for i in 3:
			if event.id.begins_with("act%d_" % (i + 1)): act = "第%d幕奇遇" % (i + 1)
		var facts := ["类型：" + str({"common": "普通奇遇", "rare": "稀有奇遇", "gamble": "赌局", "story": "故事"}.get(event.rarity, "奇遇")), "出现层数 %d — %d" % [event.min_floor, event.max_floor], "%d 个事件选项" % content.get("choices", []).size()]
		var entry := _entry(event.id, event.title, act, event.illustration, facts, sections, event)
		entry.content = content
		result.events.append(entry)
	for key in KEYS:
		result[key].sort_custom(func(a: Dictionary, b: Dictionary): return str(a.id).naturalnocasecmp_to(str(b.id)) < 0)
	return result


static func _entry(id: String, title: String, subtitle: String, icon: Texture2D, facts: Array, sections: Array, source: Resource) -> Dictionary:
	return {"id": id, "title": title, "subtitle": subtitle, "icon": icon, "facts": facts, "sections": sections, "source": source}


static func icon_for(entry: Dictionary) -> Texture2D:
	if entry.get("icon") != null: return entry.icon
	if entry.get("icon_loaded", false): return null
	entry.icon_loaded = true
	if entry.source is EventDefinition:
		entry.icon = ART.texture_for(entry.content)
	elif entry.source is UnitData:
		var path := "res://scenes/units/%s.tscn" % entry.source.unit_english_name
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			var state := packed.get_state()
			while state != null:
				for node in state.get_node_count():
					if state.get_node_name(node) != &"AnimatedSprite2D": continue
					for property in state.get_node_property_count(node):
						if state.get_node_property_name(node, property) != &"sprite_frames": continue
						var frames: SpriteFrames = state.get_node_property_value(node, property)
						var animation: StringName = &"idle" if frames.has_animation(&"idle") else frames.get_animation_names()[0]
						if frames.get_frame_count(animation) > 0:
							var frame := frames.get_frame_texture(animation, 0)
							var bounds := frame.get_image().get_used_rect()
							var cropped := AtlasTexture.new()
							cropped.atlas = frame
							cropped.region = bounds if bounds.has_area() else Rect2(Vector2.ZERO, frame.get_size())
							entry.icon = cropped
							return entry.icon
				state = state.get_base_scene_state()
	return entry.get("icon")


static func spreads(entries: Array, query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var matched: Array[Dictionary] = []
	var seen := {}
	for entry: Dictionary in entries:
		if seen.has(entry.id): continue
		var searchable: String = entry.title + " " + entry.subtitle
		for fact in entry.facts: searchable += " " + str(fact)
		for section: Dictionary in entry.sections: searchable += " " + section.title + " " + section.text
		if not query.is_empty() and not searchable.to_lower().contains(query.to_lower()): continue
		seen[entry.id] = true
		matched.append(entry)
	for start in range(0, matched.size(), ENTRIES_PER_SPREAD):
		result.append({"entries": matched.slice(start, start + ENTRIES_PER_SPREAD), "first_entry": start})
	if result.is_empty():
		result.append({"entries": [], "first_entry": 0})
	return result
