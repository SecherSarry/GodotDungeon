extends Resource
class_name Item

static var TIME_TO_THROW: float = 1.0
static var TIME_TO_PICK_UP: float = 1.0
static var TIME_TO_DROP: float = 1.0

var default_action: String
var uses_targeting: bool

var icon: Texture2D = null

var stackable: bool = false
var item_quantity: int = 1

var item_level: int

var level_known: bool = false

var cursed: bool
var cursed_known: bool

var unique: bool = false

var kept_though_lost_invent: bool = false

var bones: bool = false


var item_name: String = "未知物品"

func actions(hero: Hero):
	var actions = ["放下", "扔出"]
	return actions

func do_pickup(hero: Hero, pos: Vector2i = hero.grid_pos) -> bool:
	if(collect()):
		hero.spend(pickup_delay())
		return true
	else:
		return false
		

# 放下：整摞落在自己脚下。取出归本类（detach_all），摆位归场景；
# 目标格就是英雄所在格，距离 0，场景的飞行动画自然跳过。
func do_drop(hero: Hero):
	var gs = hero.game_scene
	if gs == null:
		return
	var stack: Item = detach_all()
	if stack == null:
		return   # 已不在包里：本次不成立
	if await gs.drop(stack, hero.grid_pos):
		hero.spend(TIME_TO_DROP)
		

# 扔出：选格 → 算落点 → 摆位，三步都在本函数里看得见。
# 选格：预览框由 select_cell 按种类内部切换，本类不必知道有哪些预览。
# 落点：选中格只是"想扔到哪"，沿直线可能被墙或敌人挡住，故由 MapManager 折算出实际落点。
# 取出（detach）放在选格之后——取消时不该动背包。
# 选格要点鼠标、跨帧，故本函数是协程，execute 必须 await，否则回合会先于投掷被推进。
func do_throw(hero: Hero):
	var gs = hero.game_scene
	if gs == null:
		return
	var target = await gs.select_cell(hero.grid_pos, "throw")
	if target == Vector2i(-1, -1):
		return   # 取消：什么都没取出，不记时、不推进回合
	var thrown: Item = detach()   # 可堆叠只扣 1，拿到的才是要落地的那份
	if thrown == null:
		return   # 已不在包里：本次不成立
	var landing = MapManager.throw_landing_cell(hero.grid_pos, target)
	if await gs.drop(thrown, landing):
		hero.spend(TIME_TO_THROW)
		

# 执行一个动作。职责三分：子类只管"效果 + 消耗（consume）"，本类管"从背包取出"
# （detach / detach_all），世界摆位（选格、算落点、飞行、落地）一律委托 hero.game_scene。
# 回合推进不归物品层：InventoryUI 在 execute 返回后调 hero.on_operate_complete() 推一次，
# 物品层若再 next() 就是同一动作的双重推进。
# 场景返回 false（取消/已不在包里）则本次不算数：不记时、不推进回合。
# 子类覆写 execute 时，自己的动作分支自行 spend，其余 `await super(hero, action)`。
func execute(hero: Hero, action: String = default_action) -> void:
	if hero == null:
		return
	match action:
		"放下":
			await do_drop(hero)
		"扔出":
			await do_throw(hero)

func identify(by_hero: bool = true) -> Item:
	level_known = true
	cursed_known = true		
	return self
	
func _init(lvl: int = 0) -> void:
	item_level = lvl

# 复制物品一律走本方法，不要直接 duplicate()。Resource.duplicate() 无法覆写（原生实现
# 保留），且它把 script 当普通属性最后才写入，挂脚本时才构造脚本实例——于是 _init 用
# 默认实参重跑一遍，构造参数（item_level、tier、RCH…）全被清零。这里复制完成后把脚本自身
# 的成员变量原样回写，抵消该副作用。子类在 _init 里从参数赋值的字段都会落入
# PROPERTY_USAGE_SCRIPT_VARIABLE，无需逐个补丁。
func copy() -> Item:
	var c: Resource = super.duplicate()
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(prop.name, get(prop.name))
	return c


func collect() -> bool:
	#这里检查背包
	Bag.add_item(self)
	print("拾取", item_name, " x", item_quantity)
	return true
	
# 从背包取出一件（投掷用）：可堆叠只扣 1、返回数量为 1 的副本，否则整件取出并返回。
# 已不在包里返回 null，调用方据此判定本次动作不成立。
# 与 consume 的区别：consume 只把物品弄没，本函数要把实例交出去（投掷需在场景里落地）。
func detach() -> Item:
	var index = Bag.get_inventory().find(self)
	if index < 0:
		return null
	return Bag.remove_one(index)

# 从背包取出整摞（放下用）：可堆叠一次全取出，不可堆叠等同 detach。
func detach_all() -> Item:
	var index = Bag.get_inventory().find(self)
	if index < 0:
		return null
	return Bag.remove_item(index)

func level():
	return item_level
	
func buffed_lvl() -> int:
	return 0

func is_identified():
	return level_known and cursed_known
	
func is_equipped (hero: Hero):
	return false




func quantity(value: int) -> Item:
	self.item_quantity = value
	return self
	
func pickup_delay():
	var pick_time = TIME_TO_PICK_UP
	return pick_time
