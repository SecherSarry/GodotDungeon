extends Armor
class_name MailArmor

func _init(lvl: int = 0):
	super(lvl)   # Item 是 Resource，没有 _ready()：tier 必须在构造时就设好
	tier = 3
	item_name = "链甲"
