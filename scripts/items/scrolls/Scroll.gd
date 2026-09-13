extends Item
class_name Scroll

const DUR_READ := 1.0   # 阅读耗时

func actions(hero: Hero):
	return super(hero) + ["阅读"]

func execute(hero: Hero, action: String) -> void:
	if action == "阅读":
		read(hero)
		consume()
		await end_action(hero, DUR_READ)
	else:
		await super(hero, action)   # 放下/扔出由基类处理

func read(curUser: Char):
	pass
