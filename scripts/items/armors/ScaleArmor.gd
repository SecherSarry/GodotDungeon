extends Armor
class_name ScaleArmor

func _init(lvl: int = 0):
	super(lvl)   # Item 是 Resource，没有 _ready()：tier 必须在构造时就设好
	tier = 4
	item_name = "鳞甲"
