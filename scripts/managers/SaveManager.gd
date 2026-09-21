# SaveManager.gd — autoload
extends Node

# ==================== 常量 ====================
const SAVE_DIR := "user://saves/"
const MAP_DIR := SAVE_DIR + "maps/"
const MAP_FILE_FMT := "floor_%d.json"
const PREVIEW_FILE := "preview.json"
const MAX_SLOTS := 4

# ==================== 状态 ====================
var current_slot: int = 0

# 当前层活实体（怪/地面物品）的采集入口：SaveManager 只认数据、不认节点，
# 故由场景层（GameScene）在就绪时把 capture_entities 挂进来。
# 未挂（如无场景）则视为无实体，不编造数据。
var entity_provider: Callable = Callable()


func _live_entities() -> Dictionary:
	if entity_provider.is_valid():
		return entity_provider.call()
	return { "monsters": [], "items": [] }


# ==================== 公共 API：地图 ====================

## 保存当前层到磁盘
func save_current_map() -> void:
	save_map(LevelManager.current_depth)


## 保存指定层到磁盘
func save_map(depth: int) -> void:
	var bundle := _build_map_bundle(depth)
	if bundle.is_empty():
		return
	var path := _map_path(current_slot, depth)
	_write_json(path, bundle)
	print("SaveManager: 地图已保存 ", path)


## 读取指定层到 MapManager（替换当前 map_data / explored / spawn / exit / 深度）
## 成功返回 true；文件不存在返回 false
func load_map(depth: int) -> bool:
	var path := _map_path(current_slot, depth)
	if not FileAccess.file_exists(path):
		return false
	var bundle := _read_json(path)
	if bundle.is_empty():
		return false
	_apply_map_bundle(bundle)
	# 同时填入内存缓存：场景重建走与"离开该层"同一条路径（get_floor_entities 取怪/物快照）。
	LevelManager.floor_cache[depth] = _bundle_to_cache(bundle)
	print("SaveManager: 地图已读取 ", path)
	return true


## 读取当前层
func load_current_map() -> bool:
	return load_map(LevelManager.current_depth)


## 只把磁盘上的某层读进内存缓存，不动当前地图状态（与 load_map 的区别：不 _apply）。
## 换层前预载目标层用：读到了 floor_cache 就有了，enter_floor 会走"返回"分支；读不到返回 false。
func cache_map_from_disk(depth: int) -> bool:
	var bundle := _read_json(_map_path(current_slot, depth))
	if bundle.is_empty():
		return false
	LevelManager.floor_cache[depth] = _bundle_to_cache(bundle)
	return true


## 保存所有已缓存楼层（含当前层）
func save_all_maps() -> void:
	# 已离开的层在 floor_cache 里；当前层不在其中，单独补上——
	# 它的怪/物走 _live_entities 取活实体，不再往缓存里塞空快照。
	var depths: Array = LevelManager.floor_cache.keys()
	if not depths.has(LevelManager.current_depth):
		depths.append(LevelManager.current_depth)
	for depth in depths:
		save_map(depth)
	print("SaveManager: 全部楼层已保存，共 ", depths.size(), " 层")


## 读取所有层到 LevelManager.floor_cache（不改变当前层）
func load_all_maps() -> void:
	LevelManager.floor_cache.clear()
	var dir_path := _map_dir(current_slot)
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		if not f.begins_with("floor_") or not f.ends_with(".json"):
			continue
		var depth := int(f.trim_prefix("floor_").trim_suffix(".json"))
		var bundle := _read_json(dir_path.path_join(f))
		if bundle.is_empty():
			continue
		LevelManager.floor_cache[depth] = _bundle_to_cache(bundle)
	print("SaveManager: 已读取所有楼层，共 ", LevelManager.floor_cache.size(), " 层")


## 删除指定层存档
func delete_map(depth: int) -> void:
	var path := _map_path(current_slot, depth)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	LevelManager.floor_cache.erase(depth)


## 删除当前槽位的所有地图存档
func delete_all_maps() -> void:
	var dir_path := _map_dir(current_slot)
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		if f.begins_with("floor_") and f.ends_with(".json"):
			DirAccess.remove_absolute(dir_path.path_join(f))
	LevelManager.floor_cache.clear()


# ==================== 公共 API：槽位 ====================

func first_empty_slot() -> int:
	for i in range(MAX_SLOTS):
		if not DirAccess.dir_exists_absolute(_slot_dir(i)):
			return i
	return -1


func slot_exists(slot: int) -> bool:
	return DirAccess.dir_exists_absolute(_slot_dir(slot))


func delete_slot(slot: int) -> void:
	var dir_path := _slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(f))
	DirAccess.remove_absolute(dir_path)


