extends FlavourBuff
class_name Invisibility

static var DURATION: float = 20

func _init() -> void:
	super()
	type = buff_type.POSITIVE
	announced = true
	
func attach_to(buff_target: Char, duration: float = 1) -> bool:
	if super.attach_to(target):
		target.invisible += 1
		return true
	else:
		return false
	
func detach() -> void:
	if(target.invisible > 0):
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
		
	
