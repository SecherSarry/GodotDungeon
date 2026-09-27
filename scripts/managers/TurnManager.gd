extends Node

# ---------- 信号 ----------
signal before_monster_turn
signal after_monster_turn
signal actor_attacked(attacker, target, damage)
signal actor_died(actor)   # 新增：角色死亡信号
signal hero_died

# ---------- 英雄和怪物 ----------
var hero: Char = null
var monsters: Array = []

# ---------- 处理标志 ----------
var is_processing: bool = false

# ---------- 注册/注销 ----------
func register_actor(actor: Char):
	if actor.is_in_group("hero"):
		hero = actor
	elif actor.is_in_group("monster"):
		if actor not in monsters:
			monsters.append(actor)

func unregister_actor(actor: Char):
	if actor == hero:
		hero = null
	elif actor in monsters:
		monsters.erase(actor)

# ---------- 获取某格的怪物 ----------
func get_monster_at(cell: Vector2i):
	for mob in monsters:
		if is_instance_valid(mob) and mob.grid_pos == cell:
			return mob
	return null

# ---------- 时间轴调度器 ----------
# 直译 SPD Actor.process()：一个循环，每轮清锁 → 挑 time 最小者 → now = 它的 time → 调 act()。
# 不再有"怪物整批回合"：所有 actor（角色 + 身上 buff）在同一条时间轴上按 time 排，最小者先动。
#
# 与 SPD 的对应关系（这是本文件最易误读之处）：
#   SPD 跑在专用线程上，靠 wait()/notify() 停产与唤醒；本工程在主线程，**没有常驻线程**。
#   "停产"的等价物就是 process() 退出（控制权还给引擎，渲染与输入照常）；
#   "唤醒"的等价物是外部再调一次 process()（输入、UI、换层）。
#   因此 Actor.next() 只负责放锁，谁来驱动循环由调用方决定——见 Actor.next 与 process 的注释。
#
# act() 的 bool 与原版同义（变量名照抄原版的 doNext）：
#   true       → 立刻重挑下一个，不等任何东西
#   false + 锁已释放（act 内调了 next()）→ 同上，继续跑。休息/麻痹走这条
#   false + 锁还在（没调 next()）      → 停产，等外部调 process()。英雄空闲待输入走这条
# 注意"停不停"由 next() 决定而非返回值本身：同是 return false，差一行 next() 就天差地别。
#
# 移动并行：各怪 act 内 walk_to 即时提交 grid 并各自启动自滑，互不 await；
# 攻击分支仍 await（动画完才结算）。所以循环体之间没有 await——同一帧里英雄和各怪
# 一起起滑，视觉上并行，这才是对的。
#
# 但"一次 process 调用"现在可能覆盖英雄的多步（Move 动作跨回合持续到终点，见 Hero.act_move）：
# 英雄第 1 步与第 2 步之间若不留时间，第 2 步会在第 1 步还没滑完时就提交 → 看着瞬移。
# 故加一个 pending 标记：**轮到英雄时**，若自上次等待以来有谁动过，先等上一步滑完
# （等 is_moving() 落，不是等定时器——见下方该处的注释）。
# 只等英雄——怪与英雄同帧起滑，为每个怪都等一次会把并行退化成串行（走一个停一下）。
# 循环退出时若还有没滑完的（末轮是怪在动），补等一次，让画面收干净。

# hero + 有效 monsters + 他们身上的 buff（单一真相源，避免另建数组失同步）。
# 入列顺序不再承载语义：平局一律由 act_priority 裁决。
func all_actors() -> Array:
	var list := []
	if is_instance_valid(hero):
		list.append(hero)
		list.append_array(hero.all_buffs())
	for mob in monsters:
		if is_instance_valid(mob):
			list.append(mob)
			list.append_array(mob.all_buffs())
	return list

# 取 time 最小者；时间相同则 act_priority **大**者先。
# 方向与 SPD 的 Actor.process 一致（那边也是 actPriority 大者先），故优先级数值与
# 原版逐一对齐、表就写在 Actor.gd 里（HERO_PRIO / MOB_PRIO / BUFF_PRIO ...）。
# 用 is_equal_approx 而非 ==：time 是累加出来的浮点，精确相等不可靠。
func next_actor() -> Actor:
	var best: Actor = null
	for a in all_actors():
		if best == null:
			best = a
			continue
		if is_equal_approx(a.time, best.time):
			if a.act_priority > best.act_priority:
				best = a
		elif a.time < best.time:
			best = a
	return best

