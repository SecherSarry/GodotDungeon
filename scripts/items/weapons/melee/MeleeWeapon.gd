extends Weapon
class_name MeleeWeapon

var tier: int = 1

func _init(lvl: int = 0):
	super(lvl)
	item_name = "武器模板"

func min(lvl: int = buffed_lvl()):
	return tier + lvl

func max(lvl: int = buffed_lvl()):
	return 5*(tier+1) + lvl*(tier+1)
