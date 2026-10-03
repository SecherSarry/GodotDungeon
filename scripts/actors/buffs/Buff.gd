extends Actor
class_name Buff

# 不写类型注解：Char 的方法签名里引用了 Buff，本类若再静态引用 Char 就构成
# 循环依赖，Godot 解析不出 Char 的基类链（表现为"spend() not found in base self"）。
# 本类对宿主只调 add/remove，本就是鸭子类型，无需静态类型。
var target: Char = null

enum buff_type{POSITIVE, NEGATIVE, NEUTRAL}
var type: buff_type = buff_type.NEUTRAL

var announced: bool = false

var revive_persists: bool = false

# 晚于宿主结算：BUFF_PRIO，与 SPD 同值（"buffs act last in a turn"）。
# 角色取 HERO_PRIO，数值大者先动，故 buff 恒排在宿主之后。
# "限时 buff 显示 20 就真是 20 回合"由两处共同保证：这里让 buff 与宿主同时到点时宿主先动，
# 宿主能动满整个时长；另一半是显示时取 visualcooldown（下方），即 cooldown + 1。
# 覆写 _init 的子类必须调 super()，否则这一行不执行、优先级静默退回 DEFAULT（见 Actor.gd 注释）。
func _init() -> void:
	act_priority = BUFF_PRIO

# 剩余回合数（供显示）。直译 SPD Buff.java 的 visualcooldown：`cooldown() + 1f`。
# 为什么 +1：buff 排在宿主之后结算，轮到它时 cooldown 已经扣掉一回合，
# 不补一回合的话"还剩 3 回合"会在第 3 回合直接消失，看着少一回合（SPD 原注释同此意）。
func visualcooldown() -> float:
	return cooldown() + 1.0

# 参数不叫 target：那是成员变量名，同名会遮蔽。同上，不注解 Char 以避开循环依赖。
func attach_to(buff_target: Char) -> bool:
	if buff_target == null:
		return false

	# 同类已挂 → 续期：把新 duration 累加到在场那个的剩余时长上。
	# 必须累加，不能写成"宿主当下 + duration"——那会把已经熬了很久的 buff 拉回满时长，
	# 是刷新不是续期。本实例只是携带 duration 的信使，效果已转交，回收掉。
	var existing = buff_target.get_buff(self.get_script())
	if existing != null and existing != self:
		return true   # 本实例只是携带 duration 的信使，效果已转交；Resource 靠引用计数回收

	# 先落 target 再 add，与 SPD 同序；add 返回 false 必须复位并拒收——
	#   if (target.add(this)) { ... return true; } else { this.target = null; return false; }
	# Char.add 只在"同类键已存在"时返回 false，也就是同一实例被 attach_to 第二次；
	# 不回退的话下面的锚点与 spend 会把时长再叠一遍（本实例本来只是重复投递）。
	self.target = buff_target
	if not buff_target.add(self):
		self.target = null
		return false

	# 先把锚点挪到"当下"，再叠加时长。否则 spend(duration) 是从本 buff 自己的 0 起算的
	# 绝对时刻：时钟早已越过它时，buff 会在下一次调度立刻到期——表现为"喝药当场失效"，
	# 且越到游戏后期越明显（只有开局时钟为 0 时才碰巧接近满时长）。
	# 锚点用全局 now 而非宿主的 time：原版走的是 Char.add → Actor.add(buff) → add(buff, now)，
	# 也就是 `buff.time += now`，本 buff 因此成为时间轴上的独立 actor，到期时刻从"当下"起算。
	# 宿主当下正在行动时 now 恰等于宿主 time，两者一致；宿主闲着时（例如英雄给怪物挂 debuff）
	# 才会分叉——那时按宿主 time 会把到期时刻拖到怪物下一次行动之后，比原版晚。
	self.time += Actor.now

	return true

# 干净退场：此前只能由外部直接动 Char.buffs。
# 直译 SPD Buff.java：`if (target.remove(this)) ...`——**不把 target 置空**。
# 原版只在 attach_to 的失败路径（target.add 返回 false）才把 target 复位为 null，detach 不碰它。
# 置空看着"更干净"，代价却摊派给所有子类：MagicalSleep.detach 开头要读 target.paralysed、
# WellFed.act 要在 detach 前先存一份宿主——每个子类都得记住这条，且二次 detach 会当场崩。
# remove 本身幂等（Char.remove 里 `buffs.get(key) != buff` 一判即返回 false），故不必靠置空防重复。
#
# 本类随 Actor 一起改继承 Resource（引用计数对象），此前为 Node 泄漏而加的
# queue_free / is_queued_for_deletion 两步全部撤掉：脱离 Char.buffs 之后引用归零即回收，
# 与 Java 侧"detach 之后由 GC 收走"同义。
func detach() -> void:
	if target != null:
		target.remove(self)

