extends Node

# 纯文件 IO：读写槽位 JSON 与楼层 JSON、删档、查有没有档。
# 不碰任何游戏流程——什么时候存、存什么、读完怎么还原，全由 GameState 决定；
# 本类只认路径与字典，不知道 GameState / LevelManager 的存在。

var cur_slot = 0
const MAX_SLOTS = 5
const SAVE_DIR := "user://saves/"
const MAP_FILE_FMT := "floor_%d.json"

func _slot_dir(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d" % slot)

func _slot_path(slot: int) -> String:
	return _slot_dir(slot).path_join("slot_%d.json" % slot)

func _map_path(slot: int, depth: int) -> String:
	return _slot_dir(slot).path_join(MAP_FILE_FMT % depth)

# ---------- 槽位存档（GameState 自身那本） ----------
func write_game(slot: int, data: Dictionary) -> bool:
	if slot < 0:
		slot = cur_slot
	data = data.duplicate()
	data["version"] = ProjectSettings.get_setting("application/config/version")
	var ok = write_json(_slot_path(slot), data)
	print("[SaveManager] write_game(slot:%d): %s" % [slot, "成功" if ok else "失败"])
	return ok

# 读回来原样交给 GameState.deserialize；无档返回空字典。
func read_game(slot: int) -> Dictionary:
	return _read_json(_slot_path(slot))

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

# ---------- 楼层 ----------
func write_floor(slot: int, depth: int, data: Dictionary) -> bool:
	var ok = write_json(_map_path(slot, depth), data)
	if not ok:
		print("[SaveManager] write_floor(depth:%d, slot:%d) 失败" % [depth, slot])
	return ok

func read_floor(slot: int, depth: int) -> Dictionary:
	return _read_json(_map_path(slot, depth))

# 删掉该槽位磁盘上的全部楼层文件（主档不动）。
# 存档前先清一次：否则上一局残留的 floor_N.json 会在下次 load_game 的 list_floors 里被读进来，
# 把不相干的楼层灌进这一局。
func clear_floors(slot: int) -> void:
	for depth in list_floors(slot):
		delete_json(_map_path(slot, depth))

# 该槽位磁盘上已存了哪些层（升序）。
func list_floors(slot: int) -> Array:
	var out := []
	var dir := DirAccess.open(_slot_dir(slot))
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("floor_") and f.ends_with(".json"):
			out.append(int(f.trim_prefix("floor_").trim_suffix(".json")))
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

# ---------- 删档 ----------
# 主档与全部楼层文件一并删，不留半截存档。
func delete_game(slot: int) -> bool:
	var ok := delete_json(_slot_path(slot))
	for depth in list_floors(slot):
		delete_json(_map_path(slot, depth))
	print("[SaveManager] delete_game(slot:%d): %s" % [slot, "成功" if ok else "失败"])
	return ok

func get_first_empty_slot() -> int:
	for i in MAX_SLOTS:
		if not has_save(i):
			return i
	return -1

# ---------- 底层 JSON IO ----------
func write_json(path: String, data: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[SaveManager] write_json(%s): 无法创建文件" % path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法打开：%s，错误码 %d" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON 解析失败：%s，第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func delete_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK
