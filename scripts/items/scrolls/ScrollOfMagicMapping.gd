extends Scroll
class_name ScrollOfMagicMapping

func _init():
	item_name = "探地卷轴"

# 读卷轴 = 触发传送：随机空位逻辑已收拢到 MapManager.teleport（含视觉摆位），
# 这里只需触发并回显，无需直握场景。
func read(curUser: Char):
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			MapManager.explored[y][x] = true
