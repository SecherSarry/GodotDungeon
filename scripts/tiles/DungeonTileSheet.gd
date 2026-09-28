class_name DungeonTileSheet
extends RefCounted

# SPD 的 DungeonTileSheet 直译。
#
# 坐标换算：SPD 通篇用线性序号 xy(x,y) = (x-1) + 16*(y-1)，本工程一律改写成图集坐标
#   Vector2i(x-1, y-1) = Vector2i(序号 % 16, 序号 / 16)
# 每个块上面标的 `xy(a,b) = N → (c,r)` 就是换算来源，方便对着 DungeonTileSheet.java 复查。
# WIDTH 只为对照 SPD 保留——本工程有了 Vector2i 就不再拿它算序号。
const WIDTH := 16
const NULL_TILE := Vector2i(-1, -1)

# ---------- 地面 ----------  GROUND = xy(1,1) = 0 → (0,0)
const GROUND         := Vector2i(0, 0)
const FLOOR          := GROUND + Vector2i(0, 0)
const FLOOR_DECO     := GROUND + Vector2i(1, 0)
const GRASS          := GROUND + Vector2i(2, 0)
const EMBERS         := GROUND + Vector2i(3, 0)
const FLOOR_SP       := GROUND + Vector2i(4, 0)
const FLOOR_ALT_1    := GROUND + Vector2i(6, 0)
const FLOOR_DECO_ALT := GROUND + Vector2i(7, 0)
const GRASS_ALT      := GROUND + Vector2i(8, 0)
const EMBERS_ALT     := GROUND + Vector2i(9, 0)
const FLOOR_SP_ALT   := GROUND + Vector2i(10, 0)
const FLOOR_ALT_2    := GROUND + Vector2i(12, 0)

const ENTRANCE       := GROUND + Vector2i(0, 1)
const EXIT           := GROUND + Vector2i(1, 1)
const WELL           := GROUND + Vector2i(2, 1)
const EMPTY_WELL     := GROUND + Vector2i(3, 1)
const PEDESTAL       := GROUND + Vector2i(4, 1)
const ENTRANCE_SP    := GROUND + Vector2i(6, 1)

# ---------- 深渊 ----------  CHASM = xy(9,2) = 24 → (8,1)
const CHASM          := Vector2i(8, 1)
const CHASM_FLOOR    := CHASM + Vector2i(1, 0)
const CHASM_FLOOR_SP := CHASM + Vector2i(2, 0)
const CHASM_WALL     := CHASM + Vector2i(3, 0)
const CHASM_WATER    := CHASM + Vector2i(4, 0)

# ---------- 水 ----------  WATER = xy(1,3) = 32 → (0,2)
# 本工程的水岸线走 Godot 原生 terrain（见 GameScene.init_water_layer），故没有 stitch_water_tile。
# SPD 的 waterStitcheable / stitchWaterTile 不在此移植。
const WATER          := Vector2i(0, 2)

# ---------- 平铺墙 ----------  FLAT_WALLS = xy(1,4) = 48 → (0,3)
const FLAT_WALLS         := Vector2i(0, 3)
const FLAT_WALL          := FLAT_WALLS + Vector2i(0, 0)
const FLAT_WALL_DECO     := FLAT_WALLS + Vector2i(1, 0)
const FLAT_BOOKSHELF     := FLAT_WALLS + Vector2i(2, 0)
const FLAT_WALL_ALT      := FLAT_WALLS + Vector2i(4, 0)
const FLAT_WALL_DECO_ALT := FLAT_WALLS + Vector2i(5, 0)
const FLAT_BOOKSHELF_ALT := FLAT_WALLS + Vector2i(6, 0)
const FLAT_DOOR          := FLAT_WALLS + Vector2i(8, 0)
const FLAT_DOOR_OPEN     := FLAT_WALLS + Vector2i(9, 0)
const FLAT_DOOR_LOCKED   := FLAT_WALLS + Vector2i(10, 0)
const FLAT_DOOR_CRYSTAL  := FLAT_WALLS + Vector2i(11, 0)
const UNLOCKED_EXIT      := FLAT_WALLS + Vector2i(12, 0)
const LOCKED_EXIT        := FLAT_WALLS + Vector2i(13, 0)

