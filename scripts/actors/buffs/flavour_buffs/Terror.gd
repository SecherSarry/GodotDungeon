extends FlavourBuff
class_name Terror

static var DURATION: float = 20

func _init() -> void:
	super()
	type = buff_type.NEGATIVE
	announced = true

var ignore_next_hit = false

func recover() -> void:
	if ignore_next_hit:
		ignore_next_hit = true
		return
	spend(-5)
	if cooldown() <= 0:
		detach()
