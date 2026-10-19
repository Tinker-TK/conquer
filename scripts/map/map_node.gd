# 这玩意儿是干嘛的（核心逻辑）：
# 显示一个地图地点。点击后，逐渐显示圈圈图片；
# 圈画完后通知地图进入事件，事件完成后显示旗帜。
#
# 数据是咋流动的（数据流向）：
# Inspector 配置图标和事件编号 → 地图设置是否可以进入 →
# 点击后更新 Shader 的 progress → 动画结束发出进入事件信号 →
# 地图调用 set_completed，让节点显示完成旗帜。
#
# 为啥这么写（选型决策）：
# 用 Shader 揭开现有圈圈素材，可以保留图片的手绘纹理。
# 每个节点复制自己的材质，避免点击一个地点时其他地点一起画圈。
#
# 性能咋样（复杂度）：
# 平时不执行每帧逻辑；点击时只短暂更新一个 Shader 参数，
# 不需要反复创建图片或节点。

extends Control
class_name MapNode

# node_id 是地图地点的唯一编号。
# event_id 指定这个地点对应的战斗、商店或其他事件内容。
## 此地图地点的唯一编号，用于路线连接、当前地点和完成状态记录；同一地图内不得重复。
@export var node_id: String = ""
## 此地点关联的战斗、商店或事件内容编号，进入地点时交给对应系统查找内容；不等同于 Node Id。
@export var event_id: String = ""
## 此地点的图标纹理；配置后覆盖子节点默认图标。地图实例化时也可按地点类型设置图标。
@export var icon_texture: Texture2D
## 地点完成后显示的旗帜纹理；留空沿用子节点默认旗帜，只控制完成标记的外观。
@export var flag_texture: Texture2D

# 从开始画圈到完整显示圈圈所需的时间。
## 点击可进入地点后，选中圈从开始绘制到完整显示的时长，单位为秒；圈画完后才请求进入对应内容。
@export_range(0.05, 3.0, 0.05)
var circle_duration: float = 0.45

# 开始选择时，让地图锁住其他地点。
signal selection_started(node: MapNode)

# 圈画完后，通知地图进入对应事件。
signal enter_requested(node: MapNode)

# 保留当前缩放动画，鼠标快速移入移出时先取消旧动画。
var legend_tween: Tween

enum State {
	IDLE,
	CIRCLING,
	ENTERING,
	COMPLETED
}

var state: State = State.IDLE
var can_enter: bool = false

var circle_tween: Tween
var ring_material: ShaderMaterial

@onready var icon_button: TextureButton = $IconButton
@onready var selection_ring: TextureRect = $SelectionRing
@onready var completed_flag: TextureRect = $CompletedFlag


# 作用：初始化图片和独立材质，由 Godot 在节点准备好时调用。
# 参数：没有参数。
# 返回值：没有返回值。
func _ready() -> void:
	# 如果脚本没有配置图片，就保留子节点上原本设置的图片。
	if icon_texture != null:
		icon_button.texture_normal = icon_texture

	if flag_texture != null:
		completed_flag.texture = flag_texture

	# 圈圈和旗帜只负责显示，不能挡住按钮的鼠标输入。
	selection_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	completed_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 复制材质，让每个地图地点拥有自己的画圈进度。
	var source_material := selection_ring.material as ShaderMaterial

	if source_material != null and source_material.shader != null:
		ring_material = source_material.duplicate() as ShaderMaterial
		selection_ring.material = ring_material
		ring_material.set_shader_parameter("progress", 0.0)
		selection_ring.resized.connect(_sync_circle_size)
		_sync_circle_size()
	else:
		push_error(
			"SelectionRing 需要配置带有 progress 参数的 ShaderMaterial。"
		)

	icon_button.pressed.connect(_on_pressed)

	# 地图可能在节点进入场景树之前就恢复了完成状态。
	selection_ring.visible = false
	completed_flag.visible = state == State.COMPLETED
	_refresh_button()


