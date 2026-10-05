extends KindOfMisc
class_name Ring

var buff: RingBuff
var buff_class: RingBuff

var anonymous = false
func anonymize() -> void:
	if !is_known():
		pass
	anonymous = true;

# 装备本戒指时挂上（或并入已有的）该戒指类的 buff。
# 本工程 Char.buffs 按脚本类去重（同类至多一个），而原版允许同类多份、靠 getBuffedBonus 求和。
# 为对齐原版"两枚同类戒指叠加"，这个唯一的 buff 改为一并持有**所有**同类戒指（rings 数组），
# 由 RingBuff.buffed_lvl 对它们求和。于是：
#   场上无同类 buff → 新建、挂上、把本戒指记进 rings；
#   已有同类 buff   → 不新建，直接把本戒指并进它的 rings（旧 buff 继续代表两枚戒指）。
func activate(ch: Char) -> void:
	var probe: RingBuff = get_buff()          # 新实例，只取它的类当作查表键
	if probe == null:
		return
	var existing: RingBuff = ch.get_buff(probe.get_script())
	if existing != null:
		buff = existing
		buff.add_ring(self)
	else:
		buff = probe
		buff.add_ring(self)
		buff.attach_to(ch)

# 脱下时只把自己从 rings 里摘掉；摘空了才真正 detach。
# 不能像以前那样直接 detach——那会把还戴着同类戒指的另一个戒指的效果一起清掉。
func do_unequip(hero: Hero, collect: bool = true, single: bool = true) -> bool:
	if super.do_unequip(hero, collect, single):
		if buff != null:
			buff.remove_ring(self)
			buff = null
		return true
	else:
		return false

func is_known() -> bool:
	return anonymous or GameState.known.has(item_name)

func set_known() -> void:
	if not anonymous:
		GameState.known[item_name] = true
		if GameState.hero.is_alive():
			pass   # SPD 的 Catalog.setSeen / Statistics 图鉴占位

# 显示名只看"这一类戒指是否已知"（is_known），不看本实例自己是否鉴定过。
# 直译 SPD Ring.java:172 `return isKnown() ? super.name() : Messages.get(Ring.class, gem)`：
# 鉴定一枚同类戒指就把整类标为已知，包里另一枚尚未单独鉴定的同类戒指随即显示真名。
# 用 is_identified() 会多要求本实例的 level_known/cursed_known，导致同类戒指仍显示假名。
func name() -> String:
	return item_name if is_known() else GameState.anonymous_names[item_name]

func upgrade() -> Item:
	super.upgrade()

	if randi_range(0, 2) == 0:
		cursed = false
	return self

func is_identified() -> bool:
	return super.is_identified() and is_known()

func identify(by_hero: bool = true) -> Item:
	set_known()
	return super.identify(by_hero)

func random() -> Item:
	var n: int = 0
	if randi_range(0, 2) == 0:
		n += 1
		if randi_range(0, 4) == 0:
			n += 1
	item_level = n
	if randf() < 0.3:
		cursed  = true
	
	return self
	
func value() -> int:
	var price: int = 75
	
	if cursed and cursed_known:
		price /= 2
	
	if level_known:
		if level() > 0:
			price *= (level() + 1)
		elif level() < 0:
			price /= (1  - level())
	if price < 1:
		price = 1;
	return price;

func get_buff() -> RingBuff:
	return null

func buffed_lvl() -> int:
	return level() + super.buffed_lvl()

# 直译 SPD Ring.soloBuffedBonus：诅咒时封顶到 0，否则 buffedLvl+1。
# 供"戒指 buff 的加成等级"回读（RingBuff.buffed_lvl）。
func solo_buffed_bonus() -> int:
	if cursed:
		return min(0, buffed_lvl() - 2)
	return buffed_lvl() + 1

# 某角色身上"该戒指 buff"的加成等级，直译 SPD Ring.getBuffedBonus(target, type)。
# 本工程同类 buff 至多一个（Char.buffs 按脚本键），但那个 buff 一并持有所有同类戒指，
# 其 buffed_lvl 已对各戒指求和，故这里取它一个即等价于原版 `for (... : target.buffs(type))` 的累加。
# MagicImmune / SpiritForm 两个分支本工程尚无对应 buff，略。
static func get_buffed_bonus(target: Char, type) -> int:
	var buff: RingBuff = target.get_buff(type)
	if buff == null:
		return 0
	return buff.buffed_lvl()

class RingBuff extends Buff:
	# 本 buff 代表的全部同类戒指。原版一个 buff 对一枚戒指、由 getBuffedBonus 跨 buff 求和；
	# 本工程每类 buff 只留一个，故把一个类下的所有戒指都收进这里，由 buffed_lvl 求和。
	# 由 Ring.activate 记入、Ring.do_unequip 摘除。空了就 detach。
	var rings: Array = []

	func add_ring(ring: Ring) -> void:
		if ring not in rings:
			rings.append(ring)

	# 摘掉一枚戒指；已无戒指提供本 buff 就自行退场。
	func remove_ring(ring: Ring) -> void:
		rings.erase(ring)
		if rings.is_empty():
			detach()

	# 直译 SPD Ring.RingBuff.act：`spend(TICK); return true;`。
	# 不写这条会继承 Buff.act 的 diactivate()——被调度一次就把自己关掉（time=INF），
	# 与"戒指 buff 一直挂着、按整拍参与时间轴"的原版行为不符。
	func act() -> bool:
		spend(TICK)
		return true

	# 加成等级 = 各戒指 soloBuffedBonus 之和（原版跨 buff 累加 RingBuff.buffedLvl）。
	func buffed_lvl() -> int:
		var total := 0
		for r in rings:
			total += r.solo_buffed_bonus()
		return total
