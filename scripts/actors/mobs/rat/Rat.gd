extends Mob
class_name Rat

func _init():
	super()   # 必须调：Mob._init 里的 act_priority / max_hp / is_monster 全靠这一行
	max_lvl = 5
	alignment = Alignment.ENEMY

func damage_roll(actor: Char = self):
	return randi_range(1, 4)

func get_attack_skill(target: Char) -> int:
	return 8
func get_defense_skill(target: Char) -> int:
	return 2

func dr_roll() -> int:
	return super.dr_roll() + randi_range(0, 1)
