extends Node
# 删除 class_name Bag

signal inventory_updated

var items: Array = []

# 初始背包：新游戏时给三种物品各一份；clear() 保证重进/新档是干净的一份而非累加
func init_starting_inventory() -> void:
	clear()

func add_item(item: Item) -> bool:
	if item.stackable:
		for inv_item in items:
			if inv_item.name() == item.name():
				inv_item.item_quantity += item.item_quantity
				emit_signal("inventory_updated")
				return true
	# 直接收原实例，不要 duplicate()：Resource.duplicate() 会重挂脚本、用默认实参重跑
	# _init，构造参数（如护甲等级）会被清零，只剩 _init 里重新算出来的字段。
	items.append(item)
	emit_signal("inventory_updated")
	return true

func remove_item(index: int) -> Item:
	if index < 0 or index >= items.size():
		return null
	var item = items[index]
	items.remove_at(index)
	emit_signal("inventory_updated")
	return item

# 取出一件：可堆叠且余量 >1 时只扣 1（返回数量为 1 的副本），否则整件移除。
# 供"每次只扔一个"的投掷使用；整摞放下仍用 remove_item。
func remove_one(index: int) -> Item:
	if index < 0 or index >= items.size():
		return null
	var item = items[index]
	if item.stackable and item.item_quantity > 1:
		item.item_quantity -= 1
		var one: Item = item.copy()   # 用 Item.copy()：duplicate() 会重跑 _init 清零构造参数
		one.item_quantity = 1
		emit_signal("inventory_updated")
		return one
	items.remove_at(index)
	emit_signal("inventory_updated")
	return item

func get_inventory() -> Array:
	return items

func clear():
	items.clear()
	emit_signal("inventory_updated")
