extends Node

# 空间查询与算法：在"当前这一层"上算能不能走、看不看得见、线怎么穿、路径怎么寻。
# 层数据（map_data / explored / 尺寸 / 出入口 / 层缓存）在 LevelManager，这里只读它；
# 本文件不持有任何地图状态。

# ---------- 辅助 ----------
func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= LevelManager.MAP_WIDTH or cell.y < 0 or cell.y >= LevelManager.MAP_HEIGHT:
		return false
	return Terrain.has_flag(LevelManager.map_data[cell.y][cell.x], Terrain.FLAG_PASSABLE)


func is_occupied(cell: Vector2i, exclude: Actor = null) -> bool:
	var monster = TurnManager.get_monster_at(cell)
	if monster != null and monster != exclude:
		return true
	return false


## 该格是不是一扇"关着的门"。开门不额外耗回合，是走进去的附带动作。
func is_door(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= LevelManager.MAP_WIDTH or cell.y < 0 or cell.y >= LevelManager.MAP_HEIGHT:
		return false
	return LevelManager.map_data[cell.y][cell.x] == Terrain.DOOR


## 把关着的门改成开着的门。成功返回 true；不是门（含上锁门）返回 false。
func open_door(cell: Vector2i) -> bool:
	if not is_door(cell):
		return false
	LevelManager.map_data[cell.y][cell.x] = Terrain.OPEN_DOOR
	return true


## 把开着的门关回去。成功返回 true；不是开着的门返回 false。
## 只改地形，不管"门格上有没有东西"——那是场景侧的事，由调用方先判定（见 GameScene.close_door_behind）。
func close_door(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= LevelManager.MAP_WIDTH or cell.y < 0 or cell.y >= LevelManager.MAP_HEIGHT:
		return false
	if LevelManager.map_data[cell.y][cell.x] != Terrain.OPEN_DOOR:
		return false
	LevelManager.map_data[cell.y][cell.x] = Terrain.DOOR
	return true


## 该格是不是一扇上锁的门。解锁要单独花一回合（见 Char.walk_to）。
func is_locked_door(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= LevelManager.MAP_WIDTH or cell.y < 0 or cell.y >= LevelManager.MAP_HEIGHT:
		return false
	return LevelManager.map_data[cell.y][cell.x] == Terrain.LOCKED_DOOR


## 给上锁的门解锁：直接变成开着的门。解锁本身耗一回合，由调用方 spend。
## 暂无钥匙系统——"必须要钥匙"的判定留给以后接在这里。
func unlock_door(cell: Vector2i) -> bool:
	if not is_locked_door(cell):
		return false
	LevelManager.map_data[cell.y][cell.x] = Terrain.OPEN_DOOR
	return true


## 返回一个随机可走且未被占用的空位；找不到返回 (-1, -1)
func get_random_empty_cell() -> Vector2i:
	for i in 200:
		var cell := Vector2i(randi_range(0, LevelManager.MAP_WIDTH - 1), randi_range(0, LevelManager.MAP_HEIGHT - 1))
		if is_walkable(cell) and not is_occupied(cell):
			return cell
	return Vector2i(-1, -1)


# ---------- 8 方向邻居偏移 ----------
const DIRS8 = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


func is_explored(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= LevelManager.MAP_WIDTH or cell.y < 0 or cell.y >= LevelManager.MAP_HEIGHT:
		return false
	return LevelManager.explored[cell.y][cell.x]


## 可作为点击目标：已探索格；或"临界未探明格"
func is_walk_target(cell: Vector2i) -> bool:
	if is_explored(cell):
		return true
	if not is_walkable(cell):
		return false
	for d in DIRS8:
		if is_explored(cell + d):
			return true
	return false


# ---------- 寻路（Pathfinding 适配） ----------
func to_index(cell: Vector2i) -> int:
	return cell.y * LevelManager.MAP_WIDTH + cell.x


func to_cell(index: int) -> Vector2i:
	return Vector2i(index % LevelManager.MAP_WIDTH, index / LevelManager.MAP_WIDTH)


## 可通行位图：1=可走。
## explored_only=true 供玩家自动行走；怪物 AI 传 false。
func build_passable(exclude: Char = null, explored_only: bool = true) -> PackedByteArray:
	var passable := PackedByteArray()
	passable.resize(LevelManager.MAP_WIDTH * LevelManager.MAP_HEIGHT)
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			var cell := Vector2i(x, y)
			var ok := is_walkable(cell)
			if ok and explored_only and not LevelManager.explored[y][x]:
				ok = false
			if ok and is_occupied(cell, exclude):
				ok = false
			passable[y * LevelManager.MAP_WIDTH + x] = 1 if ok else 0
	return passable


# ---------- 投掷落点 ----------
## 投掷落点。交给 Ballistica 解——原版 Item.throwPos 就是
## `new Ballistica(user.pos, dst, Ballistica.PROJECTILE).collisionPos`，一字对应。
## 别改回自己数格子：格子序列本身与 Ballistica 不同（见 Ballistica.gd 顶部），落点会偏。
func throw_landing_cell(from: Vector2i, to: Vector2i) -> Vector2i:
	return Ballistica.new(from, to).collision


# ---------- 传送 ----------
func teleport(actor: Char, target_cell: Vector2i = Vector2i(-1, -1)) -> String:
	if target_cell == Vector2i(-1, -1):
		target_cell = _find_teleport_cell(actor)
		if target_cell == Vector2i(-1, -1):
			return ""
	else:
		if not is_walkable(target_cell) or is_occupied(target_cell):
			return ""
	actor.grid_pos = target_cell
	var gs = actor.game_scene
	if gs != null and gs.has_method("cell_to_world"):
		actor.position = gs.cell_to_world(target_cell)
		if actor is Hero:
			actor.fieldofview()
			record_sight(actor.FOV)
	return "{0} 传送至 ({1},{2})".format([actor.name, target_cell.x, target_cell.y])


func _find_teleport_cell(actor: Char) -> Vector2i:
	for i in 100:
		var cell := get_random_empty_cell()
		if cell == Vector2i(-1, -1):
			return Vector2i(-1, -1)
		if cell != actor.grid_pos:
			return cell
	return Vector2i(-1, -1)


# ---------- 记录视野：把一份可见网格并入已探索 ----------
func record_sight(grid: Array) -> void:
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			if grid[y][x]:
				LevelManager.explored[y][x] = true
