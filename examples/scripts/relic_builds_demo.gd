## F6 遗物流派试验场。Inspector 选择流派，不改正式开局配置。
extends "res://scripts/battle/battle_scene.gd"

@export_enum("军团铺场", "单核养成", "亡语献祭", "毒火持续", "控制压制", "循环连招", "防守续航", "远程风筝", "经济补给", "中立通用") var relic_build := 0
const BUILDS := [
	["war_banner", "muster_roll", "diverse_codex", "fallen_roster", "beacon", "earth_altar"],
	["anvil", "lone_wolf", "bloodstone", "legacy_seal", "duel_pact", "kings_blade"],
	["urn", "mourner", "sacrificial_dagger", "death_echo", "martyr_crown", "undying_throne"],
	["corrosive_vial", "ember", "plague_mask", "slow_death", "sulfur_heart", "burning_city"],
	["chains", "fear_totem", "sunder", "inquisitor", "executioner", "stasis_field"],
	["gloves", "fate_coin", "steady_hands", "borrowed_time", "echo_crystal", "perpetual_gear"],
	["iron_wall", "thorn_mail", "last_stand", "counter_stance", "holy_symbol", "guardian_oath", "blood_bank", "unfallen_fortress"],
	["longbow_string", "kite_boots", "spell_focus", "hunter_mark", "volley_horn"],
	["coin_purse", "field_kit", "alchemy_pack", "merchant_seal", "greedy_cup", "relic_hunter"],
	["tactical_map", "scout_horn", "veteran_medal", "hourglass", "spare_quiver"]]

func _ready() -> void:
	var start := load("res://data/run/run_start_data.tres").duplicate(true) as RunStartData
	start.starting_relics.clear()
	for id in BUILDS[clampi(relic_build, 0, BUILDS.size() - 1)]:
		start.starting_relics.append(load("res://data/relics/%s.tres" % id))
	RunManager.start_new_run(start)
	super._ready()
