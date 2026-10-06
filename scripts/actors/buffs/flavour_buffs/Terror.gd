extends FlavourBuff
class_name Terror

static var DURATION: float = 20

func _init() -> void:
	super()
	type = buff_type.NEGATIVE
	announced = true

var ignore_next_hit = false

func recover() -> void:
	# 收到伤害时"这次不算数"：消费掉标志就直接返回，不扣时长。此前误写成 = true，
	# 标志一旦为真就永远不会被清掉，recover() 从此每次早退 —— 恐惧再也恢复不了、也永不到期。
	if ignore_next_hit:
		ignore_next_hit = false
		return
	spend(-5)
	if cooldown() <= 0:
		detach()
