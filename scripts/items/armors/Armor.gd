extends EquipableItem
class_name Armor

var glyph: Glyph
var tier: int

# 必须显式透传：本类不定义 _init 的话，子类的 super(lvl) 会落到隐式无参构造，
# 参数被丢弃、Item._init 不执行，item_lvl 就永远是字段默认值 0。
func _init(lvl: int = 0) -> void:
	super(lvl)
	item_name = "护甲模板"

# 装备全流程。直译 SPD Armor.doEquip（Armor.java:232）：
#   先 detach(backpack) 把本件从背包取出 → 再让旧甲 doUnequip(hero, true, false) 回包 →
#   写槽 → 最后 hero.spend(timeToEquip(hero))。
# 本子类与 MeleeWeapon 只在**槽位名**上不同（hero.armor vs hero.weapon）：
# 取件、旧件回包、记时三件都由 EquipableItem 的 do_unequip / TIME_TO_EQUIP 承担。
# 原版 Armor.doEquip 里还有纹章（BrokenSeal）与 HeroSprite 换装的收尾，本工程两样都没有。
func do_equip(hero: Hero) -> bool:
	detach(hero.backpack)   # 装备即离包
	
	var old_armor: Armor = hero.armor
	if hero.armor == null || hero.armor.do_unequip(hero, true, false):
		hero.armor = self                 # 护甲槽 = 本件（写入 belongings[1]）
		
		cursed_known = true
		if(cursed):
			equip_cursed(hero)
		
		activate(hero)
		Talent.on_item_equipped(hero, self)
		hero.spend(time_to_equip(hero))
		return true
	else:
		collect()
		return false

func do_unequip(hero: Hero, collect: bool, single: bool = true) -> bool:
	if super.do_unequip(hero, collect, single):
		hero.armor = null
		return true
	else:
		return false
	
func dr_max(lvl: int = buffed_lvl()) -> int:
	var max: int = tier * (2 + lvl)
	return max

func dr_min(lvl: int = buffed_lvl()) -> int:
	var max: int = dr_max(lvl)
	if(lvl >= max):
		return (lvl-max)
	else:
		return lvl
		
func speed_factor(owner: Char, speed: float) -> float:
	if owner is Hero:
		var a_enc = short_str_req() - owner.get_str()
		if a_enc > 0: speed /= pow(1.2, a_enc)
	return speed
	
func stealth_factor(owner: Char, stealth: float) -> float:
	return stealth
	
func level() -> int:
	var level: int = super.level()
	return level
	
func buffed_lvl() -> int:
	var level: int = level()
	return level + super.buffed_lvl()
	
func name() -> String:
	#if is_equipped(hero) and not has_curse_glyph() or glyph == null:
	return glyph.name_with_armor(super.name()) if glyph != null and (cursed_known or not glyph.curse()) else super.name()
		
func short_str_req() -> int:
	return str_req(self.level())
	
func str_req(lvl: int) -> int:
	var req = std_str_req(self.tier, lvl)
	return req
	
static func std_str_req(tier: int, lvl: int) -> int:
	lvl = max(0, lvl)
	return (8 + tier * 2) - (int)(sqrt(8 * lvl + 1) - 1)/2
	
func value() -> int:
	var price: int = 20 * tier
	
	if cursed_known and cursed:
		price /= 2
	if level_known and level() > 0:
		price *= (level() + 1)
	if price < 1:
		price = 1
		
	return price

func inscrible(glyph: Glyph = null) -> Armor:
	if glyph == null:
		glyph = Glyph.random()
	self.glyph = glyph
	return self
	
func has_good_glyph():
	return glyph != null and not glyph.curse()
	
func has_curse_glyph():
	return glyph != null and glyph.curse()
	
class Glyph extends Bundlable:
	static var common = []
	static var uncommon = []
	static var rare = []
	
	static var type_chances = [50, 40, 10]
	
	static var curses = []
	
	func proc(armor: Armor, attacker: Char, defender: Char, damage: int):
		pass
	
	func name() -> String:
		if not curse():
			return "附魔"
		else:
			return "诅咒"
		
	func name_with_armor(armor_name: String) -> String:
		return name() + armor_name
		
	func curse() -> bool:
		return false
	
	static func random(to_ignore: Glyph = null) -> Glyph:
		
		return Glyph.new()
