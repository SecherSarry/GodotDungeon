extends RefCounted
class_name Talent

# 天赋。原版 Talent 是个 Java 枚举（Talent.java:96-1219），每个常量自带 icon / maxPoints 字段
# 与 title() / desc() 方法；GDScript 的枚举常量只是 int，挂不住这些，故拆成
# 「enum ID 只做键 + const DATA 存元数据 + static 函数取用」三件。
#
# 本类**不持有任何行为**——这是原版的设计，不是裁剪。SPD 里没有 Talent.apply()：
# 天赋效果一律写在关心它的地方（吃东西时查 HEARTY_MEAL 见 Talent.java:584 onFoodEaten，
# 算力量时查 STRONGMAN 见 Hero.java:281）。故本类只有数据与取用函数；
# 别在这里加「天赋基类 + 子类覆写 effect()」那类原版没有的抽象。
#
# 不 extends Resource：原版 Talent 是无状态常量表，Resource 的两个用处（编辑器里存 .tres、
# 按实例挂字段）这里都用不上，改用最轻的 RefCounted（同 HeroAction 那次从 Node 改过来）。

# 键。原版是「枚举常量本身即身份」，这里 int 只做键，元数据全在 DATA。
# 只列战士一个职业（一期范围）。原版每个常量还带一个 icon 编号（Talent.java:99-113 括号里那个
# 0/1/2/…/10），本工程尚无天赋 UI，故不写进枚举值——等做图标时把编号放进 DATA 的 "icon" 字段。
# 顺带好处：不写编号就不会有人误把它当"点数值"或"层号"。
enum ID {
	# ---- 战士 T1（原版 Talent.java:99）----
	HEARTY_MEAL,
	VETERANS_INTUITION,
	PROVOKED_ANGER,
	IRON_WILL,
	# ---- 战士 T2（原版 Talent.java:101）----
	IRON_STOMACH,
	LIQUID_WILLPOWER,
	RUNIC_TRANSFERENCE,
	LETHAL_MOMENTUM,
	IMPROVISED_PROJECTILES,
	# ---- 战士 T3（原版 Talent.java:103）----
	HOLD_FAST,
	STRONGMAN,
}

