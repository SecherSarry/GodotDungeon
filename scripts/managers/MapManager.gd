extends Node

# ---------- 地形常量 ----------
# 注：FLOOR 与 RegularLevel.EMPTY 同值(=1)。RegularLevel 用 EMPTY 标记可走室内地面，
# MapManager/GameScene 以 FLOOR 识别之；地图数据数值两者一致，可直接混用。
const CHASM       = 0
const FLOOR       = 1
const GRASS       = 2
const EMPTY_WELL  = 3
const WALL        = 4
const DOOR        = 5
const OPEN_DOOR   = 6
const ENTRANCE    = 7
const ENTRANCE_SP = 37
const EXIT        = 8
const EMBERS      = 9
const LOCKED_DOOR = 10
const WATER       = 11   # 水体：浅水可通行（供 WaterLayer 渲染岸线）

# 可通行地形：门/出入口当前无独立美术，均按普通地面可走处理
const WALKABLE_CELLS = [FLOOR, GRASS, WATER, DOOR, OPEN_DOOR, ENTRANCE, EXIT]

# ---------- 地图尺寸 ----------
const MAP_WIDTH  = 30
const MAP_HEIGHT = 20

# ---------- 地图数据 ----------
var map_data = []          # 地形类型（由 RegularLevel 生成）
var visiblity = []         # 当前可见（注意拼写）
var explored  = []         # 已探索

# ---------- 房间列表（RegularLevel.Room 对象） ----------
var rooms = []

# ---------- 实体内容数据（本层出生点/怪物格/物品清单） ----------
var hero_spawn: Vector2i = Vector2i(1, 1)   # 入口（本层出生点）：站此点"上一层"
var exit_cell: Vector2i = Vector2i(-1, -1)  # 出口：站此点"下一层"
var current_depth: int = 1                   # 当前层号
var monster_placements: Array = []          # 每项 {"cell": Vector2i, "data": MonsterData}
var item_placements: Array = []             # 每项 {"cell": Vector2i, "item": Item}

func _ready() -> void:
	generate_level()

# ---------- 生成主入口：交给 RegularLevel 生成，再把结果转成 GameScene 消费的既有结构 ----------
func generate_level(depth: int = 1, feeling: String = "NORMAL") -> void:
	var result: Dictionary = RegularLevel.generate(depth, feeling)
	map_data = result["map_data"]
	rooms = result["rooms"]
	hero_spawn = result["entrance"]
	exit_cell = result["exit"]
	current_depth = depth

	# RegularLevel 的 mobs 是 {"pos": Vector2i, "data": MonsterData} 列表 → 原样收下
	monster_placements.clear()
	for m in result["mobs"]:
		monster_placements.append({ "cell": m["pos"], "data": m["data"] })

	# RegularLevel 的 items 是 {"pos": Vector2i, "type": "potion"/"scroll"} 列表
	# → 转成 {"cell": Vector2i, "item": Item}，item 换成实际 Item 资源
	item_placements.clear()
	for it in result["items"]:
		item_placements.append({ "cell": it["pos"], "item": _make_item(it["type"]) })

	init_fov()

# ---------- 层缓存：离开某层时快照，返回时原样载入（布局/迷雾记忆/剩余怪与掉落物都保留） ----------
# 实体快照（怪的位置与血量、地面物品）由场景层采集后传入——MapManager 只认数据，不认节点。
var floor_cache: Dictionary = {}   # depth -> 快照字典

func save_floor(depth: int, entities: Dictionary) -> void:
	floor_cache[depth] = {
		"map_data": map_data.duplicate(true),
		"rooms": rooms,
		"hero_spawn": hero_spawn,
		"exit_cell": exit_cell,
		"explored": explored.duplicate(true),
		"visiblity": visiblity.duplicate(true),
		"monsters": entities.get("monsters", []),
		"items": entities.get("items", []),
	}

# 进入某层：已有缓存则原样载入并返回 true；否则新生成并返回 false。
func enter_floor(depth: int) -> bool:
	if not floor_cache.has(depth):
		generate_level(depth)
		return false
	var s: Dictionary = floor_cache[depth]
	map_data = s["map_data"]
	rooms = s["rooms"]
	hero_spawn = s["hero_spawn"]
	exit_cell = s["exit_cell"]
	explored = s["explored"]
	visiblity = s["visiblity"]
	current_depth = depth
	return true

