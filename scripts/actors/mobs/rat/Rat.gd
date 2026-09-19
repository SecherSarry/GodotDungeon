extends Mob
class_name Rat

func _ready():
	super()   # 必须调：Mob._ready 里 add_to_group("monster") 是 TurnManager 注册怪物的唯一判据
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
