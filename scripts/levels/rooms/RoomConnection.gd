extends RefCounted
class_name RoomConnection

# 一条房间连接：两间房 + 它们之间的走廊格序列 + 走廊穿出各自房间那一刻的门格。
# 纯数据——怎么挖、怎么落门由 RegularLevel 决定；这里只把"路在哪、门在哪"算出来并记住。

enum Type { NORMAL, SECRET, LOCKED }

var a: Room
var b: Room
var path: Array = []                              # 中心到中心的 L 形走廊格（含两端中心）
var door_a: Vector2i = Vector2i(-1, -1)           # 紧贴房间 a 外墙的那一格（岩壁线上，见 _door_cell）
var door_b: Vector2i = Vector2i(-1, -1)
var type: Type = Type.NORMAL

func _init(room_a: Room, room_b: Room):
	a = room_a
	b = room_b


# 造一条连接：路径取两中心间的 L 形（先横后竖 / 先竖后横随机），
# 两端各算一个门格。
static func build(room_a: Room, room_b: Room) -> RoomConnection:
	var conn = RoomConnection.new(room_a, room_b)
	conn.path = l_path(room_a.center(), room_b.center())
	# 路径从 a 中心流向 b 中心：a 的门取边框外侧（往后走一格），b 的门取边框外侧（往前走一格）。
	conn.door_a = _door_cell(conn.path, room_a, 1)
	conn.door_b = _door_cell(conn.path, room_b, -1)
	return conn


# 两格之间的 L 形折线：先沿一个轴从 from 走到 to，再沿另一个轴走到 to。
# 顺序严格 from → to（首格必是 from，末格必是 to），_door_cell 的"从中心往外"才成立。
# 不能用 range(min, max)：那样永远从小走到大，from 在 to 右侧/下侧时首格就成了 to 那边。
static func l_path(from: Vector2i, to: Vector2i) -> Array:
	var path := []
	if Random.randi() % 2 == 0:
		# 先横后竖
		for x in _steps(from.x, to.x):
			path.append(Vector2i(x, from.y))
		for y in _steps(from.y, to.y):
			path.append(Vector2i(to.x, y))
	else:
		# 先竖后横
		for y in _steps(from.y, to.y):
			path.append(Vector2i(from.x, y))
		for x in _steps(from.x, to.x):
			path.append(Vector2i(x, to.y))
	return path


# from → to 的整数序列（含两端），自动判升降。from == to 时只给一格。
static func _steps(from: int, to: int) -> Array:
	var out := []
	if from <= to:
		for v in range(from, to + 1):
			out.append(v)
	else:
		for v in range(from, to - 1, -1):
			out.append(v)
	return out


# 门格 = 走廊刚跨出房间边框的那一格，紧贴外墙，正好落在岩壁线上。
# step 决定往外是沿路径的哪个方向：1 = 顺路径往前（房间在路径起点，如 a），-1 = 逆路径（房间在终点，如 b）。
# 若边框格已经是路径端点（没有外侧邻居），退回边框格本身。
static func _door_cell(path: Array, room: Room, step: int) -> Vector2i:
	for i in path.size():
		if room.border(path[i].x, path[i].y):
			var j = i + step
			if j >= 0 and j < path.size():
				return path[j]
			return path[i]
	return Vector2i(-1, -1)
