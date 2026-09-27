extends EquipableItem
class_name Armor

var tier: int

# 必须显式透传：本类不定义 _init 的话，子类的 super(lvl) 会落到隐式无参构造，
# 参数被丢弃、Item._init 不执行，item_lvl 就永远是字段默认值 0。
func _init(lvl: int = 0) -> void:
	super(lvl)
	item_name = "护甲模板"

func level() -> int:
	var level: int = super.level()
	return level
	
func buffed_lvl() -> int:
	var level: int = level()
	return level + super.buffed_lvl()

func dr_max(lvl: int = buffed_lvl()) -> int:
	var max: int = tier * (2 + lvl)
	return max

func dr_min(lvl: int = buffed_lvl()) -> int:
	var max: int = dr_max(lvl)
	if(lvl >= max):
		return (lvl-max)
	else:
		return lvl

# 装备全流程。直译 SPD Armor.doEquip（Armor.java:232）：
#   先 detach(backpack) 把本件从背包取出 → 再让旧甲 doUnequip(hero, true, false) 回包 →
#   写槽 → 最后 hero.spend(timeToEquip(hero))。
# 本子类与 MeleeWeapon 只在**槽位名**上不同（hero.armor vs hero.weapon）：
# 取件、旧件回包、记时三件都由 EquipableItem 的 do_unequip / TIME_TO_EQUIP 承担。
# 原版 Armor.doEquip 里还有纹章（BrokenSeal）与 HeroSprite 换装的收尾，本工程两样都没有。
func do_equip(hero: Hero):
	detach()   # 装备即离包
	if hero.armor != null:
		hero.armor.do_unequip(hero)   # 旧甲回包（扫 belongings 找自己、清槽、入包，并记旧件那次脱下耗时）
	hero.armor = self                 # 护甲槽 = 本件（写入 belongings[1]）
	hero.spend(TIME_TO_EQUIP)

