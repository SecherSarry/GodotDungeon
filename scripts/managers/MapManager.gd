extends Node

# ---------- 地形常量 ----------
# 数值真相统一在 Terrain（地形 id + 标志位都在那儿）。这里只是别名，不再各自维护字面量——
# 否则改一处漏一处。名称保持不变，GameScene 等调用点零改动。
# 注：FLOOR 与 Terrain.EMPTY 同值(=1)——RegularLevel 用 EMPTY 标记可走室内地面，
# MapManager/GameScene 以 FLOOR 识别之，是同一格地形。
const CHASM       := Terrain.CHASM
const FLOOR       := Terrain.EMPTY
const GRASS       := Terrain.GRASS
const EMPTY_WELL  := Terrain.EMPTY_WELL
const WALL        := Terrain.WALL
const DOOR        := Terrain.DOOR
const OPEN_DOOR   := Terrain.OPEN_DOOR
const ENTRANCE    := Terrain.ENTRANCE
const ENTRANCE_SP = 37   # Terrain 中无对应；当前无任何代码使用
const EXIT        := Terrain.EXIT
const EMBERS      := Terrain.EMBERS
const LOCKED_DOOR := Terrain.LOCKED_DOOR
const WATER       := Terrain.WATER   # 水体：浅水可通行（供 WaterLayer 渲染岸线）

# ---------- 地图尺寸 ----------
const MAP_WIDTH  = 30
const MAP_HEIGHT = 20

# ---------- 地图数据 ----------
var map_data = []          # 地形类型（由 RegularLevel 生成）
var explored  = []         # 已探索（累计）。当前可见（FOV）已归各 Char 自管，见 Char.fieldofview

# ---------- 房间列表（RegularLevel.Room 对象） ----------
var rooms = []

# ---------- 实体内容数据（本层出生点/怪物格/物品清单） ----------
var hero_spawn: Vector2i = Vector2i(1, 1)   # 入口（本层出生点）：站此点"上一层"
var exit_cell: Vector2i = Vector2i(-1, -1)  # 出口：站此点"下一层"
var current_depth: int = 1                   # 当前层号
var monster_cells: Array[Vector2i] = []     # 本层怪物放置格
var item_placements: Array = []             # 每项 {"cell": Vector2i, "item": Item}

func _ready() -> void:
	# 寻路缓冲按地图尺寸一次性分配。尺寸是常量、跨层不变，故只需一次。
	Pathfinding.set_map_size(MAP_WIDTH, MAP_HEIGHT)
	generate_level()

# ---------- 生成主入口：交给 RegularLevel 生成，再把结果转成 GameScene 消费的既有结构 ----------
func generate_level(depth: int = 1, feeling: String = "NORMAL") -> void:
	var result: Dictionary = RegularLevel.generate(depth, feeling)
	map_data = result["map_data"]
	rooms = result["rooms"]
	hero_spawn = result["entrance"]
	exit_cell = result["exit"]
	current_depth = depth

	# RegularLevel 的 mobs 是 {"pos": Vector2i, ...} 列表 → 取 pos 放入 Array[Vector2i]
	monster_cells.clear()
	for m in result["mobs"]:
		monster_cells.append(m["pos"])

	# RegularLevel 的 items 是 {"pos": Vector2i, "type": "potion"/"scroll"} 列表
	# → 转成 {"cell": Vector2i, "item": Item}，item 换成实际 Item 资源
	item_placements.clear()
	for it in result["items"]:
		item_placements.append({ "cell": it["pos"], "item": _make_item(it["type"]) })

	init_explored()

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
	return Terrain.has_flag(map_data[cell.y][cell.x], Terrain.FLAG_PASSABLE)

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

# ---------- 8 方向邻居偏移 ----------
# 寻路本体已移到 Pathfinding；这里只留给 is_walk_target 判定"临界未探明格"。
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

# ---------- 寻路（Pathfinding 适配） ----------
# 算法本体在 Pathfinding（SPD 的扁平索引 + 距离图实现）。它只认"索引 + 可通行位图"，
# 不认识 Vector2i / map_data / 已探索 / 占位，故下面三个函数是两边之间的桥。
# 唯一调用方是 Char.next_step_to（英雄自动行走与怪物追踪共用）。
func to_index(cell: Vector2i) -> int:
	return cell.y * MAP_WIDTH + cell.x

func to_cell(index: int) -> Vector2i:
	return Vector2i(index % MAP_WIDTH, index / MAP_WIDTH)

# 可通行位图：1=可走。语义同原来的 is_pathable——
# 可通行 +（explored_only 时）已探索 + 未被他人占据。
# explored_only=true 供玩家自动行走（只走己知的路）；怪物 AI 传 false，不受玩家探索范围限制。
# 每次寻路现算：地图、探索、占位每回合都在变，缓存必然失效。
func build_passable(exclude: Char = null, explored_only: bool = true) -> PackedByteArray:
	var passable := PackedByteArray()
	passable.resize(MAP_WIDTH * MAP_HEIGHT)
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			var cell := Vector2i(x, y)
			var ok := is_walkable(cell)
			if ok and explored_only and not explored[y][x]:
				ok = false
			if ok and is_occupied(cell, exclude):
				ok = false
			passable[y * MAP_WIDTH + x] = 1 if ok else 0
	return passable

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
			# 视野立即按落点重算（fieldofview 取自身 grid_pos，即刚落到的 target_cell），
			# 并落账进 explored——否则英雄会站在一片未探明的格子里
			actor.fieldofview()
			record_sight(actor.FOV)
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

# ---------- 已探索图初始化 ----------
# 只建 explored：当前可见（FOV）已归各 Char 自管，见 Char.fieldofview。
func init_explored():
	explored = []
	for y in range(MAP_HEIGHT):
		var row_e = []
		for x in range(MAP_WIDTH):
			row_e.append(false)
		explored.append(row_e)

# ---------- 记录视野：把一份可见网格并入已探索 ----------
# explored 是「这张地图被看过的地方」，属地图级事实，故留在这里——寻路 build_passable、
# is_explored / is_walk_target 都读它，还按层缓存在 floor_cache。
# 谁看得见什么由各 Char 自己的 FOV 决定；英雄算完视野后由 GameScene 调本函数落账。
# 怪算视野不会走到这里，也就不会替玩家点亮地图。
func record_sight(grid: Array) -> void:
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			if grid[y][x]:
				explored[y][x] = true

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
