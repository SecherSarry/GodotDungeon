extends Potion
class_name PotionOfStrength

func _init():
	item_name = "力量药剂"


func drink(curUser: Char):
	super(curUser)
	curUser.STR += 1
