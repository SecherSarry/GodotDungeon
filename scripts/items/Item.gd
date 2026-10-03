extends Bundlable
class_name Item

var hero: Hero:
	get:
		return GameState.hero

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

func actions(hero: Hero) -> Array:
	var actions: Array = ["放下", "扔出"]
	return actions

func do_pickup(hero: Hero, pos: Vector2i = hero.grid_pos) -> bool:
	if collect(hero.backpack):
		hero.spend(pickup_delay())
		return true
	else:
		return false
		

# 放下：整摞落在自己脚下。取出归本类（detach_all），摆位归场景；
# 目标格就是英雄所在格，距离 0，场景的飞行动画自然跳过。
# 直译 SPD Item.doDrop（Item.java:138-142）：原版是
# `spendAndNext(TIME_TO_DROP); int pos = hero.pos; Dungeon.level.drop(detachAll(backpack), pos)`。
# 原版不判取出结果——detachAll 取不到就返回自己（见下），"装备中刚脱下"的那件正是靠这条落地。
# 本工程比原版多一层 gs.drop 的返回值判定（不在玩家回合则整件事作废），故记时挪到 drop 成功之后。
func do_drop(hero: Hero):
	var gs = hero.game_scene
	if gs == null:
		return
	var stack: Item = detach_all(hero.backpack)
	if await gs.drop(stack, hero.grid_pos):
		hero.spend(TIME_TO_DROP)
		

# 扔出第一步：选落点。直译 SPD Item.doThrow（Item.java:153-155）——原版整个函数就一句
# `GameScene.selectCell(thrower);`，选中格之后才由那个回调调 cast（见下）。
# 本工程把回调换成 await：select_cell 是协程，选中格与取消都由它返回，
# 于是本函数正好是"选格 → 交给 cast"两句，与 SPD 的两段一一对应。
# 选格要点鼠标、跨帧，故本函数是协程，execute 必须 await，否则回合会先于投掷被推进。
#
# 取消（(-1,-1)）时**什么都不做**，对应原版 thrower 里那句 `if (target != null) curItem.cast(...)`
# （Item.java:715-719）：原版取消时 target 为 null，整个分支不进，物品分毫未动。
# 这条"取消不产生副作用"正是下一段 cast 必须单独存在的原因——脱装备挂在其上，不能提前到这里。
func do_throw(hero: Hero):
	var gs = hero.game_scene
	if gs == null:
		return
	var target = await gs.select_cell(hero.grid_pos, "throw")
	if target == Vector2i(-1, -1):
		return   # 取消
	await cast(hero, target)

# 扔出第二步：真正脱手并落地。直译 SPD Item.cast（Item.java:639-697）。
# 与 SPD 逐句对照，被略去的都在原版有对应物、本工程无：
#   user.sprite.zap(cell) / throwSound() —— 出手动作与音效；本工程的飞行动画由
#     gs.drop 内的 _animate_throw 承担（GameScene.gd:713-729）。
#   Char enemy = Actor.findChar(cell); QuickSlotButton.target(enemy) —— 命中判定与快捷栏。
#   MissileSprite 回调 —— 原版把"取出 + onThrow + 推进回合"整个放进飞行动画播完的回调；
#     本工程 gs.drop 自己就是"飞行 + 落地"的 await，故 detach 留在它前面，
#     两句之间的先后与原版一致（那边也只隔了一个回调边界，中间没有别的动作）。
#   castDelay(user, cell) —— 本工程固定 TIME_TO_THROW。
#   落点：原版是 throwPos（Ballistica 弹道），本工程是 MapManager.throw_landing_cell，同职。
func cast(user: Hero, dst: Vector2i) -> void:
	var thrown: Item = detach(hero.backpack)   # 可堆叠只扣 1，拿到的才是要落地的那份
	if thrown == null:
		return
	var landing = MapManager.throw_landing_cell(user.grid_pos, dst)
	if await user.game_scene.drop(thrown, landing):
		user.spend(TIME_TO_THROW)
		

# 执行一个动作。职责三分：子类只管"效果 + 消耗（consume）"，本类管"从背包取出"
# （detach / detach_all），世界摆位（选格、算落点、飞行、落地）一律委托 hero.game_scene。
# 回合推进不归物品层：InventoryUI 在 execute 返回后调 hero.on_operate_complete() 推一次，
# 物品层若再 next() 就是同一动作的双重推进。
# 场景返回 false（不在玩家回合）则本次不算数：不记时、不推进回合。
# 子类覆写 execute 时，自己的动作分支自行 spend，其余 `await super(hero, action)`。
func execute(hero: Hero, action: String = default_action) -> void:
	cur_user = hero
	cur_item = self
	# 准入判据，直译 SPD Item.execute（Item.java:163-175）：
	#   `if (hero.belongings.backpack.contains(this) || isEquipped(hero)) doDrop(hero);`
	# 原版两个分支各判一次，本工程合并到 match 之前——判据相同，写两遍只多一次查找。
	# 这道闸是必需的：detach / detach_all 改成"取不到就返回自己"之后（见下），它们不再是守卫，
	# 没有这一句，一件既不在包也不在槽里的物品（比如已扔到地上的那件）仍会被
	# do_drop / do_throw 当成有效目标走完全流程，凭空多出一份落在地上。
	#
	# 原版 execute 开头还有 `GameScene.cancel(); curUser = hero; curItem = this;`。
	# 本工程无 cancel；那两个静态字段也不需要——原版存它们是因为选格回调（Item.java:713-724）
	# 拿不到参数，本工程用 await 把参数一路传下去（见 do_throw → cast）。
	match action:
		"放下":
			await do_drop(hero)
		"扔出":
			await do_throw(hero)

