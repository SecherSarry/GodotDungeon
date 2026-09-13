extends Mob
class_name Rat

func _ready():
	HP = 8
	maxHP = 8
	defense_skill = 2
	max_lvl = 5;

func damage_roll(actor: Char = self):
	return randi_range(1, 4)

func get_attack_skill(target: Char) -> int:
	return 8

func dr_roll() -> int:
	return super.dr_roll() + randi_range(0, 1)
