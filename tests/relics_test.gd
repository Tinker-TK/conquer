## 使用正式单位、出牌、伤害、死亡和奖励入口，覆盖遗物框架与十个流派。
extends Node

const T = RelicDefinition.Trigger
const CATALOG = preload("res://scripts/events/event_rewards.gd")
const RELICS = preload("res://scripts/items/relic_catalog.gd")
var checks := 0
var failures: Array[String] = []
var battle
var cards
var hand
var rounds
var relics
var point := Vector2(300, 350)

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("RELIC_CHECK_FAILED: ", label)

func create(ids: Array, draws: int = 0) -> void:
	if is_instance_valid(battle):
		battle.finish_battle(false)
		battle.queue_free()
		await get_tree().process_frame
	var start := RunStartData.new()
	for i in 20: start.cards.append(load("res://data/units/soldier.tres"))
	for id in ids: start.starting_relics.append(load("res://data/relics/%s.tres" % id))
	RunManager.start_new_run(start)
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = draws
	config.enemy_max_hp = 1000
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	cards = battle.card_runtime
	hand = battle.hand_manager
	rounds = battle.battle_round_manager
	relics = battle.get_node("RelicRuntime")
	check(await preload("res://tests/battle_test_navigation.gd").install(battle), "遗物测试导航可部署")
	for unit in cards.living_units(): unit.process_mode = Node.PROCESS_MODE_DISABLED
	cards.set_physics_process(false)
	point = battle.random_deployment_position()

func unit(team: String = "team_a", type_name: String = "soldier") -> UnitBase:
	var result := load("res://scenes/units/%s.tscn" % type_name).instantiate() as UnitBase
	result.unit_data = result.unit_data.duplicate()
	result.unit_data.unit_team = team
	result.unit_data.attack = 20
	result.unit_data.defence = 0
	result.unit_data.max_hp = 1000
	result.remove_from_group("team_b" if team == "team_a" else "team_a")
	result.add_to_group(team)
	battle.get_node("Entities/TeamA" if team == "team_a" else "Entities/TeamB").add_child(result)
	result.global_position = point + Vector2(300 if team == "team_b" else 0, 0)
	result.process_mode = Node.PROCESS_MODE_DISABLED
	return result

func deploy(type_name: String = "soldier") -> UnitBase:
	var card := CardInstance.new(load("res://data/units/%s.tres" % type_name))
	hand.hand.append(card)
	rounds.current_energy = 99
	check(cards.try_play(card, point), "正式征召 " + type_name)
	for id in hand.board_cards:
		if hand.board_cards[id] == card:
			var result := instance_from_id(id) as UnitBase
			result.process_mode = Node.PROCESS_MODE_DISABLED
			return result
	return null

func play(id: String, target: UnitBase = null) -> CardInstance:
	var card := CardInstance.new(load("res://data/cards/%s.tres" % id))
	hand.hand.append(card)
	rounds.current_energy = 99
	var success: bool = cards.try_play(card, target.global_position if target != null else battle.battlefield_rect.get_center())
	if not success: print("RELIC_PLAY_ERROR: ", id, " ", battle.card_ui.get_node("CardFeedback").text)
	check(success, "正式效果牌 " + id)
	return card