# 取当前层已存的实体快照（供场景层重建怪/物）；无快照返回空
func get_floor_entities(depth: int) -> Dictionary:
	if floor_cache.has(depth):
		return floor_cache[depth]
	return {}

# 由 RegularLevel 的类型名构造可用的 Item 资源
func _make_item(type_name: String) -> Item:
	var item
	match type_name:
		"potion":
			item = PotionOfHealing.new()
		"scroll":
			item = ScrollOfMagicMapping.new()
		"gold":
			item = ScrollOfTeleportation.new()
		_:
			item.item_name = type_name
	return item

# ---------- 辅助 ----------
func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
		return false
	return map_data[cell.y][cell.x] in WALKABLE_CELLS

func is_occupied(cell: Vector2i, exclude: Actor = null) -> bool:
	var monster = TurnManager.get_monster_at(cell)
	if monster != null and monster != exclude:
		return true
	return false

# 返回一个随机可走且未被占用的空位；找不到返回 (-1, -1)。用于传送等
func get_random_empty_cell() -> Vector2i:
	for i in 200:
		var cell := Vector2i(randi_range(0, MAP_WIDTH - 1), randi_range(0, MAP_HEIGHT - 1))
		if is_walkable(cell) and not is_occupied(cell):
			return cell
	return Vector2i(-1, -1)

# ---------- 寻路（8 方向 BFS） ----------
const DIRS8 = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

