extends Node

# 层数据与换层编排：这一层"是什么"——地形、迷雾、出入口、实体清单、内存层缓存，
# 以及生成 / 存档快照 / 进层这三个只读写这份数据的动作。
# 空间查询与算法（能不能走、可见性、寻路桥、画线）在 MapManager，它只读这里的数据。
# 本文件不碰任何节点：实体快照由场景采集后传入，视图重建由场景自己做。

# ---------- 地图尺寸 ----------
const MAP_WIDTH  = 30
const MAP_HEIGHT = 20

# ---------- 地图数据 ----------
var map_data = []          # 地形类型（二维 int）
var explored  = []         # 已探索（二维 bool）

# ---------- 房间列表 ----------
var rooms = []             # Room 对象列表（仅生成期使用）

# ---------- 实体内容数据 ----------
var hero_spawn: Vector2i = Vector2i(1, 1)
var exit_cell: Vector2i = Vector2i(-1, -1)
var monster_cells: Array[Vector2i] = []
var item_placements: Array = []   # 每项 {"cell": Vector2i, "item": Item}

# ---------- 当前深度：真相源在 GameState ----------
var current_depth: int:
	get:
		return GameState.depth
	set(value):
		GameState.depth = value

# ---------- 层缓存：离开某层时的内存快照 ----------
var floor_cache: Dictionary = {}   # depth -> 快照字典


func _ready() -> void:
	# 寻路缓冲按地图尺寸一次性分配。尺寸是常量、跨层不变，故只需一次。
	Pathfinding.set_map_size(MAP_WIDTH, MAP_HEIGHT)
	# 进入游戏先尝试读档（当前深度的磁盘存档 → 本层状态 + 内存缓存）；读不到才现生成。
	# 这样"继续游戏"能接上次离开的那一层，新档（无存档）行为不变。
	if not SaveManager.load_current_map():
		generate_level(GameState.depth)


# ---------- 生成主入口 ----------
func generate_level(depth: int = -1, feeling: String = "NORMAL") -> void:
	if depth == -1:
		depth = GameState.depth
	var result: Dictionary = RegularLevel.generate(depth, feeling)
	map_data = result["map_data"]
	rooms = result["rooms"]
	hero_spawn = result["entrance"]
	exit_cell = result["exit"]
	current_depth = depth

	monster_cells.clear()
	for m in result["mobs"]:
		monster_cells.append(m["pos"])

	item_placements.clear()
	for it in result["items"]:
		item_placements.append({ "cell": it["pos"], "item": _make_item(it["type"]) })

	init_explored()


# ---------- 层缓存：内存快照 ----------

## 由场景层采集实体快照后传入——这里只认数据，不认节点
func save_floor(depth: int, entities: Dictionary) -> void:
	floor_cache[depth] = {
		"map_data": map_data.duplicate(true),
		"hero_spawn": hero_spawn,
		"exit_cell": exit_cell,
		"explored": explored.duplicate(true),
		"monsters": entities.get("monsters", []),
		"items": entities.get("items", []),
	}


## 进入某层：已有缓存则原样载入并返回 true；否则新生成并返回 false。
func enter_floor(depth: int) -> bool:
	if not floor_cache.has(depth):
		generate_level(depth)
		return false
	var s: Dictionary = floor_cache[depth]
	map_data = s["map_data"]
	hero_spawn = s["hero_spawn"]
	exit_cell = s["exit_cell"]
	explored = s["explored"]
	current_depth = depth
	return true


## 取某层已存的实体快照（供场景层重建怪/物）；无快照返回空
func get_floor_entities(depth: int) -> Dictionary:
	if floor_cache.has(depth):
		return floor_cache[depth]
	return {}


# ---------- 由 RegularLevel 的类型名构造 Item 资源 ----------
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
			item = Item.new()
			item.item_name = type_name
	return item


# ---------- 已探索图初始化 ----------
func init_explored():
	explored = []
	for y in range(MAP_HEIGHT):
		var row_e = []
		for x in range(MAP_WIDTH):
			row_e.append(false)
		explored.append(row_e)


# ---------- 换层 ----------
# depth 为目标层绝对深度（默认下一层）。到顶则拒绝，返回空字典。
# entities: 离开层的实体快照（由场景采集传入——这里只认数据）。
# 成功返回 { "landing": Vector2i, "restored": bool }。
#
# 离开前先把本层快照进 floor_cache（含迷雾记忆与剩余怪/掉落物），
# 返回时原样载入，因此来回跑不会重掷地图。不消耗回合。
# 不放在按键上——换层本就带着"本层收尾、下层开张"的完整现场，是天然的安全落盘点。
func switch_level(depth: int = GameState.depth+1, entities: Dictionary = {}, branch: int = 0) -> Dictionary:
	if depth < 1:
		print("已经是地牢顶层，无法再向上")
		return {}
	var left_depth = GameState.depth
	# 上行/下行须在 enter_floor 之前判定：enter_floor 会把 GameState.depth 改成 depth，
	# 之后再比就恒为 0，上楼也会错落到入口。
	var going_up = depth < left_depth
	save_floor(left_depth, entities)
	SaveManager.save_map(left_depth)          # 离开的层落盘（须在 enter_floor 改深度之前）
	SaveManager.cache_map_from_disk(depth)   # 目标层有存档则预载进缓存 → enter_floor 走"返回"分支
	var restored = enter_floor(depth)
	# 落点：下楼/新层 → 该层入口；上楼回访 → 该层出口（即当初下来所走的台阶），进出对称。
	var landing = exit_cell if going_up else hero_spawn
	print("进入第 ", depth, " 层", "（返回）" if restored else "")
	return { "landing": landing, "restored": restored }
