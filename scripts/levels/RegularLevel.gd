# RegularLevel.gd
# 模拟原版 RegularLevel 的地图生成器
# 用法：var result = RegularLevel.generate(depth, feeling)
# 返回字典 { "map_data": Array2D, "rooms": Array, "mobs": Array, "items": Array, "traps": Array, "transitions": Array }

extends Level
class_name RegularLevel

# 纯静态地图生成器：唯一对外接口是 static generate()（LevelManager.generate_level 调用）。
# 一度继承 Level（SPD 移植的新层），随新层整体放弃而解除——本文件对 Level 的成员零使用。
#
# 生成顺序：撒房间 → 连房间 → 房间自画地板 + 补走廊门 → 全局水草后处理 → 放怪放物。
# 房间几何归 Room/StandardRoom，连接归 RoomConnection，这里只做编排与全局装饰。

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

# 房间之间、以及房间与图边之间强制留出的空格数（Room.MARGIN 的简写）。
const MARGIN := Room.MARGIN

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

	# 2. 撒房间（不重叠、不贴合）
	var rooms = place_rooms(depth, rng)
	if rooms.is_empty():
		return generate_fallback(depth)

	# 3. 连通房间（近邻 MST 保连通），再给每间补到至少两道门
	var connections = connect_rooms(rooms, rng)
	ensure_two_doors(rooms, connections)

	# 4. 落地板：房间自画矩形，连接处补走廊与门
	paint_rooms(map_data, rooms)
	paint_connections(map_data, connections)

	# 5. 全局装饰：水与草（只铺在 EMPTY 上，不会盖掉门）
	var painter = get_painter(depth, feeling)
	painter.paint(map_data)

	# 6. 放置陷阱
	var traps = place_traps(map_data, depth, rng)

	# 7. 出入口：入口取首间房，出口取离它最远的那间——出入口必须拉开距离，不能开在隔壁。
	# 先占位再放怪放物，免得怪/物落在出入口上。
	var entrance_room: Room = rooms[0]
	var exit_room: Room = farthest_room(entrance_room, rooms)
	var entrance_pos: Vector2i = entrance_room.center()
	var exit_pos: Vector2i = exit_room.center()

	# occupied 记已占用的格子，出入口、怪、物共用同一份，避免同格重叠；格子键是 Vector2i，可直接当字典键。
	var occupied := {}
	occupied[entrance_pos] = true
	occupied[exit_pos] = true

	# 8. 放置怪物
	var mobs = place_mobs(map_data, rooms, entrance_room, depth, rng, occupied)

	# 9. 放置物品
	var items = place_items(map_data, rooms, entrance_room, depth, rng, occupied)

	# 出入口盖回各自的专属地形（前面可能被草/水/陷阱盖过）。ENTRANCE/EXIT 与 EMPTY 同为可走。
	map_data[entrance_pos.y][entrance_pos.x] = ENTRANCE
	map_data[exit_pos.y][exit_pos.x] = EXIT

	# 出入口各建成一个 LevelTransition，dest 由本层深度推导（入口通 depth-1，出口通 depth+1）。
	var transitions = [
		LevelTransition.make(LevelTransition.Type.REGULAR_ENTRANCE, entrance_pos, depth),
		LevelTransition.make(LevelTransition.Type.REGULAR_EXIT, exit_pos, depth),
	]

	return {
		"map_data": map_data,
		"rooms": rooms,
		"mobs": mobs,
		"items": items,
		"traps": traps,
		"transitions": transitions
	}

# ---------- 撒房间 ----------
# 反复随机尺寸与位置，重叠（含 MARGIN 间隔）就丢弃。尺寸区间由 StandardRoom 按档位决定并已按地图夹紧。
static func place_rooms(depth: int, rng: RandomNumberGenerator) -> Array:
	var rooms := []
	var max_rooms = 6 + depth % 3  # 随深度增加
	var attempts = 0

	while rooms.size() < max_rooms and attempts < 300:
		attempts += 1
		var room := StandardRoom.new()
		if not room.set_size():
			continue
		# 左上角取值范围：留出 MARGIN 边距，右/下再留 MARGIN 给邻房。
		var max_x = MAP_WIDTH - room.width() - MARGIN
		var max_y = MAP_HEIGHT - room.height() - MARGIN
		if max_x < MARGIN or max_y < MARGIN:
			continue
		room.set_pos(rng.randi_range(MARGIN, max_x), rng.randi_range(MARGIN, max_y))

		var overlaps = false
		for other in rooms:
			if room.intersects(other, MARGIN):
				overlaps = true
				break
		if not overlaps:
			rooms.append(room)

	# 邻接登记：几何上贴得最近的房间互记（供以后的房间合并/暗门用）。最近间距就是 MARGIN，放宽一格收得更多。
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if rooms[i].gap_to(rooms[j]) <= MARGIN + 1:
				rooms[i].add_neighbour(rooms[j])

	return rooms

# ---------- 房间连接（最小生成树） ----------
# 从 0 号房出发，每次把"离已连通集合最近"的未连通房间接上（Prim 式），保证全图连通；
# 每接一条产出一个 RoomConnection（含 L 形走廊格与两端门格），走廊与门的绘制交给 paint_connections。
# 这里只管连通，不管连接数够不够——那是 ensure_two_doors 的事。
static func connect_rooms(rooms: Array, rng: RandomNumberGenerator) -> Array:
	var connections := []
	if rooms.size() < 2:
		return connections

	var reached := [rooms[0]]
	var pending := rooms.slice(1)

	while not pending.is_empty():
		var best_dist = -1
		var best_a: Room = null
		var best_b: Room = null
		for a in reached:
			for b in pending:
				var dist = a.distance_to(b)
				if best_a == null or dist < best_dist:
					best_dist = dist
					best_a = a
					best_b = b
		if best_b == null:
			break

		var conn = RoomConnection.build(best_a, best_b)
		connections.append(conn)
		best_a.connect_to(best_b)
		best_b.connect_to(best_a)
		reached.append(best_b)
		pending.erase(best_b)

	return connections