# 作用：由地图管理器设置这个地点是否可以进入。
# 参数 enabled：true 表示路线允许进入，false 表示不能进入。
# 返回值：没有返回值。
func set_available(enabled: bool) -> void:
	can_enter = enabled

	if is_node_ready():
		_refresh_button()


# 作用：根据路线权限和当前状态，更新按钮是否可以点击。
# 参数：没有参数。
# 返回值：没有返回值。
func _refresh_button() -> void:
	# 正在画圈、已经进入事件或已经完成的地点，都不能重复点击。
	icon_button.disabled = (
		not can_enter
		or state != State.IDLE
		or ring_material == null
	)


# 作用：响应点击，先播放画圈，再通知地图进入事件。
# 参数：没有参数，由 IconButton 的 pressed 信号调用。
# 返回值：没有返回值。
func _on_pressed() -> void:
	if not can_enter or state != State.IDLE:
		return

	if ring_material == null:
		return

	# 立即锁住自身，防止快速点击导致重复播放或重复进入。
	state = State.CIRCLING
	_refresh_button()

	selection_ring.visible = true
	_draw_circle_progress(0.0)

	circle_tween = create_tween()

	# LINEAR 让画圈进度匀速推进。
	circle_tween.set_trans(Tween.TRANS_LINEAR)
	circle_tween.tween_method(
		_draw_circle_progress,
		0.0,
		1.0,
		circle_duration
	)
	circle_tween.finished.connect(_on_circle_finished)

	# 地图收到后，应暂时禁止点击其他地点。
	selection_started.emit(self)


# 作用：将动画进度传入圈圈图片的 Shader。
# 参数 progress：0 表示完全隐藏，1 表示完整显示。
# 返回值：没有返回值，由 Tween 在动画过程中调用。
func _sync_circle_size() -> void:
	if ring_material != null:
		ring_material.set_shader_parameter("draw_size", selection_ring.size)


func _draw_circle_progress(progress: float) -> void:
	if ring_material == null:
		return

	ring_material.set_shader_parameter("progress", progress)


# 作用：画圈结束后，请求地图打开对应事件。
# 参数：没有参数，由 Tween 的 finished 信号调用。
# 返回值：没有返回值。
func _on_circle_finished() -> void:
	# 如果地图已经取消选择或恢复了节点状态，就不再进入事件。
	if state != State.CIRCLING:
		return

	circle_tween = null
	state = State.ENTERING
	_draw_circle_progress(1.0)
	_refresh_button()

	enter_requested.emit(self)


# 作用：设置地点是否完成，也可用于返回地图时恢复旗帜状态。
# 参数 completed：true 显示旗帜，false 恢复普通图标。
# 返回值：没有返回值。
func set_completed(completed: bool) -> void:
	# 恢复状态时停止尚未结束的动画，防止之后又发出进入信号。
	if circle_tween != null:
		circle_tween.kill()
		circle_tween = null

	state = State.COMPLETED if completed else State.IDLE

	# 允许地图先设置状态，再把节点加入场景树。
	if not is_node_ready():
		return

	selection_ring.visible = false
	_draw_circle_progress(0.0)
	completed_flag.visible = completed
	_refresh_button()

# 作用：图例被悬停时放大该地点，离开时恢复。
# 参数 highlighted：true 表示突出显示，false 表示恢复。
# 返回值：没有返回值。
func set_legend_highlight(highlighted: bool) -> void:
	# 以节点中心缩放，保证放大后仍对准原来的地图位置。
	pivot_offset = size * 0.5

	# 防止移入、移出的动画同时争夺 scale。
	if legend_tween != null:
		legend_tween.kill()

	var target_scale := Vector2.ONE
	if highlighted:
		target_scale = Vector2(1.12, 1.12)

	# 放大的节点显示在同级其他节点前面。
	z_index = 1 if highlighted else 0

	legend_tween = create_tween()
	legend_tween.set_trans(Tween.TRANS_QUAD)
	legend_tween.set_ease(Tween.EASE_OUT)
	legend_tween.tween_property(self, "scale", target_scale, 0.15)
