extends Food
class_name MeatPie

# 肉派：比口粮更管饱，且吃完进入「吃饱喝足」（WellFed：450 回合不再涨饱食度，每 18 回合回 1 血）。
# 对应原版 items/food/MeatPie.java。
#
# 授予方放在本类而不是 Food 里：Food 是通用基类，只有肉派这一种食物给 WellFed。
# 这也是唯一读 Hunger.STARVING 的地方——WellFed 自己不引用 Hunger，免得两个 buff 脚本
# 互相 class_name 引用成环（见 WellFed.gd 顶部）。
func _init():
	super()
	item_name = "全肉大饼"
	energy = Hunger.STARVING * 2   # 900：一份吃满还有富余，原版值

func satisfy(hero: Hero):
	super.satisfy(hero)

	# 时长由 WellFed 自己的 left 计数管，此处只挂上、不预支时长（affect 不传 duration）。
	# affect 返回的就是真正生效的那一个（同类已在场时复用在场实例），故可直接接返回值。
	var well_fed: WellFed = Buff.affect(hero, WellFed)
	well_fed.reset(Hunger.STARVING)
