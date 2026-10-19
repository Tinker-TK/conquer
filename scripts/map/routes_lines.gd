# 这玩意儿是干嘛的（核心逻辑）：
# 把地图地点之间的路线画成略微弯曲、粗细不一的圆头虚线。
#
# 数据是咋流动的（数据流向）：
# 地图传入每条路线的两个端点 → 计算弯曲路径 →
# 沿路径间隔绘制小线段，组成手绘虚线。
#
# 为啥这么写（选型决策）：
# 使用 Godot 自带绘图，不需要额外图片。
# 每条路线使用固定随机种子，避免重绘时虚线不断抖动。
#
# 性能咋样（复杂度）：
# 只在请求重绘时计算，每条路线通常绘制几十小段；
# 普通章节地图不需要每帧更新。

extends Control

# 灰黑色，带一点透明度，适合浅色纸张背景。
## 地图路线虚线的颜色与透明度；Alpha 越低则路线越淡，只控制连线外观。
@export var line_color: Color = Color(0.24, 0.22, 0.19, 0.60)

## 路线虚线的基础线宽，单位为界面像素；越大则连线越粗，实际绘制带有轻微手绘变化。
@export_range(1.0, 12.0) var line_width: float = 4.0
## 每段实线的基础长度，单位为界面像素；越大则虚线更接近长划线。
@export_range(2.0, 40.0) var dash_length: float = 10.0
## 相邻实线段之间的基础留白长度，单位为界面像素；越大则路线虚线越稀疏。
@export_range(2.0, 40.0) var gap_length: float = 13.0

# 路线中间偏离直线的程度。
## 路线中部偏离端点直线的弯曲幅度，单位为界面像素；0 近似直线，越大则弯曲越明显。
@export_range(0.0, 80.0) var bend_amount: float = 22.0

# 单段虚线的位置轻微偏移，制造手绘不规则感。
## 单段虚线的随机位置扰动幅度，单位为界面像素；0 更规整，越大则手绘不规则感更强。每条路线使用固定随机分布，重绘不会抖动。
@export_range(0.0, 5.0) var roughness: float = 1.2

# 两端留白，避免线条画到地点图标内部。
## 路线两端距地点中心的留白距离，单位为界面像素；越大越避免线条进入图标内部，过大可能使短路线没有可绘制部分。
@export_range(0.0, 120.0) var endpoint_margin: float = 52.0

var routes: Array[PackedVector2Array] = []


# 作用：接收地图的连线端点并刷新画面。
# 参数 new_routes：每项包含起点、终点两个 Vector2。
# 返回值：没有返回值。
func set_routes(new_routes: Array[PackedVector2Array]) -> void:
	routes = new_routes
	queue_redraw()


# 作用：由 Godot 在需要重绘时调用，绘制全部路线。
# 参数：没有参数。
# 返回值：没有返回值。
func _draw() -> void:
	for index in range(routes.size()):
		var route := routes[index]
		if route.size() < 2:
			continue

		_draw_handmade_route(route[0], route[1], index)


# 作用：计算一条弯曲路径，再沿路径绘制虚线。
# 参数 start、end：两个地点的中心坐标。
# 参数 route_index：路线编号，用来保证随机外观稳定。
# 返回值：没有返回值。
func _draw_handmade_route(
	start: Vector2,
	end: Vector2,
	route_index: int
) -> void:
	var distance := start.distance_to(end)

	# 距离太短时不画，避免两端留白后线段反向。
	if distance <= endpoint_margin * 2.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026 + route_index * 7919

	var direction := start.direction_to(end)
	var normal := Vector2(-direction.y, direction.x)

	# 中间控制点向侧面偏移，让路线形成一条浅弧线。
	var control_point := (start + end) * 0.5
	control_point += normal * rng.randf_range(
		-bend_amount,
		bend_amount
	)

	# 把曲线采样成小线段，同时记录累计长度。
	# 后续按真实路径距离安排虚线，间距会比较均匀。
	var points := PackedVector2Array()
	var lengths := PackedFloat32Array()
	var sample_count := maxi(16, int(ceil(distance / 6.0)))
	var total_length := 0.0

	for i in range(sample_count + 1):
		var t := float(i) / float(sample_count)
		var point := start.bezier_interpolate(
			control_point,
			control_point,
			end,
			t
		)

		if i > 0:
			total_length += points[i - 1].distance_to(point)

		points.append(point)
		lengths.append(total_length)

	var cursor := endpoint_margin
	var stop_distance := total_length - endpoint_margin

	while cursor < stop_distance:
		# 长度、间距和粗细仅有小幅变化，保持整体整齐。
		var current_dash := dash_length * rng.randf_range(0.75, 1.25)
		var dash_end := minf(cursor + current_dash, stop_distance)
		var width := line_width * rng.randf_range(0.8, 1.2)

		var from := _point_at_distance(points, lengths, cursor)
		var to := _point_at_distance(points, lengths, dash_end)

		# 两端横向轻微错开，使每一笔不完全机械一致。
		from += normal * rng.randf_range(-roughness, roughness)
		to += normal * rng.randf_range(-roughness, roughness)

		# 小线段加两个圆形端点，形成圆头笔触。
		draw_line(from, to, line_color, width, true)
		draw_circle(from, width * 0.5, line_color, true, -1.0, true)
		draw_circle(to, width * 0.5, line_color, true, -1.0, true)

		cursor = dash_end + gap_length * rng.randf_range(0.8, 1.2)


# 作用：找到沿曲线走指定距离后的位置。
# 参数 points：曲线采样点。
# 参数 lengths：每个采样点对应的累计路径长度。
# 参数 distance：从曲线起点出发的距离。
# 返回值：这段距离对应的地图坐标。
func _point_at_distance(
	points: PackedVector2Array,
	lengths: PackedFloat32Array,
	distance: float
) -> Vector2:
	for i in range(1, points.size()):
		if distance <= lengths[i]:
			var section_length := lengths[i] - lengths[i - 1]
			var weight := (
				(distance - lengths[i - 1])
				/ maxf(section_length, 0.001)
			)
			return points[i - 1].lerp(points[i], weight)

	return points[points.size() - 1]
