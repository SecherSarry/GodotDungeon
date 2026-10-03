extends EquipableItem
class_name KindOfWeapon

func is_equipped(hero: Hero) -> bool:
	return hero != null and (hero.weapon == self or hero.second_wep == self)
	
static var is_swift_equipping = false

func time_to_equip(hero: Hero) -> float:
	return 0 if is_swift_equipping else super.time_to_equip(hero)
	
func do_equip(hero: Hero) -> bool:
	is_swift_equipping = false
	
	detach_all(hero.backpack)
	
	if hero.weapon == null or hero.weapon.do_unequip(hero, true):
		
		hero.weapon = self
		activate(hero)
		Talent.on_item_equipped(hero, self)
		
		cursed_known = true
		if(cursed):
			equip_cursed(hero)
			print("诅咒武器！")
		
		hero.spend_and_next(time_to_equip(hero))
		
		if is_swift_equipping:
			print("swift_equip")
			is_swift_equipping = false
		
		return true
	else:
		is_swift_equipping = false
		return false

func do_unequip(hero: Hero, collect: bool, single: bool = true) -> bool:
	if super.do_unequip(hero, collect, single):
		# 清槽（同 Armor.do_unequip 的 hero.armor = null / KindOfMisc 的三连清）。
		# 缺了这一步，脱下后 hero.weapon 仍指向本件：它既回了背包又被 is_equipped 判为"穿着"，
		# 于是背包里同款的另一把也会跟着显示"脱下"。武器只可能占 weapon / second_wep 两槽，故两处都查。
		if hero.weapon == self:
			hero.weapon = null
		if hero.second_wep == self:
			hero.second_wep = null
		return true
	else:
		return false