func _run() -> void:
	var pool := CATALOG.pool([], "relic")
	check(pool.size() == 66, "60件新遗物加6件兼容旧遗物")
	var ids: Dictionary = {}
	for relic: RelicDefinition in pool:
		check(not ids.has(relic.id) and not relic.tags.is_empty() and relic.icon != null, "合法唯一遗物 " + String(relic.id))
		ids[relic.id] = true
		if relic.handler != &"": check(relic.kind == RelicDefinition.Kind.NONE, "新遗物显式NONE " + String(relic.id))
	check(load("res://data/relics/draw_engine.tres").kind == RelicDefinition.Kind.DRAW_ENERGY, "保留旧默认枚举")
	await create(["tactical_map", "fate_coin", "hourglass", "war_banner", "veteran_medal", "scout_horn"], 5)
	check(hand.hand.size() == 7 and rounds.current_energy == 5, "沙盘首轮加抽2与沙漏加能2")
	check(relics.count(&"fate_coin") == 1 and relics.banner_ready, "首轮抽牌后硬币和旗幡准备完成")
	var soldier := deploy()
	check(relics.count(&"war_banner") == 1 and relics.count(&"veteran_medal") == 1, "成功征召才消耗两种首牌减费")
	check(soldier.unit_data.attack == 11 and soldier.unit_data.defence == load("res://data/units/soldier.tres").defence + 1, "侦察号角首轮攻防")
	check(not RunManager.add_relic(load("res://data/relics/hourglass.tres")), "相同ID不能重复获取")
	await create(["muster_roll", "beacon", "diverse_codex"])
	var a := deploy()
	var b := deploy("archer")
	var c := deploy("priest")
	check(relics.deployed == 3 and relics.count(&"muster_roll") == 1 and relics.count(&"beacon") == 1, "每3次部署名册和第3人烽火")
	check(a.unit_data.attack == 14 and a.unit_data.defence == load("res://data/units/soldier.tres").defence + 3, "3兵种兵书与名册烽火属性")
	check(is_equal_approx(a.skill_manager.cooldown_multiplier, 0.85), "烽火技能冷却减少15%")
	var d := deploy()
	RunManager.add_relic(load("res://data/relics/earth_altar.tres"))
	RunManager.hp -= 10
	var hp: int = RunManager.hp
	var enemy_hp: int = rounds.enemy_hp
	relics.settled()
	check(RunManager.hp == hp + 2 and rounds.enemy_hp == enemy_hp - 4, "大地祭坛4人存活结算")
	await create(["anvil", "duel_pact"])
	a = deploy()
	var attack: int = a.unit_data.attack
	play("power_enhance", a)
	check(a.unit_data.attack == attack + 5 and relics.count(&"anvil") == 1, "铁砧首次3攻向上取整为5")
	play("power_enhance", a)
	check(a.unit_data.attack == roundi((10 + 5 + 3) * 1.15), "铁砧本场只强化一次且契约同池计算")
	check(a.unit_data.max_hp == ceili(100 * 1.3), "决斗契约第一单位增加30%生命")
	await create(["anvil"])
	a = unit()
	a.current_health = 100
	var healing: CardDefinition = load("res://data/cards/heal.tres")
	var healed_amount := ceili(a.unit_data.max_hp * minf(100, ceili(healing.effects[0].amount * 1.5)) / 100.0)
	play("heal", a)
	check(a.current_health == mini(a.unit_data.max_hp, 100 + healed_amount) and relics.count(&"anvil") == 1, "铁砧也放大友军治疗强化牌")
	await create(["lone_wolf", "last_stand", "iron_wall", "spell_focus"])
	a = unit()
	cards.tactics.refresh_all()
	check(a.unit_data.attack == 25, "独狼单人攻击25%")
	b = unit()
	cards.tactics.refresh_all()
	check(a.unit_data.attack == 20, "第二人入场立即撤销独狼")
	a.current_health = 100
	a.health_changed.emit()
	check(a.unit_data.attack == 22 and a.unit_data.defence == 3, "背水低血属性自动刷新")
	b.get_parent().remove_child(b)
	b.free()
	cards.tactics.refresh_all()
	check(a.unit_data.attack == 28, "撤回后恢复独狼且无属性漂移")
	await create(["duel_pact", "lone_wolf"])
	a = deploy()
	check(a.unit_data.attack == 14, "契约15%与独狼25%相加为40%")
	await create(["fallen_roster", "death_echo", "urn", "mourner", "martyr_crown", "legacy_seal"])
	a = deploy()
	b = unit()
	c = unit("team_b", "orc")
	var original: CardInstance = hand.board_cards[a.get_instance_id()]
	var health: int = c.current_health
	a.die()
	check(hand.hand.has(original) and original.get_cost() == 0 and not hand.discard_pile.has(original), "死亡回响与抚恤只回手同一原牌且不加费")
	check(c.current_health == health - 5 and relics.count(&"urn") == 1, "骨灰瓮5点真实伤害")
	check(relics.count(&"mourner") == 1 and relics.count(&"legacy_seal") == 1 and relics.count(&"martyr_crown") == 1, "真实死亡触发抽牌与两种传承")
	b.die()
	check(relics.count(&"mourner") == 1, "送葬人每轮最多1次")
	await create(["undying_throne", "mourner", "death_echo", "fallen_roster"])
	a = deploy()
	original = hand.board_cards[a.get_instance_id()]
	a.die()
	check(hand.board_cards.size() == 1 and hand.board_cards.values().has(original) and not hand.hand.has(original), "王座复活保持唯一原牌绑定")
	b = instance_from_id(hand.board_cards.keys()[0]) as UnitBase
	check(b != a and b.has_meta("relic_revived") and int(b.current_health) == ceili(b.unit_data.max_hp * 0.5), "王座以50%生命复活")
	var deaths: int = relics.count(&"mourner")
	b.die()
	check(relics.count(&"mourner") == deaths and hand.board_cards.is_empty(), "复活单位不再次触发死亡遗物")
	await create(["corrosive_vial", "plague_mask", "chains", "sunder", "executioner", "inquisitor", "hunter_mark", "longbow_string", "kite_boots", "spell_focus"])
	a = unit("team_a", "archer")
	b = unit("team_b", "orc")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	b.get_hurt(10, a)
	b.get_hurt(10, a)
	check(cards.states[b.get_instance_id()].poison == 1, "腐蚀瓶同一目标1秒上限")
	var clock_before: float = relics.elapsed
	get_tree().paused = true
	for i in 3: await get_tree().process_frame
	check(is_equal_approx(relics.elapsed, clock_before), "暂停冻结遗物冷却时钟")
	get_tree().paused = false
	relics.elapsed += 1.1
	b.get_hurt(10, a)
	check(cards.states[b.get_instance_id()].poison == 2 and int(relics.hunter_hits[b.get_instance_id()]) == 3, "腐蚀冷却到期与猎手3次命中标记")
	b.apply_status(&"stun", 2)
	b.current_health = 100
	var modified: int = relics.incoming_damage(b, a, 100, &"skill", true)
	check(modified == 168, "5点固定加伤后百分比增伤同池封顶60%")
	check(is_equal_approx(a.get_movement_speed(), a.unit_data.speed * 1.2), "风筝靴远程移速")
	b.global_position = a.global_position + Vector2(450, 0)
	check(is_equal_approx(relics.dodge_bonus(a, b), 0.1), "风筝靴400距离闪避")
	check(is_equal_approx(relics.attack_percent(a, b), 0.15), "长弓距离增攻进入扣防御前入口")
	await create(["bloodstone", "kings_blade", "thorn_mail", "blood_bank", "holy_symbol", "counter_stance", "guardian_oath"])
	a = unit()
	b = unit("team_b", "orc")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	a.current_health = 900
	a.receive_healing(40)
	check(a.current_health == 950, "血库治疗增加25%")
	a.current_health = 990
	a.receive_healing(40, null, true)
	check(a.current_health == 1000 and a.shield_amount == 40, "血库溢出转盾只结算一次")
	a.clear_shield()
	health = b.current_health
	a.get_hurt(10, b)
	a.get_hurt(10, b)
	check(b.current_health == health - 3 and relics.count(&"thorn_mail") == 1, "荆棘同攻击者每秒1次且不会反伤递归")
	check(relics.counter_damage(a, 10) == 15, "反击姿态伤害增加50%")
	a.current_health = 900
	relics.countered(a)
	check(a.current_health == 903, "反击治疗2受血库增幅")
	health = a.current_health
	relics.end_round()
	check(a.current_health == health + 7, "圣徽治疗最低比例友军受血库增幅")
	b.current_health = 1
	b.get_hurt(50, a)
	check(relics.count(&"bloodstone") == 1 and relics.count(&"kings_blade") == 1 and a.unit_data.attack == 23, "自然击杀触发血石和王剑")
	await create(["sacrificial_dagger", "gloves", "perpetual_gear", "borrowed_time", "steady_hands", "spare_quiver", "echo_crystal"])
	RunManager.hp = 80
	var blood := play("draw_hp")
	check(RunManager.hp == 78 and relics.count(&"sacrificial_dagger") == 1, "献祭匕首4血降低为2血")
	play("master_strategy")
	check(relics.count(&"gloves") == 1, "首张0费触发魔术手套")
	play("defend", unit())
	check(relics.count(&"perpetual_gear") == 1, "每轮第3张牌齿轮回能")
	relics.end_round()
	check(relics.next_energy == 1 and hand.relic_retained != null, "借时记录下轮1能和沉稳保留1张")
	hand.discard_unused_card()
	check(hand.hand.size() == 1, "沉稳之手真实弃牌阶段保留")
	var stored: Array = hand.draw_pile.duplicate()
	hand.discard_pile.append_array(stored)
	hand.draw_pile.clear()
	hand.draw_cards(1)
	check(relics.count(&"spare_quiver") == 1 and hand.hand.size() == 4, "备用箭袋真实洗牌后额外抽2无重入")
	relics.begin_round()
	check(relics.count(&"gloves", true) == 0 and relics.next_energy == 0, "新轮重置每轮计数并兑现延迟能量")
	await create(["urn", "mourner", "unfallen_fortress"])
	a = deploy()
	battle.clear_round_units()
	check(relics.round_deaths == 0 and relics.count(&"urn") == 0 and relics.count(&"mourner") == 0, "正式回合清场不算死亡或触发亡语")
	await create(["sulfur_heart", "fear_totem", "stasis_field", "volley_horn", "slow_death", "ember", "burning_city"])
	a = unit("team_a", "archer")
	b = unit("team_a", "wizard")
	c = unit("team_b", "orc")
	d = unit("team_b", "orc")
	rounds.current_round = 3
	relics.rng.seed = 42
	relics.fire(T.ROUND_START)
	check(cards.states[c.get_instance_id()].poison == 1 and c.is_stunned and c.has_meta("relic_stasis_hit"), "硫磺起毒与第三轮静滞控制")
	check(relics.count(&"volley_horn") == 1 and relics.count(&"fear_totem") == 1, "两远程号角伤害与恐惧减攻")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	c.die(a)
	check(cards.zones.size() == 1 and cards.zones[0].source == &"relic" and cards.zones[0].effect.amount == 8, "焚城独立来源火区受余烬增幅")
	var other := unit("team_b", "orc")
	other.global_position = d.global_position + Vector2(50, 0)
	var other_hp: int = other.current_health
	for i in 200: relics.dot_tick(d, 3)
	check(relics.count(&"slow_death", true) == 2 and other.current_health == other_hp - 6, "DOT扩散真实复制伤害且每轮上限2")
	await create(["coin_purse", "field_kit", "greedy_cup", "unfallen_fortress", "alchemy_pack", "merchant_seal", "relic_hunter"])
	var items = battle.get_node("BattleItems")
	var recipe: PotionDefinition = load("res://data/potions/tornado.tres")
	var scaled: PotionDefinition = items.relic_recipe(recipe)
	check(scaled.damage == ceili(recipe.damage * 1.25) and is_equal_approx(scaled.duration, recipe.duration * 1.25), "炼金行囊伤害和持续增加25%")
	check(items.relic_recipe(scaled) == scaled and recipe.damage != scaled.damage, "药水快照不会重复放大或修改共享资源")
	RunManager.hp = 30
	RunManager.gold = 200
	enemy_hp = rounds.enemy_hp
	relics.settled()
	check(RunManager.hp == 32 and rounds.enemy_hp == enemy_hp - 2, "不落堡垒无死亡结算")
	battle.finish_battle(true)
	check(RunManager.hp == 40 and RunManager.gold == 210, "胜利钱袋急救贪杯各触发一次")
	check(not relics.can_trigger(&"coin_purse"), "结束后所有遗物停止")
	await _rewards_and_save(pool)
	if DisplayServer.get_name() != "headless":
		await _capture_ui(pool)
	if is_instance_valid(battle):
		battle.queue_free()
		await get_tree().process_frame
	var demo: Node = load("res://examples/scenes/relic_builds_demo.tscn").instantiate()
	get_tree().root.add_child(demo)
	check(RunManager.relics.size() == 6 and RunManager.has_relic(&"earth_altar"), "F6流派试验场加载真实套装")
	demo.finish_battle(false)
	demo.queue_free()
	await get_tree().process_frame
	print("RELICS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _rewards_and_save(pool: Array) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 10
	var chosen := RELICS.sample(pool, [], 3, random, true)
	check(chosen.size() == 3 and chosen.all(func(relic: RelicDefinition): return relic.rarity == RelicDefinition.Rarity.BOSS), "首领池三选一仅首领且无重复")
	var reward := preload("res://scripts/battle/battle_reward_session.gd").new()
	reward.initialize(RunManager, {"gold": 30, "potion_chance": 0, "relic_chance": 0}, 12, true)
	var index := reward.offers.size() - 1
	check(reward.offers[index].kind == "relic" and reward.offers[index].options.size() == 3, "Boss忽略旧掉率快照必掉首领三选一")
	check(not reward.claim(index, -1) and reward.claim(index, 1) and not reward.claim(index, 1), "选择验证与单次领取")
	var shop := preload("res://scripts/shop/shop_session.gd").new()
	var content: Dictionary = preload("res://scripts/shop/shop_catalog.gd").read_catalog("res://data/shops/caravan.json").data
	shop.initialize(RunManager, "relic-test", content, 19)
	var offers: Array = shop.offers.filter(func(offer: Dictionary): return offer.kind == "relic")
	check(offers.size() == 3 and offers.any(func(offer: Dictionary): return offer.data.rarity == RelicDefinition.Rarity.RARE), "商店3格且至少1稀有")
	check(offers.all(func(offer: Dictionary): return offer.data.rarity != RelicDefinition.Rarity.BOSS and offer.price == ceili(offer.original_price * 0.8)), "首领不售卖与商人8折")
	check(load("res://data/battle_rewards/normal.tres").relic_chance == 12 and load("res://data/battle_rewards/boss.tres").relic_chance == 100, "正式模板掉率12%与100%")
	RunManager.relic_draw_counts[&"draw_engine"] = 7
	check(RunManager.save_run().is_empty(), "遗物存档成功")
	var expected: int = RunManager.relics.size()
	check(RunManager.load_saved_run().is_empty() and RunManager.relics.size() == expected and RunManager.relic_draw_counts[&"draw_engine"] == 7, "遗物与旧抽牌长期进度存档往返")
	check(RunManager.discovered_relics.has("relic_hunter"), "图鉴持久发现记录")

func _capture_ui(pool: Array) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 99
	add_child(layer)
	var picker := preload("res://scripts/ui/relic_choice_panel.gd").new()
	layer.add_child(picker)
	picker.open([load("res://data/relics/earth_altar.tres"), load("res://data/relics/undying_throne.tres"), load("res://data/relics/burning_city.tres")])
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://.maintenance/relics-choice.png")
	picker.queue_free()
	await get_tree().process_frame
	var collection := preload("res://scripts/ui/relic_collection_panel.gd").new()
	layer.add_child(collection)
	collection.open()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://.maintenance/relics-collection.png")
	check(collection.catalog.size() == pool.size(), "图鉴展示全部有效遗物")
	layer.queue_free()
	await get_tree().process_frame
