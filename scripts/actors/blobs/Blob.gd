class_name Blob
extends Actor

var volume: int = 0
var cur: PackedInt32Array
var off: PackedInt32Array
var area: Rect2i = Rect2i()
var emitter = null
var always_visible: bool = false


func _init() -> void:
	act_priority = BLOB_PRIO


func act() -> bool:
	spend(TICK)

	if volume > 0:
		if _area_empty():
			_setup_area()
		volume = 0
		_evolve()
		var tmp := off
		off = cur
		cur = tmp
	else:
		if not _area_empty():
			area = Rect2i()
			off = cur.duplicate()

	return true


# 空矩形：Godot Rect2i() 的 size 为 (0,0)。对应原版 Rect.isEmpty()（right<=left 或 bottom<=top）。
func _area_empty() -> bool:
	return area.size.x <= 0 or area.size.y <= 0


# 把一格并进 area。原版 Rect.union(x,y) 对空矩形有特判：空时直接置成该格 1x1，
# 绝不与原点 (0,0) 相并。Godot 的 Rect2i.merge 没有这个特判，会悄悄把原点吞进来，故手写。
func _union(x: int, y: int) -> void:
	if _area_empty():
		area = Rect2i(x, y, 1, 1)
		return
	var left := area.position.x
	var top := area.position.y
	var right := area.position.x + area.size.x
	var bottom := area.position.y + area.size.y
	if x < left:
		left = x
	elif x >= right:
		right = x + 1
	if y < top:
		top = y
	elif y >= bottom:
		bottom = y + 1
	area = Rect2i(left, top, right - left, bottom - top)


func _setup_area() -> void:
	for cell in cur.size():
		if cur[cell] != 0:
			_union(cell % LevelManager.MAP_WIDTH, cell / LevelManager.MAP_WIDTH)


# 扩散：把 cur 里每一格的量向四周非实心邻格摊平后减 1，结果写进 off。
# 边界与原版 Level.insideMap 同义——最外一圈（上下左右贴边）算界外，故直接按格坐标判 i/j 是否在内圈。
# 循环上下界与邻格条件都随 area 的扩张实时变化（原版 for 每轮重读 area.bottom/right），下面用 while 保真。
func _evolve() -> void:
	var w := LevelManager.MAP_WIDTH
	var h := LevelManager.MAP_HEIGHT
	var map = LevelManager.level.map_data
	var i: int = area.position.y - 1
	while i <= area.end.y:
		var j: int = area.position.x - 1
		while j <= area.end.x:
			if i > 0 and i < h - 1 and j > 0 and j < w - 1:
				if not Terrain.has_flag(map[i][j], Terrain.FLAG_SOLID):
					var count := 1
					var sum := cur[j + i * w]

					if j > area.position.x and not Terrain.has_flag(map[i][j - 1], Terrain.FLAG_SOLID):
						sum += cur[j + i * w - 1]; count += 1
					if j < area.end.x and not Terrain.has_flag(map[i][j + 1], Terrain.FLAG_SOLID):
						sum += cur[j + i * w + 1]; count += 1
					if i > area.position.y and not Terrain.has_flag(map[i - 1][j], Terrain.FLAG_SOLID):
						sum += cur[j + (i - 1) * w]; count += 1
					if i < area.end.y and not Terrain.has_flag(map[i + 1][j], Terrain.FLAG_SOLID):
						sum += cur[j + (i + 1) * w]; count += 1

					var value: int = ((sum / count) - 1) if sum >= count else 0
					off[j + i * w] = value

					if value > 0:
						var left := area.position.x
						var top := area.position.y
						var right := area.end.x
						var bottom := area.end.y
						if i < top:
							top = i
						elif i >= bottom:
							bottom = i + 1
						if j < left:
							left = j
						elif j >= right:
							right = j + 1
						area = Rect2i(left, top, right - left, bottom - top)
						volume += value
				else:
					off[j + i * w] = 0
			j += 1
		i += 1


func seed(cell: int, amount: int) -> void:
	if cur.is_empty():
		cur.resize(LevelManager.MAP_WIDTH * LevelManager.MAP_HEIGHT)
		off.resize(cur.size())
	cur[cell] += amount
	volume += amount
	_union(cell % LevelManager.MAP_WIDTH, cell / LevelManager.MAP_WIDTH)


func clear(cell: int) -> void:
	if volume == 0:
		return
	volume -= cur[cell]
	cur[cell] = 0


func fully_clear() -> void:
	volume = 0
	area = Rect2i()
	cur.resize(0)
	off.resize(0)

static func seed_blob(cell: int, amount: int, blob_class) -> Blob:
	var level := LevelManager.level
	var gas: Blob = level.blobs.get(blob_class)
	if gas == null:
		gas = blob_class.new()
		# 原版：若新 gas 排在本回合行动者之后，先补一格时间，
		# 免得它在被种下的这一回合里立刻又动一次（多得一个"额外回合"）。
		var cur_prio: int = Actor.current.act_priority if Actor.current != null else HERO_PRIO
		if cur_prio < gas.act_priority:
			gas.spend(1.0)
		level.blobs[blob_class] = gas
	gas.seed(cell, amount)
	return gas


static func volume_at(cell: int, blob_class) -> int:
	var gas: Blob = LevelManager.level.blobs.get(blob_class)
	if gas == null or gas.volume == 0:
		return 0
	return gas.cur[cell]
