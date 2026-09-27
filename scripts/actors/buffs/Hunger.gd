extends Buff
class_name Hunger

static var HUNGRY: float = 300.0
static var STARVING: float = 450.0

var level: float 
var partical_damage: float

func act() -> bool:
	# 吃饱喝足期间饱食度原地踏步：既不累积，也不触发饥饿/挨饿。
	# 对应原版 Hunger.act 开头把 WellFed 并进那串"直接 spend(TICK) 后 return"的短路条件。
	if target.has_buff(WellFed):
		spend(TICK)
		return true

	if target.is_alive() and target is Hero:
		var hero: Hero = target
		
		if is_starving():
			# 1000 是原版写死的裸数（Hunger.java:81 `target.HT/1000f`），照抄不改：
			# HT=20 时约 50 拍掉 1 血。曾误写成 /100（快 10 倍），真接上打断后
			# 会每 5 拍把休息打断一次，睡觉按钮等于废掉。
			partical_damage += target.max_hp/1000.0
			
			if partical_damage > 1:
				# 原版是 `(int)partialDamage`（Java 强转，向零截断），不是四舍五入。
				# GDScript 的 int() 同为向零截断，故用它；roundi 会在 .5 上进位，差一点。
				target.damage(int(partical_damage), self)
				partical_damage -= int(partical_damage)

		else:
			var hungry_delay: float = 1
			# 原版还有 Shadows 的 1.5 倍和 SaltCube 的饥饿倍率（Hunger.java:91-94），
			# 本工程两样都没有，故 hungry_delay 恒为 1。

			var new_level = level

			new_level += (1/hungry_delay)

			# 阈值事件（原版 Hunger.java:97-113）。**这两句 print 只是提示**，但下面那句
			# interrupt() 是实打实的功能：没有它，"刚跌进挨饿"这个事件既不出声、也打不断休息。
			# 为什么这句 interrupt() 必须手写：上一行 damage 传的 src 就是本 buff，
			# 而 Hero.damage 里那条 Hunger 豁免（Hero.gd:176）恰好把它放过——豁免的是
			# "挨饿的持续滴血"，不豁免"刚变成挨饿"这件事。两处是一对，缺一即失效。
			if new_level >= STARVING:
				print("你已经饥肠辘辘！")
				hero.damage(1, self)
				hero.interrupt()
				new_level = STARVING
			elif new_level >= HUNGRY and level < HUNGRY:
				# 只是提示，不扣血也不打断（原版同）。原版这里还会翻图鉴，
				# 本工程没有图鉴系统，略。第二条判据 `level < HUNGRY` 不可省：
				# 少了它，只要还停在饿区间就每拍都印一次。
				print("你有点饿了。")

			level = new_level

		spend(TICK)
	else:
		diactivate()
	return true

func satisfy(energy: float):
	var old_level: float = level
	level -= energy
	if(level < 0):
		level = 0

func hunger() -> int:
	return ceili(level)

func is_starving() -> bool:
	return level >= STARVING

func desc() -> String:
	return str(level) + "/450"
