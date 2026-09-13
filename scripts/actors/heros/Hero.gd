extends Char
class_name Hero

const MAX_LEVEL = 30
const STARTING_STR = 10

const TIME_TO_REST = 1
const TIME_TO_SEARCH = 2
const HUNGER_FOR_SEARCH = 6

var talents = {}


var attack_skill = 10
var defense_skill = 5

var STR = 10

var lvl = 1
var exp = 0

var maxHP_boost = 0


var weapon: Meleeweapon = Hand.new()

func _ready():
	init()
	add_to_group("hero")   # 注册到组，供 TurnManager 识别

func init():
	maxHP = 20
	HP = 20
	
	STR = STARTING_STR
	
	talents[Talent.ID.HEARTY_MEAL] = Talent.DATA.get(Talent.ID.HEARTY_MEAL)
	print(talents)
	
func update_maxHP(boost_HP: bool):
	var cur_maxHP = maxHP
	maxHP = 20 + 5*(lvl-1)
	if boost_HP:
		HP += 	max(maxHP - cur_maxHP, 0)
	HP = min(HP, maxHP)

func get_STR():
	var str_bouns: int = 0
	
	return STR + str_bouns

# 移动到相邻格：同步即时提交 grid 并启动自滑，立即返回成功与否（动画由自身 _process 收尾）
func move_step(target: Vector2i) -> bool:
	var ok = walk_to(target)
	if ok:
		spend_time(DUR_MOVE)
	return ok

func damage_roll(actor: Char = self):
	return randi_range(actor.weapon.min(), actor.weapon.max())

func max_exp(lvl: int = self.lvl):
	return 5 + lvl * 5
	
func earn_exp(exp: int, source):
	self.exp += exp
	while (self.exp >= max_exp()):
		self.exp -= max_exp();
		var levelUp = up_level();
	pass

func up_level(level: int = 1):
	self.lvl += level
	
	update_maxHP(true)
	attack_skill += level
	defense_skill += level
	pass
	

func get_attack_skill(target: Char) -> int:
	return attack_skill

func get_defense_skill(target: Char) -> int:
	return defense_skill
