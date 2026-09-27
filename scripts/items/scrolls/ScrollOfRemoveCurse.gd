extends Scroll
class_name ScrollOfRemoveCurse

func _init():
	super()
	item_name = "驱邪卷轴"

func do_read(curUser: Char) -> bool:
	var gs = curUser.game_scene
	if gs == null:
		return false

	var item: Item = null
	while true:
		item = await gs.select_item()

		# 取消
		if item == null:
			print("你什么都没选择")
			if not is_identified():
				# 卷轴本身未鉴定：消耗 + 鉴定该种类
				detach()
				uncurse(curUser, item)
				read_animation()
				return true
			# 已鉴定：不消耗，不记时
			return false

		# 已鉴定物品：提示并重选
		if !item.cursed and item.cursed_known:
			print("该物品未被诅咒")
			continue

		# 选中未鉴定物品
		break

	# 鉴定物品
	uncurse(curUser, item)
	print("你净化了" + item.name())

	# 消耗卷轴 + 标记该种类已知
	detach()
	identify()
	read_animation()
	return true

# 直译 SPD ScrollOfRemoveCurse.uncurse 的**单件**那半边。原版签名是可变参
# `uncurse(Hero hero, Item... items)`，一次能净化一串；GDScript 没有可变参，
# 故拆成两个入口：本函数管一件（原版 onItemSelected 走的正是这条），uncurse_all 管一串。
# item 允许为 null：取消路径（do_read 里没选物）传进来的就是 null，
# 原版循环体内那句 `if (item != null)` 本就是这个用途，判否即原样返回 false。
func uncurse(hero: Hero, item: Item) -> bool:
	var procced: bool = false
	if ( item != null ):
		item.cursed_known = true
		if (item.cursed):
			procced = true
			item.cursed = false

	return procced

# 原版可变参的另一半：一次净化一串，任一成事即为 true。
func uncurse_all(hero: Hero, items: Array) -> bool:
	var procced: bool = false
	for item: Item in items:
		if uncurse(hero, item):
			procced = true

	return procced

func value() -> int:
	return 40 * item_quantity
