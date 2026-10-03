extends FlavourBuff
class_name MagicalSleep

static var STEP: float = 1

func attach_to(buff_target: Char) -> bool:
	# duration 必须透传：基类的默认值是 1，不透传的话卷轴传进来的时长会被吞掉。
	if not super.attach_to(buff_target):
		return false
	# 续期路径：基类已把 duration 转交给在场那个实例、并 queue_free 了本实例，target 未被赋值。
	# 此时不可再对宿主叠加副作用——本实例不会走 detach() 回收，paralysed 会只增不减。
	if target == null:
		return true

	buff_target.paralysed += 1

	if (buff_target.alignment == Char.Alignment.ALLY):
		if (buff_target.hp == buff_target.max_hp):
			print("你很健康")
			detach()
			return true
		else:
			print("你睡着了")

	if (buff_target is Mob):
		buff_target.state = Mob.State.SLEEPING

	return true

func act() -> bool:
	print("[MS] 被调度 target=", target, " =", target.hp, "/", target.max_hp, " time=", time)
	if (target is Mob and target.state != Mob.State.SLEEPING):
		detach()
		return true
			
	if (target.alignment == Char.Alignment.ALLY):
		target.hp = min(target.hp+1, target.max_hp)
		if (target is Hero):
			target.resting = true
		if (target.hp == target.max_hp):
			if (target is Hero): print("wakeup")
			detach();
			
	spend( STEP );
	return true;

func detach() -> void:
	if target.paralysed > 0:
		target.paralysed -= 1
	if (target is Hero):
		target.resting = false
	
	if (target is Mob and target.alignment == Char.Alignment.ALLY and target.state == Mob.State.SLEEPING):
		target.state = Mob.State.WANDERING
	super.detach()
