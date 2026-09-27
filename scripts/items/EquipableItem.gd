extends Item
class_name EquipableItem

const TIME_TO_EQUIP := 1.0     # 装备耗时
const TIME_TO_UNEQUIP := 1.0   # 脱下耗时

# 同 Armor：中间层不定义 _init 会吞掉子类 super(lvl) 的参数，这里必须透传。
func _init(lvl: int = 0) -> void:
	super(lvl)
	# 可装备物天然不堆叠：否则同名两件会被 Bag 合并成一份，后一件连等级一起被丢弃；
	# 且 consume()/remove_one 在 quantity>1 时只扣 1 并留一份在包里，装备会与背包同时持有。
	stackable = false

func actions(hero: Hero):
	var actions = super.actions(hero)
	actions.append("脱下" if is_equipped(hero) else "装备")
	return actions

# 装备 / 脱下分派。直译 SPD EquipableItem.execute（EquipableItem.java:70-93）：
# 原版本函数只剩两件事——`AC_EQUIP` 调 doEquip、`AC_UNEQUIP` 调 doUnequip，
# 取出（detach）与记时都在那两个方法内部；放下/扔出则落到 super（Item.execute）。
# 本工程同此：do_equip / do_unequip 各自完成"取出 + 记时"。
#
# 原版 execute 里的 quickslot 那一段（装备后把自己重新绑回快捷栏）本工程无快捷栏，略。
func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)   # 放下/扔出由 Item 处理（这两个动作本层的覆写在下面）
	if action == "装备":
		do_equip(hero)
	elif action == "脱下":
		do_unequip(hero, true)

# 装备全流程——**子类必写**（武器写 hero.weapon、护甲写 hero.armor）。
# 原版这里是 abstract（EquipableItem.java:122），GDScript 没有抽象方法，
# 但也不能不声明：execute 里那句 do_equip(hero) 是本类内的直接调用，
# GDScript 4 对静态可解析的未知方法名是**解析期**报错（"Function do_equip() not found in base self"），
# 不写这一句连编译都过不去。
# 不写成空的 pass：那会让漏覆写的子类"装备了却没进槽"而不出声。原版靠编译器挡漏覆写，
# 这里用 push_error 补上同一道闸（同类写法见 TurnManager.gd:164 的契约告警）。
func do_equip(hero: Hero):
	push_error("EquipableItem.do_equip 未覆写：%s 装备后不会进入任何槽位" % self)

# 脱下：把自己从所在槽清掉，按 collect 决定是否收回背包，并记一次脱下耗时。
#
# collect=false 是"脱下后立刻要交出去"的两条路（放下 / 投掷）专用的——直译 SPD
# EquipableItem.java:143 `if (!collect || !collect( hero.belongings.backpack ))`：
# 此时物品出槽即**悬空**（不在槽、不在包），只由调用方手里的引用活着，
# 随后的 detach / detach_all 会经兜底把它取走（见 Item.detach）。
# 本工程 Bag 无容量上限，故 collect 的差别只在这里：物品不再经背包绕一圈。
#
# 耗时按原版记在**本函数内**（SPD 的 doUnequip 自己 spend），而非调用方。
# 于是"放下/投掷一件装备中的物品"会先记一次脱下耗时、再记一次放下/投掷耗时——与原版一致。
#
# 原版三参 doUnequip 的第三参 single 是"是否顺带 next()（放锁 + 推回合）"，本工程不移植：
# 回合推进统一由 InventoryUI 在 execute 返回后调 hero.on_operate_complete() 办一次
# （见 Item.execute 顶部注释），物品层再 next() 就是同一动作的双重推进。
# 原版的诅咒检查（EquipableItem.java:126-133）本工程无对应物。
func do_unequip(hero: Hero, collect: bool = true):
	for i in hero.belongings.size():
		if hero.belongings[i] == self:
			hero.belongings[i] = null
			if collect:
				Bag.add_item(self)
			hero.spend(TIME_TO_UNEQUIP)
			return

# 放下装备中的物品：先脱下（collect=false = 只离槽、不回包），再走基类落地。
# 直译 SPD EquipableItem.doDrop（EquipableItem.java:95-99）：
#   `if (!isEquipped( hero ) || doUnequip( hero, false, false )) super.doDrop( hero );`
# 原版那个 `|| doUnequip(...)` 是"没穿就跳过脱下、穿了就想脱下"的短路；
# 脱不下来（返回 false，原版只有诅咒会拒）时整体放弃，不落地。
# 本工程 do_unequip 无失败分支（恒成功），故那句短路拆成"穿了才脱"，随后无条件走基类。
# collect=false 时物品悬空，由基类 detach_all 的兜底拿到它、落在脚下。
func do_drop(hero: Hero):
	if is_equipped(hero):
		do_unequip(hero, false)
	await super(hero)

# 投掷装备中的物品：同 do_drop，但挂在 **cast** 上——原版也是如此
# （EquipableItem.java:102-111 覆写的是 cast 而非 doThrow）。
# 位置是重点：cast 在"选格之后"被调到（见 Item.do_throw），玩家取消投掷时根本走不到这里，
# 物品不会被无故脱下。原版还判 `quantity == 1`（可堆叠物只脱 1 个），
# 本工程可装备物一律 stackable=false，无此分支。
func cast(user: Hero, dst: Vector2i) -> void:
	if is_equipped(user):
		do_unequip(user, false)
	await super(user, dst)

# 是否正穿在身上：扫 belongings 全槽。
# 原版这一条是抽象的、由子类各查自己的槽（KindOfWeapon.java:95 查 weapon/secondWep，
# Armor.java:371 查 armor）；本工程 belongings 是固定的 5 槽数组（Hero.gd:56），
# 一条 has() 就覆盖全部槽位，不必让子类各写一份。
# 本层同时是 Item.is_equipped（Item.gd:219，非可装备物恒 false）的覆写。
# 它现在是做判断用的（actions / execute 准入 / 放下与投掷的覆写），不再是唯一的守卫。
func is_equipped(hero: Hero) -> bool:
	return hero != null and hero.belongings.has(self)
