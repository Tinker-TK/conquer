## 正式资源、真实伤害入口、抽取概率、背包选择及存档往返。
extends Node

const CARD_POOL = preload("res://scripts/cards/card_reward_catalog.gd")
const REWARDS = preload("res://scripts/battle/battle_reward_session.gd")
const RELICS = preload("res://scripts/items/relic_catalog.gd")
const POTIONS = preload("res://scripts/items/potion_catalog.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var stats := {"archer": [75,9,2], "armored_axeman": [160,8,7], "soldier": [100,10,5], "priest": [100,10,4], "were_wolf": [100,15,5], "were_bear": [100,15,5], "knight": [150,15,5], "knight_templar": [160,14,6], "wizard": [115,23,3], "lancer": [160,17,6], "swords_man": [180,18,5]}
	for id: String in stats:
		var unit := load("res://data/units/" + id + ".tres") as UnitData
		check([unit.max_hp, unit.attack, unit.defence] == stats[id], id + "目标三围")
		check(unit.upgrade_ability_points == 2 and unit.max_upgrade_count == 1, id + "训练预算")
	var costs := {"vulnerability":1,"death_explosion":1,"slumber":1,"last_stand":1,"stratagem":1,"overflow_prayer":1,"sacrifice":2,"return_dead":2,"diverse_army":2,"comrade":2,"judger":2,"keep_distance":2,"transcription":2,"fortify":2,"war_cry":2,"undying_army":4}
	for id: String in costs:
		var card := CardInstance.new(load("res://data/cards/" + id + ".tres"))
		check(card.get_cost() == costs[id], id + "基础费用")
		var delta := card.definition.upgrade_cost_change
		check(card.enhance() and card.get_cost() == maxi(0, int(costs[id]) + delta), id + "强化费用")
		check(not card.enhance(), id + "只强化一次")
	for row in [["heal",30.0,45.0],["holy_bulwark",30.0,45.0],["paralysis",0.75,1.25],["haste",30.0,45.0],["last_stand",45.0,65.0]]:
		var card := CardInstance.new(load("res://data/cards/" + row[0] + ".tres"))
		check(is_equal_approx(card.definition.effects[0].amount, row[1]), row[0] + "基础效果")
		card.enhance()
		check(is_equal_approx(card.definition.effects[0].amount, row[2]), row[0] + "强化效果")
	for row in [["normal",35,35.0,12.0],["elite",60,60.0,35.0],["boss",120,100.0,100.0]]:
		var reward := load("res://data/battle_rewards/" + row[0] + ".tres") as BattleRewardConfig
		check([reward.gold,reward.potion_chance,reward.relic_chance] == row.slice(1), row[0] + "奖励预算")
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance/chapter1.json"))
	for id: String in spec.levels:
		var template: Dictionary = spec.templates[spec.levels[id]]
		for act in range(1,4):
			var path := "res://data/levels/" + (id if act == 1 else id.replace("level_", "level_act%d_" % act)) + ".tres"
			var level := load(path) as BattleLevelConfig
			check(level != null and level.validate().is_empty(), path + "配置有效")
			check(level.enemy_max_hp == int(template.hp) and level.waves.size() == template.waves.size(), path + "节点生命与轮数")
			for index in template.waves.size():
				var names: Array = template.waves[index]
				if names.is_empty():
					check(level.waves[index] == null, path + "喘息波")
					continue
				var wave := level.waves[index].instantiate()
				check(wave.get_child_count() == names.size(), path + "人数")
				for n in names.size():
					var unit := wave.get_child(n) as UnitBase
					var base := load("res://data/units/" + names[n] + ".tres") as UnitData
					check(unit.unit_data.unit_english_name == base.unit_english_name and unit.unit_data.max_hp == roundi(base.max_hp * float(spec.act_multipliers[act-1])), path + "敌人配方及幕成长")
					check(unit.get_meta("wave_cycle_effects", {}).is_empty(), path + "循环不无限成长")
				wave.free()
	await _combat()
	_items_and_rewards()
	print("BALANCE_FRAMEWORK_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _combat() -> void:
	RunManager.start_new_run(RunStartData.new())
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var attacker := load("res://scenes/units/soldier.tscn").instantiate() as UnitBase
	var target := load("res://scenes/units/orc.tscn").instantiate() as UnitBase
	attacker.unit_data = attacker.unit_data.duplicate()
	target.unit_data = target.unit_data.duplicate()
	attacker.unit_data.attack = 8
	target.unit_data.max_hp = 10000
	target.unit_data.defence = 5
	target.unit_data.dodge_rate = 0
	add_child(attacker)
	add_child(target)
	attacker.set_physics_process(false)
	target.set_physics_process(false)
	var skill := load("res://data/skills/swords_man_stick_muti_attack.tres") as SkillBase
	var before := target.current_health
	for hit in 7:
		skill.execute(attacker, target)
	check(before - target.current_health == 14, "旧8攻七段由7提升到14伤害")
	attacker.unit_data.attack = 18
	before = target.current_health
	for hit in 7:
		skill.execute(attacker, target)
	check(before - target.current_health == 42, "新18攻七段逐段扣1防御，共42")
	before = target.current_health
	target.get_hurt(18, attacker, false)
	check(before - target.current_health == 13, "普通单段仍完整扣防")
	target.unit_data.monster_rank = UnitData.MonsterRank.BOSS
	check(target.apply_status(&"stun", 4.0, 0, attacker, "first"), "首领接受首次控制")
	check(is_equal_approx(target.status_runtime.effects[&"stun"]["first"].left, 2.0), "首领首次50%")
	check(target.apply_status(&"stun", 4.0, 0, attacker, "second"), "首领接受第二次控制")
	check(is_equal_approx(target.status_runtime.effects[&"stun"]["second"].left, 1.0), "首领第二次25%")
	check(not target.apply_status(&"sleep", 4.0, 0, attacker, "third"), "连续第三次硬控免疫")
	attacker.free()
	target.free()
	await get_tree().process_frame

func _items_and_rewards() -> void:
	var initial := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	RunManager.start_new_run(initial)
	RunManager.starting_reward_pending = true
	check(RunManager.claim_starting_relic(0), "开局可选择遗物")
	check(RunManager.relics.size() == 1 and RunManager.potions.size() == 1 and RunManager.potions[0].rarity == 0, "开局一件遗物一瓶普通药水")
	check(not RunManager.claim_starting_relic(1), "开局奖励只领一次")
	RunManager.potions.clear()
	var fire := load("res://data/potions/fire.tres") as PotionDefinition
	var lightning := load("res://data/potions/lightning.tres") as PotionDefinition
	for n in 3:
		RunManager.add_potion(fire)
	RunManager.add_potion(lightning)
	check(RunManager.potions.size() == 3 and RunManager.pending_potions.size() == 1, "满格新瓶等待选择")
	RunManager.resolve_potion_overflow(1)
	check(RunManager.potions[1].id == lightning.id and RunManager.potions.size() == 3, "明确替换旧瓶")
	RunManager.add_potion(fire)
	RunManager.resolve_potion_overflow(-1)
	check(RunManager.potions[1].id == lightning.id and RunManager.pending_potions.is_empty(), "放弃新瓶保留旧瓶")
	RunManager.expand_potion_belt(9)
	check(RunManager.potion_capacity == 5, "腰带扩容上限5")
	check(RunManager.discard_potion(RunManager.potions[0]) and RunManager.potion_use_counts.is_empty(), "丢弃不算使用次数")
	RunManager.potion_capacity = 3
	RunManager.add_potion(fire)
	RunManager.add_potion(lightning)
	check(RunManager.save_run().is_empty(), "满格未决瓶可存档")
	RunManager.pending_potions.clear()
	check(RunManager.load_saved_run().is_empty() and RunManager.pending_potions.size() == 1 and RunManager.potion_capacity == 3, "未决瓶与腰带存档往返")
	RunManager.resolve_potion_overflow(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var pool := REWARDS.card_pool()
	for n in 30:
		var cards := CARD_POOL.sample(pool, 3, rng, 0.30, true)
		check(cards.size() == 3 and cards.any(CARD_POOL.rare), "首领奖励保底稀有")
		cards = CARD_POOL.sample(pool, 3, rng)
		check(cards.size() == 3 and cards.any(func(card: Resource): return not CARD_POOL.rare(card)), "普通奖励保底普通")
	var rare_count := 0
	var relic_pool := preload("res://scripts/events/event_rewards.gd").pool([], "relic")
	for n in 10000:
		var relic: RelicDefinition = RELICS.sample(relic_pool, [], 1, rng)[0]
		rare_count += int(relic.rarity == RelicDefinition.Rarity.RARE)
	check(absi(rare_count - 3000) < 180, "遗物普通70/稀有30品质概率独立于池大小")
	var recipes := POTIONS.available(POTIONS.all_potions(), 1)
	for n in 30:
		check(POTIONS.pick(recipes, 1, rng, true).rarity == PotionDefinition.Rarity.RARE, "第一幕首领不掉传说药水")
	for n in 20:
		var shop := preload("res://scripts/shop/shop_session.gd").new()
		var catalog: Dictionary = preload("res://scripts/shop/shop_catalog.gd").read_catalog("res://data/shops/caravan.json").data
		shop.initialize(RunManager, "balance_shop", catalog, n + 1)
		check(shop.offers.any(func(o: Dictionary): return o.kind == "card" and o.data.rarity == CardDefinition.Rarity.RARE), "商店稀有卡保底")
