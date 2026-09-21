extends Scroll
class_name ScrollOfMagicMapping

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "探地卷轴"

# 读卷轴 = 触发传送：随机空位逻辑已收拢到 MapManager.teleport（含视觉摆位），
# 这里只需触发并回显，无需直握场景。
func do_read(curUser: Char) -> bool:
	detach()
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			LevelManager.explored[y][x] = true
	
	identify()
	read_animation()
	return true
