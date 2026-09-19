extends Node2D
class_name Actor

var TICK: float = 1.0

# ---------- 时间轴调度（抽象刻度，非真实秒）----------
# 每个 actor 有 base_speed 与 next_action_time；一次行动消耗"基础时长/base_speed"，
# 调度器永远让 next_action_time 最小者先动。刻度只定顺序与频次，不改变单次动画快慢。
const DUR_MOVE   := 1.0   # 移动基础时长
const DUR_ATTACK := 1.0   # 攻击基础时长（暂固定，不接武器 DLY）
const DUR_PICKUP := 1.0   # 拾取基础时长
const DUR_WAIT   := 1.0   # 无法行动时也消耗：保证调度器必然前进，杜绝死循环

var next_action_time: float = 0.0

# 结算优先级：next_action_time 相同时的决胜键，数值小者先结算。
# 存在的意义是让"Buff 先于宿主结算"成为显式规则，而不是碰运气靠入列顺序。
# 角色默认 0，Buff 覆写为 -30。
# 做成方法而非成员变量：变量默认值只能靠子类 _init 里赋值，一旦子类 _init 忘了
# super() 就静默失效（本项目的 Item 继承链已被这个坑咬过三次）。虚方法覆写没有这个风险。
func get_act_priority() -> int:
	return 0

func spend_constant(time: float) -> void:
	next_action_time += time
	var ex: float = absf(fmod(next_action_time ,1.0))
	if ex < .001:
		next_action_time = roundf(next_action_time)
	
func spend(time: float) -> void:
	spend_constant(time)

func diactivate() -> void:
	next_action_time = INF
func next():
	await TurnManager.next()
# 返回本次行动是否成立。成立者已在内部用 spend 记好时长（移动 DUR_MOVE、
# 攻击由 Char.attack 记 DUR_ATTACK、buff 记 TICK）；不成立者返回 false，
# 由调度器补记 DUR_WAIT——时间必须严格递增，否则调度器会永远选中它，死循环。
func act() -> bool:
	return false