# 直译 SPD Buff.java 的默认 act()：`diactivate(); return true;`
# 语义：不自己写 act() 的 buff（被动型，如神器的 chalice_regen）被调度到时，
# 把自己的时间轴关掉（time = INF，之后不再被 next_actor 选中），并返回 true 让世界继续。
# 缺了这条会继承 Actor.act() 的 `return false`：被动 buff 每回合仍被选中、返回 false 又不 next()，
# TurnManager 判成"非英雄返回 false 且未 next()" → break，装神器（圣杯）后世界立刻停产。
func act() -> bool:
	diactivate()
	return true

func name() -> String:
	return self.get_script().get_global_name()

func desc() -> String:
	# 剩余回合走 visualcooldown（cooldown + 1），不再手写 time - target.time。
	# 二者在"宿主刚行动过"时数值相同，但 target.time 只是宿主的下次行动时刻，
	# 而 cooldown 用的是全局 now——轮到别人行动时看 buff 列表，前者会偏。
	return str(visualcooldown())

# 新建实例并挂上，不预支时长。直译 SPD Buff.java 的 append(target, buffClass)：
#   T buff = Reflection.newInstance(buffClass); buff.attachTo(target); return buff;
# duration 必须显式传 0：attach_to 的默认值是 1，会让 buff 的时间落到 now+1，
# 与"刚行动完的宿主"（now + 它这一拍）**恰好平局**，再被宿主的更高优先级压掉——
# 宿主 act() 返回 false 即 break 整个回合循环，本 buff 这一轮根本轮不到，要等下一回合。
# 治疗药剂走这条路：喝了不立刻回血、要再动一下才结算，就是这个 1 造成的。
# 0 表示"只把锚点对齐到当下"，正是 SPD attachTo 的语义（那边根本不 spend）。
static func append(target: Char, buff_class):
	var buff: Buff = buff_class.new()
	buff.attach_to(target)
	return buff

# 挂 buff 的统一入口。直译 SPD Buff.java 那对 affect 重载——Java 靠重载，
# GDScript 没有重载，故合并成一个带默认值的 duration：
#   affect(target, cl)          → 只挂，不预支时长
#   affect(target, cl, duration)→ 挂上后再 spend(duration)
# 语义要点两条：
#  1. 同类已在场就复用、不新建（首次挂载的副作用不重跑），交给调用方直接拿到"真正生效的那一个"。
#  2. duration 的预支发生在**取到实例之后**（spend 在 return 前那步），所以续期时是加在在场的那个身上。
# 调用方一律走本函数，别再手写 X.new().attach_to(...)：那样会各自决定要不要传时长、
# 传了又会撞上平局（见 append 的注释），且同类已存在时拿到的是被回收的信使实例。
static func affect(target: Char, buff_class, duration: float = 0):
	var buff: Buff = target.get_buff(buff_class)
	if buff == null:
		buff = append(target, buff_class)
	if duration != 0:
		buff.spend(duration)
	return buff
	
static func prolong(target: Char, buff_class, duration):
	var buff: Buff = affect(target, buff_class)
	buff.postpone(duration)
		
static func do_detach(target: Char, buff_class):
	var b = target.get_buff(buff_class)
	if b == null:
		return
	else:
		b.detach()


# ---------- 存档 ----------
# 存脚本路径 + 剩余时长（cooldown，相对量）+ 标量脚本属性。
# 存 cooldown 而非 time：time 是"绝对到期时刻"，锚在全局时钟上，而时钟每局归零；
# 存相对量，回来由 from_data 走 affect(owner, cls, cooldown) 重新锚定。
# 跳过 time / act_priority：前者由 affect 重建，后者由各子类 _init 重建，回写只会覆盖成错值。
func serialize() -> Dictionary:
	return {
		"script": get_script().resource_path,
		"cooldown": cooldown(),
		"props": Bundlable.script_props(self, ["time", "act_priority"]),
	}

# 由存档字典在 owner 身上重建一个 buff：先按剩余时长挂上，再回写标量属性
# （Hunger 的饱食度、Regeneration 的累积量这类就在 props 里，靠这一步带上）。
static func from_data(owner: Char, data: Dictionary):
	var path: String = data.get("script", "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var buff = affect(owner, load(path), float(data.get("cooldown", 0.0)))
	Bundlable.apply_props(buff, data.get("props", {}))
	return buff
