extends Item
class_name Potion

const TIME_TO_DRINK := 1.0   # 喝药耗时

# 药剂天然可堆叠：开局发 n 瓶、或日后捡到同名药，都该在背包里合成一格。
# 必须放在 _init 而不能用 _ready：Item 是 Resource，没有 _ready 回调（同 ClothArmor 注释）。
# 子类覆写 _init 时必须调 super()，否则本函数整个不执行（见 Armor 注释）。
func _init(lvl: int = 0) -> void:
	super(lvl)
	stackable = true

func actions(hero: Hero):
	return super(hero) + ["饮用"]

var anonymous = false
func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)
	if action == "饮用":
		drink(hero)

func drink(hero: Hero):
	detach(hero.backpack)
	hero.spend(TIME_TO_DRINK)
	print("spend")
	apply(hero)
	
func on_throw(cell: Vector2i):
	pass
	
func apply(hero: Hero) -> void:
	shatter(hero.grid_pos)
	
func shatter(cell: Vector2i):
	splash(cell)
	if GameState.hero.FOV[cell.y][cell.x]:
		print("药剂打碎")
	
func is_known() -> bool:
	return anonymous or GameState.known.has(item_name)

func set_known() -> void:
	if not anonymous:
		GameState.known[item_name] = true
		if GameState.hero.is_alive():
			pass   # SPD 的 Catalog.setSeen / Statistics 图鉴占位

func identify(by_hero: bool = true) -> Item:
	super.identify()
	
	if not is_known():
		set_known()
	return self

func splash(cell: Vector2i):
	pass

func value() -> int:
	return 30 * item_quantity

func energy_val() -> int:
	return 6 * item_quantity
