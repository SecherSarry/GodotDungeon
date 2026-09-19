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
		detach()
		satisfy(hero)
		
		hero.spend(TIME_TO_EAT)
		
func satisfy(hero: Hero):
	var food_value: float = energy
	
	hero.get_buff(Hunger).satisfy(food_value)
	
