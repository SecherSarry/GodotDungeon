extends Item
class_name Scroll

const TIME_TO_READ := 1.0   # 阅读耗时


# 卷轴天然可堆叠（同 Potion）。必须放在 _init 而不能用 _ready：
# Item 是 Resource，没有 _ready 回调。子类覆写 _init 时必须调 super()，否则本函数不执行。
func _init(lvl: int = 0) -> void:
	super(lvl)
	stackable = true
	
func name() -> String:
	return item_name if is_identified() else nickname[item_name]

func actions(hero: Hero):
	return super(hero) + ["阅读"]

func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)
	if action == "阅读":
		# do_read 可能是协程（鉴定卷轴要等玩家在背包里点选一件物品），必须 await。
		# 返回 false = 玩家取消：本次不成立，不记时、不消耗卷轴。
		if await do_read(hero):
			hero.spend(TIME_TO_READ)

# 返回"本次阅读是否成立"。子类覆写时取消/无法成立的分支 return false。
func do_read(curUser: Char) -> bool:
	return true

func read_animation():
	pass

static var nickname: Dictionary = {}
var original_names = ["升级卷轴", "鉴定卷轴", "驱邪卷轴", "镜像卷轴", "充能卷轴", "传送卷轴", "催眠卷轴", "探地卷轴", "盛怒卷轴", "复仇卷轴", "恐惧卷轴", "嬗变卷轴"]
var fake_names = ["KAUNAN卷轴", "SOWILO卷轴", "LAGUZ卷轴", "YNGVI卷轴", "GYFU卷轴", "RAIDO卷轴", "ISAZ卷轴", "MANNAZ卷轴", "NAUDIZ卷轴", "BERKANAN卷轴", "ODAL卷轴", "TIWAZ卷轴"]
func init_nickname():
	fake_names.shuffle()
	for i in range(0, original_names.size()):
		nickname[original_names[i]] = fake_names[i]
