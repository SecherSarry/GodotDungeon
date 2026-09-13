extends Meleeweapon
class_name Hand

func _init():
	item_name = "手"
	tier = 0

func min(lvl: int = 0):
	return 1
	
func max(lvl: int = 0):
	return 5
