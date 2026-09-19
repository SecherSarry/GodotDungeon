extends Item
class_name EquipableItem

const TIME_TO_EQUIP := 1.0     # 装备耗时
const TIME_TO_UNEQUIP := 1.0   # 脱下耗时

# 同 Armor：中间层不定义 _init 会吞掉子类 super(lvl) 的参数，这里必须透传。
func _init(lvl: int = 0) -> void:
	super(lvl)
	# 可装备物天然不堆叠：否则同名两件会被 Bag 合并成一份，后一件连等级一起被丢弃；
	# 且 consume()/remove_one 在 quantity>1 时只扣 1 并留一份在包里，装备会与背包同时持有。
	stackable = false

func actions(hero: Hero):
	var actions = super.actions(hero)
	actions.append("脱下" if is_equipped(hero) else "装备")
	return actions
