extends EquipableItem
class_name Meleeweapon

var ACC: float = 1
var DLY: float = 1
var RCH: int = 1

var tier: int = 1

const DUR_EQUIP := 1.0     # 装备耗时
const DUR_UNEQUIP := 1.0   # 脱下耗时

func _init():
	item_name = "武器模板"

func min(lvl: int = buffedlvl()):
	return tier + lvl

func max(lvl: int = buffedlvl()):
	return 5*(tier+1) + lvl*(tier+1)

func execute(hero: Hero, action: String) -> void:
	if action == "装备":
		do_equip(hero)
		consume()   # 装备即离包入手：从背包移除，否则会与"已在手"重复
		await end_action(hero, DUR_EQUIP)
	elif action == "脱下":
		do_unequip(hero)
		await end_action(hero, DUR_UNEQUIP)
	else:
		await super(hero, action)   # 放下/扔出由基类处理

func is_equipped(hero: Hero) -> bool:
	return hero.weapon == self

func do_equip(actor: Char):
	actor.weapon.do_unequip(actor)
	actor.weapon = self
	pass

func do_unequip(actor: Char):
	# 仅当手里是真武器（非空手）时才放回背包；用 is 做类型判断，实例与 class 比较恒等是错的
	if not actor.weapon is Hand:
		Bag.add_item(actor.weapon)
	actor.weapon = Hand.new()
	
	
