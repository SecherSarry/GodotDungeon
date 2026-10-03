extends FlavourBuff
class_name Light

static var DURATION: float = 250
static var DISTANCE: float = 6

func _init() -> void:
	super()
	type = buff_type.POSITIVE
	announced = true
	
func attach_to(buff_target: Char, duration: float = 1) -> bool:
	if super.attach_to(target):
		return true
	else:
		return false
