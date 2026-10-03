extends Item
class_name Food

static var TIME_TO_EAT: float = 3.0
var energy = Hunger.HUNGRY

func _init():
	super()
	item_name = "口粮"
	stackable = true
	
func actions(hero: Hero):
	var actions = super.actions(hero)
	actions.append("食用")
	return actions
	
func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)
	if action == "食用":
		detach(hero.backpack)
		satisfy(hero)

		hero.spend(eating_time(hero))
		
		Talent.on_food_eaten(hero, energy, self)

# 进食耗时。原版在有铁胃或任一「伙食」天赋时省 2 回合（TIME_TO_EAT - 2 = 1），否则 TIME_TO_EAT。
# 本工程 Talent.ID 眼下只有 HEARTY_MEAL / HOLD_FAST / STRONGMAN，那是原版战士 1 级与 3 级的天赋，
# 没有一个是关于进食速度的（HOLD_FAST 是站定加护甲，与食物无关），故恒为 TIME_TO_EAT。
# 等 IRON_STOMACH 那一批建出来，只改这里一行判断，调用点不动。hero 参数就是为那时留的。
func eating_time(hero: Hero) -> float:
	return TIME_TO_EAT

func satisfy(hero: Hero):
	var food_value: float = energy
	
	hero.get_buff(Hunger).satisfy(food_value)
	
