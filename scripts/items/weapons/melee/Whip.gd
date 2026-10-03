extends MeleeWeapon
class_name Whip

func _init(lvl: int = 0):
	super(lvl)   # 必须透传：否则 EquipableItem 的 stackable=false 与 Item 的等级都不生效
	item_name = "长鞭"
	tier = 3
	RCH = 3
	
func max(lvl: int = buffed_lvl()):
	return 5*(tier) + lvl*(tier);
