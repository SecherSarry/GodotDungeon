extends FlavourBuff
class_name Drowsy

static var DURATION: float = 5   # 原版值；你定

func _init() -> void:
	type = buff_type.NEUTRAL
# 到期自摘——这是唯一的expiry机制。不写这个，buff永不消失：
# 基类 act() 返回 false → 调度器补记 DUR_WAIT → 它会被反复选中，永久占着时间轴。
func attach_to(buff_target, duration: float = 1) -> bool:
	if(super.attach_to(buff_target, duration)):
		return true
	return false

func act() -> bool:
	MagicalSleep.new().attach_to(target)
	return super.act()
