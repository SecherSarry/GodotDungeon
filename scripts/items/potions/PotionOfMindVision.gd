extends Potion
class_name PotionOfMindVision

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "灵视药剂"
	
func drink(curUser: Char):
	super(curUser)
	detach()
	MindVision.new().attach_to(curUser, MindVision.DURATION)
