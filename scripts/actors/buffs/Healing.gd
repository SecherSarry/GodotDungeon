extends Buff
class_name Healing

var healing_left: int
var percent_heal_per_tick: float
var flat_heal_per_tick: int
var healing_limited: bool

# 排在宿主之后、其他 buff 之前：直译 SPD Healing.java 构造器 `actPriority = HERO_PRIO - 1`。
# super() 必须先调：Buff._init 会把 act_priority 设成 BUFF_PRIO，本行再把它提前到 -1。
func _init() -> void:
	super()
	act_priority = HERO_PRIO-1
	type = buff_type.POSITIVE
	
func act() -> bool:
	if (target.hp < target.max_hp):
		# 加在**当前血量**上（直译 SPD `Math.min(target.HT, target.HP + healingThisTick())`）。
		# 写成 target.max_hp + … 时 min(上限, 上限+heal) 恒等于上限，一 tick 直接满血，
		# set_heal 定的量就再也看不出来了。
		target.hp = mini(target.max_hp, target.hp + healing_this_tick())
		
		if (target.hp == target.max_hp and target is Hero):
			target.resting = false
	
	healing_left -= healing_this_tick()
	
	if(healing_left <= 0):
		if (target is Hero):
			target.resting = false
		detach()
	
	spend(TICK)
	return true

func healing_this_tick() -> int:
	var heal = clampi(roundi(healing_left * percent_heal_per_tick) + flat_heal_per_tick, 1, healing_left)
	#血瓶逻辑
	return heal
	
# 直译 SPD Healing.java 的 setHeal：
#   healingLeft = Math.max(healingLeft, amount);
#   percentHealPerTick = Math.max(percentHealPerTick, percentPerTick);
#   flatHealPerTick = Math.max(flatHealPerTick, flatPerTick);
# 三个字段各自跟**自己的旧值**取大（原版注释：多份治疗不叠加，但各取所长），
# 不是跟 healing_left 比——写成 healing_left 会让后两个参数彻底失效。
# percent 是 float，必须用 maxf：maxi 收 int，传 float 会报
# "Cannot convert argument 2 from float to int"，该表达式取空，字段保不住值。
func set_heal(amount: int, percent_per_tick: float, flat_per_tick: int) -> void:
	healing_left = maxi(healing_left, amount)
	percent_heal_per_tick = maxf(percent_heal_per_tick, percent_per_tick)
	flat_heal_per_tick = maxi(flat_heal_per_tick, flat_per_tick)

func apply_vial_effect() -> void:
	pass
	
func increase_heal(amount: int):
	healing_left += amount
	
func desc() -> String:
	return str(healing_left)
