extends Item
class_name Bag

var owner: Char

var items: Array = []

func capacity() -> int:
	return 20

# SPD 的 Bag 有 grabItems() / grabItems(Bag container) 两个重载；GDScript 无重载，故合成一个：
# 不传 container 即无参版——它只对**嵌套袋**有意义（把英雄主背包里装得下的东西吸进自己），
# 主背包调用它自己是 no-op。原版正是这条守卫切断无限递归：Item.detachAll 结尾会回调
# container.grabItems()，若主背包也照跑，就会 detachAll → grabItems → detachAll … 指数展开，
# 20 格的背包直接把游戏卡死（装备即触发：do_equip 一上来就 detach_all(backpack)）。
func grab_items(container: Bag = null) -> void:
	if container == null:
		var o := owner as Hero
		if o != null and self != o.backpack:
			grab_items(o.backpack)
		return
	# 遍历 container.items 的**副本**：detach_all / collect 会就地增删 container.items，
	# 直接遍历活数组会漏项、重复（原版 toArray(new Item[0]) 同理）。
	for item: Item in container.items.duplicate():
		if can_hold(item):
			item.detach_all(container)
			if not item.collect(self):
				item.collect(container)
			
func contains(item: Item) -> bool:
	for i in items:
		if i == item:
			return true
		elif i is Bag and i.contains(item):
			return true
	return false

func can_hold(item: Item) -> bool:
	if item in items or item is Bag or items.size() < capacity():
		return true
	elif item.stackable:
		for i in items:
			if item.is_similar(i):
				return true
	return false


#---------------------------------------
signal inventory_updated


# 开一局前的背包清场，由 GameState._reset_run 调用。
# 此前叫 init_starting_inventory，名字撒了谎——它只是 clear()，初始物品其实由
# HeroClass.init_hero 发放（见 GameState._reset_run 的次序注释）。改回贴切的名字。
func reset() -> void:
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

# ---------- 存档 ----------
# 逐件走 Item.serialize（脚本路径 + 标量属性），不能把 Item 实例直接塞进字典——
# Resource 实例 JSON.stringify 出来是 "():<Resource#...>" 这种废话，落盘即废。
# 本类覆写了 Item.serialize，故先 super() 补上 {"script","props"} 信封（Item.from_data 靠 "script" 重建），
# 再挂 "inventory"。嵌套袋（作为 items 里的一件）因此也能经 from_data 还原；
# 顶层背包的信封不参与重建（Belongings 知道自己装的是 Backpack，直接调 deserialize），留着无害。
func serialize() -> Dictionary:
	var data: Dictionary = super.serialize()
	var inv := []
	for item: Item in items:
		inv.append(item.serialize())
	data["inventory"] = inv
	return data

var loading: bool = false
# 读档还原：先清空再逐件重建。
# 直接 append 不走 add_item / collect——存下来的每一摞本来就是合并好的，同类合并会把
# 两摞同名物品又并回去（数量对不上，且并的顺序改变包里的次序）；更不该在还原途中触发
# Talent.on_item_collected 这类收集副作用。from_data 建不出来（脚本丢失）的条目跳过。
func deserialize(data: Dictionary) -> void:
	items.clear()
	loading = true
	for d in data.get("inventory", []):
		# 旧档（Bag.serialize 修好之前写的）里每项是 "():<Resource#...>" 这个字符串，
		# 不是字典；from_data 会去 String.get 而崩。跳过即可——那种档的包内容本就已废。
		if d is not Dictionary:
			continue
		var item: Item = Item.from_data(d)
		if item != null:
			items.append(item)
	loading = false
	emit_signal("inventory_updated")