# ---------- 每间房至少两道门 ----------
# MST 出来的树必有叶子（只连了一条），叶子房就只有一个门。这里反复给门不够的房间补连接，
# 补到每间都够 2 扇门；补不动就停（房间太少时会补不满，属正常退化）。
static func ensure_two_doors(rooms: Array, connections: Array) -> void:
	var guard = rooms.size() * rooms.size() + 8   # 兜底：每加一条连接就消耗一轮，避免逻辑意外时死循环

	while guard > 0:
		guard -= 1
		var progress := false
		for lacking in rooms:
			if doors_of(lacking, connections).size() >= 2:
				continue
			var best_conn: RoomConnection = null
			var best_dist = 0
			for other in rooms:
				if not lacking.can_connect(other) or lacking.is_connected_to(other):
					continue
				var conn = RoomConnection.build(lacking, other)
				# 必须在这间房上真的新开一扇门。两条走廊若都从同一格穿出，等于没多开门。
				if not is_new_door_for(conn, lacking, connections):
					continue
				var dist = lacking.distance_to(other)
				if best_conn == null or dist < best_dist:
					best_conn = conn
					best_dist = dist
			if best_conn == null:
				continue   # 这间眼下补不动，让同轮的其他房间先连
			connections.append(best_conn)
			var other = best_conn.b if best_conn.a == lacking else best_conn.a
			lacking.connect_to(other)
			other.connect_to(lacking)
			progress = true
		if not progress:
			return   # 整轮没人补得动 → 收工（房间太少时会提前退出，属正常退化）


# 某间房现有的门格（去重）。门格落在房间边框上，两条走廊可能从同一格穿出，故必须去重。
static func doors_of(room: Room, connections: Array) -> Array:
	var out := []
	for conn in connections:
		var cell: Vector2i
		if conn.a == room:
			cell = conn.door_a
		elif conn.b == room:
			cell = conn.door_b
		else:
			continue
		if cell != Vector2i(-1, -1) and not out.has(cell):
			out.append(cell)
	return out


# conn 是以 room 为 a 端造出来的，door_a 就是它给 room 开的那扇门；看这格是不是新的。
static func is_new_door_for(conn: RoomConnection, room: Room, connections: Array) -> bool:
	return not doors_of(room, connections).has(conn.door_a)


# 离 from 最远的房间（中心曼哈顿距离）。出口房用它选，免得出口就开在入口隔壁。
static func farthest_room(from: Room, rooms: Array) -> Room:
	var best: Room = from
	var best_dist = -1
	for room in rooms:
		if room == from:
			continue
		var dist = from.distance_to(room)
		if dist > best_dist:
			best_dist = dist
			best = room
	return best

# ---------- 绘制房间地板 ----------
static func paint_rooms(map_data: Array, rooms: Array) -> void:
	for room in rooms:
		room.paint(map_data)

# ---------- 绘制走廊与门 ----------
# 走廊格全程铺 EMPTY（穿房部分本来就是地板，重复写无妨）；两端门格落在走廊穿出房间的那一格。
static func paint_connections(map_data: Array, connections: Array) -> void:
	for conn in connections:
		for cell in conn.path:
			if in_bounds(cell):
				map_data[cell.y][cell.x] = EMPTY
		if in_bounds(conn.door_a):
			map_data[conn.door_a.y][conn.door_a.x] = DOOR
		if in_bounds(conn.door_b):
			map_data[conn.door_b.y][conn.door_b.x] = DOOR

static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < MAP_WIDTH and cell.y >= 0 and cell.y < MAP_HEIGHT

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

	# 只做全局后处理：把空地随机铺成草或水。房间地板与走廊由 RegularLevel 先画好。
	# 门不是 EMPTY，不受影响；出入口不在这里处理。
	func paint(map_data: Array):
		for y in range(MAP_HEIGHT):
			for x in range(MAP_WIDTH):
				if map_data[y][x] == EMPTY:
					if randf() < grass_chance:
						map_data[y][x] = GRASS
					elif randf() < water_chance:
						map_data[y][x] = WATER

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
				map_data[y][x] = Terrain.TRAP
				traps.append(Vector2i(x, y))
				break
			attempts += 1
	return traps

# ---------- 怪物放置 ----------
static func place_mobs(map_data: Array, rooms: Array, entrance_room: Room, depth: int, rng: RandomNumberGenerator, occupied: Dictionary) -> Array:
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
		if occupied.has(cell):
			continue  # 该格已被出入口、怪或物品占住
		if map_data[cell.y][cell.x] == EMPTY or map_data[cell.y][cell.x] == GRASS:
			occupied[cell] = true
			mobs.append({"pos": cell, "type": "rat", "hp": 8, "atk": 2})
			placed += 1
	return mobs

# ---------- 物品放置 ----------
static func place_items(map_data: Array, rooms: Array, entrance_room: Room, depth: int, rng: RandomNumberGenerator, occupied: Dictionary) -> Array:
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
		if occupied.has(cell):
			continue  # 该格已被出入口、怪或物品占住
		if map_data[cell.y][cell.x] == EMPTY:
			occupied[cell] = true
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
		"transitions": [
			LevelTransition.make(LevelTransition.Type.REGULAR_ENTRANCE, Vector2i(1, 1), depth),
			LevelTransition.make(LevelTransition.Type.REGULAR_EXIT, Vector2i(MAP_WIDTH-2, MAP_HEIGHT-2), depth),
		]
	}
