extends Potion
class_name PotionOfHealing

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "治疗药剂"
	
func drink(curUser: Char):
	super(curUser)
	detach()
	curUser.HP += 10
