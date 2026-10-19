# 界面、手牌反馈共用有界播放器池；暂停菜单仍可发声，独立 RNG 不干扰抽牌。
extends Node

signal sound_played(category: StringName, stream: AudioStream)
const BUS := &"UISFX"
var settings = preload("res://data/audio/ui_sounds.tres")
var _players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _last: Dictionary = {}
var _variants: Dictionary = {}
var _semantic_time := -10000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"SFX")
		AudioServer.add_bus_effect(index, AudioEffectLimiter.new())
	for i in settings.max_voices:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_players.append(voice)
	get_tree().node_added.connect(_node_added)
	SceneTransition.started.connect(stop_all)


func _node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button.call_deferred(weakref(node))


func _bind_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as BaseButton
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var callback := _button_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return
	var ancestor: Node = button
	while ancestor != null:
		if ancestor.scene_file_path == "res://examples/scenes/audio_library.tscn" or ancestor.get_meta("mute_ui_audio", false):
			return
		ancestor = ancestor.get_parent()
	var category := StringName(button.get_meta("ui_sound", &""))
	if category == &"silent" or Time.get_ticks_msec() - _semantic_time < 45:
		return
	if category == &"":
		category = &"click"
		var label: String = button.text if button is Button else str(button.name)
		for word in ["取消", "返回", "关闭"]:
			if word in label:
				category = &"cancel"
		for word in ["确认", "确定", "开始战斗", "开始征途", "继续征途", "购买", "领取", "保存"]:
			if word in label:
				category = &"confirm"
	play(category)


func play(category: StringName) -> bool:
	if not settings.enabled:
		return false
	var clips: Variant = settings.get(str(category))
	if not clips is Array or clips.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var interval := 130 if category == &"hover" else 45
	if now - int(_last.get(category, -10000)) < interval:
		return false
	var voice: AudioStreamPlayer
	for player in _players:
		if not player.playing:
			voice = player
			break
	if voice == null:
		if category in [&"hover", &"click", &"card_draw"]:
			return false
		voice = _players[0]
		for player in _players:
			if int(player.get_meta("started", 0)) < int(voice.get_meta("started", 0)):
				voice = player
	var variant := _rng.randi_range(0, clips.size() - 1)
	if clips.size() > 1 and variant == int(_variants.get(category, -1)):
		variant = (variant + 1) % clips.size()
	voice.stop()
	voice.stream = clips[variant]
	voice.volume_db = settings.volume_db - (10.0 if category == &"hover" else 0.0)
	voice.pitch_scale = _rng.randf_range(.975, 1.025)
	voice.set_meta("started", now)
	voice.play()
	_last[category] = now
	_variants[category] = variant
	if category in [&"confirm", &"cancel", &"error", &"upgrade"]:
		_semantic_time = now
	sound_played.emit(category, voice.stream)
	return true


func stop_all() -> void:
	for voice in _players:
		voice.stop()
		voice.stream = null
	_last.clear()
	_semantic_time = -10000