# 元数据表。
# max_points 照抄原版构造参数：Talent.java:438-445 有两个构造——Talent(icon) 默认 maxPoints=2，
# 只有 Talent(icon, maxPoints) 才显式给。故 T1/T2 清一色 2，仅 HOLD_FAST(9,3) / STRONGMAN(10,3) 是 3。
# （曾误写成三个都 3，那是把 HEARTY_MEAL 当成了显式给点的那个。）
# title / desc 取自 SPD 官方简体中文（messages/actors/actors_zh.properties）。
# desc 里的 `_…_` 是原版的强调标记、`\n\n` 是分段，**原样保留**：等有 UI 渲染时再决定怎么解析，
# 现在自行清洗会丢掉原文（清洗过就找不回原味了）。
const DATA := {
	ID.HEARTY_MEAL: {
		"title": "丰盛一餐",
		"max_points": 2,
		"desc": "_+1：_ 战士在生命值不高于33%时进食将恢复_4点生命_。\n\n_+2：_ 战士在生命值不高于33%时进食将恢复_6点生命_。",
	},
	ID.VETERANS_INTUITION: {
		"title": "老兵直觉",
		"max_points": 2,
		"desc": "_+1：_战士鉴定武器的速度提升至原来的_1.75倍_，鉴定护甲的速度提升至原来的_2.5倍_。\n\n_+2：_战士鉴定武器的速度提升至原来的_2.5倍_，且能在_装备护甲时_将其直接鉴定。",
	},
	ID.PROVOKED_ANGER: {
		"title": "受衅怒火",
		"max_points": 2,
		"desc": "_+1：_当 战士所获的任何护盾效果被伤害击碎时，他的下一次物理攻击将造成_3点额外伤害_。\n\n_+2：_当战士所获的任何护盾效果被伤害击碎时，他的下一次物理攻击将造成_5点额外伤害_。",
	},
	ID.IRON_WILL: {
		"title": "钢铁意志",
		"max_points": 2,
		"desc": "_+1：_战士的纹章所提供的护盾_增加1点_。\n\n_+2：_战士的纹章所提供的护盾_增加2点_。",
	},
	ID.IRON_STOMACH: {
		"title": "钢铁之胃",
		"max_points": 2,
		"desc": "_+1：_战士进食只花费1回合，并在进食过程中获得_75%的伤害抗性_。\n\n_+2：_战士进食只花费1回合，并在进食过程中获得_100%的伤害抗性_。",
	},
	ID.LIQUID_WILLPOWER: {
		"title": "液蕴意志",
		"max_points": 2,
		"desc": "_+1：_当战士饮用或投掷一瓶药剂、魔药或秘药时，他会获得他_最大生命值6.5%的护盾_。\n\n_+2：_当战士饮用或投掷一瓶药剂、魔药或秘药时，他会获得他_最大生命值10%的护盾_。\n\n如果使用的是力量药剂、经验药剂或须用前述药剂炼制的炼金物品，则获得的护盾量翻倍。\n\n对产量较高的炼金物品(如水爆魔药)，这项天赋会基于该物品的单次产出数量概率触发。",
	},
	ID.RUNIC_TRANSFERENCE: {
		"title": "刻印转移",
		"max_points": 2,
		"desc": "_+1：_战士的破损纹章可以像携带一层升级一样携带_常见刻印_。\n\n_+2：_战士的破损纹章可以像携带一层升级一样携带_常见、强力或诅咒刻印_。\n\n破损纹章只能携带护甲贴附有纹章时刻在上面的刻印。",
	},
	ID.LETHAL_MOMENTUM: {
		"title": "手起刀落",
		"max_points": 2,
		"desc": "_+1：_战士使用物理武器击杀敌人的一击有_67%的概率_不消耗回合数。\n\n_+2：_战士使用物理武器击杀敌人的一击有_100%的概率_不消耗回合数。",
	},
	ID.IMPROVISED_PROJECTILES: {
		"title": "即兴投掷",
		"max_points": 2,
		"desc": "_+1：_战士向敌人扔出非投掷武器的物品时会对其造成_2回合_的致盲效果。这个天赋有50回合的冷却时间。\n\n_+2：_战士向敌人扔出非投掷武器的物品时会对其造成_3回合_的致盲效果。这个天赋有50回合的冷却时间。",
	},
	ID.HOLD_FAST: {
		"title": "不动如山",
		"max_points": 3,
		"desc": "_+1：_当战士等待时，他可获得_1~2点护甲_并将连击和护盾的衰减速度减缓_50%_，直至他移动为止。\n\n_+2：_当战士等待时，他可获得_2~4点护甲_并将连击和护盾的衰减速度减缓_75%_，直至他移动为止。\n\n_+3：_当战士等待时，他可获得_3~6点护甲_并将连击和护盾的衰减速度减缓_100%_，直至他移动为止。",
	},
	ID.STRONGMAN: {
		"title": "力大无穷",
		"max_points": 3,
		"desc": "_+1：_战士的力量提升_8%_，向下取整。\n\n_+2：_战士的力量提升_13%_，向下取整。\n\n_+3：_战士的力量提升_18%_，向下取整。",
	},
}

# tiers 1/2/3/4 start at levels 2/7/13/21（原版 Talent.java:436）。
# 读法：threshold[T] 是第 T 层的**开放等级**，threshold[T] - threshold[T-1] 是第 T 层的**点数预算**。
# 首项 0 是哨兵，只为让「层号直接当下标」成立（第 1 层查 [1]），本身不表示层级；
# 末项 31 = 英雄满级 MAX_LEVEL(30) + 1，给 T4 封顶用。
# 于是各层预算 = 2/5、7/6、13/8、21/10（开放等级 → 5/6/8/10 点）。
# 注意**预算 ≠ 容量**：战士 T1 四个天赋各 2 点 = 容量 8，预算只有 5，必然点不满，这是有意的取舍设计。
const TIER_LEVEL_THRESHOLDS := [0, 2, 7, 13, 21, 31]

