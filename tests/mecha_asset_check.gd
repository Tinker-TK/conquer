# 这玩意儿是干嘛的（核心逻辑）：让引擎实际播放机甲少女的七组动作，检查有没有漏帧和错误循环。
# 数据是咋流动的（数据流向）：读取 SpriteFrames，交给 AnimatedSprite2D 播放，再把观察结果写成 JSON。
# 为啥这么写（选型决策）：直接使用游戏引擎的动画节点，能发现纯图片检查无法发现的资源引用和播放配置问题。
# 性能咋样（复杂度）：仅在手动检查时运行一次，每帧只观察一个动画节点，整个过程约几秒。
extends SceneTree

var failures: Array[String] = []
var results: Array[Dictionary] = []

# 引擎启动时调用，没有参数、没有返回值；延后开始，确保场景树已能容纳动画节点。
func _initialize() -> void:
	_run.call_deferred()

# 没有参数、没有返回值；逐个播放动画并检查边界，结束后用退出码告诉外部工具是否通过。
func _run() -> void:
	# 加载最终交付场景；如果纹理或资源路径错了，这里就会直接发现。
	var packed := load("res://assets/MechaGirl/MechaGirl.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load MechaGirl scene")
		quit(1)
		return
	var sprite := packed.instantiate() as AnimatedSprite2D
	root.add_child(sprite)
	var names := ["idle", "walk", "attack1", "attack2", "shoot", "hurt", "die"]
	var counts := [6, 8, 6, 6, 9, 4, 4]
	# 每组动作都从第一帧起播，循环动作必须绕回第一帧，单次动作必须停在最后一帧。
	for index in range(names.size()):
		var action: String = names[index]
		var expected: int = counts[index]
		var observed: Array[int] = []
		var transitions: Array[int] = []
		var looped := false
		var previous := -1
		var finished := false
		if sprite.sprite_frames.get_frame_count(action) != expected:
			failures.append(action + ": wrong frame count")
		sprite.stop()
		sprite.play(action)
		var start := Time.get_ticks_msec()
		# 三秒是本素材任一动作时长的数倍；超时说明没有按预期结束，避免检查无限等待。
		while Time.get_ticks_msec() - start < 3000:
			var current := sprite.frame
			if not observed.has(current):
				observed.append(current)
			if current != previous:
				transitions.append(current)
			if previous == expected - 1 and current == 0:
				looped = true
			previous = current
			if index < 2 and looped:
				finished = true
				break
			if index >= 2 and not sprite.is_playing():
				finished = true
				break
			await process_frame
		# 单次动作结束后继续等一小段时间，确认死亡等动作不会自行跳回站姿。
		if index >= 2:
			await create_timer(0.15).timeout
			if sprite.frame != expected - 1:
				failures.append(action + ": final frame did not hold")
		if not finished or observed.size() != expected:
			failures.append(action + ": playback incomplete")
		results.append({"animation": action, "expected_frames": expected, "observed_frames": observed, "transitions": transitions, "looped": looped, "completed": finished, "last_frame": sprite.frame})
	# 别名使资源能被原项目的 Soldier 脚本调用，避免换贴图后找不到攻击或死亡动作。
	for alias in ["attack_01", "attack_02", "attack_03", "death"]:
		if not sprite.sprite_frames.has_animation(alias):
			failures.append("Missing alias: " + alias)
	DirAccess.make_dir_recursive_absolute("res://.maintenance")
	var file := FileAccess.open("res://.maintenance/mecha-girl-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "passed": failures.is_empty(), "failures": failures, "animations": results}, "\t"))
	print("MECHA_GIRL_QA ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
