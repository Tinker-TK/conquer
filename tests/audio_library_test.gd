# 单场景试听库：分类完整、点击切换不叠音、搜索收藏持久化，以及每类真实混音输出。
extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("AUDIO_LIBRARY: " + description)


func _mix_frames(count: int) -> void:
	for i in count:
		await process_frame
		OS.delay_msec(12)


func _run() -> void:
	var scene := load("res://examples/scenes/audio_library.tscn") as PackedScene
	_check(scene != null, "F6 scene loads")
	var library = scene.instantiate()
	root.add_child(library)
	current_scene = library
	await process_frame
	_check(library.samples.size() >= 326, "all old and complete Kenney packs collected in one scene")
	for pack in {"kenney_impact": 130, "kenney_rpg": 52}:
		library.set_category(pack)
		_check(library.visible_samples().size() == {"kenney_impact": 130, "kenney_rpg": 52}[pack], "complete local pack: " + pack)
	var audio_paths: Dictionary = {}
	for sample in library.samples:
		_check(not audio_paths.has(sample.stream.resource_path), "no duplicated audio paths")
		audio_paths[sample.stream.resource_path] = true
		_check(sample.stream.get_length() > .02, "playable duration: " + str(sample.name))
		_check(not sample.playing, "no autoplay: " + str(sample.name))
		_check(not str(sample.get_meta("source", "")).is_empty(), "source recorded: " + str(sample.name))
		_check(str(sample.get_meta("license", "")) in ["CC0-1.0", "CC-BY-3.0", "AI-ELEVENLABS", "AI-SUNO"], "license recorded")
	var required := ["kenney_impact", "kenney_rpg", "blade_clash", "hammer_swing", "weapon_swing", "bow_shot", "spell_cast",
		"physical_hit", "magic_hit", "lightning_hit", "fire_hit", "block", "death", "previous",
		"ui", "card", "ai_combat", "music", "ambience"]
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var bus := AudioServer.get_bus_index(&"AudioLibraryPreview")
	AudioServer.add_bus_effect(bus, capture)
	for category in required:
		library.set_category(category)
		var category_samples: Array[AudioStreamPlayer] = library.visible_samples()
		_check(not category_samples.is_empty(), "required category: " + category)
		if category_samples.is_empty():
			continue
		var sample: AudioStreamPlayer = category_samples[0]
		capture.clear_buffer()
		# Exercise the real button signal used when clicking the row in F6.
		library.sample_buttons[sample].pressed.emit()
		_check(library.selected_sample == sample and sample.playing, "click starts selected sound")
		await _mix_frames(28)
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		_check(peak > .0001, category + " produces audible samples; peak=" + str(peak))
		library.stop_preview()
		await _mix_frames(6)
		print("AUDIO_LIBRARY_CAPTURE: %s peak=%.5f frames=%d" % [category, peak, frames.size()])
	# Capture every new design through the same player and bus as an F6 click.
	library.set_category("latest")
	var batch: Array[AudioStreamPlayer] = library.visible_samples()
	_check(batch.size() == int(library.get_meta("audition_count", 0)) and batch.size() >= 2,
		"latest listening batch is complete and contains comparison candidates")
	var batch_paths: Dictionary = {}
	for sample in batch:
		batch_paths[sample.stream.resource_path] = true
		capture.clear_buffer()
		library.sample_buttons[sample].pressed.emit()
		await _mix_frames(16)
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		_check(peak > .0001, "new batch audible: " + sample.stream.resource_path)
		library.stop_preview()
		await _mix_frames(3)
	library.set_category("music")
	for sample in library.visible_samples():
		if batch_paths.has(sample.stream.resource_path):
			library.play_sample(sample)
			library._set_loop(true)
			_check(sample.stream.loop, "new music supports seamless player looping")
			library._set_loop(false)
			_check(not sample.stream.loop, "loop can be disabled for transition listening")
	library.stop_preview()
	library.set_category("ai_combat")
	for sample in library.visible_samples():
		if str(sample.get_meta("provider", "")) == "elevenlabs":
			capture.clear_buffer()
			library.sample_buttons[sample].pressed.emit()
			await _mix_frames(16)
			var frames := capture.get_buffer(capture.get_frames_available())
			var peak := 0.0
			for frame in frames:
				peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			_check(peak > .0001, "downloaded ElevenLabs candidate produces real mixed audio")
			_check(str(sample.get_meta("license", "")) == "AI-ELEVENLABS", "AI source license remains separate")
			library.stop_preview()
	AudioServer.remove_bus_effect(bus, 1)
	library.set_category("blade_clash")
	var matching: Array[AudioStreamPlayer] = library.visible_samples()
	library.play_sample(matching[0])
	library.play_sample(matching[1])
	_check(not matching[0].playing and matching[1].playing, "switching stops previous sound")
	library._set_volume(-20)
	library._set_pitch(.75)
	_check(is_equal_approx(matching[1].volume_db, -20) and is_equal_approx(matching[1].pitch_scale, .75), "live volume and pitch adjustment")
	library.stop_preview()
	_check(library.playing_sample == null and not matching[1].playing, "stop preview")
	library.favorites.clear()
	library._toggle_favorite(matching[0])
	library._favorites_only.button_pressed = true
	_check(library.visible_samples().size() == 1, "favorite filter")
	library._favorites_only.button_pressed = false
	library._search.text = "不存在的试听音效"
	_check(library.visible_samples().is_empty(), "search has empty state")
	library._search.text = "北欧剑"
	_check(library.visible_samples().size() == 4, "Chinese title search")
	library._search.text = "norse_sword"
	_check(library.visible_samples().size() == 4, "original filename search")
	library._search.text = ""
	var saved_path: String = matching[0].stream.resource_path
	await _mix_frames(6)
	library.queue_free()
	await process_frame
	_check(AudioServer.get_bus_index(&"AudioLibraryPreview") == -1, "preview bus cleaned up")
	var reopened = scene.instantiate()
	root.add_child(reopened)
	current_scene = reopened
	await process_frame
	_check(reopened.favorites.has(saved_path), "favorites persist between F6 runs")
	_check(is_equal_approx(reopened.volume_db, -20) and is_equal_approx(reopened.preview_pitch, .75), "preview settings persist")
	# Leave the isolated test profile at normal defaults for repeatable graphical QA.
	reopened.favorites.clear()
	reopened._set_volume(-8)
	reopened._set_pitch(1)
	reopened.queue_free()
	await _mix_frames(6)
	print("AUDIO_LIBRARY_TEST: %d checks; %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)
