extends RefCounted
class_name Belongings

# SPD Belongings：一局的随身物容器——一个背包 + 六个装备槽（武器/护甲/神器/杂物/戒指/第二武器）。
# SPD 里它由 Hero 构造持有（Belongings(Hero owner)），本工程 Hero 是 Resource，同样在 Hero._init 里 new 一份。
# hero.belongings 即本对象；hero.belongings.backpack 才是背包（SPD 同此）。
#
# extends RefCounted 而非 Node：本类从不 add_child，是纯数据容器。Node 不是引用计数对象，
# new 了不入场景树就是永久泄漏（每次建英雄 / 读档漏一份）——HeroAction / Talent / HeroClass
# 都已按此改过来，本类此前漏改（HeroAction.gd:9-10 的注释正是解释这个坑）。

# SPD Belongings 持 owner 供 activate/uncursing 用；本工程暂未用到。
# **必须保持不赋值**：本类是 RefCounted、Hero 是 Resource，都是有引用计数的对象，
# 一旦赋值就是 Hero→belongings→Hero 的强引用环，两者永不回收（改成 RefCounted 之后
# 这条约束比原先更硬——之前是 Node 泄漏，现在是直接的引用环）。
# 真要用 owner 时以 `weakref(hero)` 存 WeakRef，取用处 .get_ref()，别直接存 Hero。
# 全树无 b_owner 的读取点（仅本行声明），不赋值即安全。
var b_owner: Hero

class Backpack extends Bag:
	func capacity() -> int:
		var cap: int = super.capacity()
		return cap

var backpack: Backpack

var weapon: KindOfWeapon

var armor: Armor

var artifact: Artifact

var misc: KindOfMisc

var ring: Ring

var second_wep: KindOfWeapon

func _init() -> void:
	backpack = Backpack.new()

# 六槽按 SPD 顺序列出，供 UI 遍历 / 序列化 / contains 扫描。
func slots() -> Array:
	return [weapon, armor, artifact, misc, ring, second_wep]

# 是否正穿在身上（SPD Belongings 可迭代，isEquipped 扫全槽）。
func contains(item: Item) -> bool:
	if item == null:
		return false
	for s: Item in slots():
		if s == item:
			return true
	return false

func clear() -> void:
	backpack.clear()
	weapon = null
	armor = null
	artifact = null
	misc = null
	ring = null
	second_wep = null

# ---------- 存档（SPD storeInBundle/restoreFromBundle） ----------
# 背包与六槽合成一份。空槽存 null，读档时按 null 跳过——不能存空字典再喂 from_data（那边没有 "script" 键会炸）。
func serialize() -> Dictionary:
	return {
		"backpack": backpack.serialize(),
		"weapon": weapon.serialize() if weapon != null else null,
		"armor": armor.serialize() if armor != null else null,
		"artifact": artifact.serialize() if artifact != null else null,
		"misc": misc.serialize() if misc != null else null,
		"ring": ring.serialize() if ring != null else null,
		"second_wep": second_wep.serialize() if second_wep != null else null,
	}

static func _item_from(d) -> Item:
	return Item.from_data(d) if d is Dictionary else null

func deserialize(data: Dictionary) -> void:
	backpack.deserialize(data.get("backpack", {"inventory": []}))
	weapon = _item_from(data.get("weapon"))
	armor = _item_from(data.get("armor"))
	artifact = _item_from(data.get("artifact"))
	misc = _item_from(data.get("misc"))
	ring = _item_from(data.get("ring"))
	second_wep = _item_from(data.get("second_wep"))
