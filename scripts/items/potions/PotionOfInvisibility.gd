extends Potion
class_name PotionOfInvisibility

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "隐形药剂"


func apply(hero: Hero):
	identify()
	print("你隐形了")
	
	Buff.prolong(hero, Haste, Haste.DURATION)
	
