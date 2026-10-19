# 真实单位动画、远程命中和音频总线回归；混音捕获证明音频资源产生非静音采样。
extends Node2D

var events: Array[StringName] = []
var checks := 0


func _ready() -> void:
	CombatAudio.sound_played.connect(_on_sound)
	_run.call_deferred()


func _on_sound(category: StringName, _point: Vector2, _stream: AudioStream) -> void:
	events.append(category)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		push_error("COMBAT_AUDIO: " + description)
		get_tree().quit(1)
		assert(condition, description)


func _unit(resource_name: String, team: String = "") -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/" + resource_name + ".tscn").instantiate()
	add_child(unit)
	unit.set_physics_process(false)
	unit.global_position = Vector2(960, 540)
	unit.unit_data.dodge_skill = null
	unit.unit_data.dodge_rate = 0.0
	if not team.is_empty():
		unit.unit_data.unit_team = team
	return unit


func _reset() -> void:
	CombatAudio.stop_all()
	events.clear()


func _voices() -> int:
	var count := 0
	for player: AudioStreamPlayer2D in CombatAudio._players:
		if player.playing:
			count += 1
	return count


func _run() -> void:
	get_tree().current_scene = self
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	var original_settings: CombatSoundBank = CombatAudio.settings
	CombatAudio.settings = original_settings.duplicate()
	CombatAudio.settings.category_interval = 0.0
	var bank: CombatSoundBank = CombatAudio.settings
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/combat/manifest.json"))
	_check(manifest.files.size() == 30, "30 份可追溯的素材")
	for entry in manifest.files:
		var path: String = "res://assets/audio/combat/" + entry.path
		var stream := load(path) as AudioStream
		_check(stream != null and stream.get_length() > 0.01 and stream.get_length() < 8.0, "素材时长有效：" + path)
		_check(FileAccess.get_sha256(path) == entry.sha256 and entry.license == "CC0-1.0", "原始音频哈希和许可：" + path)
	_check(AudioServer.get_bus_index(CombatAudio.BUS) >= 0, "战斗专用总线")
	_check(CombatAudio._players.size() == bank.max_voices, "固定播放器池")
	var soldier := _unit("soldier", "team_a")
	var target := _unit("orc", "team_b")
	var skill: SkillBase = soldier.unit_data.skills[0]

	# 准备阶段、暂停、禁用时不播放，也不改变音频总线或战斗属性。
	Global.game_phase = Global.GamePhase.CARD_PLAY
	CombatAudio.play_attack(soldier, skill, target)
	_check(events.is_empty(), "准备阶段静音")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	get_tree().paused = true
	CombatAudio.play_attack(soldier, skill, target)
	get_tree().paused = false
	bank.enabled = false
	CombatAudio.play_attack(soldier, skill, target)
	bank.enabled = true
	_check(events.is_empty(), "暂停和禁用时静音")

	seed(71268)
	var expected_random := randi()
	seed(71268)
	CombatAudio.play_attack(soldier, skill, target)
	_check(randi() == expected_random, "音效随机变化不消耗玩法 RNG")
	_check(events == [&"melee"], "步兵使用近战声音")
	_reset()
	soldier.skill_manager.current_skill = skill
	soldier.skill_manager.current_target = target
	soldier.switch_state(UnitBase.State.ATTACK)
	soldier.skill_manager.attack()
	_check(events.is_empty(), "开始动画不提前播放挥击")
	soldier.animated_sprite_2d.frame = skill.hit_frame[0]
	_check(events == [&"melee", &"hit"] and target.current_health < target.unit_data.max_hp, "命中帧同步挥击和真实受击")
	soldier.skill_manager.finish_skill(skill)
	_reset()
	target.unit_data.dodge_skill = SkillBase.new()
	target.unit_data.dodge_rate = 1.0
	var health: int = target.current_health
	_check(not target.get_hurt(20, soldier) and target.current_health == health, "闪避不造成伤害")
	_check(events == [&"block"], "闪避只播放格挡声")
	target.unit_data.dodge_skill = null
	target.unit_data.dodge_rate = 0.0
	_reset()
	target.current_health = 1
	target.get_hurt(100, soldier)
	_check(events == [&"hit", &"death_monster"], "致命命中播放受击与怪物死亡")
	var event_count := events.size()
	target.get_hurt(100, soldier)
	target.die(soldier)
	_check(events.size() == event_count, "尸体不重复播放受击和死亡")

	# 弓箭在发射时播放弓弦，碰撞时才播放命中；发射者释放后仍保留音色。
	_reset()
	var archer := _unit("archer", "team_a")
	var victim := _unit("soldier", "team_b")
	victim.global_position.x += 250
	var arrow_skill: SkillBase = archer.unit_data.skills[0]
	archer.skill_manager.current_skill = arrow_skill
	archer.skill_manager.current_target = victim
	archer.switch_state(UnitBase.State.ATTACK)
	archer.skill_manager.attack()
	archer.animated_sprite_2d.frame = arrow_skill.hit_frame[0]
	_check(events == [&"bow"], "射箭不提前播放命中声")
	var projectile: Projectile
	for child in get_children():
		if child is Projectile:
			projectile = child
	_check(projectile != null and projectile.hit_sound_profile == &"bow", "投射物保存音色")
	archer.free()
	projectile._deal_damage()
	_check(events == [&"bow", &"hit_bow"], "发射者被释放后箭仍播放命中声")
	await get_tree().process_frame
	_reset()
	var wizard := _unit("wizard", "team_a")
	var fire_skill: SkillBase = wizard.unit_data.skills[0]
	var ice_skill: SkillBase = wizard.unit_data.skills[1]
	CombatAudio.play_attack(wizard, fire_skill, victim)
	_check(events == [&"fire"], "火球使用火焰发射音")
	_reset()
	CombatAudio.play_attack(wizard, ice_skill, victim)
	_check(events == [&"ice"], "冰晶使用冰系声音")
	_reset()
	victim.get_hurt(10, null, false, &"fire")
	_check(events == [&"hit_fire"], "火球命中保持火焰音色")
	_reset()
	for entry in [["skeleton", &"undead"], ["slime", &"slime"], ["were_wolf", &"beast"], ["priest", &"human"]]:
		var unit := _unit(entry[0])
		_check(CombatAudio.unit_profile(unit) == entry[1], "单位音色：" + entry[0])
		CombatAudio.play_death(unit)
		_check(not events.is_empty(), "此类型有死亡素材：" + entry[0])
		_reset()
		unit.free()

	# 同源限频与全场限频；有界池满时死亡声优先于普通攻击。
	CombatAudio.play_attack(soldier, skill, victim)
	CombatAudio.play_attack(soldier, skill, victim)
	_check(events.size() == 1, "同源高频重复合并")
	_reset()
	bank.category_interval = 0.2
	CombatAudio.play_attack(soldier, skill, victim)
	CombatAudio.play_attack(victim, skill, soldier)
	_check(events.size() == 1, "全场同类限频")
	_reset()
	bank.category_interval = 0.0
	var sources: Array[Node2D] = []
	for index in bank.max_voices + 5:
		var source := Node2D.new()
		add_child(source)
		sources.append(source)
		CombatAudio._play(&"melee", Vector2(960, 540), source, 0, -10.0)
	_check(_voices() == bank.max_voices and CombatAudio.get_child_count() == bank.max_voices, "大量单位同时攻击不增加播放器")
	var before := events.size()
	CombatAudio.play_death(soldier)
	_check(events.size() == before + 1 and _voices() == bank.max_voices, "死亡声抢占普通音效")
	Global.game_phase = Global.GamePhase.ROUND_RESOLVE
	_check(_voices() == 1, "结算只保留最后死亡声的尾音")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	_check(_voices() == 0, "下一轮准备前清理所有音效")
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	_reset()
	var temporary_scene := Node2D.new()
	get_tree().root.add_child(temporary_scene)
	get_tree().current_scene = temporary_scene
	CombatAudio.play_attack(soldier, skill, victim)
	temporary_scene.free()
	get_tree().current_scene = self
	_check(_voices() == 0, "退出场景清理池中的声音")

	# 捕获专用总线的真实混音，不依赖电脑扬声器。
	_reset()
	var bus_index := AudioServer.get_bus_index(CombatAudio.BUS)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus_index, capture)
	CombatAudio.play_attack(soldier, skill, victim)
	for frame in 24:
		OS.delay_msec(12)
		await get_tree().process_frame
	var buffer := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in buffer:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	_check(buffer.size() > 0 and peak > 0.0001, "实际混音包含非静音音频")
	print("COMBAT_AUDIO_MIX: frames=", buffer.size(), "; peak=", peak)
	AudioServer.remove_bus_effect(bus_index, AudioServer.get_bus_effect_count(bus_index) - 1)
	_reset()
	# stop 后给音频线程和主循环时间释放播放流，避免立即 quit 的引擎退出告警。
	for frame in 6:
		OS.delay_msec(12)
		await get_tree().process_frame
	CombatAudio.settings = original_settings
	for source in sources:
		source.free()
	print("COMBAT_AUDIO_TEST: ", checks, " checks; PASS")
	get_tree().quit()
