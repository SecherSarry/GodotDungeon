extends Meleeweapon
class_name Whip

func _init():
	item_name = "长鞭"
	tier = 3
	RCH = 3
	
func max(lvl: int = buffedlvl()):
	return 5*(tier) + lvl*(tier);