# ---------- 平铺杂物 ----------  FLAT_OTHER = xy(1,5) = 64 → (0,4)
const FLAT_OTHER           := Vector2i(0, 4)
const FLAT_ALCHEMY_POT     := FLAT_OTHER + Vector2i(0, 0)
const FLAT_BARRICADE       := FLAT_OTHER + Vector2i(1, 0)
const FLAT_HIGH_GRASS      := FLAT_OTHER + Vector2i(2, 0)
const FLAT_FURROWED_GRASS  := FLAT_OTHER + Vector2i(3, 0)
const FLAT_HIGH_GRASS_ALT  := FLAT_OTHER + Vector2i(5, 0)
const FLAT_FURROWED_ALT    := FLAT_OTHER + Vector2i(6, 0)
const FLAT_STATUE          := FLAT_OTHER + Vector2i(8, 0)
const FLAT_STATUE_SP       := FLAT_OTHER + Vector2i(9, 0)
const FLAT_REGION_DECO     := FLAT_OTHER + Vector2i(10, 0)
const FLAT_REGION_DECO_ALT := FLAT_OTHER + Vector2i(11, 0)
const FLAT_MINE_CRYSTAL    := FLAT_OTHER + Vector2i(12, 0)
const FLAT_MINE_CRYSTAL_ALT   := FLAT_OTHER + Vector2i(13, 0)
const FLAT_MINE_CRYSTAL_ALT_2 := FLAT_OTHER + Vector2i(14, 0)
const FLAT_MINE_BOULDER       := FLAT_OTHER + Vector2i(12, 0)
const FLAT_MINE_BOULDER_ALT   := FLAT_OTHER + Vector2i(13, 0)
const FLAT_MINE_BOULDER_ALT_2 := FLAT_OTHER + Vector2i(14, 0)

# ---------- 直接映射 ----------
const DIRECT_VISUALS := {
	Terrain.EMPTY:              FLOOR,
	Terrain.GRASS:              GRASS,
	Terrain.EMPTY_WELL:         EMPTY_WELL,
	Terrain.ENTRANCE:           ENTRANCE,
	Terrain.EXIT:               EXIT,
	Terrain.EMBERS:             EMBERS,
	Terrain.PEDESTAL:           PEDESTAL,
	Terrain.EMPTY_SP:           FLOOR_SP,
	Terrain.ENTRANCE_SP:        ENTRANCE_SP,
	# 陷阱与自定义装饰无独立美术，直接铺地板（同 SPD `directVisuals.get(Terrain.EMPTY)`）
	Terrain.SECRET_TRAP:        FLOOR,
	Terrain.TRAP:               FLOOR,
	Terrain.INACTIVE_TRAP:      FLOOR,
	Terrain.CUSTOM_DECO:        FLOOR,
	Terrain.CUSTOM_DECO_EMPTY:  FLOOR,
	Terrain.EMPTY_DECO:         FLOOR_DECO,
	Terrain.LOCKED_EXIT:        LOCKED_EXIT,
	Terrain.UNLOCKED_EXIT:      UNLOCKED_EXIT,
	Terrain.WELL:               WELL,
}

# ---------- 平铺映射（地形按平面显示时用） ----------
const DIRECT_FLAT_VISUALS := {
	Terrain.WALL:           FLAT_WALL,
	Terrain.DOOR:           FLAT_DOOR,
	Terrain.OPEN_DOOR:      FLAT_DOOR_OPEN,
	Terrain.LOCKED_DOOR:    FLAT_DOOR_LOCKED,
	Terrain.HERO_LKD_DR:    FLAT_DOOR_LOCKED,
	Terrain.CRYSTAL_DOOR:   FLAT_DOOR_CRYSTAL,
	Terrain.WALL_DECO:      FLAT_WALL_DECO,
	Terrain.BOOKSHELF:      FLAT_BOOKSHELF,
	Terrain.ALCHEMY:        FLAT_ALCHEMY_POT,
	Terrain.BARRICADE:      FLAT_BARRICADE,
	Terrain.HIGH_GRASS:     FLAT_HIGH_GRASS,
	Terrain.FURROWED_GRASS: FLAT_FURROWED_GRASS,
	Terrain.STATUE:         FLAT_STATUE,
	Terrain.STATUE_SP:      FLAT_STATUE_SP,
	Terrain.REGION_DECO:    FLAT_REGION_DECO,
	Terrain.REGION_DECO_ALT: FLAT_REGION_DECO_ALT,
	Terrain.MINE_CRYSTAL:   FLAT_MINE_CRYSTAL,
	Terrain.MINE_BOULDER:   FLAT_MINE_BOULDER,
	Terrain.SECRET_DOOR:    FLAT_WALL,
}

