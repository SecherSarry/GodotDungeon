extends Buff
class_name Hunger

static var HUNGRY: float = 300.0
static var STARVING: float = 450.0

var level: float 
var partical_damage: float

func act() -> bool:
	if target.is_alive() and target is Hero:
		var hero: Hero = target
		
		if is_starving():
			partical_damage += target.maxHP/100.0
			
			if partical_damage > 1:
				target.damage(roundi(partical_damage), self)
				partical_damage -= roundi(partical_damage)
				
		else:
			var hungry_delay: float = 1

			var new_level = level

			new_level += (1/hungry_delay)

			level = new_level
	
		spend(TICK)
	else:
		diactivate()
	return true

func satisfy(energy: float):
	var old_level: float = level
	level -= energy
	if(level < 0):
		level = 0

func hunger() -> int:
	return ceili(level)

func is_starving() -> bool:
	return level >= STARVING
