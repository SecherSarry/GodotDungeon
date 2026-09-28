extends EquipableItem
class_name KindOfWeapon

func is_equipped(hero: Hero) -> bool:
	return hero != null and (hero.weapon == self)
	
var is_swift_equipping: bool = false

func time_to_equip(hero: Hero) -> float:
	return 0 if is_swift_equipping else super.time_to_equip(hero)

func do_equip(hero: Hero) -> bool:
	
	is_swift_equipping = false
	
	detach_all()
	
	return true
	