# ---------- 凸起墙（下层） ----------  RAISED_WALLS = xy(1,6) = 80 → (0,5)
# +1 右侧开口，+2 左侧开口（两个 bit 由 get_raised_wall_tile 叠加）
const RAISED_WALL               := Vector2i(0, 5)
const RAISED_WALL_DECO          := Vector2i(4, 5)
const RAISED_WALL_DOOR          := Vector2i(8, 5)
const RAISED_WALL_BOOKSHELF     := Vector2i(12, 5)
const RAISED_WALL_ALT           := Vector2i(0, 6)
const RAISED_WALL_DECO_ALT      := Vector2i(4, 6)
const RAISED_WALL_BOOKSHELF_ALT := Vector2i(12, 6)

# ---------- 凸起门 ----------  RAISED_DOORS = xy(1,8) = 112 → (0,7)
const RAISED_DOORS          := Vector2i(0, 7)
const RAISED_DOOR           := RAISED_DOORS + Vector2i(0, 0)
const RAISED_DOOR_OPEN      := RAISED_DOORS + Vector2i(1, 0)
const RAISED_DOOR_LOCKED    := RAISED_DOORS + Vector2i(2, 0)
const RAISED_DOOR_CRYSTAL   := RAISED_DOORS + Vector2i(3, 0)
const RAISED_DOOR_SIDEWAYS  := RAISED_DOORS + Vector2i(4, 0)

# ---------- 凸起杂物 ----------  RAISED_OTHER = xy(9,8) = 120 → (8,7)
# 注意：SPD 的 +8 起是线性偏移，块首落在第 8 列，故 +8 会折到图集下一行行首，不是同行第 16 列。
const RAISED_OTHER           := Vector2i(8, 7)
const RAISED_ALCHEMY_POT     := RAISED_OTHER + Vector2i(0, 0)
const RAISED_BARRICADE       := RAISED_OTHER + Vector2i(1, 0)
const RAISED_HIGH_GRASS      := RAISED_OTHER + Vector2i(2, 0)
const RAISED_FURROWED_GRASS  := RAISED_OTHER + Vector2i(3, 0)
const RAISED_HIGH_GRASS_ALT  := RAISED_OTHER + Vector2i(5, 0)
const RAISED_FURROWED_ALT    := RAISED_OTHER + Vector2i(6, 0)
const RAISED_STATUE          := Vector2i(0, 8)
const RAISED_STATUE_SP       := Vector2i(1, 8)
const RAISED_REGION_DECO     := Vector2i(2, 8)
const RAISED_REGION_DECO_ALT := Vector2i(3, 8)
const RAISED_MINE_CRYSTAL    := Vector2i(4, 8)
const RAISED_MINE_CRYSTAL_ALT   := Vector2i(5, 8)
const RAISED_MINE_CRYSTAL_ALT_2 := Vector2i(6, 8)
# 巨石与水晶共用一套图（同 SPD 两者同号）
const RAISED_MINE_BOULDER       := RAISED_MINE_CRYSTAL
const RAISED_MINE_BOULDER_ALT   := RAISED_MINE_CRYSTAL_ALT
const RAISED_MINE_BOULDER_ALT_2 := RAISED_MINE_CRYSTAL_ALT_2

# ---------- 内部墙（上层） ----------  WALLS_INTERNAL = xy(1,10) = 144 → (0,9)
# +1 右侧开口，+2 右下开口，+4 左下开口，+8 左侧开口
const WALLS_INTERNAL       := Vector2i(0, 9)
const WALL_INTERNAL        := WALLS_INTERNAL + Vector2i(0, 0)
const WALL_INTERNAL_DECO   := WALLS_INTERNAL + Vector2i(0, 1)
const WALL_INTERNAL_WOODEN := WALLS_INTERNAL + Vector2i(0, 2)

