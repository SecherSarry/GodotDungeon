extends Potion
class_name PotionOfHealing

func _init():
	super()   # 必须调：Potion._init 里设的 stackable 才会生效
	item_name = "治疗药剂"
	
func apply(hero: Hero):
	identify()
	cure(hero)
	heal(hero)
	
func heal(ch: Char):
	var healing: Healing = Buff.affect(ch, Healing)
	healing.set_heal(floori(0.8 * ch.max_hp + 14), 0.25, 0)
	
func cure(ch: Char):
	Buff.do_detach(ch, Weakness)
	Buff.do_detach(ch, Blindness)
	Buff.do_detach(ch, Drowsy)
