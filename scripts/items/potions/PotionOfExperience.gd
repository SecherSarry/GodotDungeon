extends Potion
class_name PotionOfExperience

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "经验药剂"


func drink(curUser: Char):
	super(curUser)
	curUser.earn_exp(curUser.max_exp(), self);
