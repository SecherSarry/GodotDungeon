extends Node
# 删除 class_name Bag

signal inventory_updated

var items: Array = []

# 初始背包：新游戏时给三种物品各一份；clear() 保证重进/新档是干净的一份而非累加
func init_starting_inventory() -> void:
	clear()
	PotionOfHealing.new().collect(5)
	PotionOfStrength.new().collect(5)
	PotionOfExperience.new().collect(5)
	
	ScrollOfMagicMapping.new().collect(3)
	ScrollOfTeleportation.new().collect(5)
	
	WornShortsword.new().collect()
	Whip.new().collect()

func add_item(item: Item) -> bool:
	if item.stackable:
		for inv_item in items:
			if inv_item.item_name == item.item_name:
				inv_item.quantity += item.quantity
				emit_signal("inventory_updated")
				return true
	items.append(item.duplicate())
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
	if item.stackable and item.quantity > 1:
		item.quantity -= 1
		var one: Item = item.duplicate()
		one.quantity = 1
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
