extends Item
class_name Scroll

const TIME_TO_READ := 1.0   # 阅读耗时

var talent_factor: float = 1
var talent_chance: float = 1

# 卷轴天然可堆叠（同 Potion）。必须放在 _init 而不能用 _ready：
# Item 是 Resource，没有 _ready 回调。子类覆写 _init 时必须调 super()，否则本函数不执行。
func _init(lvl: int = 0) -> void:
	super(lvl)
	stackable = true
	
var anonymous: bool = false
func anonymize() -> void:
	if not is_known():
		pass
	anonymous = true

func actions(hero: Hero) -> Array:
	var actions: Array = super(hero)
	actions.append("阅读")
	return actions


func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)
	if action == "阅读":
		# do_read 可能是协程（鉴定卷轴要等玩家在背包里点选一件物品），必须 await。
		# 返回 false = 玩家取消：本次不成立，不记时、不消耗卷轴。
		if hero.has_buff(Blindness):
			print("你失明了")
		else:
			await do_read(hero)
	
# 返回"本次阅读是否成立"。子类覆写时取消/无法成立的分支 return false。
func do_read(curUser: Char) -> void:
	pass

func read_animation():
	if not anonymous:
		Invisibility.dispel()
	cur_user.spend(TIME_TO_READ)
	
	if not anonymous:
		Talent.on_scroll_used(cur_user, cur_user.grid_pos, talent_factor, self)

# 已知 = 占位卷轴（anonymous）或该类型已被鉴定过。
# 取代 SPD ItemStatusHandler，集合落在 GameState.known（键为 item_name）。
func is_known() -> bool:
	return anonymous or GameState.known.has(item_name)

func set_known() -> void:
	if not anonymous:
		GameState.known[item_name] = true
		if GameState.hero.is_alive():
			pass   # SPD 的 Catalog.setSeen / Statistics 图鉴占位

func identify(by_hero: bool = true) -> Item:
	super.identify(by_hero)
	if not is_known():
		set_known()
	return self
	
func name() -> String:
	return item_name if is_identified() else GameState.anonymous_names[item_name]

func is_upgradable() -> bool:
	return false
	
func is_identified() -> bool:
	return is_known()

func all_known() -> bool:
	return true
	
func value() -> int:
	return 30 * item_quantity

func energy_val():
	return 6 * item_quantity
