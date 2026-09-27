class_name HeroClass
extends RefCounted

# 英雄职业。原版 HeroClass 是个 Java 枚举，每个常量本身就是一个对象（枚举常量可带字段与方法），
# hero.heroClass 持有其中之一，初始化由该对象自己的 initHero 执行。
# GDScript 的枚举常量只是 int，挂不住方法，故把语义原样搬成"类 + 静态实例"：
# 本类是基类，三个职业是内层子类，WARRIOR/MAGE/ROGUE 是各自的单例。
# 于是 hero.heroClass 存的是一个对象而非 int，调用点写 hero.heroClass.init_hero(hero)。
#
# 三个职业不各占一个文件：HeroClass.ROGUE 必须**是**一个 HeroClass，实例就得和基类同文件，
# 拆成独立脚本会变成 HeroClass 引 RogueClass、RogueClass 又 extends HeroClass 的 class_name 循环
# （同 Mob.gd:37 与 WellFed.gd 顶部那条的处理）。
#
# hero 一律不注解类型：Hero 是本工程另一个 class_name，而 Hero.gd 要用 HeroClass 声明字段，
# 两边互相注解即成环。内层子类里靠动态派发访问 hero 的成员，够用。

# 原版 HeroClass.initHero 的公共段（所有职业都跑）：
#   hero.heroClass = this; Talent.initClassTalents(hero);
#   ClothArmor、Food、VelvetPouch、Waterskin、ScrollOfIdentify 各发一份。
# 本工程目前只有 ClothArmor 与 Food 两件成形的物品，其余等补齐再落。
func init_hero(hero:Hero) -> void:
	PotionOfHealing.new().quantity(5).collect()
	PotionOfStrength.new().quantity(5).collect()
	PotionOfExperience.new().quantity(30).collect()
	PotionOfMindVision.new().quantity(5).collect()
	PotionOfHaste.new().quantity(5).collect()
	
	ScrollOfIdentify.new().quantity(5).collect()
	ScrollOfLullaby.new().quantity(5).collect()
	ScrollOfMagicMapping.new().quantity(5).collect()
	ScrollOfRecharging.new().quantity(5).collect()
	ScrollOfRemoveCurse.new().quantity(5).collect()
	ScrollOfRetribution.new().quantity(5).collect()
	ScrollOfTeleportation.new().quantity(5).collect()
	ScrollOfTerror.new().quantity(5).collect()
	ScrollOfUpgrade.new().quantity(5).collect()
	
	Whip.new().collect()
	
	Food.new().quantity(5).collect()
	MeatPie.new().quantity(5).collect()


# ---------- 三职业 ----------
# 原版各自的初始化在 HeroClass 的私有静态方法 initWarrior/initMage/initRogue 里；
# 本工程把"同一职业的初始化"收进该职业自己的 init_hero，调用方只管 hero.heroClass.init_hero(hero)。
# 每段的注释记下原版发了什么，缺的物品等有了再补进来——不要凭记忆现造。

class Warrior extends HeroClass:
	func init_hero(hero: Hero) -> void:
		super(hero)
		hero.weapon = WornShortsword.new(2).identify()
		hero.armor = ClothArmor.new(1).identify()
		# 原版 initWarrior：WornShortsword 入武器槽并鉴定、ThrowingStone、
		# 护甲镶 BrokenSeal、PotionOfHealing、ScrollOfRage。
		pass


class Mage extends HeroClass:
	func init_hero(hero) -> void:
		# 原版 initMage：MagesStaff( WandOfMagicMissile ) 入武器槽并 activate、
		# ScrollOfUpgrade、PotionOfLiquidFlame。
		pass


class Rogue extends HeroClass:
	func init_hero(hero) -> void:
		# 原版 initRogue：Dagger 入武器槽、CloakOfShadows 入神器槽并 activate、
		# ThrowingKnife、ScrollOfMagicMapping、PotionOfInvisibility。
		pass


static var WARRIOR := Warrior.new()
static var MAGE := Mage.new()
static var ROGUE := Rogue.new()
