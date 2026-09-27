extends RefCounted
class_name Ballistica

# 投射物弹道求解：直译 SPD 的 mechanics/Ballistica.java。
# 给一个起点、一个想打到的格、一组标志位，算出"实际撞在哪一格"。
#
# 为何不自己写个"看着等价"的画线法：格子序列跟标准 Bresenham 根本不同。
# 原版用 err = dA/2 起手的整数 DDA，平局时先走对角；标准 Bresenham 平局时先走主轴。
# 当年实测 30x20 全部内点对（254016 组）里有 32% 序列不同，撞点自然也不同。
# 例：(1,1)→(3,2) 本类走 (1,1),(2,2),(3,2)，标准 Bresenham 走 (1,1),(2,1),(3,2)。
# 故这里逐行照抄原版循环，不做"等价重写"。
#
# path 是完整弹道，含撞点之后的余程——原版如此（注释见 Ballistica.java:33）。
# 只要"起点到撞点"那一段就自己切前 path.find(collision)+1 个。

# ---------- 撞点判据，可位或组合 ----------
const STOP_TARGET       := 1   # 到达目标格即停
const STOP_CHARS        := 2   # 撞到角色即停
const STOP_SOLID        := 4   # 撞到实心地形即停
const IGNORE_SOFT_SOLID := 8   # 忽略"软实心"（挡投射物但人能走的门一类）

# ---------- 常用组合 ----------
const PROJECTILE := STOP_TARGET | STOP_CHARS | STOP_SOLID   # 一般投掷物
const MAGIC_BOLT := STOP_CHARS | STOP_SOLID                 # 法术射线：能穿过目标格继续走
const WONT_STOP  := 0                                       # 只求弹道、不求撞点

var collision: Vector2i = Vector2i.ZERO   # 撞点；全程无碰撞则为离开地图前的最后一格
var path: Array = []                      # 完整弹道（Vector2i）

func _init(from: Vector2i, to: Vector2i, params: int = PROJECTILE) -> void:
	_build(from, to,
		(params & STOP_TARGET) > 0,
		(params & STOP_CHARS) > 0,
		(params & STOP_SOLID) > 0,
		(params & IGNORE_SOFT_SOLID) > 0)

	if path.is_empty():
		# 起点本身就在界外（原版的兜底分支）：弹道只有起点自己
		path.append(to_index(from))
		collision = from
		return

	if path.has(to_index(collision)):
		return   # 已在循环里定下撞点
	collision = to_cell(path[path.size() - 1])

func _build(from: Vector2i, to: Vector2i, stop_target: bool, stop_chars: bool,
		stop_terrain: bool, ignore_soft_solid: bool) -> void:
	var w := LevelManager.MAP_WIDTH
	var from_i := to_index(from)
	var to_i := to_index(to)

	var dx := to.x - from.x
	var dy := to.y - from.y
	var step_x := 1 if dx > 0 else -1
	var step_y := 1 if dy > 0 else -1
	dx = absi(dx)
	dy = absi(dy)

	# 主轴走 ±1，次轴走 ±w（一维索引下的"上下一格"）。
	# dx == dy 时走 else 分支（y 为主轴）——原版是 `dx > dy`，不是 `>=`，平局归 y 轴，照抄。
	var step_a: int
	var step_b: int
	var d_a: int
	var d_b: int
	if dx > dy:
		step_a = step_x
		step_b = step_y * w
		d_a = dx
		d_b = dy
	else:
		step_a = step_y * w
		step_b = step_x
		d_a = dy
		d_b = dx

	var cell := from_i
	# 原版是 `err = dA / 2`（整数除法）。写成 int(d_a / 2.0) 避开 GDScript 的整数除法告警，
	# d_a 恒非负，两者等价。
	var err := int(d_a / 2.0)
	var collided := false

	while _inside_map(cell):
		# 软实心：人可以走、投射物过不去。撞点在**前一格**，不是这一格——原版 collide(path 的末格)。
		if (not collided and stop_terrain and cell != from_i
				and not _passable(cell) and not _avoid(cell) and not _char_at(cell)):
			collided = true
			collision = to_cell(path[path.size() - 1])

		path.append(cell)

		if not collided and stop_terrain and cell != from_i and _solid(cell):
			# 硬实心。ignore_soft_solid 时，若这格同时是可走的软实心（比如关着的门）则放行。
			if not (ignore_soft_solid and (_passable(cell) or _avoid(cell))):
				collided = true
				collision = to_cell(cell)

		if not collided and cell != from_i and stop_chars and _char_at(cell):
			collided = true
			collision = to_cell(cell)

		if not collided and cell == to_i and stop_target:
			collided = true
			collision = to_cell(cell)

		cell += step_a
		err += d_b
		if err >= d_a:
			err -= d_a
			cell += step_b

# 原版的 insideMap 不是"在边界内"那么简单：它把最外一圈整圈都算作界外
# （上下各一行、左右各一列）。故弹道最多走到第一圈内沿。
func _inside_map(index: int) -> bool:
	var w := LevelManager.MAP_WIDTH
	var total := w * LevelManager.MAP_HEIGHT
	if index < w or index >= total - w:
		return false
	var col := index % w
	return col != 0 and col != w - 1

# 不写成 static：它们要读 LevelManager 这个 autoload，而 static 上下文里拿不到单例。
func to_index(cell: Vector2i) -> int:
	return cell.y * LevelManager.MAP_WIDTH + cell.x

func to_cell(index: int) -> Vector2i:
	return Vector2i(index % LevelManager.MAP_WIDTH, index / LevelManager.MAP_WIDTH)

# 三个地形判据都走 Terrain 的标志位，不硬编码地形 id——与 Char._blocks_sight 同一套读法。
func _passable(index: int) -> bool:
	return Terrain.has_flag(_terrain_at(index), Terrain.FLAG_PASSABLE)

func _solid(index: int) -> bool:
	return Terrain.has_flag(_terrain_at(index), Terrain.FLAG_SOLID)

func _avoid(index: int) -> bool:
	return Terrain.has_flag(_terrain_at(index), Terrain.FLAG_AVOID)

func _terrain_at(index: int) -> int:
	return LevelManager.map_data[index / LevelManager.MAP_WIDTH][index % LevelManager.MAP_WIDTH]

# 撞点判据之一：该格有没有角色。原版是 findChar（角色+怪），
# 但弹道起点恒为投掷者自身、而下面各处都带 `cell != from_i`，故只需问"是否有别人"。
func _char_at(index: int) -> bool:
	return MapManager.is_occupied(to_cell(index))
