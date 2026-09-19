extends Actor
class_name Buff

# 不写类型注解：Char 的方法签名里引用了 Buff，本类若再静态引用 Char 就构成
# 循环依赖，Godot 解析不出 Char 的基类链（表现为"spend() not found in base self"）。
# 本类对宿主只调 add/remove，本就是鸭子类型，无需静态类型。
var target: Char = null

enum buff_type{POSITIVE, NEGATIVE, NEUTRAL}
var type: buff_type = buff_type.NEUTRAL

# 早于宿主结算：否则英雄行动时读到的还是上一轮的状态。
# 与宿主 next_action_time 持平时由调度器比这个值，故 buff 必然先被调度。
# 用虚方法覆写而非 _init 赋值：子类写自己的 _init 设时长时不必记得 super()。
func get_act_priority() -> int:
	return -30

# 参数不叫 target：那是成员变量名，同名会遮蔽。同上，不注解 Char 以避开循环依赖。
func attach_to(buff_target: Char, duration: float = 1) -> bool:
	if buff_target == null:
		return false

	# 同类已挂 → 续期：把新 duration 累加到在场那个的剩余时长上。
	# 必须累加，不能写成"宿主当下 + duration"——那会把已经熬了很久的 buff 拉回满时长，
	# 是刷新不是续期。本实例只是携带 duration 的信使，效果已转交，回收掉。
	var existing = buff_target.get_buff(self.get_script())
	if existing != null and existing != self:
		existing.spend(duration)
		queue_free()
		return true

	buff_target.add(self)
	self.target = buff_target

	# 先对齐宿主的时间轴，再叠加时长。否则 spend(duration) 是从本 buff 自己的 0 起算的
	# 绝对时刻：宿主时钟早已越过它时，buff 会在下一次调度立刻到期——表现为"喝药当场失效"，
	# 且越到游戏后期越明显（只有开局时钟为 0 时才碰巧接近满时长）。
	self.next_action_time += buff_target.next_action_time
	if duration != 0:
		self.spend(duration)

	return true

# 干净退场：此前只能由外部直接动 Char.buffs
func detach() -> void:
	if target != null:
		target.remove(self)
	target = null
	
