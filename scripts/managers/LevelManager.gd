extends Node

# 层数据与换层编排：这一层"是什么"——地形、迷雾、出入口、实体清单、内存层缓存，
# 以及生成 / 存档快照 / 进层这三个只读写这份数据的动作。
# 空间查询与算法（能不能走、可见性、寻路桥、画线）在 MapManager，它只读这里的数据。
# 本文件不碰任何节点：实体快照由场景采集后传入，视图重建由场景自己做。

# ---------- 地图尺寸 ----------
const MAP_WIDTH  = 30
const MAP_HEIGHT = 20

# ---------- 当前层：每层的全部数据（地形/迷雾/房间/出入口/实体）都收在 Level 里 ----------
var level: Level = Level.new()

# ---------- 当前深度：真相源在 GameState ----------
var current_depth: int:
	get:
		return GameState.depth
	set(value):
		GameState.depth = value

# ---------- 层缓存：离开某层时的内存快照 ----------
var floor_cache: Dictionary = {}   # depth -> Level


func _ready() -> void:
	# 寻路缓冲按地图尺寸一次性分配。尺寸是常量、跨层不变，故只需一次。
	Pathfinding.set_map_size(MAP_WIDTH, MAP_HEIGHT)
	# 这里**不**生成地图：本 autoload 先于任何场景就绪，此刻 GameState.depth 还是初值，
	# 按它生成会做一层马上被丢掉的活。真正的生成/载入由 GameState.new_game / load_game
	# 在深度定下来之后调（新档 generate_level，读取 enter_floor）。
	# 代价：单独运行 GameScene.tscn（F6）时没有地图数据——正常入口是 TitleScene（主场景）。


# ---------- 开一局前的清场 ----------
# 由 GameState._reset_run 调用。地形 / 迷雾 / 房间 / 实体清单全部丢弃，重开一局从零开始。
# floor_cache 必须清：它记的是"这一局走过哪些层"，跨局留着会把上一局的层当成这一局的。
func reset() -> void:
	level = Level.new()
	floor_cache.clear()


# ---------- 生成主入口 ----------
func generate_level(depth: int = -1, feeling: String = "NORMAL") -> void:
	if depth == -1:
		depth = GameState.depth
	var result: Dictionary = RegularLevel.generate(depth, feeling)
	var lv := Level.new()
	lv.map_data = result["map_data"]
	lv.rooms = result["rooms"]
	lv.transitions = result["transitions"]

	for m in result["mobs"]:
		lv.monster_cells.append(m["pos"])

	for it in result["items"]:
		lv.drop_item(_make_item(it["type"]), it["pos"])

	lv.explored = _blank_explored()
	level = lv
	current_depth = depth


# ---------- 层缓存：内存快照 ----------

## 由场景层采集实体快照后传入——这里只认数据，不认节点。
## 当前层的 Level 直接进缓存：调用方随即离开该层，指针交给缓存后不再改动。
func save_floor(depth: int, entities: Dictionary) -> void:
	level.monsters = entities.get("monsters", [])
	level.heaps = entities.get("heaps", [])
	floor_cache[depth] = level


## 进入某层：已有缓存则原样载入并返回 true；否则新生成并返回 false。
func enter_floor(depth: int) -> bool:
	if not floor_cache.has(depth):
		generate_level(depth)
		return false
	level = floor_cache[depth]
	current_depth = depth
	return true


## 取某层已存的实体快照（供场景层重建怪/物）；无快照返回空
func get_floor_entities(depth: int) -> Dictionary:
	if floor_cache.has(depth):
		var lv: Level = floor_cache[depth]
		return { "monsters": lv.monsters, "heaps": lv.heaps }
	return {}


# ---------- 磁盘边界：floor_cache ↔ JSON ----------
# floor_cache 里，地面物品保持原形（一格一个 Heap：pos = Vector2i，items = Item 实例），
# 落盘/读盘时才转换；怪则直接存 mob.serialize() 的字典（本就是 JSON 安全的），
# 落盘原样透传、读回原样透传，于是内存形与磁盘形对怪是同一份——场景 _render_monsters_from
# 直接拿它喂 Mob.from_data。

