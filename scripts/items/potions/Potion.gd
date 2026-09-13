extends Item
class_name Potion

const DUR_DRINK := 1.0   # 喝药耗时

func actions(hero: Hero):
	return super(hero) + ["饮用"]

func execute(hero: Hero, action: String) -> void:
	if action == "饮用":
		drink(hero)
		consume()
		await end_action(hero, DUR_DRINK)
	else:
		await super(hero, action)   # 放下/扔出由基类处理

func drink(curUser: Char):
	pass
