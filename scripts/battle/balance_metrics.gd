## 每场与每轮写入本地JSONL，供第12节试玩矩阵汇总；不上传，不参与胜负。
extends Node

var battle: Node2D
var hp_start := 0
var elapsed := 0.0
var combat_elapsed := 0.0
var history: Array[Dictionary] = []
var enabled := true

func setup(owner_battle: Node2D) -> void:
	battle = owner_battle
	hp_start = RunManager.hp
	# 自动化夹具不会混进玩家试玩样本。
	for argument in OS.get_cmdline_user_args():
		if argument.ends_with("-regression") or argument.begins_with("--test-timeout=") or argument == "--no-balance-metrics":
			enabled = false
	set_physics_process(enabled)
	battle.battle_round_manager.round_settled.connect(func(result: StringName, damage: int, base: int, units: int):
		history.append({"round": battle.battle_round_manager.current_round, "result": String(result), "damage": damage, "base_damage": base, "unit_damage": units, "hp": RunManager.hp, "enemy_hp": battle.battle_round_manager.enemy_hp}))

func _physics_process(delta: float) -> void:
	if battle.battle_finished:
		return
	elapsed += delta
	if Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		combat_elapsed += delta

func finish(won: bool) -> void:
	if not enabled:
		return
	var record := {"version": "NUM-DESIGN-v1.0", "time": Time.get_datetime_string_from_system(),
		"seed": RunManager.map_seed, "difficulty": RunManager.map_difficulty, "act": RunManager.current_act,
		"node": RunManager.pending_battle_id, "level": battle.level_config.resource_path if battle.level_config != null else "preview",
		"won": won, "hp_start": hp_start, "hp_end": RunManager.hp, "hp_loss_net": hp_start - RunManager.hp,
		"rounds": battle.battle_round_manager.current_round, "game_seconds": elapsed, "combat_seconds": combat_elapsed,
		"deck_size": RunManager.deck.size(), "relic_count": RunManager.relics.size(), "potion_uses": RunManager.potion_use_counts.duplicate(), "round_results": history}
	var path := "user://balance_metrics.jsonl"
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(record))
