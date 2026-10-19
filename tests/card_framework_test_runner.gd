# 在全局节点初始化后运行测试。卡牌内部回归参数继续交给默认烟测处理。
extends SceneTree

const TEST_SCRIPTS := {
	"balance-framework": "balance_framework_test.gd",
	"balance-ui": "balance_ui_test.gd",
	"relics": "relics_test.gd",
	"potion-catalog": "potion_catalog_test.gd",
	"potion-effects": "potion_effects_test.gd",
	"expanded-cards": "expanded_cards_test.gd",
	"card-enhancement": "card_enhancement_test.gd",
	"stair-displacement": "stair_displacement_test.gd",
	"combat-numbers": "combat_numbers_test.gd",
	"status-effects": "unit_status_effects_test.gd",
	"strategy-cards": "strategy_cards_test.gd",
	"card-description": "card_description_test.gd",
	"flying": "flying_units_test.gd",
	"enemy-only": "enemy_only_units_test.gd",
	"deployment-floors": "deployment_floors_test.gd",
	"enemy-pack": "enemy_pack_test.gd",
	"floors": "battle_floors_test.gd",
	"stair-crowd": "stair_crowd_test.gd",
	"stair-visual": "stair_visual_render_test.gd",
	"were-wolf-skills": "were_wolf_skills_test.gd",
	"wolf-pounce": "wolf_pounce_test.gd",
	"consecutive-attack": "consecutive_attack_test.gd",
	"protection-aura": "protection_aura_test.gd",
	"knight-draw": "knight_deployment_draw_test.gd",
	"knight-blood": "knight_blood_test.gd",
	"templar-taunt": "templar_taunt_test.gd",
	"cavalry-charge": "cavalry_charge_test.gd",
	"sword-wind": "sword_wind_test.gd",
	"bear-leap-chain": "bear_leap_chain_test.gd",
	"sword-arrow": "sword_arrow_test.gd",
	"skill-unlock": "skill_unlock_test.gd",
	"card-unit-details": "card_unit_details_test.gd",
	"battle-speed": "battle_speed_test.gd",
	"combat-audio": "combat_audio_test.gd",
	"level-spawn": "level_spawn_test.gd",
	"tactical-cards": "tactical_cards_test.gd",
	"unit-details": "unit_details_test.gd",
	"battle-rewards": "battle_rewards_test.gd",
	"combat-card": "combat_card_play_test.gd",
	"card-targeting": "card_targeting_test.gd",
	"status": "unit_status_test.gd",
	"round-damage": "round_damage_effect_test.gd",
	"card-motion": "card_motion_test.gd",
	"card-cost": "card_cost_increase_test.gd",
	"undying-army": "undying_army_test.gd",
	"battle-architecture": "battle_architecture_test.gd",
	"monster-test": "monster_test_scene_test.gd",
	"skeleton-archer": "skeleton_archer_attack_test.gd",
	"wizard-fire-ball": "wizard_fire_ball_test.gd",
	"wizard-frost-storm": "wizard_frost_storm_test.gd",
	"priest-chant-shield": "priest_chant_shield_test.gd",
	"monster-test-priest": "monster_test_priest_test.gd",
	"archer-piercing": "archer_piercing_test.gd",
	"soldier-branches": "soldier_branches_test.gd",
	"armored-axeman": "armored_axeman_test.gd",
	"counter": "counter_attack_test.gd",
	"bloodthirst": "bloodthirst_attack_test.gd",
	"targeting": "skill_targeting_test.gd",
	"targeting-navigation": "enemy_targeting_navigation_test.gd",
	"summon": "summon_skill_test.gd",
	"items-ui": "run_items_ui_test.gd",
	"potion-visuals": "potion_visuals_test.gd",
	"thunder-cloud-potion": "thunder_cloud_potion_test.gd",
	"items": "run_items_test.gd",
	"camera": "battle_camera_test.gd",
	"pointer": "pointer_interaction_test.gd",
	"pile-view": "pile_view_test.gd",
	"movement": "navigation_movement_test.gd",
	"shop": "shop_test.gd",
	"campfire": "campfire_regression.gd",
	"game-session": "game_session_smoke_case.gd",
	"unit-lifecycle": "unit_lifecycle_test.gd",
}
const PREVIEW_TESTS := ["combat-numbers", "flying", "combat-card", "status", "round-damage", "card-motion", "monster-test", "level-spawn", "protection-aura"]
const SMOKE_TESTS := ["navigation-deploy", "energy", "random-draw", "level", "zone", "buff", "inspector", "new-unit", "round"]
var _deadline_usec := 0


func _initialize() -> void:
	_start.call_deferred()


func default_test_script() -> String:
	return "card_framework_smoke.gd"


func _process(_delta: float) -> bool:
	if _deadline_usec > 0 and Time.get_ticks_usec() >= _deadline_usec:
		_deadline_usec = 0
		push_error("TEST_TIMEOUT: wall-clock deadline exceeded")
		quit(1)
	return false


func _start() -> void:
	var startup_errors := preload("res://autoload/runtime_guard.gd").startup_errors(root)
	if not startup_errors.is_empty():
		push_error("TEST_STARTUP_FAILED: " + "；".join(startup_errors))
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	# 普通逻辑回归会立即 quit；Godot 的音频线程在这种退出时可能保留正在播放的流。
	# 音频由专门的真实混音回归验证，其余 headless 回归关闭播放但仍加载全部音效资源。
	if DisplayServer.get_name() == "headless" and "--combat-audio-regression" not in args:
		var audio := root.get_node("CombatAudio")
		audio.settings = audio.settings.duplicate()
		audio.settings.enabled = false
	# 保留旧命令参数；基地兼容验收已统一为战斗架构检查。
	if "--base-regression" in args:
		args.append("--battle-architecture-regression")
	for arg: String in args:
		if arg.begins_with("--") and arg.ends_with("-regression"):
			var name := arg.trim_prefix("--").trim_suffix("-regression")
			if name != "base" and not TEST_SCRIPTS.has(name) and name not in SMOKE_TESTS:
				push_error("UNKNOWN_REGRESSION: " + arg)
				quit(2)
				return
	# 单独运行入口也有真实时间 watchdog；外部运行器负责捕获脚本错误并立即结束。
	var timeout_seconds := 60.0
	for arg: String in args:
		if arg.begins_with("--test-timeout="):
			timeout_seconds = arg.trim_prefix("--test-timeout=").to_float()
	if not is_finite(timeout_seconds) or timeout_seconds <= 0:
		push_error("TEST_TIMEOUT: timeout must be positive and finite")
		quit(2)
		return
	# --fixed-fps 可以加速模拟帧，SceneTreeTimer 不是可靠的真实时长限制。
	_deadline_usec = Time.get_ticks_usec() + int(timeout_seconds * 1000000.0)
	var script_name := default_test_script()
	for name in TEST_SCRIPTS:
		if "--%s-regression" % name in args or (name in PREVIEW_TESTS and "--%s-preview" % name in args):
			script_name = TEST_SCRIPTS[name]
			break
	var script := load("res://tests/" + script_name) as Script
	if script == null or not script.can_instantiate():
		push_error("无法加载测试：" + script_name)
		quit(1)
		return
	root.add_child(script.new())
