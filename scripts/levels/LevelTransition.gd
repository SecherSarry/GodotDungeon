# LevelTransition.gd
# 关卡出入口。一层里的上行/下行楼梯（以及地表口）都表达为一个 Transition，
# 由 Level.transitions 持有，经 get_transition(type) / get_transition_at(cell) 取用。
#
# 直译 SPD levels/features/LevelTransition.java 的核心：type 定"这是什么口"，
# dest_depth/dest_branch/dest_type 记"通向哪"——换层时落点不再是"下楼去入口/上楼去出口"的
# 启发式，而是由源 transition 的 dest_type 在目标层上查到对应出入口（进出对称，原版同）。
#
# 坐标用 Vector2i（本工程 Actor.grid_pos / Level 的格一律 Vector2i；SPD 那边是扁平索引）。
class_name LevelTransition
extends RefCounted

enum Type {
	REGULAR_ENTRANCE,   # 本层入口（从上一层下来的落点）
	REGULAR_EXIT,       # 本层出口（下行楼梯）
	BRANCH_ENTRANCE,    # 支线入口
	BRANCH_EXIT,        # 支线出口
	SURFACE,            # 地表（唯一的向上出口）
}

var type: int
var cell: Vector2i       # 落点格
var dest_depth: int      # 目标深度
var dest_branch: int     # 目标支线（0 = 主线）
var dest_type: int       # 目标层上对应的出入口类型（-1 = 无，如地表）

func _init(t: int, c: Vector2i, d: int = -1, b: int = 0, dt: int = -1) -> void:
	type = t
	cell = c
	dest_depth = d
	dest_branch = b
	dest_type = dt

# 常用出入口的默认 dest（对齐 SPD 的三参构造：dest 由所在层推导）。
# 本工程的生成器是静态的、不读 GameState，故把"本层深度"显式传进来，而非隐式取 Dungeon.depth。
static func make(t: int, c: Vector2i, level_depth: int, branch: int = 0) -> LevelTransition:
	match t:
		Type.REGULAR_EXIT:
			return LevelTransition.new(t, c, level_depth + 1, branch, Type.REGULAR_ENTRANCE)
		Type.BRANCH_EXIT:
			return LevelTransition.new(t, c, level_depth + 1, branch, Type.BRANCH_ENTRANCE)
		Type.SURFACE:
			return LevelTransition.new(t, c, 0, 0, -1)
		_:   # REGULAR_ENTRANCE / BRANCH_ENTRANCE
			return LevelTransition.new(t, c, level_depth - 1, branch, Type.REGULAR_EXIT)

# 该格是否属于本出入口。当前生成器只产单格出入口（RegularLevel 的 entrance/exit 各一格），
# 故按单格判定；SPD 的"三格宽楼梯"尚未移植，届时需在此扩成区间并让 Transition 记录跨格范围。
func inside(c: Vector2i) -> bool:
	return c == cell
