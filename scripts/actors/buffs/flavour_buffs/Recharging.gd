extends FlavourBuff
class_name Recharging

static var DURATION: float = 30

func _init() -> void:
	super()
	type = buff_type.POSITIVE
	announced = true
