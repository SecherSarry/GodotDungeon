extends Scroll
class_name ScrollOfIdentify

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "鉴定卷轴"

# 鉴定：读者从背包里点选一件物品，把它的等级/诅咒状态标为已知（Item.identify）。
# 点选要跨帧等鼠标，故本函数是协程，由 Scroll.execute await。
# detach 放在选定之后——玩家取消时不该扣掉卷轴。
func do_read(curUser: Char) -> bool:
	var gs = curUser.game_scene
	if gs == null:
		return false
	var item: Item = await gs.select_item()
	if item == null:
		print("你什么都没选择")
		return false   # 取消：不消耗卷轴、不记时
	if item.is_identified():
		print("已经被鉴定过了")
		return false   # 取消：不消耗卷轴、不记时
	
	print("你鉴定了"+item.item_name)
	item.identify()
	detach()
	identify()
	read_animation()
	return true

func value() -> int:
	return 40 * item_quantity
