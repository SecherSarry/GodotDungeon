extends RefCounted
class_name Room

# 房间矩形：left/top/right/bottom 都是地图格坐标（含端点），与 map_data[y][x] 同体系。
# 生成期对象——只做几何、连通图与抽象接口，具体往图里画什么交给子类的 paint()。
# 不继承 Node：房间不进场景树，RefCounted 自动回收，免去每层生成后的泄漏。
#
# 术语：
#   neighbours —— 几何上紧邻的房间（双向登记，供以后的"房间合并/暗门"之类用）
#   connected  —— 已经有走廊连上的房间（connect_rooms 连线时登记）

const MARGIN := 1   # 房间之间、以及房间与图边之间强制留出的空格数

var left: int = 0
var top: int = 0
var right: int = -1
var bottom: int = -1

var connected: Array = []
var neighbours: Array = []


# ---------- 几何 ----------
func width() -> int:
	return right - left + 1

func height() -> int:
	return bottom - top + 1

func size() -> int:
	return width() * height()

func center_x() -> int:
	return (left + right) / 2

func center_y() -> int:
	return (top + bottom) / 2

func center() -> Vector2i:
	return Vector2i(center_x(), center_y())

func contains(point: Vector2i) -> bool:
	return point.x >= left and point.x <= right and point.y >= top and point.y <= bottom

# 该格是否落在矩形的四条边上（门就落在走廊穿出房间的那一格边框上）。
func border(x: int, y: int) -> bool:
	return (y == top or y == bottom) and x >= left and x <= right \
		or (x == left or x == right) and y >= top and y <= bottom

func cells() -> Array:
	var result := []
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			result.append(Vector2i(x, y))
	return result

# 内圈随机格：避开四条边，免得怪/物生在门口或贴着墙。
# 极小的房间（宽或高 <= 2）没有内圈，退回中心。
func random_point() -> Vector2i:
	if width() <= 2 or height() <= 2:
		return center()
	return Vector2i(Random.randi_range(left + 1, right - 1), Random.randi_range(top + 1, bottom - 1))


# ---------- 关系 ----------
# margin > 0 时把两矩形各自外扩 margin 格再判重叠，等价于要求两者间隔 >= margin。
# 放置房间时传 MARGIN，保证房间之间不贴合（贴合会让它们合并成一片，走廊也无处落脚）。
func intersects(other: Room, margin: int = 0) -> bool:
	return not (other.left > right + margin or other.right < left - margin
		or other.top > bottom + margin or other.bottom < top - margin)

# 两中心的曼哈顿距离：MST 挑最近房间用。
func distance_to(other: Room) -> int:
	return absi(center_x() - other.center_x()) + absi(center_y() - other.center_y())

# 两房间之间的空隙格数：贴合为 0，重叠为负。
func gap_to(other: Room) -> int:
	var dx: int = maxi(other.left - right - 1, left - other.right - 1)
	var dy: int = maxi(other.top - bottom - 1, top - other.bottom - 1)
	return maxi(dx, dy)


# ---------- 连通图 ----------
# 名字不能叫 connect：那会撞上 Object.connect(signal, callable)，GDScript 禁止用不兼容的签名覆盖原生方法。
func connect_to(room: Room) -> void:
	if not is_connected_to(room):
		connected.append(room)

func is_connected_to(room: Room) -> bool:
	return connected.has(room)

func can_connect(room: Room) -> bool:
	return room != self and room != null

func add_neighbour(room: Room) -> void:
	if not is_neighbour(room):
		neighbours.append(room)
		room.neighbours.append(self)

func is_neighbour(room: Room) -> bool:
	return neighbours.has(room)


# ---------- 尺寸 ----------
# 四个区间由子类覆写提供；基类返回 -1 表示"没有默认档位"。
func min_width() -> int:
	return -1

func max_width() -> int:
	return -1

func min_height() -> int:
	return -1

func max_height() -> int:
	return -1

# 随机取一档尺寸，right/bottom 由 left/top 推出（初始落在原点附近，之后用 set_pos 平移）。
# 区间传 -1 = 回退到 min/max_*()。之所以用 -1 哨兵而非把方法调用写进默认值：
# GDScript 要求参数默认值必须是常量表达式，写成 min_width() 直接编译不过。
func set_size(min_w: int = -1, max_w: int = -1, min_h: int = -1, max_h: int = -1) -> bool:
	if min_w < 0:
		min_w = min_width()
	if max_w < 0:
		max_w = max_width()
	if min_h < 0:
		min_h = min_height()
	if max_h < 0:
		max_h = max_height()
	if min_w < 1 or max_w < min_w or min_h < 1 or max_h < min_h:
		return false
	return set_size_exact(Random.randi_range(min_w, max_w), Random.randi_range(min_h, max_h))

func set_size_exact(w: int, h: int) -> bool:
	if w < 1 or h < 1:
		return false
	right = left + w - 1
	bottom = top + h - 1
	return true

# 保持宽高，把矩形左上角挪到 (px, py)。
func set_pos(px: int, py: int) -> void:
	var w := width()
	var h := height()
	left = px
	top = py
	right = px + w - 1
	bottom = py + h - 1

func set_bounds(l: int, t: int, r: int, b: int) -> void:
	left = l
	top = t
	right = r
	bottom = b


# ---------- 绘制：子类覆写，把自己写进 map_data ----------
func paint(map_data: Array) -> void:
	pass


# 走廊与房间交界处的一格门。type 预留给"普通门 / 上锁门 / 隐藏门"。
class Door:
	var x: int
	var y: int
	var type: int

	func _init(px: int, py: int, ptype: int = 0):
		x = px
		y = py
		type = ptype

	func cell() -> Vector2i:
		return Vector2i(x, y)

	# 这扇门是否开在该房间的边框上（判归属用）。
	func other_side(room: Room) -> bool:
		return room.border(x, y)
