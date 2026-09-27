extends Buff
class_name Regeneration

func _init() -> void:
	super()
	act_priority = HERO_PRIO - 1;

var partical_regen: float = 0
var REGENERATION_DELAY: float = 10

func act() -> bool:
	if target.is_alive():
		if regen_on() and target.hp < regen_cap() and !target.is_starving():
			var delay: float = REGENERATION_DELAY
			
			partical_regen += 1.0 / delay

			if partical_regen >= 1:
				var regen_hp = floori(partical_regen)
				target.hp += min(regen_hp, target.max_hp-target.hp)
				partical_regen -= regen_hp
				if target.hp == regen_cap():
					target.resting = false
		spend(TICK)
			
	else:
		diactivate()
	return true
	
func regen_cap() -> int:
	return target.max_hp
	
func regen_on() -> bool:
	var lock: LockedFloor = GameState.hero.get_buff(LockedFloor)
	if(lock != null and !lock.regen_on()):
		return false
		
	return true

func desc() -> String:
	return str(partical_regen)
