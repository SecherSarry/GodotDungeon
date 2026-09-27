extends FlavourBuff
class_name Terror

static var DURATION: float = 20

func act() -> bool:
	detach()
	return true
