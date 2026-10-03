extends Scroll
class_name ScrollOfIdentify

func _init():
	super()
	item_name = "鉴定卷轴"

func do_read(curUser: Char) -> void:
	var gs = curUser.game_scene
	if gs == null:
		return

	var item: Item = null
	while true:
		item = await gs.select_item()

		# 取消
		if item == null:
			print("你什么都没选择")
			if not is_identified():
				# 卷轴本身未鉴定：消耗 + 鉴定该种类
				detach(curUser.backpack)
				identify()
				read_animation()
				return
			# 已鉴定：不消耗，不记时
			return

		# 已鉴定物品：提示并重选
		if item.is_identified():
			print("已经被鉴定过了，请选择其他物品")
			continue

		# 选中未鉴定物品
		break

	# 鉴定物品
	item.identify()
	print("你鉴定了" + item.name())

	# 消耗卷轴 + 标记该种类已知
	detach(curUser.backpack)
	identify()
	read_animation()
	return


func value() -> int:
	return 40 * item_quantity