# ---------- 墙根悬垂 ----------  WALLS_OVERHANG = xy(1,13) = 192 → (0,12)
# 画在"正下方是墙"的那一格上：墙的投影压在下方格顶端。+1 右下开口，+2 左下开口
const WALLS_OVERHANG                := Vector2i(0, 12)
const WALL_OVERHANG                 := WALLS_OVERHANG + Vector2i(0, 0)
const WALL_OVERHANG_DECO            := WALLS_OVERHANG + Vector2i(4, 0)
const WALL_OVERHANG_WOODEN          := WALLS_OVERHANG + Vector2i(8, 0)
const DOOR_SIDEWAYS_OVERHANG        := WALLS_OVERHANG + Vector2i(0, 1)
const DOOR_SIDEWAYS_OVERHANG_CLOSED := WALLS_OVERHANG + Vector2i(4, 1)
const DOOR_SIDEWAYS_OVERHANG_LOCKED := WALLS_OVERHANG + Vector2i(8, 1)
const DOOR_SIDEWAYS_OVERHANG_CRYSTAL := WALLS_OVERHANG + Vector2i(12, 1)

# ---------- 门顶悬垂 ----------  DOOR_OVERHANG = xy(1,15) = 224 → (0,14)
const DOOR_OVERHANG         := Vector2i(0, 14)
const DOOR_OVERHANG_OPEN    := DOOR_OVERHANG + Vector2i(1, 0)
const DOOR_OVERHANG_CRYSTAL := DOOR_OVERHANG + Vector2i(2, 0)
const DOOR_SIDEWAYS         := DOOR_OVERHANG + Vector2i(3, 0)
const DOOR_SIDEWAYS_LOCKED  := DOOR_OVERHANG + Vector2i(4, 0)
const DOOR_SIDEWAYS_CRYSTAL := DOOR_OVERHANG + Vector2i(5, 0)
# 出口是平铺美术，所以它的悬垂其实是"下挂"
const EXIT_UNDERHANG        := DOOR_OVERHANG + Vector2i(6, 0)

# ---------- 杂物顶悬垂 ----------  OTHER_OVERHANG = xy(9,15) = 232 → (8,14)
# 同上：+8 起是线性偏移，折到图集下一行。
const OTHER_OVERHANG              := Vector2i(8, 14)
const ALCHEMY_POT_OVERHANG        := OTHER_OVERHANG + Vector2i(0, 0)
const BARRICADE_OVERHANG          := OTHER_OVERHANG + Vector2i(1, 0)
const HIGH_GRASS_OVERHANG         := OTHER_OVERHANG + Vector2i(2, 0)
const FURROWED_OVERHANG           := OTHER_OVERHANG + Vector2i(3, 0)
const HIGH_GRASS_OVERHANG_ALT     := OTHER_OVERHANG + Vector2i(5, 0)
const FURROWED_OVERHANG_ALT       := OTHER_OVERHANG + Vector2i(6, 0)
const STATUE_OVERHANG             := Vector2i(0, 15)
const STATUE_SP_OVERHANG          := Vector2i(1, 15)
const REGION_DECO_OVERHANG        := Vector2i(2, 15)
const REGION_DECO_ALT_OVERHANG    := Vector2i(3, 15)
const MINE_CRYSTAL_OVERHANG       := Vector2i(4, 15)
const MINE_CRYSTAL_OVERHANG_ALT   := Vector2i(5, 15)
const MINE_CRYSTAL_OVERHANG_ALT_2 := Vector2i(6, 15)
const MINE_BOULDER_OVERHANG       := MINE_CRYSTAL_OVERHANG
const MINE_BOULDER_OVERHANG_ALT   := MINE_CRYSTAL_OVERHANG_ALT
const MINE_BOULDER_OVERHANG_ALT_2 := MINE_CRYSTAL_OVERHANG_ALT_2
const HIGH_GRASS_UNDERHANG        := OTHER_OVERHANG + Vector2i(2, 1)
const FURROWED_UNDERHANG          := OTHER_OVERHANG + Vector2i(3, 1)
const HIGH_GRASS_UNDERHANG_ALT    := OTHER_OVERHANG + Vector2i(5, 1)
const FURROWED_UNDERHANG_ALT      := OTHER_OVERHANG + Vector2i(6, 1)

