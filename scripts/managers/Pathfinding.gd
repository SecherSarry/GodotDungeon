class_name Pathfinding
extends RefCounted

# ==================== 静态数据 ====================
static var distance: PackedInt32Array      # 每个格子到目标的最短距离
static var max_val: PackedInt32Array       # 全 MAX_VALUE，用于快速重置
static var goals: PackedByteArray          # 多目标时标记目标格子
static var queue: PackedInt32Array         # BFS 队列
static var queued: PackedByteArray         # getStepBack 去重
static var size: int = 0
static var width: int = 0

static var dir: PackedInt32Array           # 8方向，用于找最小邻居
static var dir_lr: PackedInt32Array        # 8方向，用于 BFS

# 邻居数组
static var NEIGHBOURS4: PackedInt32Array
static var NEIGHBOURS8: PackedInt32Array
static var NEIGHBOURS9: PackedInt32Array
static var CIRCLE4: PackedInt32Array
static var CIRCLE8: PackedInt32Array

const MAX_INT := 2147483647

# ==================== 初始化 ====================
static func set_map_size(w: int, h: int) -> void:
	width = w
	size = w * h

	distance = PackedInt32Array()
	distance.resize(size)

	goals = PackedByteArray()
	goals.resize(size)

	queue = PackedInt32Array()
	queue.resize(size)

	queued = PackedByteArray()
	queued.resize(size)

	max_val = PackedInt32Array()
	max_val.resize(size)
	max_val.fill(MAX_INT)

	dir = PackedInt32Array([-1, 1, -w, w, -w - 1, -w + 1, w - 1, w + 1])
	dir_lr = PackedInt32Array([-1 - w, -1, -1 + w, -w, w, 1 - w, 1, 1 + w])

	NEIGHBOURS4 = PackedInt32Array([-w, -1, 1, w])
	NEIGHBOURS8 = PackedInt32Array([-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1])
	NEIGHBOURS9 = PackedInt32Array([-w - 1, -w, -w + 1, -1, 0, 1, w - 1, w, w + 1])
	CIRCLE4 = PackedInt32Array([-w, 1, w, -1])
	CIRCLE8 = PackedInt32Array([-w - 1, -w, -w + 1, 1, w + 1, w, w - 1, -1])

# ==================== 重置 distance ====================
static func _reset_distance() -> void:
	# 用 arraycopy 等价物快速复制 max_val 到 distance
	for i in size:
		distance[i] = MAX_INT

# ==================== find：返回完整路径 ====================
static func find(from: int, to: int, passable: PackedByteArray) -> Array[int]:
	if not _build_distance_map_single(from, to, passable):
		return []

	var result: Array[int] = []
	var s := from
	while true:
		var min_d := distance[s]
		var mins := s
		for i in dir.size():
			var n := s + dir[i]
			if n < 0 or n >= size:
				continue
			var this_d := distance[n]
			if this_d < min_d:
				min_d = this_d
				mins = n
		s = mins
		result.append(s)
		if s == to:
			break
	return result

# ==================== getStep：返回下一步 ====================
static func get_step(from: int, to: int, passable: PackedByteArray) -> int:
	if not _build_distance_map_single(from, to, passable):
		return -1

	var min_d := distance[from]
	var best := from
	for i in dir.size():
		var n := from + dir[i]
		if n < 0 or n >= size:
			continue
		var step_d := distance[n]
		if step_d < min_d:
			min_d = step_d
			best = n
	return best

# ==================== getStepBack：逃跑 ====================
static func get_step_back(cur: int, from: int, lookahead: int, passable: PackedByteArray, can_approach_from_pos: bool) -> int:
	var d := _build_escape_distance_map(cur, from, lookahead, passable)
	if d == 0:
		return -1

	if not can_approach_from_pos:
		var head := 0
		var tail := 0
		var new_d := distance[cur]
		queued.fill(0)

		queue[tail] = cur
		tail += 1
		queued[cur] = 1

		while head < tail:
			var step := queue[head]
			head += 1

			if distance[step] > new_d:
				new_d = distance[step]

			var start := 3 if step % width == 0 else 0
			var end := 3 if (step + 1) % width == 0 else 0
			for i in range(start, dir_lr.size() - end):
				var n := step + dir_lr[i]
				if n >= 0 and n < size and passable[n] == 1:
					if distance[n] < distance[cur]:
						passable[n] = 0
					elif distance[n] >= distance[step] and queued[n] == 0:
						queue[tail] = n
						tail += 1
						queued[n] = 1

		d = min(new_d, d)

	for i in size:
		goals[i] = 1 if distance[i] == d else 0
	if not _build_distance_map_multi(cur, goals, passable):
		return -1

	var s := cur
	var min_d := distance[s]
	var mins := s
	for i in dir.size():
		var n := s + dir[i]
		if n < 0 or n >= size:
			continue
		var this_d := distance[n]
		if this_d < min_d:
			min_d = this_d
			mins = n
	return mins

