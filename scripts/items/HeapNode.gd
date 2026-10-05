extends Node2D

# 地面物品堆的表现节点：一格一个 HeapNode，画堆顶那件（heap.peek()）。
# 与 Actor 那条线同构：Heap(Resource) + HeapNode(Node2D) ↔ Actor(Resource) + ActorNode(Node2D)。
# 数据（pos / items）在 heap 那份 Resource 上，本节点只管画面。
#
# 不加 class_name：本类静态引用 Heap（heap 的类型），数据侧 Heap.sprite 则不写类型，
# 只保留"节点引用数据"这一个方向，避免 class_name 互相引用导致解析失败（同 ActorNode.gd 顶部）。
var heap: Heap = null

# 冗余存一份格坐标，供场景遍历做匹配（读 peek 之外不必回数据层取）。
var grid_pos: Vector2i = Vector2i.ZERO

# 节点层薄壳：把英雄递给堆顶那件，按其类型分发拾取。
# 是否真拾进包由 item.do_pickup 判定；"从堆里摘除"由 GameScene.try_collect 在成功后办。
func do_pickup(hero: Hero) -> bool:
	if heap == null or heap.is_empty():
		return false
	return heap.peek().do_pickup(hero)