func is_explored(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
		return false
	return explored[cell.y][cell.x]

# 可作为点击目标：已探索格；或"临界未探明格"——尚未探索、可通行、且与任一已探索格相邻。
# 后者允许玩家点着黑暗边缘的相邻格继续走过去（走过去后即揭示），扩大自动行走的可用范围。
func is_walk_target(cell: Vector2i) -> bool:
	if is_explored(cell):
		return true
	if not is_walkable(cell):
		return false
	for d in DIRS8:
		if is_explored(cell + d):
			return true
	return false

# 可寻路格：可通行 +（explored_only 时）已探索 + 未被他人占据。
# explored_only=true 供玩家自动行走（只走己知的路）；怪物 AI 传 false，不受玩家探索范围限制。
func is_pathable(cell: Vector2i, exclude: Char = null, explored_only: bool = true) -> bool:
	if not is_walkable(cell):
		return false
	if explored_only and not explored[cell.y][cell.x]:
		return false
	return not is_occupied(cell, exclude)

# 返回从 from 到 to 的逐步格子序列（不含 from，末元素为终点）；8 方向、斜向可穿墙角（只看目标格）。
# 绕开被占据的格（含目标被占的情况）；若 to 本身不可达，则走向"离 to 最近"的可达格。
# 无处可去时返回空数组。调用方逐步消费 path[0]，每步后重算以应对移动中的怪。
# 通用：英雄自动行走与怪物 AI 都可调用（后者传 explored_only=false）。
func find_path(from: Vector2i, to: Vector2i, exclude: Char = null, explored_only: bool = true) -> Array[Vector2i]:
	var dist := {from: 0}
	var came_from := {}
	var queue: Array[Vector2i] = [from]
	var best_cell := from
	var best_score := _chebyshev(from, to)

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var score = _chebyshev(cur, to)
		if score < best_score:
			best_score = score
			best_cell = cur
		for d in DIRS8:
			var nxt: Vector2i = cur + d
			if dist.has(nxt):
				continue
			var ok := is_pathable(nxt, exclude, explored_only)
			# 例外：终点可为"临界未探明格"——允许踏上它。其余格仍受 explored_only 限制，
			# 故进入终点的 cur 必为已探索格，等价于"仅当终点与已探索区域相邻时才可达"。
			if not ok and nxt == to and is_walkable(nxt) and not is_occupied(nxt, exclude):
				ok = true
			if not ok:
				continue
			dist[nxt] = dist[cur] + 1
			came_from[nxt] = cur
			queue.append(nxt)

	var goal := to if dist.has(to) else best_cell
	if goal == from:
		return []

	var path: Array[Vector2i] = []
	var node := goal
	while node != from:
		path.append(node)
		node = came_from[node]
	path.reverse()
	return path

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

# ---------- 投掷落点 ----------
# 从 from 朝 to 沿直线前进；撞到敌人即落在该敌人脚下（其格子），撞到不可通行格（墙、深渊等）
# 则停在它的前一格；否则落在 to。不检查是否已探索（可投向未知区域）。返回实际落点格。
func throw_landing_cell(from: Vector2i, to: Vector2i) -> Vector2i:
	var landing := from
	var line = get_line(from, to)
	for i in range(1, line.size()):
		var c: Vector2i = line[i]
		if is_occupied(c):
			landing = c   # 路径上有敌人：掉在其脚下
			break
		if not is_walkable(c):
			break   # 撞到墙：留在上一格
		landing = c
	return landing

# ---------- 传送 ----------
# 把 actor 瞬移到随机可走空位（或指定 target_cell）。逻辑与网格权威收在 MapManager（空间数据层），
# 使卷轴等物品只需调 MapManager.teleport，无需直握场景。
# 视觉摆位复用 actor 所在场景的 格子→像素 服务（同 Char.walk_to）。返回给玩家的消息；失败返回空串。
func teleport(actor: Char, target_cell: Vector2i = Vector2i(-1, -1)) -> String:
	if target_cell == Vector2i(-1, -1):
		target_cell = _find_teleport_cell(actor)
		if target_cell == Vector2i(-1, -1):
			return ""
	else:
		if not is_walkable(target_cell) or is_occupied(target_cell):
			return ""
	actor.grid_pos = target_cell
	var gs = actor.game_scene
	if gs != null and gs.has_method("cell_to_world"):
		actor.position = gs.cell_to_world(target_cell)
		if actor is Hero:
			update_fov(target_cell)
	return "{0} 传送至 ({1},{2})".format([actor.name, target_cell.x, target_cell.y])

# 找与 actor 当前位置不同的随机空位
func _find_teleport_cell(actor: Char) -> Vector2i:
	for i in 100:
		var cell := get_random_empty_cell()
		if cell == Vector2i(-1, -1):
			return Vector2i(-1, -1)
		if cell != actor.grid_pos:
			return cell
	return Vector2i(-1, -1)

# ---------- 视野初始化 ----------
func init_fov():
	visiblity = []
	explored = []
	for y in range(MAP_HEIGHT):
		var row_v = []
		var row_e = []
		for x in range(MAP_WIDTH):
			row_v.append(false)
			row_e.append(false)
		visiblity.append(row_v)
		explored.append(row_e)

# ---------- 视野更新（修复：原点可见 + 墙壁可见） ----------
func update_fov(origin: Vector2i, fov_radius: int = 8):
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			visiblity[y][x] = false

	if origin.x >= 0 and origin.x < MAP_WIDTH and origin.y >= 0 and origin.y < MAP_HEIGHT:
		visiblity[origin.y][origin.x] = true
		explored[origin.y][origin.x] = true

	for dy in range(-fov_radius, fov_radius + 1):
		for dx in range(-fov_radius, fov_radius + 1):
			var dist = sqrt(dx*dx + dy*dy)
			if dist > fov_radius:
				continue
			var tx = origin.x + dx
			var ty = origin.y + dy
			if tx < 0 or tx >= MAP_WIDTH or ty < 0 or ty >= MAP_HEIGHT:
				continue
			if tx == origin.x and ty == origin.y:
				continue

			var points = get_line(origin, Vector2i(tx, ty))
			for p in points:
				if p == origin:
					continue
				if map_data[p.y][p.x] == WALL:
					visiblity[p.y][p.x] = true
					explored[p.y][p.x] = true
					break
				visiblity[p.y][p.x] = true
				explored[p.y][p.x] = true

# Bresenham 画线算法
func get_line(from: Vector2i, to: Vector2i) -> Array:
	var points = []
	var x0 = from.x
	var y0 = from.y
	var x1 = to.x
	var y1 = to.y
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return points
