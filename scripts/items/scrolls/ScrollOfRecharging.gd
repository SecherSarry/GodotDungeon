extends Scroll
class_name ScrollOfRecharging

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "充能卷轴"

# 催眠：读者视野内的怪全部陷入困倦，读者自己也困倦。
# 过滤用 curUser.FOV 而非写死英雄的——卷轴按"读者自己的视野"生效，将来怪读卷轴也自动成立。
# FOV 无需在此重算：它由 GameScene.observe() 在每次行动后刷新，而读者此刻尚未移动。
func do_read(curUser: Char) -> void:
	detach(curUser.backpack)
	
	Buff.affect(curUser, Recharging, Recharging.DURATION)
	
	identify()
	read_animation()
	return

func value() -> int:
	return 40 * item_quantity
