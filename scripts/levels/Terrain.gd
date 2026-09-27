# Terrain.gd
# 地形字典：地形 id → 一组布尔标志位。地形语义（可走 / 挡视线 / 可燃 / 实心 …）集中在这里，
# 其它地方不再各自维护「哪些地形算可走」的白名单。
#
# id 沿用 RegularLevel 既有的 0–13，数值可直接互通。
class_name Terrain
extends RefCounted

# ==================== 地形 id ====================
# 0–13 为既有地形 id，数值可直接互通，勿擅自改动。
const CHASM          := 0    # 深渊
const EMPTY          := 1    # 空地板
const GRASS          := 2
const EMPTY_WELL     := 3    # 空水井
const WALL           := 4
const DOOR           := 5
const OPEN_DOOR      := 6
const ENTRANCE       := 7
const EXIT           := 8
const EMBERS         := 9
const LOCKED_DOOR    := 10
const WATER          := 11
const HIGH_GRASS     := 12
const FURROWED_GRASS := 13

# 14 起：尚未有生成器产出，留给后续新增地形
const WALL_DECO      := 14   # 装饰性墙（仍是墙）
const EMPTY_DECO     := 15   # 带装饰的地板（可走）
const EMPTY_SP       := 16   # 特殊空地（可走）
const TRAP           := 17
const SECRET_TRAP    := 18   # 未发现的陷阱：可走 + SECRET
const INACTIVE_TRAP  := 19   # 已解除的陷阱：等同地板

# 别名：新层用 WELL，旧层用 EMPTY_WELL，同一格地形
const WELL := EMPTY_WELL

# ==================== 标志位 ====================
const FLAG_PASSABLE     := 1    # 可走
const FLAG_LOS_BLOCKING := 2    # 阻挡视线
const FLAG_FLAMABLE     := 4    # 可燃
const FLAG_SECRET       := 8    # 未发现（需 discover 才揭示）
const FLAG_SOLID        := 16   # 实心（墙/门一类，阻挡移动与开掘）
const FLAG_AVOID        := 32   # 怪物绕行（深渊等）
const FLAG_LIQUID       := 64   # 液体
const FLAG_PIT          := 128  # 坑：踏入即坠落

# ==================== id → flags ====================
# 标志取"游戏语义"而非"美术表现"：ENTRANCE/EXIT 当前无独立美术，按普通地板（可走）处理。
# 门分两类，与 SPD Terrain.java 的 flags 表逐条一致：
# - DOOR/OPEN_DOOR 可走。DOOR 另带 FLAG_SOLID（原版 flags[DOOR] 一字不差）：
#   可走 + 实心 = 原版所谓"软实心"——人过得去、投射物过不去，
#   正是 Ballistica 里 IGNORE_SOFT_SOLID 要区分的那一类。
#   "开门"是走上去那一刻的附带动作（见 Char.walk_to），不体现在可走性上。
# - LOCKED_DOOR 不可走（原版 flags[LOCKED_DOOR] = LOS_BLOCKING | SOLID）。
#   原版要站到门下用对应钥匙解锁，本工程暂无钥匙系统，改成正交相邻即解锁——
#   Char.walk_to 里 is_locked_door 那一支排在 is_walkable 之前，故不可走不影响解锁。
#   改后自动寻路不再穿锁门，与原版同。
# 关着的门仍 FLAG_LOS_BLOCKING——挡视线照旧。
# 深渊可走"不过去"但不算实心——视线能穿过、怪会绕。
const FLAGS := {
	CHASM:          FLAG_PIT | FLAG_AVOID,
	EMPTY:          FLAG_PASSABLE,
	GRASS:          FLAG_PASSABLE | FLAG_FLAMABLE,
	EMPTY_WELL:     FLAG_PASSABLE,
	WALL:           FLAG_LOS_BLOCKING | FLAG_SOLID,
	DOOR:           FLAG_PASSABLE | FLAG_LOS_BLOCKING | FLAG_FLAMABLE | FLAG_SOLID,
	OPEN_DOOR:      FLAG_PASSABLE | FLAG_FLAMABLE,
	ENTRANCE:       FLAG_PASSABLE,
	EXIT:           FLAG_PASSABLE,
	EMBERS:         FLAG_PASSABLE,
	LOCKED_DOOR:    FLAG_LOS_BLOCKING | FLAG_SOLID,
	WATER:          FLAG_PASSABLE | FLAG_LIQUID,
	HIGH_GRASS:     FLAG_PASSABLE | FLAG_FLAMABLE,
	FURROWED_GRASS: FLAG_PASSABLE | FLAG_FLAMABLE,
	WALL_DECO:      FLAG_LOS_BLOCKING | FLAG_SOLID,
	EMPTY_DECO:     FLAG_PASSABLE,
	EMPTY_SP:       FLAG_PASSABLE,
	TRAP:           FLAG_PASSABLE,
	SECRET_TRAP:    FLAG_PASSABLE | FLAG_SECRET,
	INACTIVE_TRAP:  FLAG_PASSABLE,
}

# 未知 id 一律按实心墙处理：宁可挡路，也不要让一格坏数据变成可穿行的洞
const FLAGS_UNKNOWN := FLAG_LOS_BLOCKING | FLAG_SOLID

static func get_flags(id: int) -> int:
	return int(FLAGS.get(id, FLAGS_UNKNOWN))

static func has_flag(id: int, flag: int) -> bool:
	return (get_flags(id) & flag) != 0

# ==================== 揭示 ====================
# 未发现地形 → 已发现。新层 Level.discover() 调用，用于踩中/搜索时揭示隐藏陷阱。
const DISCOVERED := {
	SECRET_TRAP: TRAP,
}

static func discover(id: int) -> int:
	return int(DISCOVERED.get(id, id))
