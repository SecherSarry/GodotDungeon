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

# 地面物品：一格一个 Heap（原版 Level.heaps）。生成期直接建 Heap，运行期就地增删，
# 离层快照也用它——三态合一，不再有"生成清单 / 快照 / 节点数组"三套平行表示。
var heaps: Array = []              # Heap 列表（Heap 自带 pos）

# 运行期实体快照（离开本层时场景采集，原 floor_cache 字典的 "monsters"/"heaps"）
var monsters: Array = []           # 快照：mob.serialize() 字典

# 层上的 blob（火焰/毒气/水一类的场地效应），按 blob 类做键——原版 Level.blobs。
# Blob.seed/volumeAt 只认这一处存储；换层时随 Level 一起进 floor_cache。
var blobs: Dictionary = {}


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


# ---------- 地面物品堆取用 ----------
# 访问器与 get_transition_at 同风格：Array + 扫描（一层上的堆很少，不值得另建索引）。

func heap_at(cell: Vector2i) -> Heap:
	for h: Heap in heaps:
		if h.pos == cell:
			return h
	return null

# 往某格放一件：该格已有堆就并进去，没有就新建一个。返回落定的那个堆。
func drop_item(item: Item, cell: Vector2i) -> Heap:
	var h := heap_at(cell)
	if h == null:
		h = Heap.new()
		h.pos = cell
		heaps.append(h)
	h.drop(item)
	return h

func remove_heap(h: Heap) -> void:
	heaps.erase(h)
