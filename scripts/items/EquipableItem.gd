extends Item
class_name EquipableItem

func actions(hero: Hero):
	var actions = super.actions(hero)
	actions.append("取下" if is_equipped(hero) else "装备")
	return actions