# Vector2i 进不了 JSON，一律拆成 [x, y]。楼层与物品堆共用这一对，别在各调用点各写一遍。
func cell_to_arr(cell: Vector2i) -> Array:
	return [cell.x, cell.y]

func arr_to_cell(arr) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))


## 把 floor_cache[depth] 转成可进 JSON 的字典。层不在缓存里返回空。
func serialize_floor(depth: int) -> Dictionary:
	if not floor_cache.has(depth):
		return {}
	var lv: Level = floor_cache[depth]
	var heaps := []
	for h: Heap in lv.heaps:
		heaps.append(h.serialize())
	var transitions := []
	for t in lv.transitions:
		transitions.append(_transition_to_data(t))
	return {
		"map_data": lv.map_data,
		"transitions": transitions,
		"explored": lv.explored,
		"monsters": lv.monsters,   # 已是 mob.serialize() 的 JSON 安全字典，原样透传
		"heaps": heaps,
	}


func _transition_to_data(t: LevelTransition) -> Dictionary:
	return {
		"type": t.type,
		"cell": cell_to_arr(t.cell),
		"dest_depth": t.dest_depth,
		"dest_branch": t.dest_branch,
		"dest_type": t.dest_type,
	}


func _transition_from_data(d: Dictionary) -> LevelTransition:
	return LevelTransition.new(
		int(d.get("type", 0)),
		arr_to_cell(d.get("cell", [0, 0])),
		int(d.get("dest_depth", -1)),
		int(d.get("dest_branch", 0)),
		int(d.get("dest_type", -1))
	)


## 由磁盘字典还原一层进 floor_cache（内存原形，供 enter_floor 载入）。
## 逐处 int() 归一：JSON 数字读回来一律是 float，而地形要喂 Terrain.has_flag 的位运算——
## 留着 float 会静默算错。怪不必在这里转换（Mob.from_data 在场景侧重建时自己归一）。
func deserialize_floor(depth: int, data: Dictionary) -> void:
	var heaps := []
	for hd in data.get("heaps", []):
		var h: Heap = Heap.from_data(hd)
		if h != null and not h.is_empty():
			heaps.append(h)
	var transitions := []
	for td in data.get("transitions", []):
		transitions.append(_transition_from_data(td))
	var lv := Level.new()
	lv.map_data = _int_grid(data.get("map_data", []))
	lv.transitions = transitions
	lv.explored = data.get("explored", [])
	lv.monsters = data.get("monsters", [])   # 已是 JSON 安全字典，原样透传
	lv.heaps = heaps
	floor_cache[depth] = lv


# 二维地形数组逐格 int()：JSON 数字是 float，位运算要 int。
func _int_grid(grid: Array) -> Array:
	var out := []
	for row in grid:
		var r := []
		for v in row:
			r.append(int(v))
		out.append(r)
	return out


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
func _blank_explored() -> Array:
	var grid := []
	for y in range(MAP_HEIGHT):
		var row_e = []
		for x in range(MAP_WIDTH):
			row_e.append(false)
		grid.append(row_e)
	return grid


# ---------- 视野 observe ----------
# SPD Dungeon.observe()（Dungeon.java:897）的数据侧：重算英雄 FOV → 灵视叠层 → 落账进已探索 →
# 贴身 9 格无条件记入。场景侧（画迷雾、刷实体可见性）由 GameScene.observe 收尾——
# manager 不碰节点，故那边只能"调一次本函数再自己渲染"。
# 每回合开头（Hero.act）与换层后各走一次，于是边走边开图（原版同）。
func observe() -> void:
	var hero = GameState.hero
	hero.fieldofview()                              # = level.updateFieldOfView：只写 hero.FOV
	_reveal_by_mind_vision(hero)
	MapManager.record_sight(hero.FOV)               # = BArray.or(visited, heroFOV)：落账进已探索
	MapManager.record_adjacent(hero.grid_pos)       # = 贴身 NEIGHBOURS9 那行：脚下 3x3 无条件算走过