# ---------- 静态表 ----------
# SPD 的数组里带了 NULL_TILE(-1)：越界邻居也算"可拼接"，于是地图边上的墙不会多出开口 bit。
# 本工程的哨兵是 int -1（_terrain_at 越界返回），不是 NULL_TILE 那个 Vector2i，故这里写字面量 -1。
static var _wall_stitcheable_list: Array = [
	Terrain.WALL, Terrain.WALL_DECO, Terrain.SECRET_DOOR,
	Terrain.LOCKED_EXIT, Terrain.UNLOCKED_EXIT, Terrain.BOOKSHELF,
	-1,
]

static var _door_tiles: Array = [
	Terrain.DOOR, Terrain.LOCKED_DOOR, Terrain.HERO_LKD_DR,
	Terrain.CRYSTAL_DOOR, Terrain.OPEN_DOOR,
]

# 深渊拼接：上方地形 → 该画哪种深渊瓦片。表外一律 CHASM。
static var chasm_stitcheable: Dictionary = {}

static var tile_variance: PackedByteArray = PackedByteArray()
static var common_alt_visuals: Dictionary = {}
static var rare_alt_visuals: Dictionary = {}


static func _static_init() -> void:
	# 能拼深渊的地形（同 SPD chasmStitcheable）
	for t in [Terrain.EMPTY, Terrain.GRASS, Terrain.EMBERS, Terrain.EMPTY_WELL,
			Terrain.HIGH_GRASS, Terrain.FURROWED_GRASS, Terrain.EMPTY_DECO,
			Terrain.CUSTOM_DECO, Terrain.WELL, Terrain.STATUE, Terrain.REGION_DECO,
			Terrain.SECRET_TRAP, Terrain.INACTIVE_TRAP, Terrain.TRAP, Terrain.BOOKSHELF,
			Terrain.BARRICADE, Terrain.PEDESTAL, Terrain.CUSTOM_DECO_EMPTY,
			Terrain.MINE_BOULDER, Terrain.MINE_CRYSTAL]:
		chasm_stitcheable[t] = CHASM_FLOOR
	chasm_stitcheable[Terrain.EMPTY_SP] = CHASM_FLOOR_SP
	chasm_stitcheable[Terrain.STATUE_SP] = CHASM_FLOOR_SP
	for t in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR,
			Terrain.HERO_LKD_DR, Terrain.SECRET_DOOR, Terrain.WALL_DECO]:
		chasm_stitcheable[t] = CHASM_WALL
	chasm_stitcheable[Terrain.WATER] = CHASM_WATER

	# 常见替代美术（50% 触发）
	common_alt_visuals[FLOOR] = FLOOR_ALT_1
	common_alt_visuals[GRASS] = GRASS_ALT
	common_alt_visuals[EMBERS] = EMBERS_ALT
	common_alt_visuals[FLOOR_SP] = FLOOR_SP_ALT
	common_alt_visuals[FLOOR_DECO] = FLOOR_DECO_ALT
	common_alt_visuals[FLAT_WALL] = FLAT_WALL_ALT
	common_alt_visuals[FLAT_WALL_DECO] = FLAT_WALL_DECO_ALT
	common_alt_visuals[FLAT_BOOKSHELF] = FLAT_BOOKSHELF_ALT
	common_alt_visuals[FLAT_HIGH_GRASS] = FLAT_HIGH_GRASS_ALT
	common_alt_visuals[FLAT_FURROWED_GRASS] = FLAT_FURROWED_ALT
	common_alt_visuals[FLAT_MINE_CRYSTAL] = FLAT_MINE_CRYSTAL_ALT
	common_alt_visuals[FLAT_MINE_BOULDER] = FLAT_MINE_BOULDER_ALT
	common_alt_visuals[RAISED_WALL] = RAISED_WALL_ALT
	common_alt_visuals[RAISED_WALL_DECO] = RAISED_WALL_DECO_ALT
	common_alt_visuals[RAISED_WALL_BOOKSHELF] = RAISED_WALL_BOOKSHELF_ALT
	common_alt_visuals[RAISED_HIGH_GRASS] = RAISED_HIGH_GRASS_ALT
	common_alt_visuals[RAISED_FURROWED_GRASS] = RAISED_FURROWED_ALT
	common_alt_visuals[RAISED_MINE_CRYSTAL] = RAISED_MINE_CRYSTAL_ALT
	common_alt_visuals[RAISED_MINE_BOULDER] = RAISED_MINE_BOULDER_ALT
	common_alt_visuals[HIGH_GRASS_OVERHANG] = HIGH_GRASS_OVERHANG_ALT
	common_alt_visuals[FURROWED_OVERHANG] = FURROWED_OVERHANG_ALT
	common_alt_visuals[HIGH_GRASS_UNDERHANG] = HIGH_GRASS_UNDERHANG_ALT
	common_alt_visuals[FURROWED_UNDERHANG] = FURROWED_UNDERHANG_ALT
	common_alt_visuals[MINE_CRYSTAL_OVERHANG] = MINE_CRYSTAL_OVERHANG_ALT
	common_alt_visuals[MINE_BOULDER_OVERHANG] = MINE_BOULDER_OVERHANG_ALT

	# 稀有替代美术（5% 触发，优先于常见替代）
	rare_alt_visuals[FLOOR] = FLOOR_ALT_2
	rare_alt_visuals[FLAT_MINE_CRYSTAL] = FLAT_MINE_CRYSTAL_ALT_2
	rare_alt_visuals[FLAT_MINE_BOULDER] = FLAT_MINE_BOULDER_ALT_2
	rare_alt_visuals[RAISED_MINE_CRYSTAL] = RAISED_MINE_CRYSTAL_ALT_2
	rare_alt_visuals[RAISED_MINE_BOULDER] = RAISED_MINE_BOULDER_ALT_2
	rare_alt_visuals[MINE_CRYSTAL_OVERHANG] = MINE_CRYSTAL_OVERHANG_ALT_2
	rare_alt_visuals[MINE_BOULDER_OVERHANG] = MINE_BOULDER_OVERHANG_ALT_2


