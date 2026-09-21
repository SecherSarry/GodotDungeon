extends Char
class_name Mob

var max_lvl = Hero.MAX_LEVEL -1

func can_attack(enemy: Char):
	var diff = enemy.grid_pos - self.grid_pos
	return max(absi(diff.x), absi(diff.y)) <= 1
	return false

func _ready():
	maxHP = 8
	HP = 8
	add_to_group("monster")
	rest_anim = "run"   # 静止站立动画

	$ProgressBar.max_value = maxHP
	# 起播静止动画。GameScene 不做动画点播（动画由角色自管），.tscn 里也没开 autoplay，
	# 故这里必须自己播一次；否则 AnimatedSprite2D 只显示默认动画的第 0 帧然后定格。
	play_anim(rest_anim)

func _process(delta: float) -> void:
	super._process(delta)   # 继承基类滑动推进（移动自滑由 Char._process 驱动）

	$ProgressBar.value = HP
	if HP == maxHP or HP == 0:
		$ProgressBar.visible = false
	else:
		$ProgressBar.visible = true

# ---------- AI 状态机 ----------
# 按状态分派行为的骨架：每个状态是一支 AiState 子类，行为写在各自 act()。
# 状态对象无自身数据、由本怪持有并复用（_states）；可变数据（锁定敌人、游荡目标）挂在怪身上，
# 于是同一种怪的实例共享状态对象，却不共享进度。
#
# GDScript 的内层类没有 Java 那种隐式外层实例（Outer.this），故 AiState 必须显式持有宿主 mob。
# 这里不注解 mob 的类型（沿用 Buff.target 的写法）：Mob 是本脚本的 class_name，注解会绕成自引用。
enum State { SLEEPING, WANDERING, HUNTING }

var state: State = State.SLEEPING   # 出生即眠；被负面 buff 或视野里的敌人打断
var enemy: Char = null              # 锁定的敌人（Hunting 追它）
var target: Vector2i = Vector2i(-1, -1)   # 游荡的目的格
var enemy_seen: bool = false        # 本 tick 是否看见敌人
var just_alerted: bool = false      # notice() 置位、act 读取后清空（预留给"刚发现"的分支）

var _states := {}

func _state():
	if _states.is_empty():
		_states[State.SLEEPING]  = Sleeping.new(self)
		_states[State.WANDERING] = Wandering.new(self)
		_states[State.HUNTING]   = Hunting.new(self)
	return _states[state]

# 惊醒：转入 Hunting。调用方负责已把 enemy 锁定好。
func notice() -> void:
	state = State.HUNTING
	enemy_seen = true
	just_alerted = true

# 视野内是否看得见该角色。读自己那份 FOV（act 开头刚重算过）；越界一律不可见。
func can_see(c: Char) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	var p: Vector2i = c.grid_pos
	if p.x < 0 or p.x >= LevelManager.MAP_WIDTH or p.y < 0 or p.y >= LevelManager.MAP_HEIGHT:
		return false
	return FOV[p.y][p.x]

# 随机挑一个可走的相邻格作游荡目标；八向皆堵返回 (-1,-1)。
func pick_wander_target() -> Vector2i:
	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	dirs.shuffle()
	for d in dirs:
		var c: Vector2i = grid_pos + d
		if MapManager.is_walkable(c) and not MapManager.is_occupied(c, self):
			return c
	return Vector2i(-1, -1)

# 行动入口：只做感知，行为交给当前状态对象。
# 契约同前——返回本次行动是否成立；时长由状态内的 spend 自记，兜底由调度器补 DUR_WAIT。
func act() -> bool:
	if game_scene == null:
		return false
	var hero = game_scene.get("hero")
	if hero == null:
		return false

	# 行动前按自身 view_distance 刷新视野（写入 mob.FOV）。
	# 只写自己那份，不落账 explored——怪看得见什么不该替玩家点亮地图。
	fieldofview()

	# 感知：暂无锁定目标就先盯上英雄（本工程目前只有英雄一种敌对角色）。
	if enemy == null or not is_instance_valid(enemy):
		enemy = hero
	var in_fov := can_see(enemy)

	var alerted := just_alerted
	just_alerted = false
	return await _state().act(in_fov, alerted)


