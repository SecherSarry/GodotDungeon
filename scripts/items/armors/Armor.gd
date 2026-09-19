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

func execute(hero: Hero, action: String = default_action) -> void:
	if action == "装备":
		do_equip(hero)
		detach()
		hero.spend(TIME_TO_EQUIP)
	elif action == "脱下":
		do_unequip(hero)
		hero.spend(TIME_TO_UNEQUIP)
	else:
		await super(hero, action)   # 放下/扔出由基类处理

func is_equipped(hero: Hero) -> bool:
	return hero.armor == self

func do_equip(hero: Hero):
	if hero.armor != null:
		hero.armor.do_unequip(hero)   # 旧甲回包
	hero.armor = self                 # 护甲槽 = 本件（写入 belongings[1]）

func do_unequip(hero: Hero):
	if hero.armor != null:
		Bag.add_item(hero.armor)
	hero.armor = null   # 空甲槽用 null 表示（武器侧同样用 null）
	