func identify(by_hero: bool = true) -> Item:
	level_known = true
	cursed_known = true
	return self
	
func title() -> String:
	var name: String = name()
	
	if(visibly_upgraded() != 0):
		name += " +" + str(visibly_upgraded())
	
	if(item_quantity > 1):
		name += " x" + str(item_quantity)
	
	return name

func name() -> String:
	return true_name()

func true_name() -> String:
	return item_name

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


# ---------- 存档 ----------
# 存的是脚本路径 + 全部标量脚本属性（见 Bundlable.script_props）。
# 取路径而非类名：反序列化照路径 load().new() 复原，不必另维护一张"类名 → 脚本"的表。
func serialize() -> Dictionary:
	return { "script": get_script().resource_path, "props": Bundlable.script_props(self) }

func deserialize(data: Dictionary) -> void:
	Bundlable.apply_props(self, data.get("props", {}))

# 由存档字典重建一件物品。脚本路径失效（物品被删/改名）返回 null，调用方跳过，
# 不让一件读不回来的东西把整包拖崩。
# scr 显式声明 Variant：load() 静态返回 Resource，而 Resource 上没有 new()，写 `load(path).new()`
# 会在解析期报"找不到 new"。声明成 Variant 让 new() 走动态派发。
static func from_data(data: Dictionary) -> Item:
	var path: String = data.get("script", "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scr: Variant = ResourceLoader.load(path)
	var item: Item = scr.new()
	item.deserialize(data)
	return item

func merge(other: Item) -> Item:
	if is_similar(other):
		item_quantity += other.item_quantity
		other.item_quantity = 0
	return self

func collect(container: Bag = hero.backpack) -> bool:
	if item_quantity < 0:
		return true
	
	var items: Array = container.items
	
	if self in items:
		return true
	
	for item: Item in items:
		if item is Bag and item.can_hold(self):
			if collect(item):
				return true
	
	if not container.can_hold(self):
		return false
	
	if stackable:
		for item in items:
			if is_similar(item):
				item.merge(self)
				return true
	
	if hero != null and hero.is_alive():
		Talent.on_item_collected(hero, self)
		
	items.append(self)
	
	return true

func split(amount: int) -> Item:
	if amount <= 0 or amount >= item_quantity:
		return null
	else:
		var split = new()
		
		if split == null:
			return null
		
		item_quantity -= amount
		
		return split
		
# 从背包取出一件（投掷用）：可堆叠只扣 1、返回数量为 1 的副本，否则整件取出并返回。
# **取不到就返回自己**（不动任何容器）——直译 SPD Item.detachAll 末尾那句
# `updateQuickslot(); return this;`（Item.java:363-364），原版 detach(container) 也共用同一段兜底。
# 这是原版刻意留的宽松语义，不是疏漏：装备中的物品被"脱下但不入包"地取出后不在任何容器里
# （见 EquipableItem.do_unequip 的 collect=false），原版正是靠这条把**调用方手里的这件**交回去，
# 放下/投掷才落得下去。
# 本工程曾改成"取不到返回 null"，让它兼职 execute 的准入守卫；准入现已回到原版的位置
# （见 Item.execute），这里必须恢复宽松——否则上面那条路径会把物品直接弄丢
# （槽已清空、包没进、投掷又中止，实例只剩调用方一个引用）。
func detach(container: Bag) -> Item:
	if item_quantity <= 0:
		return null
	elif item_quantity == 1:
		if stackable:
			pass
		return detach_all(container)
	else:
		var detached: Item = split(1)
		if detached != null:
			detached.on_detach()
		return detached

# 从背包取出整摞（放下用）：可堆叠一次全取出，不可堆叠等同 detach。
# 兜底同 detach（原版 detach 与 detachAll 共用同一段收尾）。
func detach_all(container: Bag) -> Item:
	for item: Item in container.items:
		if item == self:
			container.items.erase(self)
			item.on_detach()
			container.grab_items()
			return self   # 原版取到即 return this（Item.java:352）：不继续遍历已被就地改动的 container.items
		elif item is Bag:
			if item.contains(self):
				return detach_all(item)
	return self

func is_similar(item: Item):
	return get_script() == item.get_script()

func on_detach() -> void:
	pass

func level():
	return item_level
	
func buffed_lvl() -> int:
	return 0

func upgrade() -> Item:
	self.item_level += 1	
	return self

func upgradeN(n: int) -> Item:
	for i in range(n):
		upgrade()
	return self
	
func degrade() -> Item:
	self.item_level -= 1
	return self
	
func degradeN(n: int) -> Item:
	for i in range(n):
		degrade()
	return self
	
func is_upgradable() -> bool:
	return true
	
func is_identified() -> bool:
	return level_known and cursed_known
	
func is_equipped (hero: Hero) -> bool:
	return false

func visibly_upgraded() -> int:
	return level() if level_known else 0

func buffed_visibly_upgraded() -> int:
	return buffed_lvl() if level_known else 0

func quantity(value: int) -> Item:
	self.item_quantity = value
	return self
	
func value() -> int:
	return 0

func pickup_delay():
	var pick_time = TIME_TO_PICK_UP
	return pick_time


static var cur_user: Hero = null
static var cur_item: Item = null
