extends Node2D
class_name Actor

# 一"拍"的时长。直译 SPD `public static final float TICK = 1f`：常量，不可改。
# 子类/内层类里经由实例访问（如 Mob.gd 的 mob.TICK）仍成立，动态查名不区分常量与变量。
const TICK := 1.0

# ---------- 时间轴调度（抽象刻度，非真实秒）----------
# 每个 actor 有 base_speed 与 time；一次行动消耗"基础时长/base_speed"，
# 调度器永远让 time 最小者先动。刻度只定顺序与频次，不改变单次动画快慢。
const DUR_MOVE   := 1.0   # 移动基础时长
const DUR_ATTACK := 1.0   # 攻击基础时长（暂固定，不接武器 DLY）
const DUR_PICKUP := 1.0   # 拾取基础时长
const DUR_WAIT   := 1.0   # 旧"无法行动也消耗一拍"的兜底量。改锁模型后已无调用点（见 act() 契约注释）

# 下次行动时刻。名字与 SPD Actor.java 的字段逐字一致（原版是 private float time）。
var time: float = 0.0

# 调度器的"当下"：全局唯一一份，不随 actor 走。直译 SPD Actor.java 的
# `private static float now`——那边由静态 process() 每次选中 actor 后写 now = current.time；
# 本工程由 TurnManager.process() 在选中后写同一处（同样的"先定 now 再 act"次序）。
# 它是"相对当下"类算法的基准：cooldown（还差多久轮到）、postpone（至少排到多久以后），
# 以及原版里新增 actor 一律以 now 为锚（add / addDelayed）。没有它，这些只能拿绝对时刻充数——
# 局部看没错，跨层/时钟基数一变就错。它取值恒等于"当前被选中者的 time"，也就是全场最小 time。
static var now: float = 0.0

# 世界锁：当前独占时间轴的那一个 actor。直译 SPD Actor.java 的 `private static Actor current`。
# 语义是"谁在行动"——非空期间世界归它，且只有它自己能调 next() 放开。
# 它是 act() 返回 false 时的唯一判据：锁已释放 → 调度器继续挑下一个；锁还在 → 整个世界停产
# （原版是把 actor 线程 wait() 睡下，本工程等价物是 process() 退出，见 TurnManager.process）。
# 原版把它当线程归属标志用，故与"能否接受输入"无关——空闲待输入的英雄**正**持有本锁。
static var current: Actor = null

# 结算优先级：time 相同时的决胜键，数值**大**者先结算（方向同 SPD 的 Actor.process）。
# 直译 SPD Actor.java 的优先级表，每个类别一格，数值不要改号：
# 原版是各类别在自己的构造器里写 actPriority 字段，本工程同：Buff/Char/Mob 各自在 _init 里赋本字段。
# 注意由此带来的 super() 纪律——子类覆写 _init 而不调 super()，本类（乃至中间层）的赋值整个不执行，
# 会静默退回 DEFAULT（排在所有类别之后）。新增带 _init 的子类务必先 super()。
# 赋在各层 _init 而非 var 默认值：GDScript 子类无法改写父类 var 的初值，只有 _init 能分层生效。
const VFX_PRIO  := 100    # 视觉特效最先
const HERO_PRIO := 0      # 角色；正数排在角色之前，负数排在之后
const BLOB_PRIO := -10    # blob 排在角色之后、怪物之前
const MOB_PRIO  := -20    # 怪物排在 blob 之后、buff 之前
const BUFF_PRIO := -30    # buff 在一回合里最后结算
const DEFAULT   := -100   # 未给优先级者，排在所有类别之后

var act_priority = DEFAULT

func act() -> bool:
	return false
	
# 参数与成员同名（原版逐字如此，spendConstant 的参数就叫 time），故成员一律写 self.time——
# 对应原版的 this.time。参数遮蔽成员，裸写 time 拿到的是参数，务必别省 self.。
func spend_constant(time: float) -> void:
	self.time += time
	var ex: float = absf(fmod(self.time, 1.0))
	if ex < .001:
		self.time = roundf(self.time)

func spend(time: float) -> void:
	spend_constant(time)

# ---------- 时间轴操作族（直译 SPD Actor.java 的同名方法）----------

# 收拢到整拍：向上取整。直译 SPD `public void spendToWhole(){ time = (float)Math.ceil(time); }`。
# 用途是"不许在层与层之间留半拍"——原版换层前对英雄、以及赶在英雄之前的人各调一次。
func spend_to_whole() -> void:
	time = ceilf(time)

# 至少排到 now + time 之后。直译 SPD `protected void postpone(float time)`：
# 已经排在更后面就不动（只往后推，绝不提前），太靠前才拉平到指定时刻。
# 末尾两行取整与 spend_constant 同款：贴着整拍就吸附上去。
# 参数与成员同名（原版逐字如此），故成员写 self.time、now + time 里的 time 是参数。
func postpone(time: float) -> void:
	if self.time < now + time:
		self.time = now + time
		var ex: float = absf(fmod(self.time, 1.0))
		if ex < .001:
			self.time = roundf(self.time)

# 直接跳到当下。直译 SPD `public void timeToNow(){ time = now; }`
# ——与 postpone 相对：postpone 兜底"不早于"，timeToNow 是"追平当前时刻"。
func time_to_now() -> void:
	time = now

# 距当下还剩多久才轮到本 actor。直译 SPD：`return time - now;`
# （此前写成返回绝对时刻 time，只有在 now 恒为 0 时才碰巧对。）
func cooldown() -> float:
	return time - now

func diactivate() -> void:
	time = INF

# 释放世界锁。直译 SPD Actor.java：
#   public void next() { if (current == this) current = null; }
# 它**不是**"推进到下一个 actor"——是"我这一拍不再独占世界"。名实不符，原版就叫 next()，
# 此处保持同名以免移植时对不上。
# 返回值本身不决定世界走不走，本函数才决定：act() 返回 false 时，调度器据锁是否还在来判断。
# 于是"同是 return false，休息/麻痹继续跑、空闲停产"，差别全在有没有多这一行 next()——
# 原版 Hero.act 的两个分支正是如此，本工程 Hero.act 照写。
func next():
	if current == self:
		current = null
	await TurnManager.process()

# ---------- act() 的契约（直译 SPD Actor.act / process 的调用约定）----------
# 返回 true  → 调度器立刻重挑下一个（不论锁在不在）。
# 返回 false → 调度器再看锁：锁已放开（本函数内调过 next()）就继续跑；锁还在就整个停产。
# 于是有两条合法写法，取决于"这一拍之后世界该不该继续走"：
#   1. spend(...) 之后 return true              —— 常规行动：记好时长、让出，世界照走。
#   2. spend(...) 之后 next() 再 return false   —— 同样照走，只是走"放锁"这条出口。
# 时长必须由 act 自己用 spend 记（移动 DUR_MOVE、攻击 DUR_ATTACK、buff TICK）。
# 原版没有"调度器替你补时长"这一说：不 spend 又 return true 会让它被无限重挑、时间轴原地打转。
# 本类的 DUR_WAIT 正是旧版那种兜底的残留，现已无调用点，保留待定。