func copy_slot(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot:
		return false
	var from_dir := _slot_dir(from_slot)
	if not DirAccess.dir_exists_absolute(from_dir):
		return false
	var to_dir := _slot_dir(to_slot)
	DirAccess.make_dir_recursive_absolute(to_dir)
	for f in DirAccess.get_files_at(from_dir):
		DirAccess.copy_absolute(from_dir.path_join(f), to_dir.path_join(f))
	return true


# ==================== 内部：构建 bundle ====================

func _build_map_bundle(depth: int) -> Dictionary:
	var cache: Dictionary
	if depth == LevelManager.current_depth:
		var ents := _live_entities()
		cache = {
			"map_data": LevelManager.map_data,
			"explored": LevelManager.explored,
			"hero_spawn": LevelManager.hero_spawn,
			"exit_cell": LevelManager.exit_cell,
			"monsters": ents["monsters"],
			"items": ents["items"],
		}
	elif LevelManager.floor_cache.has(depth):
		cache = LevelManager.floor_cache[depth]
	else:
		push_error("SaveManager: 深度 %d 无数据可存" % depth)
		return {}

	return {
		"version": 1,
		"depth": depth,
		"width": LevelManager.MAP_WIDTH,
		"height": LevelManager.MAP_HEIGHT,
		"map_data": _flatten_2d(cache["map_data"]),
		"explored": _flatten_2d(cache["explored"]),
		"hero_spawn": _vec_to_arr(cache["hero_spawn"]),
		"exit_cell": _vec_to_arr(cache["exit_cell"]),
		"monsters": _serialize_monsters(cache.get("monsters", [])),
		"items": _serialize_items(cache.get("items", [])),
	}


# ==================== 内部：应用 bundle ====================

func _apply_map_bundle(bundle: Dictionary) -> void:
	var w: int = bundle.get("width", LevelManager.MAP_WIDTH)
	var h: int = bundle.get("height", LevelManager.MAP_HEIGHT)
	LevelManager.map_data = _unflatten_2d(bundle["map_data"], w, h, true)
	LevelManager.explored = _unflatten_2d(bundle["explored"], w, h)
	LevelManager.hero_spawn = _arr_to_vec(bundle["hero_spawn"])
	LevelManager.exit_cell = _arr_to_vec(bundle["exit_cell"])
	LevelManager.current_depth = bundle.get("depth", LevelManager.current_depth)


func _bundle_to_cache(bundle: Dictionary) -> Dictionary:
	var w: int = bundle.get("width", LevelManager.MAP_WIDTH)
	var h: int = bundle.get("height", LevelManager.MAP_HEIGHT)
	return {
		"map_data": _unflatten_2d(bundle["map_data"], w, h, true),
		"explored": _unflatten_2d(bundle["explored"], w, h),
		"hero_spawn": _arr_to_vec(bundle["hero_spawn"]),
		"exit_cell": _arr_to_vec(bundle["exit_cell"]),
		"monsters": _deserialize_monsters(bundle.get("monsters", [])),
		"items": _deserialize_items(bundle.get("items", [])),
	}


# ==================== 内部：路径 ====================

func _slot_dir(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d" % slot)


func _map_dir(slot: int) -> String:
	return _slot_dir(slot).path_join("maps")


func _map_path(slot: int, depth: int) -> String:
	return _map_dir(slot).path_join(MAP_FILE_FMT % depth)


# ==================== 内部：文件 IO ====================

func _write_json(path: String, data: Dictionary) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: 无法写入 %s" % path)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveManager: 解析失败 %s" % path)
		return {}
	return parsed


# ==================== 内部：类型转换 ====================

func _flatten_2d(arr: Array) -> Array:
	var result := []
	if arr == null:
		return result
	for row in arr:
		if row is Array:
			result.append_array(row)
		else:
			result.append(row)
	return result


# JSON 把所有数字都解析成 float（Godot 已知行为），地形 id 会变成 4.0 这种。
# 渲染层的 match / in 是类型严格的（4.0 不匹配 4），而水层的 == 宽松——读档后正是
# "水还在、地面与墙全没了"。故地形表用 as_int 转回 int；explored 是布尔，保持原样。
func _unflatten_2d(flat: Array, w: int, h: int, as_int: bool = false) -> Array:
	var result := []
	for y in h:
		var row := []
		for x in w:
			var idx := y * w + x
			var v = flat[idx] if idx < flat.size() else 0
			row.append(int(v) if as_int else v)
		result.append(row)
	return result


func _vec_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]


func _arr_to_vec(a) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO


# ==================== 内部：怪物 / 物品序列化 ====================

func _serialize_monsters(arr: Array) -> Array:
	var result := []
	for m in arr:
		result.append({
			"cell": _vec_to_arr(m["cell"]),
			"hp": m.get("hp", 0),
			"max_hp": m.get("max_hp", 0),
		})
	return result


func _deserialize_monsters(arr: Array) -> Array:
	var result := []
	for m in arr:
		result.append({
			"cell": _arr_to_vec(m["cell"]),
			"hp": m.get("hp", 0),
			"max_hp": m.get("max_hp", 0),
		})
	return result


func _serialize_items(arr: Array) -> Array:
	var result := []
	for e in arr:
		var item = e.get("item", null)
		result.append({
			"cell": _vec_to_arr(e["cell"]),
			"item": item.serialize() if item and item.has_method("serialize") else {},
		})
	return result


func _deserialize_items(arr: Array) -> Array:
	var result := []
	for e in arr:
		var item_data = e.get("item", {})
		var item = null
		result.append({
			"cell": _arr_to_vec(e["cell"]),
			"item": item,
		})
	return result
