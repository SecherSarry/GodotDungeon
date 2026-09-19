# RegularLevel.gd
# 模拟原版 RegularLevel 的地图生成器
# 用法：var result = RegularLevel.generate(depth, feeling)
# 返回字典 { "map_data": Array2D, "rooms": Array, "mobs": Array, "items": Array, "traps": Array, "entrance": Vector2i, "exit": Vector2i }

extends Node2D
class_name RegularLevel

# 纯静态地图生成器：唯一对外接口是 static generate()（MapManager.generate_level 调用）。
# 一度继承 Level（SPD 移植的新层），随新层整体放弃而解除——本文件对 Level 的成员零使用。

# ---------- 地形常量（数值真相在 Terrain，这里只是简写别名） ----------
const CHASM          := Terrain.CHASM
const EMPTY          := Terrain.EMPTY
const GRASS          := Terrain.GRASS
const EMPTY_WELL     := Terrain.EMPTY_WELL
const WALL           := Terrain.WALL
const DOOR           := Terrain.DOOR
const OPEN_DOOR      := Terrain.OPEN_DOOR
const ENTRANCE       := Terrain.ENTRANCE
const EXIT           := Terrain.EXIT
const EMBERS         := Terrain.EMBERS
const LOCKED_DOOR    := Terrain.LOCKED_DOOR
const WATER          := Terrain.WATER
const HIGH_GRASS     := Terrain.HIGH_GRASS
const FURROWED_GRASS := Terrain.FURROWED_GRASS

# ---------- 地图尺寸 ----------
const MAP_WIDTH  = 30
const MAP_HEIGHT = 20

# ---------- 房间类 ----------
class Room:
	var left: int
	var top: int
	var width: int
	var height: int
	var neighbours: Array = []  # 相邻房间
	var connected: Array = []   # 已连接的房间
	
	func _init(l, t, w, h):
		left = l; top = t; width = w; height = h
	
	func center() -> Vector2i:
		return Vector2i(left + width/2, top + height/2)
	
	func random_point() -> Vector2i:
		return Vector2i(
			randi_range(left + 1, left + width - 2),
			randi_range(top + 1, top + height - 2)
		)
	
	func intersects(other: Room) -> bool:
		# 包含边界重叠检测
		return not (other.left >= left + width or other.left + other.width <= left or
					other.top >= top + height or other.top + other.height <= top)

# ---------- 生成主函数 ----------
static func generate(depth: int = 1, feeling: String = "NORMAL") -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# 1. 初始化地图（全墙壁）
	var map_data = []
	for y in range(MAP_HEIGHT):
		var row = []
		for x in range(MAP_WIDTH):
			row.append(WALL)
		map_data.append(row)
	
	var rooms = []
	
	# 2. 生成房间
	var max_rooms = 6 + depth % 3  # 随深度增加
	var min_room_size = 3
	var max_room_size = 6
	var attempts = 0
	var room_count = 0
	
	var entrance_room: Room = null
	var exit_room: Room = null
	
	while room_count < max_rooms and attempts < 300:
		attempts += 1
		var w = randi_range(min_room_size, max_room_size)
		var h = randi_range(min_room_size, max_room_size)
		var x = randi_range(1, MAP_WIDTH - w - 1)
		var y = randi_range(1, MAP_HEIGHT - h - 1)
		
		var new_room = Room.new(x, y, w, h)
		var overlaps = false
		for room in rooms:
			if new_room.intersects(room):
				overlaps = true
				break
		if not overlaps:
			rooms.append(new_room)
			room_count += 1
			if room_count == 1:
				entrance_room = new_room
			elif room_count == max_rooms:
				exit_room = new_room
	
	# 确保至少有入口和出口
	if entrance_room == null or exit_room == null:
		# 如果房间不够，回退到简单地图
		return generate_fallback(depth)
	
	# 3. 连接房间（简单随机连接，保证连通性）
	connect_rooms(rooms)
	
	# 4. 绘制房间和走廊（使用 Painter）
	var painter = get_painter(depth, feeling)
	painter.paint(map_data, rooms)
	
	# 5. 放置陷阱
	var traps = place_traps(map_data, depth, rng)
	
	# 6. 放置怪物（简化）
	var mobs = place_mobs(map_data, rooms, entrance_room, depth, rng)
	
	# 7. 放置物品（简化）
	var items = place_items(map_data, rooms, entrance_room, depth, rng)
	
	# 8. 设置入口和出口位置
	var entrance_pos = entrance_room.center()
	var exit_pos = exit_room.center()
	
	# 确保入口和出口是空地
	map_data[entrance_pos.y][entrance_pos.x] = EMPTY
	map_data[exit_pos.y][exit_pos.x] = EMPTY
	
	# 在入口和出口标记特殊地形（可选）
	map_data[entrance_pos.y][entrance_pos.x] = EMPTY
	map_data[exit_pos.y][exit_pos.x] = EMPTY
	
	return {
		"map_data": map_data,
		"rooms": rooms,
		"mobs": mobs,
		"items": items,
		"traps": traps,
		"entrance": entrance_pos,
		"exit": exit_pos
	}

