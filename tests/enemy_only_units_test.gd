# 敌方数据不能进入玩家卡池；旧存档清除混入的敌方牌时保留其余牌的顺序、训练和征途进度。
extends Node

const ENEMIES := ["bear", "bomb_fish", "bumblebee", "giant_bat", "gnoll", "gnome",
	"harpoon_shark", "hex_shaman", "imp", "lizard", "minotaur", "paddle_shark", "panda",
	"skull", "slingshot_gnome", "snake", "spear_goblin", "spider", "thief", "torch_goblin",
	"troll", "turtle", "pig_rider"]
var failures: Array[String] = []
var checks := 0
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var rewards: Script = load("res://scripts/events/event_rewards.gd")
	var battle_rewards: Script = load("res://scripts/battle/battle_reward_session.gd")
	var run := root.get_node("RunManager")
	run.start_new_run()
	var count: int = run.deck.size()
	var pool: Array[Resource] = rewards.pool([], "unit")
	for id: String in ENEMIES:
		var path := "res://data/units/%s.tres" % id
		var data := load(path) as UnitData
		check(data.unit_team == "team_b" and data.card_name.is_empty() and data.card_image == null and data.card_discription.is_empty(), id + " 仅有敌方单位配置，不配置卡牌")
		check(not pool.has(data) and rewards.pool([path], "unit").is_empty(), id + " 自动扫描和指定事件池都不生成怪物牌")
		check(not rewards.validate_pool([path], "unit", 1).is_empty(), id + " 事件配置拒绝敌方奖励")
		check(run.add_card(data) == null and run.deck.size() == count, id + " 入库入口拒绝敌方单位")
		var unit := load("res://scenes/units/%s.tscn" % id).instantiate() as UnitBase
		check(unit != null and unit.is_in_group("team_b") and unit.unit_data.skills.size() == 1, id + " 敌方战斗场景和攻击仍完整")
		unit.free()
	check(pool.size() >= 5 and pool.all(func(data: Resource): return data is UnitData and data.unit_team == "team_a"), "事件招募仍有至少五种己方卡")
	check(battle_rewards.card_pool().all(func(data: Resource): return not data is UnitData or data.unit_team == "team_a"), "胜利奖励排除敌方单位")
	# 即使旧快照仍带卡名和图片，或外层包成 CardDefinition，也不能绕过阵营校验。
	var stale := load("res://data/units/troll.tres").duplicate() as UnitData
	stale.card_name = "旧巨魔牌"
	stale.card_image = load("res://data/units/soldier.tres").card_image
	var wrapped := CardInstance.new(stale).definition
	var wrapper_path := "res://.maintenance/checks/enemy_only_wrapped.tres"
	check(ResourceSaver.save(wrapped, wrapper_path) == OK, "创建旧版怪物征召牌快照")
	check(rewards.pool([wrapper_path], "unit").is_empty() and not rewards.validate_pool([wrapper_path], "unit", 1).is_empty(), "封装征召牌也不能进入事件奖励池")
	check(run.add_card(wrapped) == null, "入库入口拒绝封装的敌军征召牌")
	# 首、尾两张合法牌之间夹一张旧怪物牌，确保过滤时不会把训练记录错配。
	run.start_new_run()
	run.deck.clear()
	var first: CardInstance = run.add_card(load("res://data/units/soldier.tres"))
	first.upgrade_count = 1
	first.attack_points = 3
	first.permanent_buffs.assign([{"attack": 2}])
	var last: CardInstance = run.add_card(load("res://data/units/archer.tres"))
	last.defence_points = 4
	run.hp = 37
	run.gold = 123
	run.current_id = "enemy_only_probe"
	var saved: Resource = run.create_save_data()
	saved.card_definitions.insert(1, wrapped)
	saved.card_states.insert(1, {"upgrade_count": 7, "attack_points": 99})
	check(ResourceSaver.save(saved, run.SAVE_PATH) == OK and run.load_saved_run().is_empty(), "旧存档中的怪物牌可自动过滤后继续")
	check(run.deck.size() == 2 and run.deck[0].unit_data.unit_english_name == "soldier" and run.deck[1].unit_data.unit_english_name == "archer", "读取旧存档只移除混入的敌军牌，保留合法牌顺序")
	check(run.deck[0].attack_points == 3 and run.deck[0].upgrade_count == 1 and run.deck[0].permanent_buffs == [{"attack": 2}] and run.deck[1].defence_points == 4, "旧存档的训练、强化和永久增益不串到其它牌")
	check(run.hp == 37 and run.gold == 123 and run.current_id == "enemy_only_probe", "清理怪物牌保留征途进度和资源")
	# 直接遗留在内存中的旧牌在下一场抽牌前移除，保存也不把它带回去。
	run.deck.insert(1, CardInstance.new(wrapped))
	saved = run.create_save_data()
	check(saved.card_definitions.size() == 2 and saved.card_states.size() == 2, "重新保存不再写入敌军牌")
	var hand: Node = load("res://scripts/cards/hand_manager.gd").new()
	root.add_child(hand)
	hand.build_initial_deck()
	check(run.deck.size() == 2 and hand.draw_pile.size() == 2 and hand.draw_pile.all(func(card: CardInstance): return card.unit_data.unit_team == "team_a"), "战斗开场的真实抽牌堆排除旧怪物牌")
	hand.free()
	var start := RunStartData.new()
	var ability := CardDefinition.new()
	ability.category = CardDefinition.Category.ABILITY
	start.cards.assign([load("res://data/units/soldier.tres"), stale, wrapped, ability])
	run.start_new_run(start)
	check(run.deck.size() == 2 and run.deck[0].unit_data.unit_english_name == "soldier" and run.deck[1].definition == ability, "初始牌组保留己方征召和效果牌，跳过敌军配置")
	print("ENEMY_ONLY_UNITS_TEST: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
