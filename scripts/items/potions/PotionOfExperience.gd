extends Potion
class_name PotionOfExperience

func _init():
	item_name = "经验药剂"


func drink(curUser: Char):
	super(curUser)
	curUser.earn_exp(curUser.max_exp(), self);
