# 四层地形各自拥有碰撞和导航图；重叠的桥上/桥下不会连接成同一条路。
# 入场时从实际瓦片烘焙一次，寻路只在楼梯连接点之间查询，不逐帧重建地图。
extends NavigationRegion2D

const FLOOR_COUNT := 4
const TERRAIN_MASK := 0b1111000 # 物理层 4~7。
const UNIT_MASK := 0b11110000000 # 物理层 8~11。
const TEAM_MASK := 0b11
const FLIGHT_FLOOR_HEIGHT := 64.0
const FLIGHT_SURFACE_CELL := 128.0

## 四个可行走楼层，顺序对应单位的 Floor Id 1~4。
@export var floor_layer_paths: Array[NodePath] = [NodePath("Layer01"), NodePath("Layer02"), NodePath("Layer03"), NodePath("Layer04")]
## 同层的附属瓦片层，例如坡道。主 Layer 下的子 TileMapLayer 会自动归入该层。
@export var floor_1_extra_layers: Array[NodePath] = []
@export var floor_2_extra_layers: Array[NodePath] = [NodePath("stair02")]
@export var floor_3_extra_layers: Array[NodePath] = [NodePath("stair03")]
@export var floor_4_extra_layers: Array[NodePath] = [NodePath("stair04")]
## 导航与瓦片边缘/障碍之间的留白，需至少容纳普通单位的身体半径。
@export_range(1.0, 64.0, 1.0) var floor_agent_radius: float = 24.0
## 每层的绘制间隔；地面单位保持 Z=0，上层地形可遮住下层单位。
@export_range(32, 256, 1) var floor_z_stride: int = 64

var floor_layers: Array[TileMapLayer] = []
var floor_maps: Array[RID] = []
var floor_regions: Array[NavigationRegion2D] = []
var transitions: Array[Node2D] = []
var _route_cache: Dictionary = {}
var _floor_tile_layers: Dictionary = {}
var _flight_surfaces: Dictionary = {}


func _ready() -> void:
	# 旧地图可能留下已从图集中删除的格子。只清理本次场景实例，避免解析导航时报错。
	for node in find_children("*", "TileMapLayer", true, false):
		_remove_invalid_cells(node)
	for index in FLOOR_COUNT:
		var layer := get_node_or_null(floor_layer_paths[index]) as TileMapLayer if index < floor_layer_paths.size() else null
		floor_layers.append(layer)
		var layers: Array[TileMapLayer] = []
		_collect_tile_layers(layer, layers)
		var extra_paths: Array = [floor_1_extra_layers, floor_2_extra_layers, floor_3_extra_layers, floor_4_extra_layers][index]
		for path in extra_paths:
			_collect_tile_layers(get_node_or_null(path) as TileMapLayer, layers)
		_floor_tile_layers[index + 1] = layers
		for tile_layer in layers:
			if tile_layer.tile_set == null:
				continue
			# 附属层和主层共用楼层位；先复制资源，防止同一 TileSet 被别层改写。
			tile_layer.tile_set = tile_layer.tile_set.duplicate(true)
			for physics_index in tile_layer.tile_set.get_physics_layers_count():
				tile_layer.tile_set.set_physics_layer_collision_layer(physics_index, terrain_bit(index + 1))
				tile_layer.tile_set.set_physics_layer_collision_mask(physics_index, 0)
			tile_layer.navigation_enabled = false
			# 子瓦片层不能再次累加父 Layer 的楼层 Z，坡道画在本层地面上方。
			tile_layer.z_as_relative = false
			tile_layer.z_index = (index * floor_z_stride) - 20 + (0 if tile_layer == layer else 1)
			tile_layer.update_internals()
	for floor_id in range(1, FLOOR_COUNT + 1):
		var map := get_world_2d().navigation_map if floor_id == 1 else NavigationServer2D.map_create()
		if floor_id != 1:
			NavigationServer2D.map_set_active(map, true)
			NavigationServer2D.map_set_cell_size(map, 1.0)
		floor_maps.append(map)
		var region: NavigationRegion2D = self if floor_id == 1 else NavigationRegion2D.new()
		if region != self:
			region.name = "Floor%02dNavigation" % floor_id
			add_child(region)
		region.set_navigation_map(map)
		region.navigation_polygon = _bake_floor(floor_id)
		floor_regions.append(region)
	for node in find_children("*", "Area2D", true, false):
		if node.has_method("destination_floor"):
			transitions.append(node)


func _collect_tile_layers(layer: TileMapLayer, result: Array[TileMapLayer]) -> void:
	if layer == null or result.has(layer):
		return
	result.append(layer)
	for child in layer.find_children("*", "TileMapLayer", true, false):
		if not result.has(child):
			result.append(child)