# ==================== 内部：单目标 BFS ====================
static func _build_distance_map_single(from: int, to: int, passable: PackedByteArray) -> bool:
	if from == to:
		return false

	_reset_distance()

	var path_found := false
	var head := 0
	var tail := 0

	queue[tail] = to
	tail += 1
	distance[to] = 0

	while head < tail:
		var step := queue[head]
		head += 1

		if step == from:
			path_found = true
			break

		var next_distance := distance[step] + 1
		var start := 3 if step % width == 0 else 0
		var end := 3 if (step + 1) % width == 0 else 0
		for i in range(start, dir_lr.size() - end):
			var n := step + dir_lr[i]
			if n == from or (n >= 0 and n < size and passable[n] == 1 and distance[n] > next_distance):
				queue[tail] = n
				tail += 1
				distance[n] = next_distance

	return path_found

# ==================== 内部：多目标 BFS ====================
static func _build_distance_map_multi(from: int, to: PackedByteArray, passable: PackedByteArray) -> bool:
	if to[from] == 1:
		return false

	_reset_distance()

	var path_found := false
	var head := 0
	var tail := 0

	for i in size:
		if to[i] == 1:
			queue[tail] = i
			tail += 1
			distance[i] = 0

	while head < tail:
		var step := queue[head]
		head += 1

		if step == from:
			path_found = true
			break

		var next_distance := distance[step] + 1
		var start := 3 if step % width == 0 else 0
		var end := 3 if (step + 1) % width == 0 else 0
		for i in range(start, dir_lr.size() - end):
			var n := step + dir_lr[i]
			if n == from or (n >= 0 and n < size and passable[n] == 1 and distance[n] > next_distance):
				queue[tail] = n
				tail += 1
				distance[n] = next_distance

	return path_found

# ==================== 公开：带 limit 的 BFS ====================
static func build_distance_map_limit(to: int, passable: PackedByteArray, limit: int) -> void:
	_reset_distance()

	var head := 0
	var tail := 0

	queue[tail] = to
	tail += 1
	distance[to] = 0

	while head < tail:
		var step := queue[head]
		head += 1

		var next_distance := distance[step] + 1
		if next_distance > limit:
			return

		var start := 3 if step % width == 0 else 0
		var end := 3 if (step + 1) % width == 0 else 0
		for i in range(start, dir_lr.size() - end):
			var n := step + dir_lr[i]
			if n >= 0 and n < size and passable[n] == 1 and distance[n] > next_distance:
				queue[tail] = n
				tail += 1
				distance[n] = next_distance

# ==================== 公开：完整 BFS ====================
static func build_distance_map(to: int, passable: PackedByteArray) -> void:
	_reset_distance()

	var head := 0
	var tail := 0

	queue[tail] = to
	tail += 1
	distance[to] = 0

	while head < tail:
		var step := queue[head]
		head += 1
		var next_distance := distance[step] + 1

		var start := 3 if step % width == 0 else 0
		var end := 3 if (step + 1) % width == 0 else 0
		for i in range(start, dir_lr.size() - end):
			var n := step + dir_lr[i]
			if n >= 0 and n < size and passable[n] == 1 and distance[n] > next_distance:
				queue[tail] = n
				tail += 1
				distance[n] = next_distance

# ==================== 内部：逃跑距离图 ====================
static func _build_escape_distance_map(cur: int, from: int, look_ahead: int, passable: PackedByteArray) -> int:
	_reset_distance()

	var dest_dist := MAX_INT
	var head := 0
	var tail := 0

	queue[tail] = from
	tail += 1
	distance[from] = 0

	var dist := 0

	while head < tail:
		var step := queue[head]
		head += 1
		dist = distance[step]

		if dist > dest_dist:
			return dest_dist

		if step == cur:
			dest_dist = dist + look_ahead

		var next_distance := dist + 1
		var start := 3 if step % width == 0 else 0
		var end := 3 if (step + 1) % width == 0 else 0
		for i in range(start, dir_lr.size() - end):
			var n := step + dir_lr[i]
			if n >= 0 and n < size and passable[n] == 1 and distance[n] > next_distance:
				queue[tail] = n
				tail += 1
				distance[n] = next_distance

	return dist
