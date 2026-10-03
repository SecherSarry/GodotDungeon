extends Buff
class_name Regeneration

var hero: Hero:
	get:
		return GameState.hero
		
func _init() -> void:
	super()
	act_priority = HERO_PRIO - 1;

var partical_regen: float = 0
var REGENERATION_DELAY: float = 10

func act() -> bool:
	if target.is_alive():
		if regen_on() and target.hp < regen_cap() and !target.is_starving():
			var chalice_cursed: bool = false
			var chalice_level = -1
			if 1:
				if hero.get_buff(ChaliceOfBlood.ChaliceRegen) != null:
					chalice_cursed = hero.get_buff(ChaliceOfBlood.ChaliceRegen).is_cursed()
					chalice_level = hero.get_buff(ChaliceOfBlood.ChaliceRegen).item_level()
				#elif (hero.buff(SpiritForm.SpiritFormBuff.class) != null && hero.buff(SpiritForm.SpiritFormBuff.class).artifact() instanceof ChaliceOfBlood):
					#chaliceLevel = SpiritForm.artifactLevel();
			
			var delay: float = REGENERATION_DELAY
			if chalice_level != -1:
				if chalice_cursed:
					delay *= 1.5
				else:
					delay -= 1.33 + chalice_level * 0.667
					#delay /= 
			
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