# ==================== 查询 ====================

# 算作"墙"的地形——用于墙体拼接的邻接判定
static func wall_stitcheable(tile: int) -> bool:
	return _wall_stitcheable_list.has(tile)


static func door_tile(tile: int) -> bool:
	return _door_tiles.has(tile)


# tile_variance 由 setup_variance() 一次性铺满；没铺时一律返回原图（无替代）。
# SPD 传进来的 pos 是线性序号，这里 pos 是关卡格坐标，故内部换算成序号再查表。
static func get_visual_with_alts(visual: Vector2i, pos: Vector2i) -> Vector2i:
	if tile_variance.is_empty():
		return visual
	var index := pos.y * LevelManager.MAP_WIDTH + pos.x
	if index < 0 or index >= tile_variance.size():
		return visual
	var v := tile_variance[index]
	if v >= 95 and rare_alt_visuals.has(visual):
		return rare_alt_visuals[visual]
	if v >= 50 and common_alt_visuals.has(visual):
		return common_alt_visuals[visual]
	return visual


# ==================== 拼接 ====================

# 凸起墙（下层）。正下方出界或仍是墙 → 归上层画内部墙面，这里返回空。
# 正下方是门 → 用 RAISED_WALL_DOOR（"门后的墙"）。左右开口各叠一个 bit。
static func get_raised_wall_tile(tile: int, pos: Vector2i, right: int, below: int, left: int) -> Vector2i:
	if below == -1 or wall_stitcheable(below):
		return NULL_TILE

	var result: Vector2i
	if door_tile(below):
		result = RAISED_WALL_DOOR
	elif tile == Terrain.WALL or tile == Terrain.SECRET_DOOR:
		result = RAISED_WALL
	elif tile == Terrain.WALL_DECO:
		result = RAISED_WALL_DECO
	elif tile == Terrain.BOOKSHELF:
		result = RAISED_WALL_BOOKSHELF
	else:
		return NULL_TILE

	result = get_visual_with_alts(result, pos)

	if not wall_stitcheable(right):
		result.x += 1
	if not wall_stitcheable(left):
		result.x += 2
	return result


