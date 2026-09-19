# LevelTransition.gd
# 关卡出入口。一层里的上行/下行楼梯（以及地表口）都表达为一个 Transition，
# 由 Level.transitions 持有，经 get_transition(type) / get_transition_at(cell) 取用。
#
# 坐标用扁平索引（i = y * width + x），与 Level.map / Actor.grid_pos 同一套。
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
var cell: int           # 扁平索引
var dest_depth: int     # 目标深度
var dest_branch: int    # 目标支线（0 = 主线）

func _init(t: int, c: int, d: int = -1, b: int = 0) -> void:
	type = t
	cell = c
	dest_depth = d
	dest_branch = b

# 该格是否属于本出入口。当前生成器只产单格出入口（RegularLevel 的 entrance/exit 各一格），
# 故按单格判定；SPD 的"三格宽楼梯"尚未移植，届时需在此扩成区间并让 Transition 记录跨格范围。
func inside(c: int) -> bool:
	return c == cell