# 原版 Talent.MAX_TALENT_TIERS（Talent.java:957）。
# 在**本工程**它同时是职业树的上限：每职业填 T1~T3，T4 留给子职业 / 护甲技能
# （原版 initClassTalents 末尾也只写到 tier3、tier4 是 "//TBD"）。
const MAX_TALENT_TIERS := 4


# 原版 Talent.title()。本工程沿用用户起的 name()（Hero.init 里的调试打印在用），不改成 title()。
static func name(id) -> String:
	return DATA[id]["title"]


# 原版 Talent.desc()。metamorphed 分支（变形术换天赋时的 meta_desc）本工程没有，略。
static func desc(id) -> String:
	return DATA[id]["desc"]


# 原版 Talent.maxPoints()。
static func max_points(id) -> int:
	return DATA[id]["max_points"]


# 直译 SPD Talent.initClassTalents（Talent.java:959-1068）的战士那半边。
# 返回天赋树容器：Array[Dictionary]，**下标 = 层号 - 1**，每个值形如 {天赋ID: 已投点数}。
# 只建结构、不发点数——新树点数一律 0。点数不存储，由 Hero.talent_points_available 按当前
# lvl 现算，故升级不必"发点"、读档也不会错账（原版同此设计，见该函数注释）。
#
# 参数不注解类型，也不在本函数里引用 HeroClass：一期只有战士一个职业的名单成形，
# 那三层 if 还没写。等另两职业补齐时，照原版在这里按 hero_class 分三份名单
# （Talent.java:971-1010 是三层 switch），那时再加 HeroClass 的类型引用。
# Talent → HeroClass 的引用本身不成环（HeroClass.gd 只在注释里提到 Talent），
# 但能不引就不引，与工程里其它跨类处保持一致的克制。
static func init_class_talents(hero_class) -> Array:
	var talents: Array = []
	for i in MAX_TALENT_TIERS:
		talents.append({})

	# ---- 战士 T1（Talent.java:972）----
	for id in [ID.HEARTY_MEAL, ID.VETERANS_INTUITION, ID.PROVOKED_ANGER, ID.IRON_WILL]:
		talents[0][id] = 0

	# ---- 战士 T2（Talent.java:990）----
	for id in [ID.IRON_STOMACH, ID.LIQUID_WILLPOWER, ID.RUNIC_TRANSFERENCE, ID.LETHAL_MOMENTUM, ID.IMPROVISED_PROJECTILES]:
		talents[1][id] = 0

	# ---- 战士 T3（Talent.java:1008）。原版这里只有 HOLD_FAST / STRONGMAN 两项；
	# 子职业（狂战士 / 角斗士）的 T3 由 initSubclassTalents 追加进**同一层**，
	# 那正是 T3 预算 8 点 > 这俩容量 6 点的原因——多出的 2 点留给子职业天赋。
	for id in [ID.HOLD_FAST, ID.STRONGMAN]:
		talents[2][id] = 0

	# ---- 战士 T4：原版留空（"//tier4 //TBD"），由 initArmorTalents 追加。本工程同。
	return talents

static func on_food_eaten(hero: Hero, food_val: float, food_sourse: Item):
	print("进食", food_val, food_sourse)
	if 1 or hero.has_talent(ID.HEARTY_MEAL):
		if 1 or hero.hp/float(hero.max_hp) <= 0.33:
			var healing = 2 + 2 * hero.points_in_talent(ID.HEARTY_MEAL)
			hero.hp = mini(hero.hp + healing, hero.max_hp)