# ---------- 房间连接（最小生成树 + 额外随机） ----------
static func connect_rooms(rooms: Array):
	# 使用简单算法：每个房间随机连接到另一个未连接的房间，直到全部连通
	var connected_rooms = []
	var unconnected = rooms.duplicate()
	
	# 从第一个房间开始
	var start = unconnected.pop_front()
	connected_rooms.append(start)
	
	while unconnected.size() > 0:
		var best_dist = INF
		var best_a = null
		var best_b = null
		for a in connected_rooms:
			for b in unconnected:
				var dist = abs(a.center().x - b.center().x) + abs(a.center().y - b.center().y)
				if dist < best_dist:
					best_dist = dist
					best_a = a
					best_b = b
		if best_a != null and best_b != null:
			# 连接两个房间（记录连接）
			best_a.connected.append(best_b)
			best_b.connected.append(best_a)
			# 挖走廊
			var p1 = best_a.center()
			var p2 = best_b.center()
			# 水平或垂直优先（随机）
			if randi() % 2 == 0:
				# 水平优先
				for x in range(min(p1.x, p2.x), max(p1.x, p2.x) + 1):
					# 走廊放在 y1 行
					pass  # 实际绘制在 painter 中处理，这里只记录连接
				for y in range(min(p1.y, p2.y), max(p1.y, p2.y) + 1):
					pass
			else:
				# 垂直优先
				pass
			connected_rooms.append(best_b)
			unconnected.erase(best_b)
		else:
			break  # 防止死循环
	
	# 额外随机连接（增加环）
	for i in range(rooms.size()):
		if randi() % 3 == 0:
			var other = rooms[randi() % rooms.size()]
			if other != rooms[i] and not other in rooms[i].connected:
				rooms[i].connected.append(other)
				other.connected.append(rooms[i])

# ---------- 绘制器（Painter） ----------
static func get_painter(depth: int, feeling: String):
	# 返回一个 Painter 对象，根据深度和感觉定制
	return Painter.new(depth, feeling)

class Painter:
	var depth: int
	var feeling: String
	var water_chance: float
	var grass_chance: float
	
	func _init(d, f):
		depth = d
		feeling = f
		# 根据感觉调整水和草地概率
		match f:
			"WATER":
				water_chance = 0.6
				grass_chance = 0.2
			"GRASS":
				water_chance = 0.2
				grass_chance = 0.6
			_:
				water_chance = 0.25 + depth * 0.05  # 深度加深水更多
				grass_chance = 0.2 + depth * 0.03
	
	func paint(map_data: Array, rooms: Array):
		# 1. 将所有房间内部填充为 EMPTY
		for room in rooms:
			for y in range(room.top, room.top + room.height):
				for x in range(room.left, room.left + room.width):
					map_data[y][x] = EMPTY
		
		# 2. 绘制走廊（基于房间连接）
		for room in rooms:
			for other in room.connected:
				var p1 = room.center()
				var p2 = other.center()
				# 水平优先或垂直优先（随机）
				if randi() % 2 == 0:
					for x in range(min(p1.x, p2.x), max(p1.x, p2.x) + 1):
						map_data[p1.y][x] = EMPTY
					for y in range(min(p1.y, p2.y), max(p1.y, p2.y) + 1):
						map_data[y][p2.x] = EMPTY
				else:
					for y in range(min(p1.y, p2.y), max(p1.y, p2.y) + 1):
						map_data[y][p1.x] = EMPTY
					for x in range(min(p1.x, p2.x), max(p1.x, p2.x) + 1):
						map_data[p2.y][x] = EMPTY
		
		# 3. 添加草地和水
		for y in range(MAP_HEIGHT):
			for x in range(MAP_WIDTH):
				if map_data[y][x] == EMPTY:
					if randf() < grass_chance:
						map_data[y][x] = GRASS
					elif randf() < water_chance:
						map_data[y][x] = WATER
		
		# 4. 放置门（在走廊与房间交界处简化）
		# 原版有复杂的门逻辑，我们简化为：在房间边界与走廊连接的格子设为 DOOR
		for room in rooms:
			var center = room.center()
			# 检查四个方向相邻的走廊
			var dirs = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
			for d in dirs:
				var check = center + d
				if check.x >= 0 and check.x < MAP_WIDTH and check.y >= 0 and check.y < MAP_HEIGHT:
					if map_data[check.y][check.x] == EMPTY and not room_contains(rooms, check):
						# 该格是走廊，设为门
						map_data[check.y][check.x] = EMPTY
		
		# 5. 放置墙壁装饰（可选）
		# 这里省略，可由子类重写
	
	func room_contains(rooms: Array, point: Vector2i) -> bool:
		for room in rooms:
			if point.x >= room.left and point.x < room.left + room.width and point.y >= room.top and point.y < room.top + room.height:
				return true
		return false

