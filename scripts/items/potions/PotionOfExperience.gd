extends Potion
class_name PotionOfExperience

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "经验药剂"

func apply(hero: Hero) -> void:
	identify()
	hero.earn_exp(hero.max_exp(), self)

func value() -> int:
	return 50 * item_quantity if is_known() else super.value()
	
func energy_val() -> int:
	return 10 * item_quantity if is_known() else super.energy_val()
