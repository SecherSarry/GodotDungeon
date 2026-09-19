extends Armor
class_name ClothArmor

func _init(lvl: int = 0):
	super(lvl)   # Item 是 Resource，没有 _ready()：tier 必须在构造时就设好
	tier = 1
	item_name = "布甲"
