extends Potion
class_name PotionOfMindVision

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "灵视药剂"

func apply(hero: Hero) -> void:
	identify()
	Buff.affect(hero, MindVision, MindVision.DURATION)
	

func value() -> int:
	return 50 * item_quantity if is_known() else super.value()
	
func energy_val() -> int:
	return 10 * item_quantity if is_known() else super.energy_val()
