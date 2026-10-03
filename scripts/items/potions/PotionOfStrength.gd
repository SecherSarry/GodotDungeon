extends Potion
class_name PotionOfStrength

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "力量药剂"

func apply(hero: Hero):
	identify()
	
	hero.str += 1
	
	print("俺变得更强大了")

func value() -> int:
	return 50 * item_quantity if is_known() else super.value()
	
func energy_val() -> int:
	return 10 * item_quantity if is_known() else super.energy_val()
