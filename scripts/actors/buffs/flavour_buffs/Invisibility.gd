extends FlavourBuff
class_name Invisibility

static var DURATION: float = 20

func _init() -> void:
	super()
	type = buff_type.POSITIVE
	announced = true
	
# 注意参数名 buff_target 必须一路传给 super：成员 target 在 attach 成功前恒为 null
# （Buff.attach_to 内部才 self.target = buff_target），写成 super.attach_to(target) 会当场返回 false，
# 隐形永远挂不上。detach 里同理——那边 target 已非空，但用成员名极易被误读成"参数"，故一并写全。
func attach_to(buff_target: Char, duration: float = 1) -> bool:
	if super.attach_to(buff_target):
		buff_target.invisible += 1
		return true
	else:
		return false
	
func detach() -> void:
	if target != null and target.invisible > 0:
		target.invisible -= 1
	super.detach()
	
static func dispel(ch: Char = null):
	if ch == null:
		if GameState.hero == null:
			return
		else:
			ch = GameState.hero
	
	var invis: Invisibility = ch.get_buff(Invisibility)
	if invis != null:
		invis.detach()
		
	