func _remove_invalid_cells(layer: TileMapLayer) -> void:
	if layer.tile_set == null:
		return
	for cell in layer.get_used_cells():
		var source_id := layer.get_cell_source_id(cell)
		if not layer.tile_set.has_source(source_id):
			layer.erase_cell(cell)
			continue
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		var coords := layer.get_cell_atlas_coords(cell)
		var alternative := layer.get_cell_alternative_tile(cell) & ~(TileSetAtlasSource.TRANSFORM_FLIP_H \
			| TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE)
		if not source.has_tile(coords) or not source.has_alternative_tile(coords, alternative):
			layer.erase_cell(cell)
	layer.update_internals()


func _exit_tree() -> void:
	# 默认 World2D 导航图归场景所有，只释放本系统建立的上层图。
	for index in range(1, floor_maps.size()):
		NavigationServer2D.free_rid(floor_maps[index])


static func terrain_bit(floor_id: int) -> int:
	return 1 << (clampi(floor_id, 1, FLOOR_COUNT) + 2)


static func unit_bit(floor_id: int) -> int:
	return 1 << (clampi(floor_id, 1, FLOOR_COUNT) + 6)


func get_floor_map(floor_id: int) -> RID:
	return floor_maps[floor_id - 1] if floor_id >= 1 and floor_id <= floor_maps.size() else RID()


# 天气等地表效果共用楼层归属和绘制高度，不使用导航烘焙范围判断地面。
func get_tile_layer_floor(layer: TileMapLayer) -> int:
	for floor_id in _floor_tile_layers:
		if _floor_tile_layers[floor_id].has(layer):
			return floor_id
	return 1


func get_floor_z_index(floor_id: int) -> int:
	return (floor_id - 1) * floor_z_stride


func _bake_floor(floor_id: int) -> NavigationPolygon:
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = floor_agent_radius
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	# entity 为共用实体障碍；旧 Collision 容器中的 land 障碍属于第一层。
	polygon.parsed_collision_mask = terrain_bit(floor_id) | 4
	var source := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(polygon, source, self)
	for layer: TileMapLayer in _floor_tile_layers.get(floor_id, []):
		if not layer.enabled or layer.tile_set == null:
			continue
		var transform_to_region := global_transform.affine_inverse() * layer.global_transform
		for cell in layer.get_used_cells():
			if layer.get_cell_tile_data(cell) == null:
				continue
			for surface in _cell_surfaces(layer, cell):
				var outline := transform_to_region * surface
				source.add_traversable_outline(outline)
				_index_flight_surface(floor_id, layer, outline)
	# 没有地面瓦片的旧场景仍允许使用手绘导航外轮廓。
	if floor_id == 1 and source.get_traversable_outlines().is_empty() and navigation_polygon != null:
		for index in navigation_polygon.get_outline_count():
			polygon.add_outline(navigation_polygon.get_outline(index))
			_index_flight_surface(floor_id, null, navigation_polygon.get_outline(index))
	if not source.get_traversable_outlines().is_empty() or polygon.get_outline_count() > 0:
		NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	return polygon


# 合并图块只保存一个地图格的 ID，但绘制范围可能跨多格；按真实尺寸与原点计算地面。
# 显式的瓦片导航多边形优先，可用它排除斜坡图片的透明三角和岩壁立面。
func _cell_surfaces(layer: TileMapLayer, cell: Vector2i) -> Array[PackedVector2Array]:
	var data := layer.get_cell_tile_data(cell)
	var alternative := layer.get_cell_alternative_tile(cell)
	var flip_h := bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_H)
	var flip_v := bool(alternative & TileSetAtlasSource.TRANSFORM_FLIP_V)
	var transpose := bool(alternative & TileSetAtlasSource.TRANSFORM_TRANSPOSE)
	if layer.tile_set.get_navigation_layers_count() > 0:
		var navigation := data.get_navigation_polygon(0, flip_h, flip_v, transpose)
		if navigation != null and navigation.get_polygon_count() > 0:
			var surfaces: Array[PackedVector2Array] = []
			for polygon_index in navigation.get_polygon_count():
				var surface := PackedVector2Array()
				for vertex_index in navigation.get_polygon(polygon_index):
					surface.append(layer.map_to_local(cell) + navigation.get_vertices()[vertex_index])
				surfaces.append(surface)
			return surfaces
		if navigation != null and navigation.get_outline_count() == 1:
			var outline := navigation.get_outline(0)
			for index in outline.size():
				outline[index] += layer.map_to_local(cell)
			return [outline]
	var atlas := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	var size := Vector2(layer.tile_set.tile_size)
	if atlas != null:
		size = Vector2(atlas.get_tile_texture_region(layer.get_cell_atlas_coords(cell)).size)
	if data.transpose:
		size = Vector2(size.y, size.x)
	var half := size * 0.5
	var points := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	for index in points.size():
		var point := points[index] - Vector2(data.texture_origin)
		if transpose:
			point = Vector2(point.y, point.x)
		if flip_h:
			point.x = -point.x
		if flip_v:
			point.y = -point.y
		points[index] = layer.map_to_local(cell) + point
	return [points]


