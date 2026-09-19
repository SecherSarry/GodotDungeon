extends Buff
class_name MindVision

static var DURATION: float = 20
# 照亮半径（切比雪夫）：1 = 生物所在格的九宫格。半径挂在效果自己身上，
# Char.reveal_around 只认参数、不认识 buff。
const RADIUS := 1

func act() -> bool:
	detach()
	return true
