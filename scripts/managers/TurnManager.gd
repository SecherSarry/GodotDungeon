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
# hero 与 monster 共用 act()/spend_time；轮到 hero 槽位时让出，等玩家输入。
# 移动并行：各怪 act 内 walk_to 即时提交 grid 并各自启动自滑，互不 await；
# 攻击分支仍 await（动画完才结算）。末尾统一等一个 MOVE_DURATION，让英雄与怪物
# 同一帧发起的滑动一起收尾（仅等一次，避免"英雄滑完再等怪物滑"的走-停-走卡顿）。

# hero + 有效 monsters（单一真相源，避免另建数组失同步）；hero 优先入列，平局取先到者
func all_actors() -> Array:
	var list := []
	if is_instance_valid(hero):
		list.append(hero)
	for mob in monsters:
		if is_instance_valid(mob):
			list.append(mob)
	return list

# 取 next_action_time 最小者
func next_actor() -> Char:
	var best: Char = null
	for a in all_actors():
		if best == null or a.next_action_time < best.next_action_time:
			best = a
	return best

func advance() -> void:
	if is_processing:
		return
	is_processing = true
	emit_signal("before_monster_turn")
	var moved := false
	while true:
		if not is_instance_valid(hero):
			break   # 无英雄槽位可让出（异常态）：立即收手，避免无限循环
		var a = next_actor()
		if a == null or a == hero:
			break   # 轮到玩家槽位 → 让出控制等输入
		var before = a.grid_pos
		var base = await a.act()
		if not is_instance_valid(a):
			continue   # act 中可能死亡/释放
		# 记账约定：act 返回 >0 → 由调度器记账（移动/空耗）；
		# 返回 0 → 该行动已在 act 内部自行记账（攻击走 Char.attack）。两种都使时间严格递增，终将轮到 hero。
		if base > 0.0:
			a.spend_time(base)
		if a.grid_pos != before:
			moved = true
	# 统一收尾：怪物本批有移动，或英雄自身正在滑行（发起者已 step），都只等这一次。
	# 英雄与怪物在同一帧起滑 → 并行滑完，避免"英雄滑完再等怪物滑"造成的走-停-走卡顿。
	if moved or (is_instance_valid(hero) and hero.is_moving()):
		await get_tree().create_timer(Char.MOVE_DURATION).timeout
	emit_signal("after_monster_turn")
	is_processing = false
