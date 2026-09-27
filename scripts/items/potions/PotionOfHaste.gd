extends Potion
class_name PotionOfHaste

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "极速药剂"


func apply(hero: Hero):
	identify()
	print("你感觉有活力")
	
	Buff.prolong(hero, Haste, Haste.DURATION)
	
