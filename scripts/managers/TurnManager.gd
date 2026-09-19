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
# 不再有"怪物整批回合"：所有 actor 按 next_action_time 排序，最小者先动。
# hero 与 monster/buff 共用 act()/spend()；轮到 hero 槽位时让出，等玩家输入。
# act() 返回 bool：成立者已在内部自记时长，不成立者由调度器补记 DUR_WAIT。
# 移动并行：各怪 act 内 walk_to 即时提交 grid 并各自启动自滑，互不 await；
# 攻击分支仍 await（动画完才结算）。末尾统一等一个 MOVE_DURATION，让英雄与怪物
# 同一帧发起的滑动一起收尾（仅等一次，避免"英雄滑完再等怪物滑"的走-停-走卡顿）。

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

# 取 next_action_time 最小者；时间相同则 act_priority 小者先（Buff=-30 早于角色=0）。
# 用 is_equal_approx 而非 ==：next_action_time 是累加出来的浮点，精确相等不可靠。
func next_actor() -> Actor:
	var best: Actor = null
	for a in all_actors():
		if best == null:
			best = a
			continue
		if is_equal_approx(a.next_action_time, best.next_action_time):
			if a.get_act_priority() < best.get_act_priority():
				best = a
		elif a.next_action_time < best.next_action_time:
			best = a
	return best

func next() -> void:
	if is_processing:
		return
	is_processing = true
	emit_signal("before_monster_turn")
	var moved := false
	while true:
		if not is_instance_valid(hero):
			break   # 无英雄槽位可让出（异常态）：立即收手，避免无限循环
		var a = next_actor()
		if a == null:
			break
		if a == hero:
			# 英雄槽位：先问一次英雄能否自行处理（麻痹跳回合等）。
			# act() 返回 true = 已自行扣时处理完，调度器继续推进；false = 无自处理，让出等输入。
			# 基类与 Hero 当前实现都返回 false，故正常回合仍是"让出"，行为不变。
			if not await hero.act():
				break
			continue   # 已自行处理完：重新取最小者，不可落回下面再调一次 a.act()
		# buff 不是 Char、没有 grid_pos：只有角色才谈"是否移动过"
		var is_char := a is Char
		var before: Vector2i = a.grid_pos if is_char else Vector2i.ZERO
		var acted: bool = await a.act()
		if not is_instance_valid(a):
			continue   # act 中可能死亡/释放
		# 记账：行动成立者已在 act 内自记（移动 DUR_MOVE、攻击 DUR_ATTACK、buff TICK）。
		# 不成立者由调度器补记 DUR_WAIT——时间必须严格递增，否则 next_actor 永远选中它，死循环。
		if not acted:
			a.spend(Actor.DUR_WAIT)
		if is_char and a.grid_pos != before:
			moved = true
	# 统一收尾：怪物本批有移动，或英雄自身正在滑行（发起者已 step），都只等这一次。
	# 英雄与怪物在同一帧起滑 → 并行滑完，避免"英雄滑完再等怪物滑"造成的走-停-走卡顿。
	if moved or (is_instance_valid(hero) and hero.is_moving()):
		await get_tree().create_timer(Char.MOVE_DURATION).timeout
	emit_signal("after_monster_turn")
	is_processing = false
