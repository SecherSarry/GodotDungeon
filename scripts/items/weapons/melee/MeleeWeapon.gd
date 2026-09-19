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

func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)   # 放下/扔出由基类处理
	if action == "装备":
		do_equip(hero)
		detach()
		hero.spend(TIME_TO_EQUIP)
	elif action == "脱下":
		do_unequip(hero)
		hero.spend(TIME_TO_UNEQUIP)

func is_equipped(hero: Hero) -> bool:
	return hero.weapon == self

func do_equip(hero: Hero):
	if hero.weapon != null:
		hero.weapon.do_unequip(hero)   # 旧武器回包
	hero.weapon = self                 # 武器槽 = 本件（写入 belongings[0]）

func do_unequip(hero: Hero):
	if hero.weapon != null:
		Bag.add_item(hero.weapon)
	hero.weapon = null   # 空手槽用 null 表示（与护甲侧一致）
	