# 灵视：把每个生物及其九宫格补进英雄视野（fieldofview 每次先清空 FOV 再重算，
# 故 buff 一掉，这些格自然恢复黑暗；explored 已记下，地形仍留在迷雾记忆中）。
func _reveal_by_mind_vision(hero) -> void:
	if not hero.has_buff(MindVision):
		return
	var cells := []
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			cells.append(mob.grid_pos)
	hero.reveal_around(cells, MindVision.RADIUS)


# ---------- 换层 ----------
# 对齐原版的两级结构：descend/ascend 是 InterlevelScene.descend/ascend 的对应物（存旧层 + 定目标层 + 定落点），
# switch_level 是 Dungeon.switchLevel 的对应物（只装层 + 世界接线）。
# 触发链：Hero.act_transition → GameScene.activate_transition（按类型选 descend/ascend）→ 这里。

# 由"踩到的 transition"驱动换层。entities：离开层的实体快照（场景采集传入——这里只认数据）。
# 成功返回 { "landing": Vector2i }；到顶返回空字典。不消耗回合。
# descend/ascend 只差方向名（原版两方法体也近乎相同），真正读的是 transition.dest_depth。
func descend(transition: LevelTransition, entities: Dictionary) -> Dictionary:
	return _traverse(transition, entities)

func ascend(transition: LevelTransition, entities: Dictionary) -> Dictionary:
	return _traverse(transition, entities)

func _traverse(transition: LevelTransition, entities: Dictionary) -> Dictionary:
	var dest_depth: int = transition.dest_depth
	if dest_depth < 1:
		print("已经是地牢顶层，无法再向上")
		return {}
	var left_depth = GameState.depth
	# 离开前先把本层快照进 floor_cache（含迷雾记忆与剩余怪/掉落物），回来时原样载入、不重掷地图。
	save_floor(left_depth, entities)
	# 离开的层即刻落盘：换层是天然的安全落盘点，此刻存档能扛住中途崩溃。
	# 须在改深度之前（serialize_floor 读的就是刚写好 floor_cache[left_depth]）。
	# 只在已有主档时才写：还没存过档就落楼层，会留下没有主档的孤儿 floor_*.json。
	if SaveManager.has_save(SaveManager.cur_slot):
		SaveManager.write_floor(SaveManager.cur_slot, left_depth, serialize_floor(left_depth))
	# 定目标深度/支线（原版 InterlevelScene 在切场景前就改好 Dungeon.depth/branch），再载入或生成。
	GameState.depth = dest_depth
	GameState.branch = transition.dest_branch
	var target := _load_or_generate(dest_depth)
	# 落点：由源 transition 的 dest_type 在目标层上查到对应出入口（进出对称）；查不到则退回入口。
	var dest_trans := target.get_transition(transition.dest_type)
	var landing: Vector2i = dest_trans.cell if dest_trans != null else target.entrance()
	switch_level(target, landing)
	print("进入第 ", dest_depth, " 层")
	return { "landing": landing }


# 目标层已有内存缓存则原样载入，否则新生成（原版：levelHasBeenGenerated ? loadLevel : newLevel）。
func _load_or_generate(depth: int) -> Level:
	if floor_cache.has(depth):
		return floor_cache[depth]
	generate_level(depth)
	return level


# Dungeon.switchLevel 的对应物：把给定 Level 装进来并做世界接线，不碰存/生成。
# 本工程数据侧的世界接线：装层、英雄落点、视野半径、清当前动作、时间轴归零（玩家先动）。
# 原版其余几步按数据/场景分工分散在别处，不在本函数：
#   FOV observe()     → GameScene.rebuild_level 里的 observe()
#   挪开同格怪         → GameScene.rebuild_level 里的 _displace_mobs_from_hero()（要动表现节点）
#   saveAll()         → _traverse 里离开层的落盘 + 手动存档（GameState.save_game）
func switch_level(level: Level, pos: Vector2i) -> void:
	self.level = level
	GameState.hero.grid_pos = pos
	GameState.hero.cur_action = null
	GameState.hero.reset_timeline()
	GameState.hero.view_distance = level.view_distance
