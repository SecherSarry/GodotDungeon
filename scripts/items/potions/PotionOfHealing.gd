extends Potion
class_name PotionOfHealing

func _init():
	item_name = "治疗药剂"
	
func drink(curUser: Char):
	super(curUser)
	curUser.HP += 10