# ---------- 状态对象 ----------
# 契约：act() 必须 spend 并返回 true。时间严格递增，否则调度器永远选中它，死循环。
# enemy_in_fov / just_alerted 由 Mob.act 算好传入；just_alerted 暂无使用者，保留备用。
class AiState:
	var mob = null   # 宿主，构造时注入
	func _init(host):
		mob = host
	func act(enemy_in_fov: bool, just_alerted: bool) -> bool:
		return false


# 休眠：原地不动，只花时间。被负面 buff 或视野内的敌人打断。
class Sleeping extends AiState:
	func act(enemy_in_fov: bool, just_alerted: bool) -> bool:
		for b in mob.all_buffs():
			if b.type == Buff.buff_type.NEGATIVE:
				mob.spend(mob.TICK)
				mob.state = Mob.State.WANDERING
				return true
		if enemy_in_fov:
			mob.spend(mob.TICK)
			mob.notice()   # → Hunting
			return true
		mob.enemy_seen = false
		mob.spend(mob.TICK)
		return true


# 游荡：在相邻可走格之间乱走；看见敌人就转入追击。
class Wandering extends AiState:
	func act(enemy_in_fov: bool, just_alerted: bool) -> bool:
		if enemy_in_fov:
			mob.spend(mob.TICK)
			mob.notice()   # → Hunting
			return true
		if mob.target == Vector2i(-1, -1):
			mob.target = mob.pick_wander_target()
		if mob.target != Vector2i(-1, -1) and mob.walk_to(mob.target):
			mob.target = Vector2i(-1, -1)   # 走到即弃，下轮重挑
			mob.spend(mob.DUR_MOVE)
			return true
		mob.target = Vector2i(-1, -1)
		mob.spend(mob.TICK)
		return true


# 追击：贴脸就打，否则寻路逼近；目标没了退回游荡。
class Hunting extends AiState:
	func act(enemy_in_fov: bool, just_alerted: bool) -> bool:
		var foe = mob.enemy
		if foe == null or not is_instance_valid(foe) or not foe.is_alive():
			mob.enemy = null
			mob.state = Mob.State.WANDERING
			mob.spend(mob.TICK)
			return true

		if mob.can_attack(foe):
			await mob.attack(foe)   # 动画/音效/结算/计时（DUR_ATTACK）都在 attack 内自管
			return true

		# 寻路逼近（可绕房间与走廊，不再直撞墙角）。算不出路时退回"朝目标轴逼近一步"、
		# 再退回随机——怪不会呆立不动。walk_to 即时提交 grid 并启动自滑，多怪各自 _process 并行滑。
		var step = mob.next_step_to(foe.grid_pos, false)
		if step != Vector2i(-1, -1) and mob.walk_to(step):
			mob.spend(mob.DUR_MOVE)
			return true

		var diff: Vector2i = foe.grid_pos - mob.grid_pos
		var dirs := []
		if diff.x != 0:
			dirs.append(Vector2i(sign(diff.x), 0))
		if diff.y != 0:
			dirs.append(Vector2i(0, sign(diff.y)))
		dirs.shuffle()
		for d in dirs:
			if mob.walk_to(mob.grid_pos + d):
				mob.spend(mob.DUR_MOVE)
				return true

		var random_dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		random_dirs.shuffle()
		for d in random_dirs:
			if mob.walk_to(mob.grid_pos + d):
				mob.spend(mob.DUR_MOVE)
				return true

		mob.spend(mob.TICK)   # 全方向堵死：仍记一笔时间，交给调度器继续
		return true