# 保留当前楼层优先，避免点击桥的投影就把桥下单位自动抬上桥。
func floor_at(point: Vector2, preferred: int = 1, floor_step: int = 0) -> int:
	# 重叠位置可显式指定上一层/下一层，避免鼠标只有 XY 时无法表达桥上目标。
	if floor_step != 0:
		var direction := 1 if floor_step > 0 else -1
		for floor_id in range(preferred + direction, FLOOR_COUNT + 1 if direction > 0 else 0, direction):
			if is_walkable(point, floor_id):
				return floor_id
		return preferred
	if is_walkable(point, preferred):
		return preferred
	for floor_id in range(FLOOR_COUNT, 0, -1):
		if is_walkable(point, floor_id):
			return floor_id
	return preferred


# 波次只保存 XY 站位时按最上方地面认层。直接使用地表轮廓，首轮无需等待导航同步，
# 也不会因导航为身体半径留白而把靠近高地边缘的出生点误判到下层。
func spawn_floor_at(point: Vector2) -> int:
	for floor_id in range(FLOOR_COUNT, 0, -1):
		if _has_flight_surface(point, floor_id):
			return floor_id
	return 1


func is_walkable(point: Vector2, floor_id: int, tolerance: float = 2.0) -> bool:
	var map := get_floor_map(floor_id)
	return map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 \
		and floor_regions[floor_id - 1].navigation_polygon.get_polygon_count() > 0 \
		and not NavigationServer2D.map_get_regions(map).is_empty() \
		and NavigationServer2D.map_get_closest_point(map, point).distance_to(point) <= tolerance


# 强制位移使用真实地表边界，不能把导航为身体预留的空隙当作墙体。
func has_ground_at(point: Vector2, floor_id: int) -> bool:
	return _has_flight_surface(point, floor_id)


# 飞行按原始地面轮廓认层，不受导航留白、墙体或断路影响。桶索引只检查附近瓦片。
func _index_flight_surface(floor_id: int, layer: TileMapLayer, polygon: PackedVector2Array) -> void:
	if polygon.is_empty():
		return
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var start := Vector2i((bounds.position / FLIGHT_SURFACE_CELL).floor())
	var finish := Vector2i((bounds.end / FLIGHT_SURFACE_CELL).floor())
	for y in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			var key := Vector3i(x, y, floor_id)
			if not _flight_surfaces.has(key):
				_flight_surfaces[key] = []
			_flight_surfaces[key].append({"layer": layer, "polygon": polygon})


func _has_flight_surface(world_point: Vector2, floor_id: int) -> bool:
	var point := to_local(world_point)
	var cell := Vector2i((point / FLIGHT_SURFACE_CELL).floor())
	for surface: Dictionary in _flight_surfaces.get(Vector3i(cell.x, cell.y, floor_id), []):
		var layer: TileMapLayer = surface.layer
		if layer != null and (not layer.enabled or not layer.is_visible_in_tree()):
			continue
		if Geometry2D.is_point_in_polygon(point, surface.polygon):
			return true
	return false


# 将各层投影回同一地面平面；升降改变显示坐标，不会把移动方向拉回悬崖边。
func flight_floor_at_ground(ground_point: Vector2) -> int:
	for floor_id in range(FLOOR_COUNT, 0, -1):
		if _has_flight_surface(ground_point - Vector2.DOWN * (floor_id - 1) * FLIGHT_FLOOR_HEIGHT, floor_id):
			return floor_id
	return 1


func flight_destination_floor(point: Vector2, preferred: int = 1, floor_step: int = 0) -> int:
	if floor_step != 0:
		var direction := 1 if floor_step > 0 else -1
		for floor_id in range(preferred + direction, FLOOR_COUNT + 1 if direction > 0 else 0, direction):
			if _has_flight_surface(point, floor_id):
				return floor_id
	if _has_flight_surface(point, preferred):
		return preferred
	for floor_id in range(FLOOR_COUNT, 0, -1):
		if _has_flight_surface(point, floor_id):
			return floor_id
	return 1