# ---------- 陷阱放置 ----------
static func place_traps(map_data: Array, depth: int, rng: RandomNumberGenerator) -> Array:
	var traps = []
	# 简单放置 2~4 个陷阱在空地上
	var count = randi_range(2, 4 + depth / 3)
	for i in range(count):
		var attempts = 0
		while attempts < 100:
			var x = randi_range(1, MAP_WIDTH - 2)
			var y = randi_range(1, MAP_HEIGHT - 2)
			if map_data[y][x] == EMPTY and rng.randf() < 0.5:  # 避免所有空地都放陷阱
				traps.append(Vector2i(x, y))
				# 可选：在地图上标记陷阱类型，这里简化为占位
				break
			attempts += 1
	return traps

# ---------- 怪物放置 ----------
static func place_mobs(map_data: Array, rooms: Array, entrance_room: Room, depth: int, rng: RandomNumberGenerator) -> Array:
	var mobs = []
	var count = 3 + depth % 3 + randi_range(0, 2)
	var placed = 0
	var attempts = 0
	while placed < count and attempts < 200:
		attempts += 1
		var room = rooms[randi() % rooms.size()]
		if room == entrance_room:
			continue  # 不在入口房生成
		var cell = room.random_point()
		if map_data[cell.y][cell.x] == EMPTY or map_data[cell.y][cell.x] == GRASS:
			# 检查是否已被占用（简化，这里只放置位置）
			mobs.append({"pos": cell, "type": "rat", "hp": 8, "atk": 2})
			placed += 1
	return mobs

# ---------- 物品放置 ----------
static func place_items(map_data: Array, rooms: Array, entrance_room: Room, depth: int, rng: RandomNumberGenerator) -> Array:
	var items = []
	var count = 2 + randi_range(0, 3)
	var placed = 0
	var attempts = 0
	while placed < count and attempts < 150:
		attempts += 1
		var room = rooms[randi() % rooms.size()]
		if room == entrance_room:
			continue
		var cell = room.random_point()
		if map_data[cell.y][cell.x] == EMPTY:
			var rad = rng.randf()
			var item_type
			if rad < 0.3:
				item_type = "potion"
			elif rad < 0.6:
				item_type = "gold"
			else:
				item_type = "scroll"
			items.append({"pos": cell, "type": item_type})
			placed += 1
	return items

# ---------- 备用地图（当生成失败时） ----------
static func generate_fallback(depth: int) -> Dictionary:
	var map_data = []
	for y in range(MAP_HEIGHT):
		var row = []
		for x in range(MAP_WIDTH):
			if x == 0 or x == MAP_WIDTH-1 or y == 0 or y == MAP_HEIGHT-1:
				row.append(WALL)
			else:
				row.append(EMPTY)
		map_data.append(row)
	# 增加一些草地
	for y in range(2, MAP_HEIGHT-2, 2):
		for x in range(2, MAP_WIDTH-2, 2):
			map_data[y][x] = GRASS
	return {
		"map_data": map_data,
		"rooms": [],
		"mobs": [],
		"items": [],
		"traps": [],
		"entrance": Vector2i(1, 1),
		"exit": Vector2i(MAP_WIDTH-2, MAP_HEIGHT-2)
	}
