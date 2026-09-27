extends Buff
class_name WellFed

# 吃饱喝足：饱食度不再增长，并持续回血。对应原版 actors/buffs/WellFed.java。
#
# 时长不走 time，而是自带的 left 计数：每行动一次减 1，减成负数就退场。
# 原版 reset() 把 left 设成 Hunger.STARVING（450）——这里不直接引用 Hunger，因为 Hunger.act
# 要读本类来判断是否该停止累积，两边互相 class_name 引用会成环（本项目已被这个坑咬过一次，
# 见 Char/Buff 那条）。故改成由授予方把时长传进来，环就断在授予方那一侧（那边两个类都能引用）。
var left: int = 0

func _init() -> void:
	super()
	type = buff_type.POSITIVE

# 授予方在 attach_to 之后调用，对应原版的 reset()。duration 传 Hunger.STARVING。
func reset(duration: float) -> void:
	left = int(duration)

# 续期，对应原版的 extend()（原版由 MnemonicPrayer 这类法术调用）。
func extend(duration: float) -> void:
	left += int(duration)

func act() -> bool:
	left -= 1

	if left < 0:
		# 先抓住宿主再 detach（防御写法，保留）：detach 已不再置空 target（见 Buff.detach），
		# 这里读 target 也安全，但多存一份不碍事。
		var host = target
		detach()
		if host is Hero:
			host.resting = false
		return true   # 退场即不再记时：本实例已从宿主 buff 表移除，调度器不会再选到它

	elif left % 18 == 0 and target.hp < target.max_hp:
		# 每 18 回合回 1 血，450 回合共 25 点（18×25 = 450）。18 是原版写死的裸数，照抄不改。
		target.hp += 1
		if target.hp == target.max_hp and target is Hero:
			target.resting = false

	spend(TICK)
	return true

func desc() -> String:
	return str(left)
