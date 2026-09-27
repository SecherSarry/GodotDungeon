extends Buff
class_name LockedFloor

var left: float = 50

func act() -> bool:
	spend(TICK)
	
	if left >= 1:
		left -= 1
		
	return true

func add_time(time: float) -> void:
	left += time
	left = minf(left, 50)

func remove_time(time: float) -> void:
	left -= time
	
func regen_on() -> bool:
	return left >= 1

func desc() -> String:
	return str(left)
