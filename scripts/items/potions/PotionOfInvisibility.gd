extends Potion
class_name PotionOfInvisibility

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "隐形药剂"


func apply(hero: Hero):
	identify()
	print("你隐形了")
	
	# 曾经这里给的是 Haste（复制 PotionOfHaste 时漏改）：隐形药剂喝了只是加速。
	# 且 Invisibility.attach_to 当时还有一处 target 误用，于是即便改对类名也挂不上——
	# 两处是一对，只修一处等于没修（见 Invisibility.gd 顶部）。
	Buff.prolong(hero, Invisibility, Invisibility.DURATION)
	
