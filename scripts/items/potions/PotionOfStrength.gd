extends Potion
class_name PotionOfStrength

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "力量药剂"


func drink(curUser: Char):
	super(curUser)
	curUser.STR += 1
