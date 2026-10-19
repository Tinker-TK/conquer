# 按战斗事件播放短音效：固定池、独立随机数、限频和距离衰减，声音不改变战斗随机结果。
extends Node

signal sound_played(category: StringName, point: Vector2, stream: AudioStream)

const BUS := &"CombatSFX"
const BANK = preload("res://data/audio/combat_sounds.tres")
var settings: CombatSoundBank = BANK
var _players: Array[AudioStreamPlayer2D] = []
var _rng := RandomNumberGenerator.new()
var _last_category: Dictionary = {}
var _last_variant: Dictionary = {}
var _last_source: Dictionary = {}
var _scene_id := 0


func _ready() -> void:
	_rng.randomize()
	var bus_index := AudioServer.get_bus_index(BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, BUS)
		AudioServer.set_bus_send(bus_index, &"SFX")
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(bus_index, limiter)
	for index in settings.max_voices:
		var player := AudioStreamPlayer2D.new()
		player.name = "CombatVoice%d" % index
		player.bus = BUS
		player.panning_strength = 0.45
		add_child(player)
		_players.append(player)
	SignalBus.phase_change.connect(_on_phase_changed)
	SceneTransition.started.connect(stop_all)
	# 场景销毁时清理声音；单位死亡时播放器仍留在池中，能播完死亡声。
	get_tree().node_removed.connect(_on_node_removed)


# 自动匹配现有全部兵种；配置覆盖可让新单位沿用合适的音色。
func unit_profile(unit: Node2D) -> StringName:
	if unit.unit_data.combat_sound_profile != &"":
		return unit.unit_data.combat_sound_profile
	match unit.unit_data.unit_type:
		Global.UnitType.SKELETON, Global.UnitType.SKELETONARCHER, Global.UnitType.GREATSWORDSKELETON:
			return &"undead"
		Global.UnitType.SLIME:
			return &"slime"
		Global.UnitType.BAT, Global.UnitType.WEREBEAR, Global.UnitType.WEREWOLF:
			return &"beast"
		Global.UnitType.ORC, Global.UnitType.ARMOREDORC, Global.UnitType.ELITEORC, Global.UnitType.ORCRIDER:
			return &"monster"
	return &"human"


func attack_profile(unit: Node2D, skill: Resource = null) -> StringName:
	if skill != null:
		if skill.combat_sound_profile not in ["auto", "melee", "beast", "bow"]:
			return StringName(skill.combat_sound_profile)
		match skill.get_script().resource_path.get_file():
			"ally_heal.gd": return &"heal"
			"summon_unit.gd": return &"summon"
			"dash_attack.gd": return &"charge"
			"bear_earth_shake.gd": return &"heavy"
			"arrow_attack.gd":
				return _ranged_profile(unit)
		if skill.combat_sound_profile == "bow":
			return _ranged_profile(unit)
	match unit.unit_data.unit_type:
		Global.UnitType.ARCHER, Global.UnitType.SKELETONARCHER: return &"bow"
		Global.UnitType.WIZARD: return &"ice"
		Global.UnitType.NECROMANCER: return &"magic"
		Global.UnitType.SLIME: return &"slime"
		Global.UnitType.KNIGHT, Global.UnitType.KNIGHTTEMPLAR, Global.UnitType.SWORDSMAN, Global.UnitType.GREATSWORDSKELETON, Global.UnitType.THIEF:
			return &"sword"
		Global.UnitType.ARMOREDAXEMAN, Global.UnitType.ARMOREDORC: return &"axe"
		Global.UnitType.LANCER, Global.UnitType.SPEARGOBLIN: return &"spear"
		Global.UnitType.PRIEST: return &"staff"
		Global.UnitType.ORC, Global.UnitType.ELITEORC, Global.UnitType.ORCRIDER, Global.UnitType.TROLL, Global.UnitType.MINOTAUR, Global.UnitType.PADDLESHARK, Global.UnitType.PIGRIDER, Global.UnitType.TURTLE:
			return &"heavy"
		Global.UnitType.WEREWOLF, Global.UnitType.WEREBEAR, Global.UnitType.BEAR, Global.UnitType.PANDA, Global.UnitType.LIZARD, Global.UnitType.SPIDER:
			return &"claw"
		Global.UnitType.BAT, Global.UnitType.GIANTBAT, Global.UnitType.SNAKE, Global.UnitType.BUMBLEBEE:
			return &"bite"
	return &"melee"


func _ranged_profile(unit: Node2D) -> StringName:
	if unit.unit_data.unit_type in [Global.UnitType.SLINGSHOTGNOME, Global.UnitType.GNOLL]:
		return &"stone"
	return &"fire" if unit.unit_data.unit_type == Global.UnitType.WIZARD else &"bow"


func play_attack(unit: Node2D, skill: Resource, target: Node2D) -> void:
	if not _can_play(unit) or skill == null:
		return
	# 跳砸的冲击在实际落地时播放，起跳帧不能提前轰鸣。
	if skill.get_script().resource_path.get_file() == "bear_earth_shake.gd":
		return
	if skill.target_type != skill.TargetType.SELF and skill.get_script().resource_path.get_file() != "area_attack.gd":
		if not is_instance_valid(target) or target.current_state == target.State.DEATH or target.is_queued_for_deletion():
			return
	var profile := attack_profile(unit, skill)
	if profile != &"silent":
		_play(profile, unit.global_position, unit, 0, -10.0)


