extends Resource
class_name Item

@export var item_name: String = "未知物品"
@export var icon: Texture2D = null
@export var stackable: bool = true
@export var quantity: int = 1

var level = 0

func actions(hero: Hero):
	var actions = ["放下", "扔出"]
	return actions

# 执行一个动作。子类只管"效果 + 消耗（consume）"，收尾一律走 end_action（全类唯一一处
# spend_time/advance）。放下/扔出需场景配合（选格、飞行动画、刷可见性），故委托回
# hero.game_scene 的摆位服务——那两个服务已不再自行推进回合。子类覆写 execute 时，
# 自己的动作分支调 end_action(hero, 该动作的时长常量)，其余 `await super(hero, action)`。
# 放下/扔出被取消时场景返回 false，则本次不算数：不记时、不推进回合。
func execute(hero: Hero, action: String) -> void:
	if hero == null:
		return
	var gs = hero.game_scene
	if gs == null:
		return
	var acted := true
	match action:
		"放下":
			acted = await gs.drop_all_from_inventory(Bag.get_inventory().find(self))
		"扔出":
			acted = await gs.drop_item_from_inventory(Bag.get_inventory().find(self))
	if not acted:
		return
	await end_action(hero, 1.0)   # 放下/扔出暂用固定时长

# 动作收尾：记账 + 推进回合。全类唯一一处 advance；时长由调用方（各动作的时长常量）传入。
func end_action(hero: Hero, duration: float) -> void:
	hero.spend_time(duration)
	await TurnManager.advance()

# ---------- 消耗物品（下放自场景层） ----------
# 消耗自身一份：可堆叠扣 1，用尽或不可堆叠则整份移除。
# 由"用掉即消失"的子类在效果后自行调用，时机先于 super() 的收尾。
func consume() -> void:
	var index = Bag.get_inventory().find(self)
	if index >= 0:
		Bag.remove_one(index)

func collect(quantity: int = 1) -> bool:
	self.quantity = quantity
	Bag.add_item(self)
	print("拾取", item_name, " x", quantity)
	return true
	

func buffedlvl() -> int:
	return level

func is_equipped (hero: Hero):
	return false