# 下落完成后身体仍可能横跨岩壁；包含本层下方 64 像素的立面，直到整段身体飞离才降绘制层。
func flight_overlaps_floor(world_bounds: Rect2, floor_id: int) -> bool:
	world_bounds.position.y -= FLIGHT_FLOOR_HEIGHT
	world_bounds.size.y += FLIGHT_FLOOR_HEIGHT
	var bounds := global_transform.affine_inverse() * world_bounds
	var outline := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	var start := Vector2i((bounds.position / FLIGHT_SURFACE_CELL).floor())
	var finish := Vector2i((bounds.end / FLIGHT_SURFACE_CELL).floor())
	for y in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			for surface: Dictionary in _flight_surfaces.get(Vector3i(x, y, floor_id), []):
				var layer: TileMapLayer = surface.layer
				if layer != null and (not layer.enabled or not layer.is_visible_in_tree()):
					continue
				if not Geometry2D.intersect_polygons(outline, surface.polygon).is_empty():
					return true
	return false


func apply_unit_floor(unit: CharacterBody2D) -> void:
	var floor_id: int = unit.floor_id
	# 阵营位继续留给技能 Area 查询；身体只检测本层单位位，避免隔着桥互相阻挡。
	unit.collision_layer = (unit.collision_layer & ~UNIT_MASK) | (0 if unit.unit_data.is_flying else unit_bit(floor_id))
	unit.collision_mask = 0 if unit.unit_data.is_flying else \
		(unit.collision_mask & ~(TERRAIN_MASK | UNIT_MASK | TEAM_MASK)) | terrain_bit(floor_id) | unit_bit(floor_id)
	unit.z_index = (floor_id - 1) * floor_z_stride
	var agent: NavigationAgent2D = unit.get_node_or_null("NavigationAgent2D")
	if agent != null:
		agent.set_navigation_map(get_floor_map(floor_id))
		agent.avoidance_layers = 1 << (floor_id - 1)
		agent.avoidance_mask = 1 << (floor_id - 1)
		if agent.has_method("reset_after_teleport"):
			agent.reset_after_teleport()


# 每层内仍由 Godot 求最短路；楼层之间只通过显式楼梯连接点。
func path_distance(start: Vector2, finish: Vector2, floor_id: int) -> float:
	var map := get_floor_map(floor_id)
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return INF
	var path := NavigationServer2D.map_get_path(map, start, finish, true)
	# 出生点可能暂时在网格外；允许投影到附近边缘，但不能把断开的岛屿误判为可达。
	if path.is_empty() or path[path.size() - 1].distance_to(NavigationServer2D.map_get_closest_point(map, finish)) > 4.0:
		return INF
	var distance := start.distance_to(path[0])
	for index in range(1, path.size()):
		distance += path[index - 1].distance_to(path[index])
	return distance + path[path.size() - 1].distance_to(finish)


# Dijkstra 在入口/出口图上规划，可经过多段楼梯。缓存固定端点之间的楼层内距离。
func route(start: Vector2, from_floor: int, finish: Vector2, to_floor: int) -> Dictionary:
	var points: Array[Vector2] = [start, finish]
	var floors: Array[int] = [from_floor, to_floor]
	var links: Array[Node2D] = [null, null]
	for link in transitions:
		if not is_instance_valid(link) or not link.enabled:
			continue
		if not is_walkable(link.entry_point(link.from_floor), link.from_floor, 4.0) \
			or not is_walkable(link.entry_point(link.to_floor), link.to_floor, 4.0):
			continue
		points.append(link.entry_point(link.from_floor))
		points.append(link.entry_point(link.to_floor))
		floors.append(link.from_floor)
		floors.append(link.to_floor)
		links.append(link)
		links.append(link)
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for index in points.size():
		distances.append(0.0 if index == 0 else INF)
		previous.append(-1)
		visited.append(false)
	for step in points.size():
		var current := -1
		for index in points.size():
			if not visited[index] and distances[index] < INF and (current == -1 or distances[index] < distances[current]):
				current = index
		if current == -1 or current == 1:
			break
		visited[current] = true
		for next in points.size():
			if visited[next] or current == next:
				continue
			var cost := INF
			if floors[current] == floors[next]:
				var key := "%d:%s:%s" % [floors[current], points[current], points[next]]
				if current >= 2 and next >= 2 and _route_cache.has(key):
					cost = _route_cache[key]
				else:
					cost = path_distance(points[current], points[next], floors[current])
					if current >= 2 and next >= 2:
						_route_cache[key] = cost
			elif current >= 2 and next >= 2 and links[current] == links[next] \
				and links[current].destination_floor(floors[current]) == floors[next]:
				cost = points[current].distance_to(points[next]) + 0.01
			if distances[current] + cost < distances[next]:
				distances[next] = distances[current] + cost
				previous[next] = current
	if distances[1] == INF:
		return {}
	var chain: Array[int] = [1]
	while previous[chain[0]] > 0:
		chain.push_front(previous[chain[0]])
	var transition: Node2D = null
	for index in range(chain.size() - 1):
		if floors[chain[index]] != floors[chain[index + 1]]:
			transition = links[chain[index]]
			break
	return {"distance": distances[1], "transition": transition}
