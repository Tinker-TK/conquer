## 将第11节配方保存为正式关卡；保留每个战场原有的安全出生点和楼层。
extends Node

func _ready() -> void:
	_apply.call_deferred()

func quit(code: int = 0) -> void:
	get_tree().quit(code)

func _apply() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance/chapter1.json"))
	var report: Array[Dictionary] = []
	for id: String in spec.levels:
		var config := load("res://data/levels/" + id + ".tres") as BattleLevelConfig
		var template: Dictionary = spec.templates[spec.levels[id]]
		var placements: Array[Array] = []
		var all_slots: Array[Dictionary] = []
		for packed in config.waves:
			var slots: Array = []
			if packed != null:
				var old := packed.instantiate()
				for child in old.get_children():
					if child is UnitBase:
						var slot := {"position": child.position, "floor": child.floor_id}
						slots.append(slot)
						all_slots.append(slot)
				old.free()
			placements.append(slots)
		for act_index in 3:
			var target := config.duplicate() as BattleLevelConfig
			target.waves = []
			target.level_name = "第%d幕 · %s" % [act_index + 1, template.name]
			target.notes = "%s / 模板%s；攻击和生命×%.2f；循环不额外成长。" % [spec.version, spec.levels[id], spec.act_multipliers[act_index]]
			target.enemy_max_hp = int(template.hp)
			target.victory_rewards = load("res://data/battle_rewards/boss.tres" if spec.levels[id] == "F" else "res://data/battle_rewards/elite.tres" if "_elite_" in id else "res://data/battle_rewards/normal.tres")
			for wave_index in template.waves.size():
				var names: Array = template.waves[wave_index]
				if names.is_empty():
					target.waves.append(null)
					continue
				var slots: Array = placements[wave_index % placements.size()].duplicate()
				for slot in all_slots:
					if slots.size() >= names.size():
						break
					if not slots.any(func(existing: Dictionary): return existing.position.distance_to(slot.position) < 32):
						slots.append(slot)
				if slots.size() < names.size():
					push_error("缺少安全出生点：" + id)
					quit(1)
					return
				var wave := Node2D.new()
				wave.name = "Wave"
				for index in names.size():
					var unit := load("res://scenes/units/" + names[index] + ".tscn").instantiate() as UnitBase
					unit.unit_data = load("res://data/units/" + names[index] + ".tres").duplicate() as UnitData
					unit.unit_data.max_hp = roundi(unit.unit_data.max_hp * float(spec.act_multipliers[act_index]))
					unit.unit_data.attack = roundi(unit.unit_data.attack * float(spec.act_multipliers[act_index]))
					if spec.levels[id] == "F" and names[index] == "elite_orc":
						unit.unit_data.monster_rank = UnitData.MonsterRank.BOSS
					unit.position = slots[index].position
					unit.floor_id = slots[index].floor
					unit.set_meta("wave_cycle_effects", {})
					wave.add_child(unit)
					unit.owner = wave
				var packed := PackedScene.new()
				packed.pack(wave)
				wave.free()
				target.waves.append(packed)
			target.repeat_waves = true
			target.repeat_start = 9 if spec.levels[id] == "F" else 1
			target.repeat_end = target.waves.size()
			var output := "res://data/levels/" + (id if act_index == 0 else id.replace("level_", "level_act%d_" % (act_index + 1))) + ".tres"
			var error := ResourceSaver.save(target, output)
			if error != OK:
				push_error("无法保存：" + output)
				quit(1)
				return
			report.append({"path": output, "template": spec.levels[id], "waves": target.waves.size(), "hp": target.enemy_max_hp})
	var file := FileAccess.open("res://.maintenance/balance-v1/waves.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BALANCE_WAVES_APPLIED: ", report.size())
	quit()
