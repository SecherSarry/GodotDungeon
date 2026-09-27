extends FlavourBuff
class_name Blindness

static var DURATION: float = 10

func _init() -> void:
	super()
	type = buff_type.NEGATIVE
	
func detach() -> void:
	super.detach()
	