# 全场回拨到整拍。直译 SPD Actor.fixTime（原版是 Actor 上的静态方法，靠 Actor.all 全局表；
# 本工程的全局表就是 all_actors()，故跟着调度器住这里）。
# 做法：取全场最小 time，只按**整数**回拨——这样回合始终对齐整拍，不会漂出半拍；
# now 同步回拨同一个量，于是所有 cooldown 原封不动，只是整条时间轴被搬回原点附近。
# 原版调用点：InterlevelScene（换层前）、Dungeon.saveAll、英雄阵亡、Multiplicity 分裂。
# 本工程换层用的是 Char.reset_timeline（直接把英雄落到 0），尚未接本函数。
func fix_time() -> void:
	var actors = all_actors()
	if actors.is_empty():
		return
	var min_time: float = INF
	for a in actors:
		if a.time < min_time:
			min_time = a.time
	min_time = float(int(min_time))   # 原版 (int)min：只按整数回拨（int() 向零截断，与 Java 强转同）
	for a in actors:
		a.time -= min_time
	Actor.now -= min_time

# 还有角色在滑吗（供收尾等待用：末轮可能是怪在动，那时 pending_wait 没记是谁）。
func _any_actor_moving() -> bool:
	for a in all_actors():
		if a is Char and is_instance_valid(a) and a.is_moving():
			return true
	return false

func process() -> void:
	if is_processing:
		return   # 已在循环里（同一次动作/同一次唤醒内的重入）：不叠第二层
	is_processing = true
	emit_signal("before_monster_turn")
	var pending_wait := false   # 有角色的滑动已起但还没等过
	while true:
		if not is_instance_valid(hero):
			break   # 无英雄槽位可让出（异常态）：立即收手，避免无限循环
		Actor.current = null   # 每轮开头清锁：原版 process() 同序（先 current = null 再挑）
		var a = next_actor()
		if a == null:
			break
		if a == hero and pending_wait:
			# 英雄连走两步之间留一拍：等上一步滑完再提交下一步（见顶部注释）。
			# 放在持锁之前：等待期间世界无主，语义干净。
			# 等 is_moving() 落而不是等定时器：滑动的位置在 Char._process 里推进，起点却在
			# walk_to 里当场读 position（Char.gd:148）。定时器与 _process 是两个不同步的钟，
			# 定时器早到一步，下一步就从半格处起步——时长一样、距离变长，看着偏快。
			# 滑完那一刻 position 已被赋成 _to_pos（Char.gd:120-121），正好落在格中心。
			while is_instance_valid(a) and a.is_moving():
				await get_tree().process_frame
			pending_wait = false
		Actor.current = a   # 选定即持锁：直到它自己 next() 放开，或本函数退出
		# 定当下：与 SPD Actor.process 同序——先 now = current.time，再 act。
		# 只写这一处，全局唯一的 now 才恒等于"当前被选中者的 time"（也就是全场最小 time）。
		Actor.now = a.time
		# buff 不是 Char、没有 grid_pos：只有角色才谈"是否移动过"
		var is_char := a is Char
		var before: Vector2i = a.grid_pos if is_char else Vector2i.ZERO
		var do_next: bool = await a.act()
		if not is_instance_valid(a):
			Actor.current = null
			continue   # act 中可能死亡/释放
		if is_char and a.grid_pos != before:
			pending_wait = true   # walk_to 已即时提交 grid，滑动从这一刻起算
		# doNext 为真：立刻重挑，不等任何东西（原版同）。
		# doNext 为假时要问锁：act 内调过 next() 就已放开，世界照走；没调就是停产。
		# 停产 = 原版的线程 wait()（那边由渲染线程 notify 唤醒，本工程由外部调本函数唤醒）。
		if not do_next and Actor.current != null:
			if a != hero:
				# 只有英雄该走这条（空闲待输入）。别类 actor 落到这里等于世界停摆且无唤醒源——
				# 那是它的 bug：契约是"要不停产就 spend 后 return true，或调 next() 再 return false"。
				push_warning("[TurnManager] %s 返回 false 且未 next()：世界停产且无唤醒源" % a)
			break
	# 收尾：末轮若是怪在动，它的滑动还没等过 → 补等一次，让画面收干净再交回输入。
	# 判据同上一处：谁在滑就等谁，不猜时长（这里的 pending_wait 不记是谁动的，统查一遍）。
	if pending_wait:
		while _any_actor_moving():
			await get_tree().process_frame
	emit_signal("after_monster_turn")
	is_processing = false
