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

var resting: bool = false

var belongings = []   # 已装备物品：[0]=武器, [1]=护甲（SPD 风格）；空槽一律 null

var STR = 10

var lvl = 1
var exp = 0

var maxHP_boost = 0


# 手中武器即 belongings[0]。留 weapon 这个访问名，各处读 hero.weapon 不必改写成 belongings[0]。
var weapon: Meleeweapon:
	get:
		return belongings[0] if belongings.size() > 0 else null
	set(value):
		if belongings.is_empty():
			belongings.append(value)
		else:
			belongings[0] = value

var armor: Armor:
	get:
		return belongings[1] if belongings.size() > 1 else null
	set(value):
		if belongings.size() < 2:
			belongings.resize(2)   # 补齐到 2 槽（缺位补 null）
		belongings[1] = value

func _ready():
	init()
	add_to_group("hero")   # 注册到组，供 TurnManager 识别

func init():
	alignment = Alignment.ALLY
	maxHP = 20
	HP = 20
	
	STR = STARTING_STR
	
	Hunger.new().attach_to(self)
	
	belongings = [null, null, null, null, null]   # 开局空手、无甲；两槽必须齐备，否则取值越界
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
		spend(1/speed())
	return ok

func dr_roll() -> int:
	if armor == null:
		return 0   # 无甲：不减伤
	return randi_range(armor.dr_min(), armor.dr_max())
	
func damage_roll() -> int:
	if weapon == null:
		return randi_range(1, 5)   # 空手：1-5
	return randi_range(weapon.min(), weapon.max())

# 攻击触及距离：空手为 1
func reach() -> int:
	return weapon.RCH if weapon != null else 1

func speed() -> float:
	var speed: float = 1.0
	return speed

func can_attack(enemy: Char) -> bool:
	if(enemy == null or grid_pos == enemy.grid_pos):
		return false
	
	var diff = enemy.grid_pos - self.grid_pos
	var dis = max(absi(diff.x), absi(diff.y))
	if dis == 1:
		return true
	return dis <= reach()
	
func damage(dmg: int, src = null):

	if (self.has_buff(Drowsy)):
		self.get_buff(Drowsy).detach()
		
	var damage: float = dmg
	dmg = roundi(dmg)
	
	super.damage(dmg, src)
	
func attack_delay():
	var delay: float = 1.0
	
	return delay/speed()
	
func spend(time: float) -> void:
	super.spend(time)

func spend_and_next(time: float):
	spend(time)
	next()
	
func act() -> bool:
	if (paralysed > 0):
		print("[HERO] 麻痹中 paralysed=", paralysed, " HP=", HP, "/", maxHP, " time=", next_action_time)
		spend(TICK)
		return true
	if (resting):
		spend_constant(TIME_TO_REST)
		next()
		return true
	return false
	
func act_pickup():
	
	pass

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
	var evasion = defense_skill
	if paralysed > 0:
		evasion /= 2
	return max(1, roundi(evasion))

func on_operate_complete():
	super.on_operate_complete()

func next():
	if (is_alive()):
		super.next()