# 凸起门。正下方是墙 → 侧向门（门开在上下墙之间，透视上要画成横躺的）；
# 否则按门的开闭状态选图。
static func get_raised_door_tile(tile: int, below: int) -> Vector2i:
	if wall_stitcheable(below):
		return RAISED_DOOR_SIDEWAYS
	match tile:
		Terrain.DOOR:         return RAISED_DOOR
		Terrain.OPEN_DOOR:    return RAISED_DOOR_OPEN
		Terrain.LOCKED_DOOR:  return RAISED_DOOR_LOCKED
		Terrain.HERO_LKD_DR:  return RAISED_DOOR_LOCKED
		Terrain.CRYSTAL_DOOR: return RAISED_DOOR_CRYSTAL
	return NULL_TILE


# 内部墙面（上层）。四个邻接 bit：右、右下、左下、左。
# 书架（自己或正下方）用木纹变体；矿区(WALL_DECO + branch 1)用装饰变体。
static func stitch_internal_wall_tile(tile: int, right: int, right_below: int, below: int, left_below: int, left: int) -> Vector2i:
	var result: Vector2i
	if tile == Terrain.BOOKSHELF or below == Terrain.BOOKSHELF:
		result = WALL_INTERNAL_WOODEN
	elif GameState.branch == 1 and tile == Terrain.WALL_DECO:
		result = WALL_INTERNAL_DECO
	else:
		result = WALL_INTERNAL

	if not wall_stitcheable(right):
		result.x += 1
	if not wall_stitcheable(right_below):
		result.x += 2
	if not wall_stitcheable(left_below):
		result.x += 4
	if not wall_stitcheable(left):
		result.x += 8
	return result


# 深渊拼接：只看正上方那格是什么地形，决定深渊上沿怎么和它接。
static func stitch_chasm_tile(above: int) -> Vector2i:
	if above == Terrain.REGION_DECO_ALT:
		if GameState.depth <= 5:
			return CHASM_FLOOR_SP
		if GameState.depth <= 10:
			return CHASM
		if GameState.depth <= 20:
			return CHASM_FLOOR_SP
		return CHASM_FLOOR
	return chasm_stitcheable.get(above, CHASM)


# 墙根悬垂：画在"正下方是墙"的那一格上，让墙投一条影子下来。
# 门/书架/装饰各有变体；两个 bit 对应右下 / 左下开口。
static func stitch_wall_overhang_tile(tile: int, right_below: int, below: int, left_below: int) -> Vector2i:
	var visual: Vector2i
	if tile == Terrain.OPEN_DOOR:
		visual = DOOR_SIDEWAYS_OVERHANG
	elif tile == Terrain.DOOR:
		visual = DOOR_SIDEWAYS_OVERHANG_CLOSED
	elif tile == Terrain.LOCKED_DOOR:
		visual = DOOR_SIDEWAYS_OVERHANG_LOCKED
	elif tile == Terrain.HERO_LKD_DR:
		visual = DOOR_SIDEWAYS_OVERHANG_LOCKED
	elif tile == Terrain.CRYSTAL_DOOR:
		visual = DOOR_SIDEWAYS_OVERHANG_CRYSTAL
	elif GameState.branch == 1 and below == Terrain.WALL_DECO:
		visual = WALL_OVERHANG_DECO
	elif below == Terrain.BOOKSHELF:
		visual = WALL_OVERHANG_WOODEN
	else:
		visual = WALL_OVERHANG

	if not wall_stitcheable(right_below):
		visual.x += 1
	if not wall_stitcheable(left_below):
		visual.x += 2
	return visual


# ==================== 杂项 ====================

# 一次铺满全关卡的替代美术随机表。seed 由调用方给，保证同层同貌。
static func setup_variance(size: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	tile_variance.resize(size)
	for i in size:
		tile_variance[i] = rng.randi_range(0, 99)


static func get_visual(terrain: int) -> Vector2i:
	return DIRECT_VISUALS.get(terrain, NULL_TILE)