func play_movement(unit: Node2D, profile: StringName, skill: Resource) -> void:
	if _can_play(unit) and skill != null and skill.combat_sound_profile != "silent":
		_play(profile, unit.global_position, unit, 0, -12.0)


func play_hit(unit: Node2D, attacker: Node2D = null, profile: StringName = &"") -> void:
	if not _can_play(unit):
		return
	if profile == &"":
		if is_instance_valid(attacker):
			profile = attack_profile(attacker, attacker.skill_manager.current_skill)
	var category: StringName = &"hit"
	if profile in [&"bow", &"fire", &"ice", &"magic", &"stone", &"lightning"]:
		category = StringName("hit_" + str(profile))
	elif unit_profile(unit) in [&"undead", &"slime"]:
		category = StringName("hit_" + str(unit_profile(unit)))
	elif unit.unit_data.unit_type in [Global.UnitType.KNIGHT, Global.UnitType.KNIGHTTEMPLAR, Global.UnitType.ARMOREDAXEMAN, Global.UnitType.ARMOREDORC]:
		category = &"hit_armor"
	elif profile in [&"axe", &"charge", &"heavy"]:
		category = &"hit_heavy"
	_play(category, unit.global_position, unit, 1, -14.0)


func play_block(unit: Node2D) -> void:
	if _can_play(unit):
		_play(&"block", unit.global_position, unit, 1, -12.0)


func play_death(unit: Node2D) -> void:
	if not _can_play(unit):
		return
	var profile := unit_profile(unit)
	if profile == &"beast":
		profile = &"monster"
	_play(StringName("death_" + str(profile)), unit.global_position, unit, 2, -8.0)


func _can_play(unit: Node2D) -> bool:
	return settings.enabled and not get_tree().paused and Global.game_phase == Global.GamePhase.AUTO_BATTLE \
		and is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() \
		and unit.current_state != unit.State.DEATH \
		and not unit._encounter_finished()


# 音频自己使用 RNG，不能消耗闪避、奖励、抽牌等玩法使用的全局随机数。
func _play(category: StringName, point: Vector2, source: Node2D, priority: int, gain_db: float) -> bool:
	var clips: Variant = settings.get(str(category))
	if not clips is Array:
		return false
	var variants: Array[AudioStream] = clips
	if variants.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var source_key := "%d:%s" % [source.get_instance_id(), category]
	if now - int(_last_source.get(source_key, -10000)) < 90:
		return false
	if priority < 2 and now - int(_last_category.get(category, -10000)) < int(settings.category_interval * 1000.0):
		return false
	var voice: AudioStreamPlayer2D = null
	for player in _players:
		if not player.playing:
			voice = player
			break
	if voice == null:
		for player in _players:
			if int(player.get_meta("priority", 0)) < priority:
				if voice == null or int(player.get_meta("started", 0)) < int(voice.get_meta("started", 0)):
					voice = player
	if voice == null:
		return false
	# 多变体不连续重复；单变体仍有轻微音高变化。
	var variant := _rng.randi_range(0, variants.size() - 1)
	if variants.size() > 1 and variant == int(_last_variant.get(category, -1)):
		variant = (variant + 1) % variants.size()
	voice.stop()
	voice.stream = variants[variant]
	voice.global_position = point
	voice.volume_db = gain_db + settings.volume_db
	voice.max_distance = settings.max_distance
	voice.pitch_scale = _rng.randf_range(1.0 - settings.pitch_variation, 1.0 + settings.pitch_variation)
	# 同源材质按武器体量调整；受击与元素法术维持原音高。
	match category:
		&"spear": voice.pitch_scale *= 1.2
		&"heavy": voice.pitch_scale *= .78
		&"stone": voice.pitch_scale *= .78
		&"staff": voice.pitch_scale *= .88
		&"claw": voice.pitch_scale *= 1.12
	voice.set_meta("priority", priority)
	voice.set_meta("started", now)
	var scene := source.get_tree().current_scene
	if is_instance_valid(scene):
		_scene_id = scene.get_instance_id()
	voice.play()
	_last_variant[category] = variant
	_last_category[category] = now
	_last_source[source_key] = now
	# 同源限频表按战斗清理；长时间练兵时也保持有界。
	if _last_source.size() > 1024:
		for key in _last_source.keys():
			if now - int(_last_source[key]) > 1000:
				_last_source.erase(key)
	sound_played.emit(category, point, voice.stream)
	return true


func stop_all() -> void:
	for player in _players:
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
	_scene_id = 0
	_last_category.clear()
	_last_source.clear()


func _on_phase_changed(phase: int) -> void:
	if phase == Global.GamePhase.ROUND_RESOLVE:
		# 最后一击常会立即切入结算；让已经开始的死亡声播完，普通攻击声立即停止。
		for player in _players:
			if player.playing and int(player.get_meta("priority", 0)) < 2:
				player.stop()
				player.stream = null
		_last_category.clear()
		_last_source.clear()
	elif phase != Global.GamePhase.AUTO_BATTLE:
		stop_all()


func _on_node_removed(node: Node) -> void:
	if node.get_instance_id() == _scene_id:
		stop_all()


func _exit_tree() -> void:
	stop_all()
