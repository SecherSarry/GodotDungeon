extends EquipableItem
class_name Meleeweapon

var ACC: float = 1
var DLY: float = 1
var RCH: int = 1

var tier: int = 1

func _init(lvl: int = 0):
	super(lvl)
	item_name = "武器模板"

func min(lvl: int = buffed_lvl()):
	return tier + lvl

func max(lvl: int = buffed_lvl()):
	return 5*(tier+1) + lvl*(tier+1)

# 装备全流程。直译 SPD KindOfWeapon.doEquip（KindOfWeapon.java:106）：
#   先 detachAll(backpack) 把本件从背包取出 → 再让旧件 doUnequip(hero, true) 回包 →
#   写槽 → 最后 hero.spend(timeToEquip(hero))。
# 本子类与 Armor 只在**槽位名**上不同（hero.weapon vs hero.armor）：
# 取件、旧件回包、记时三件都由 EquipableItem 的 do_unequip / TIME_TO_EQUIP 承担。
# （原版 Weapon 用 detachAll、Armor 用 detach，对不可堆叠物两者等价，本工程统一 detach。）
func do_equip(hero: Hero):
	detach()   # 装备即离包
	if hero.weapon != null:
		hero.weapon.do_unequip(hero)   # 旧武器回包（扫 belongings 找自己、清槽、入包，并记旧件那次脱下耗时）
	hero.weapon = self                 # 武器槽 = 本件（写入 belongings[0]）
	hero.spend(TIME_TO_EQUIP)
