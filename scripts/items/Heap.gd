extends Bundlable
class_name Heap

# 地面物品堆：某一格上的全部物品（原版 items/Heap.java）。
# 一格一个 Heap（数据）+ 一个 HeapNode（视图），取代过去"一个物品一个 ItemNode"。
# 于是同一格上多件物品天然共存，且拾一件后其余仍在（原版行为）。
#
# 队首 items[0] 是最后放下的、也是下一个被拾的——直译原版 LinkedList 的
# addFirst / peek / removeFirst（原版 Heap.drop 默认 addFirst，只有 dropsDownHeap 才 add）。
# type 只留 HEAP：宝箱 / 墓碑 / 尸骸等机制本工程还没有，等有了再加，不造空壳常量。
enum Type { HEAP }

var pos: Vector2i = Vector2i.ZERO
var type: int = Type.HEAP
var seen: bool = false

var items: Array = []

# 表现节点弱引用（HeapNode）。不注解类型：本类若静态引用 HeapNode，
# 会与 HeapNode.heap 构成 class_name 互相引用 → 解析失败（同 Actor.gd 顶部那条）。
# "谁是我的数据"由 HeapNode.heap 承担，两边各持一边、不成环。
var sprite = null

func size() -> int:
	return items.size()

func is_empty() -> bool:
	return items.is_empty()

# 队首那件（下一个被拾的）。空堆返回 null。
func peek() -> Item:
	return items.front() if not items.is_empty() else null

# 取走队首那件。空堆返回 null；堆空之后的拆卸（remove_heap / 释放节点）由调用方办。
func pick_up() -> Item:
	if items.is_empty():
		return null
	return items.pop_front()

# 放入一件。可堆叠的先与同类合并（直译原版 Heap.drop 的 stackable 分支），
# 否则放到队首——后放的在最上、也下一个被拾。
func drop(item: Item) -> void:
	if item.stackable:
		for i: Item in items:
			if i.is_similar(item):
				i.merge(item)
				return
	items.push_front(item)

func remove(item: Item) -> void:
	items.erase(item)

# ---------- 存档 ----------
# pos 进不了 JSON，拆成 [x, y]（与 LevelManager.cell_to_arr 同一约定）。
func serialize() -> Dictionary:
	var out := []
	for i: Item in items:
		out.append(i.serialize())
	return { "pos": [pos.x, pos.y], "type": type, "seen": seen, "items": out }

func deserialize(data: Dictionary) -> void:
	var p = data.get("pos", [0, 0])
	pos = Vector2i(int(p[0]), int(p[1]))
	type = int(data.get("type", Type.HEAP))
	seen = data.get("seen", false)
	items.clear()
	for d in data.get("items", []):
		# 旧档 / 脚本失效的条目不是字典或建不出来：跳过，不让一件读不回来的东西拖崩整堆。
		if d is not Dictionary:
			continue
		var item: Item = Item.from_data(d)
		if item != null:
			items.append(item)

# 由存档字典重建一个堆。空字典返回 null（调用方据此跳过）。
static func from_data(data: Dictionary) -> Heap:
	if data.is_empty():
		return null
	var h := Heap.new()
	h.deserialize(data)
	return h
