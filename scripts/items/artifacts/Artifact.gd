extends KindOfMisc
class_name Artifact

var passive_buff: Buff
var active_buff: Buff

var exp: int = 0
var level_cap: int = 10

var cur_charge: int = 0
var partical_charge: float = 0
var charge_cap: int = 0

var colldown: int = 0

func _init(lvl: int = 0) -> void:
	super(lvl)
	item_name = "神器模板"

func do_equip(hero: Hero) -> bool:
	if hero.artifact != null and hero.artifact.get_script() == self.get_script() \
		or hero.misc != null and hero.misc.get_script() == self.get_script():
		print("别装俩一样的")
		return false
	else:
		if super.do_equip(hero):
			identify()
			return true
		else:
			return false

func activate(ch: Char) -> void:
	if passive_buff != null:
		if passive_buff.target != null:
			passive_buff.detach()
		passive_buff = null
	passive_buff = get_passive_buff()
	# 回填外引用：GDScript 内层类没有 Java 的隐式 Artifact.this，被动 buff 的
	# item_level / is_cursed / charge 要靠它找回本神器（见 ArtifactBuff）。
	passive_buff.artifact = self
	passive_buff.attach_to(ch)

func do_unequip(hero: Hero, collect: bool = true, single: bool = true) -> bool:
	if super.do_unequip(hero, collect, single):
		if passive_buff != null:
			if passive_buff.target != null:
				passive_buff.detach()
		passive_buff = null
		return true
	else:
		return false

func is_upgradable() -> bool:
	return false

func visibly_upgraded() -> int:
	return roundi(level() * 10 / float(level_cap)) if level_known else 0

func buffed_visibly_upgraded() -> int:
	return visibly_upgraded()
	
func buffed_lvl() -> int:
	return level()
	
func value() -> int:
	var price = 100
	if level() > 0:
		price += 20*visibly_upgraded()
	if cursed and cursed_known:
		price /= 2
	if price < 1:
		price = 1
	return price

func get_passive_buff() -> ArtifactBuff:
	return null

func charge(target: Hero, amount: float):
	pass

class ArtifactBuff extends Buff:

	# GDScript 内层类没有 Java 那样的隐式外引用（SPD 里写作 Artifact.this），
	# 故显式持有本 buff 所属的神器；由 Artifact.activate 在 new 出被动 buff 后回填。
	# 下面三个方法在原版里用的 target / cursed / level() 全都解析到外层 Artifact 实例，本工程改走此引用。
	var artifact: Artifact

	func attach_to(buff_target: Char) -> bool:
		if super.attach_to(buff_target):
			# 全程用参数 buff_target，不用字段 target：SPD 里此方法内的 target 就是那个参数
			# （Java 参数同名遮蔽字段）。字段此刻虽已被 super 设好、两者相等，但混用正是
			# 上一版 super 误传字段那次崩溃的同款坑，索性统一。
			if buff_target is Hero and GameState.hero == null and cooldown() == 0 and buff_target.cooldown() > 0:
				spend(TICK)
			return true
		return false

	# ---------- 直译 SPD Artifact.ArtifactBuff 的三个转发方法 ----------
	# 取外层的 level()（即神器的 item_level）。
	func item_level() -> int:
		return artifact.level() if artifact != null else 0

	# SPD 是 `target.buff(MagicImmune.class) == null && cursed`；本工程尚无 MagicImmune，先只剩 cursed。
	func is_cursed() -> bool:
		return artifact != null and artifact.cursed

	# 充能入口：转发给外层的 Artifact.charge（各神器在此实现回血 / 充能等效果）。
	# 参数名避开 Buff 的 target 字段（同 attach_to 的教训）。
	func charge(buff_target: Hero, amount: float) -> void:
		if artifact != null:
			artifact.charge(buff_target, amount)
	
