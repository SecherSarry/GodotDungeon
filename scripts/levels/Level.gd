extends Bundlable
class_name Level

# ---------- 既有字段（SPD 移植的旧新层残留，暂按占位保留，未接） ----------
var width: int
var height: int
static var TIME_TO_RESPAWN: float = 50
var version: int

var map = []
var visited = []
var mapped = []
var discoverable = []

var view_distance = 8

# ---------- 每层数据（原 LevelManager 的平铺字段收进这里）----------
var map_data = []          # 地形类型（二维 int）
var explored = []          # 已探索（二维 bool）
var rooms = []             # Room 对象列表（仅生成期使用）

# 出入口。原版的 hero_spawn/exit_cell 两个字段由这张表取代：入口 = get_transition(null).cell，
# 出口 = get_transition(REGULAR_EXIT).cell（见 entrance()/exit()）。每个 transition 还带着 dest_*，
# 换层时据此定目标深度与落点。
var transitions: Array = []        # LevelTransition 列表
var monster_cells: Array = []      # 生成期怪格（种子）
var item_placements: Array = []    # 生成期物品清单（[{cell: Vector2i, item: Item}]）

# 运行期实体快照（离开本层时场景采集，原 floor_cache 字典的 "monsters"/"items"）
var monsters: Array = []           # 快照：mob.serialize() 字典
var items: Array = []              # 快照：[{cell: Vector2i, item: Item}]


# ---------- 出入口取用（对齐 SPD Level.getTransition 系列） ----------

# type 传 -1 表示"任意入口"——优先返回 REGULAR_ENTRANCE / BRANCH_ENTRANCE / SURFACE 之一；
# 指定类型找不到时退回"任意入口"，仍无则取第一个（原版同：`type != null ? getTransition(null) : transitions.get(0)`）。
func get_transition(type: int = -1) -> LevelTransition:
	if transitions.is_empty():
		return null
	for t in transitions:
		if type == -1 and (t.type == LevelTransition.Type.REGULAR_ENTRANCE
				or t.type == LevelTransition.Type.BRANCH_ENTRANCE
				or t.type == LevelTransition.Type.SURFACE):
			return t
		elif t.type == type:
			return t
	if type != -1:
		return get_transition(-1)
	return transitions[0]

func get_transition_at(c: Vector2i) -> LevelTransition:
	for t in transitions:
		if t.inside(c):
			return t
	return null

func entrance() -> Vector2i:
	var t = get_transition(-1)
	return t.cell if t != null else Vector2i(0, 0)

func exit() -> Vector2i:
	var t = get_transition(LevelTransition.Type.REGULAR_EXIT)
	return t.cell if t != null else Vector2i(0, 0)
