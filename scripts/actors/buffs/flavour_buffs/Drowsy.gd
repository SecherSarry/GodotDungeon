extends FlavourBuff
class_name Drowsy

static var DURATION: float = 5   # 原版值；你定

func _init() -> void:
	super()
	type = buff_type.NEUTRAL
	
# 到期自摘——这是唯一的expiry机制。不写这个，buff 永不消失：
# 不 detach 也不 spend，时间停在原地，调度器会一遍遍挑中它。
func attach_to(buff_target, duration: float = 1) -> bool:
	if(super.attach_to(buff_target, duration)):
		return true
	return false

func act() -> bool:
	Buff.affect(target, MagicalSleep)
	return super.act()
