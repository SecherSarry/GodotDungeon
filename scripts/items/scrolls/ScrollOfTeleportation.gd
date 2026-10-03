extends Scroll
class_name ScrollOfTeleportation

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "传送卷轴"

# 读卷轴 = 触发传送：随机空位逻辑已收拢到 MapManager.teleport（含视觉摆位），
# 这里只需触发并回显，无需直握场景。
func do_read(curUser: Char) -> void:
	detach(curUser.backpack)
	MapManager.teleport(curUser)

	identify()
	read_animation()
	return
