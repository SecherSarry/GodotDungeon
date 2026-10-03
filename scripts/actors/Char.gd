extends Actor
class_name Char

var grid_pos: Vector2i = Vector2i.ZERO

var max_hp: int = 10
var hp: int = 10

var base_speed: float = 1.0

var paralysed: int = 0
var rooted: bool = false
var flying: bool = false
var invisible: int = 0


enum Alignment{
	ENEMY,
	NEUTRAL,
	ALLY
}
var alignment

var view_distance = 8
var FOV = []

var buffs: Dictionary = {}

# 角色类别取 HERO_PRIO（Actor 里的优先级表）：与怪物同刻到点时角色先动。
# Hero 覆写 _init 时也已 super() 调到这里（它同时在那儿建 belongings）；Mob 覆写 _init 时以 super() 调到这里再改成 MOB_PRIO。
# 本类若被新子类带 _init 地继承，那个子类必须调 super()，否则本行不执行（见 Actor.gd 注释）。
func _init() -> void:
	act_priority = HERO_PRIO

func act() -> bool:
	return false
	
func name() -> String:
	return " "

func can_interact(c: Char):
	return true

func hit_sound():
	AudioManager.play_sound(preload("res://assets/sounds/hit.mp3"), -5, randf_range(0.9, 1.1))

# base_speed / time / spend / act / DUR_* 已上移到 Actor：
# Buff 与角色共用同一套调度刻度，故这些必须落在共同基类上。
# 表现（精灵、朝向、自滑插值、血条、动画）已下沉到 ActorNode，本类经 Actor.sprite 发号施令。

# 本角色在该场景里的服务入口（cell_to_world / 开关门 / 拾取…）。
# 本次分层不动它——数据侧仍持有场景引用，控制爆炸半径（见计划）。
var game_scene: Node = null

# 角色"静止(站立)"动画：滑完/攻击/受击结束后回到它。Hero=idle，Mob=run。
var rest_anim := "idle"

# 怪物判据。原为 is_in_group("monster")，分组随节点体系一并消失后改为显式字段：
# 决定死亡时是"移出调度队列 + 释放节点"（怪）还是"锁操作、留原地"（英雄）。
var is_monster: bool = false

# 攻击结算信号：攻击方发出，携带受害者与伤害（供 UI/音效等消费者连接）
signal actor_attacked(attacker, target, damage)

# ---------- 移动：逻辑即时提交 grid + 令表现层启动自滑，立即返回，不等待动画（并行移动不阻塞回合） ----------
func walk_to(target: Vector2i) -> bool:
	var gs = game_scene
	if gs == null or MapManager.is_occupied(target, self):
		return false
	var step = target - grid_pos

	# 上锁的门：单独花一回合解锁，这一步只解锁、不挪窝（调用方见 true 即 spend）。
	# 正交相邻才解锁——隔着格子或斜着都够不着门锁。
	if MapManager.is_locked_door(target):
		if absi(step.x) + absi(step.y) == 1 and MapManager.unlock_door(target):
			if sprite: sprite.set_facing(step)
			return true
		return false

	# 关着的门：开门不单独计回合，顺手打开，紧接着照常走进去——开门与迈步并作一步。
	# 目标是别的格子时 open_door 是 no-op。
	MapManager.open_door(target)

	if not MapManager.is_walkable(target):
		return false
	var delta = target - grid_pos
	if sprite: sprite.set_facing(delta)
	grid_pos = target   # 逻辑权威：同帧生效，供占用/视野判定
	if sprite: sprite.slide_to(target)   # 视觉从当前位置滑向新格，由 _process 收尾
	return true

# 是否正在滑行（供回合编排等待所有并行滑动收尾）
func is_moving() -> bool:
	return sprite != null and sprite.is_moving()

# 瞬移到某格（换层/传送等）：取消残留滑动并直接摆位，避免插值把角色拽回旧位置
func snap_to(cell: Vector2i) -> void:
	grid_pos = cell
	if sprite: sprite.snap_to(cell)

# ---------- 寻路步进（英雄自动行走与怪物追踪共用） ----------
# 朝 target 计算下一步（8 方向、避障、可绕房间走廊）；无路可走返回 (-1,-1)。
# explored_only=true 只走己知格（玩家）；怪物 AI 传 false。
# 算法在 Pathfinding：拼出可通行位图后由目标反向 BFS 一次距离图，
# 取 from 的最近邻居即下一步——不必展开整条路径。每步现算，以应对移动中的怪。
func next_step_to(target: Vector2i, explored_only: bool = true) -> Vector2i:
	# Pathfinding 会把终点无条件种入距离图（distance[to]=0），故终点是墙也会算出路。
	# 这里先自挡：墙 / 深渊 / 地图外不可作终点。
	if not MapManager.is_walkable(target):
		return Vector2i(-1, -1)
	var passable := MapManager.build_passable(self, explored_only)
	var step := Pathfinding.get_step(MapManager.to_index(grid_pos), MapManager.to_index(target), passable)
	if step < 0:
		return Vector2i(-1, -1)   # 不可达（隔断 / 被围）
	var cell := MapManager.to_cell(step)
	if cell == grid_pos:
		return Vector2i(-1, -1)   # 无更近邻居（理论上已排除，兜底防原地打转）
	return cell

# 朝 target 走一步（计算 + 移动）；成功返回 true
func step_toward(target: Vector2i, explored_only: bool = true) -> bool:
	var step = next_step_to(target, explored_only)
	if step == Vector2i(-1, -1):
		return false
	return walk_to(step)

# ---------- 视野（递归阴影投射） ----------
# 每个单位各有一份 FOV：视野是「这个单位此刻看得见什么」，半径取它自己的 view_distance。
# 与 explored（MapManager 持有的「这张地图被看过的地方」）是两回事——本函数只写 self.FOV，
# 绝不碰 explored。否则怪算一次视野就把玩家的探索图点亮了；落账由英雄一侧单独做
# （GameScene 调 MapManager.record_sight）。
#
# 八个八分仪对称展开，每个逐行推进，用斜率区间追踪墙投下的阴影。相比逐格 Bresenham 画线：
# 每格只处理一次（O(r²) 对 O(r³)），遮挡形状对称，不再斜向穿过墙角看到背后格子。
func fieldofview() -> void:
	if FOV.is_empty():
		for y in range(LevelManager.MAP_HEIGHT):
			var row := []
			for x in range(LevelManager.MAP_WIDTH):
				row.append(false)
			FOV.append(row)
	else:
		# 尺寸是常量、跨层不变，故网格只建一次；之后原地清空重用，不每回合重排 600 格
		for y in range(LevelManager.MAP_HEIGHT):
			for x in range(LevelManager.MAP_WIDTH):
				FOV[y][x] = false

	var origin := grid_pos
	if origin.x < 0 or origin.x >= LevelManager.MAP_WIDTH or origin.y < 0 or origin.y >= LevelManager.MAP_HEIGHT:
		return

	# 失明：正常阴影投射整个跳过，只留贴身一圈。
	# 对应 SPD Level.updateFieldOfView——那边把 sighted 判成 false 后 BArray.setFalse 清空 FOV，
	# 再用 sense 兜底扫一圈，失明时 sense 起手就是 1。远处置暗、脚下仍亮，不至于彻底失去参照。
	# 收窄只做在这一处就够：FOV 是「此刻看得见什么」的单一真相源，怪物/物品可见性与迷雾层都读它，
	# 于是「失明的怪看不见远处的敌人」也自动成立（Mob.can_see 读的正是它自己这份 FOV）。
	# 灵视不受影响：它不是视觉，是另加的一层感知，在 GameScene._reveal_by_mind_vision 里叠加，
	# 原版同理——失明只掐掉阴影投射，不减 sense 里 MindVision 给的半径。
	if has_buff(Blindness):
		reveal_around([origin], 1)
		return

	FOV[origin.y][origin.x] = true

	for o in _OCTANTS:
		_cast_light(origin, 1, 1.0, 0.0, view_distance, o[0], o[1], o[2], o[3])

# 八个八分仪的坐标变换基：(xx, xy, yx, yy)
const _OCTANTS := [
	[1, 0, 0, 1],   [0, 1, 1, 0],
	[0, -1, 1, 0],  [-1, 0, 0, 1],
	[-1, 0, 0, -1], [0, -1, -1, 0],
	[0, 1, -1, 0],  [1, 0, 0, -1],
]

# 单个八分仪的递归扫描（recursive shadowcasting）。
# row=当前行号；start/end=本段光锥的斜率区间（start<end 时区间为空，直接返回）。
func _cast_light(origin: Vector2i, row: int, start: float, end: float,
		radius: int, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var radius_sq := radius * radius
	var new_start := start
	var blocked := false
	for j in range(row, radius + 1):
		var dy := -j
		var dx := -j - 1
		blocked = false
		while dx <= 0:
			dx += 1
			# 该格左右边缘的斜率
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue   # 整格在光锥右侧之外
			if end > l_slope:
				break      # 已越过光锥左侧
			# 变换到地图坐标
			var mx: int = origin.x + dx * xx + dy * xy
			var my: int = origin.y + dx * yx + dy * yy
			if dx * dx + dy * dy <= radius_sq:
				_set_visible(mx, my)
			if blocked:
				# 正扫过一段被挡的行：仍是墙则延后左边界，否则阴影结束
				if _blocks_sight(mx, my):
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif _blocks_sight(mx, my) and j < radius:
				# 遇到墙：在它背后重启一次子扫描
				blocked = true
				_cast_light(origin, j + 1, start, l_slope, radius, xx, xy, yx, yy)
				new_start = r_slope
		if blocked:
			break

# 是否挡光。判据取 Terrain 的语义标志而非硬编码地形 id——视野因此不必认识地形表，
# 将来加门/窗只需改 Terrain 一处。越界一律视为挡光：光不外泄，边界自然收束。
func _blocks_sight(cell_x: int, cell_y: int) -> bool:
	if cell_x < 0 or cell_x >= LevelManager.MAP_WIDTH or cell_y < 0 or cell_y >= LevelManager.MAP_HEIGHT:
		return true
	return Terrain.has_flag(LevelManager.level.map_data[cell_y][cell_x], Terrain.FLAG_LOS_BLOCKING)

func _set_visible(cell_x: int, cell_y: int) -> void:
	if cell_x < 0 or cell_x >= LevelManager.MAP_WIDTH or cell_y < 0 or cell_y >= LevelManager.MAP_HEIGHT:
		return
	FOV[cell_y][cell_x] = true

# 把一批格子及其周边 radius 格（切比雪夫）纳入自身视野。供灵视这类"临时感知"效果使用：
# 只写 self.FOV；迷雾层与实体可见性都读 FOV，故亮起后会自动跟着更新。
func reveal_around(cells: Array, radius: int) -> void:
	for cell in cells:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				_set_visible(cell.x + dx, cell.y + dy)





# 战斗步骤一：给出攻击。自播攻击动画并结算——动画由角色自管，调用方只需 await 本函数
# （Hero 与 Mob 共用；不再由 Mob.act 在外层重复点播动画/音效）。
# 返回是否命中。敌人死亡由 take_damage → die → destory 自理，此处不重复触发。
func attack(enemy: Char, dmg_multi: float = 1.0, dmg_bonus: float = 0.0, acc_multi: float = 1.0) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return false

	spend(DUR_ATTACK)   # 攻击计时由本函数自负：英雄走场景直驱、怪物走调度器，都无需再记账

	# 朝向目标，自播攻击动画与音效；动画播完再结算（动画由表现层自管，此处只 await）
	if sprite:
		sprite.set_facing(enemy.grid_pos - grid_pos)
		await sprite.play_once("attack")

	# 战斗步骤二：命中检定（含命中修正 acc_multi）
	
	if hit(self, enemy, acc_multi, false):
		var dr: int = enemy.dr_roll()
		var dmg: float = damage_roll() * dmg_multi + dmg_bonus
		
		if has_buff(Weakness):
			dmg *= 0.67
		
		var effective_damage: int = enemy.defenseProc(self, roundi(dmg))
		
		if effective_damage >= 0:
			effective_damage = max(effective_damage-dr, 0)
			
			effective_damage = attackProc(self, effective_damage)
			hit_sound()
			
		enemy.damage(effective_damage, self)
		print(self.name, " 攻击 ", enemy.name, " 造成 ", effective_damage, " 点伤害")
		emit_signal("actor_attacked", self, enemy, effective_damage)
		if sprite: sprite.play_anim(rest_anim)   # 攻完回到静止动画（Hero=idle，Mob=run）
		return true

	else:
		if sprite: sprite.play_anim(rest_anim)   # 未命中也要收回动画
		return false



# 战斗步骤二：命中检定（acc_multi 缩放攻方命中值；magic 预留给法术命中）
func hit(attacker: Char, defender: Char, acc_multi: float, magic: bool) -> bool:
	# 直译 SPD Char.hit 开头：`if (defender instanceof Hero && ((Hero) defender).damageInterrupt) interrupt();`
	# —— 英雄正走在半路时被挨一下，就地停下等玩家决策，而不是埋头走到底。
	# 不写 `defender is Hero`：Char 静态引用子类 Hero 会绕成解析环（同 Mob.gd:37）。
	# 故 damage_interrupt / interrupt() 这对钩子开在基类上，非英雄那侧恒为假、空实现。

	# 战斗步骤三：预修正
	var acu_stat: float = attacker.get_attack_skill(defender)
	var def_stat: float = defender.get_defense_skill(attacker)
	
	var acu_roll: float = randf_range(0, acu_stat)
	var def_roll: float = randf_range(0, def_stat)
	
	print(acu_stat, "-", acu_roll, "  ", def_stat, "-", def_roll)
	
	if (acu_roll >= def_roll):
		#hitMissIcon = FloatingText.getHitReasonIcon(attacker, acuRoll, defender, defRoll);
		return true;
	else:
		#hitMissIcon = FloatingText.getMissReasonIcon(attacker, acuRoll, defender, defRoll);
		return false;
	
func get_attack_skill(target: Char) -> int:
	return 0
	
func get_defense_skill(target: Char) -> int:
	return 0
	
func dr_roll() -> int:
	var dr: int = 0
	return dr

func damage_roll() -> int:
	return 1

# 战斗步骤六：攻方修正
func attackProc(enemy: Char, damage: int) -> int:
	return damage

# 战斗步骤四：守方修正
func defenseProc(enemy: Char, damage: int) -> int:
	return damage

func speed() -> float:
	var speed: float = base_speed
	if get_buff(Haste) != null: speed *= 3.0
	return speed
	
# 战斗步骤七：承受伤害	
func damage(dmg: int, src = null) -> void:
	if !is_alive() or dmg<0:
		return
	
	var damage = dmg
	
	var t: Terror = get_buff(Terror)
	if t != null:
		t.recover()
	if (self.has_buff(MagicalSleep)):
		self.get_buff(MagicalSleep).detach()
	
	dmg = roundi(damage)
	
	var shielded: int = dmg
	
	shielded -= dmg
	hp -= dmg
	
	if hp < 0:
		hp = 0
	# 受击自反应（非致死一击；致死那下交给 destory 播 die，避免动画重叠）
	if not is_alive():
		die( src )
	elif 1:
		pass
	
# ---------- 死亡：自播 die 并自理清理 ----------
# 整合了原 start_dying/_on_death_started/_on_death_finished：
#   怪物 → 动画前移出行动列表，动画后移除自身；
#   英雄 → 动画前锁操作（游戏结束），动画后保留在原地。
var _dying := false

func destory():
	if _dying:
		return
	_dying = true
	hp = 0
	if is_monster:
		TurnManager.unregister_actor(self)   # 立刻移出行动列表，避免死亡动画期间再被调度
	else:
		var gs = game_scene
		if gs and gs.has_method("set_hero_dead"):
			gs.set_hero_dead()
	if sprite != null:
		await sprite.play_die()
		if is_monster:
			sprite.queue_free()   # 怪物移除；英雄保留在原地

func die( src = null ):
	destory()
	print(self.name, "因", src.name, "而死")
	
var death_marked: bool = false

func is_alive() -> bool:
	return hp>0 or death_marked
	
func is_active() -> bool:
	return is_alive()
	
# 键 = buff 的脚本类型，故同类至多一个（重挂不叠加）；值 = 实例，可按类型 O(1) 查询。
# 注意这里只是容器：同类已存在时一律拒绝。要不要续期由 Buff.attach_to 决定——
# 它在调本函数之前就先查了同类，直接把在场那个的到期时刻往后顺延。
func add(buff: Buff) -> bool:
	var key = buff.get_script()
	if buffs.has(key):
		return false   # 同类已存在：拒绝插入（续期逻辑在 Buff.attach_to）
	buffs[key] = buff
	return true

func remove(buff: Buff) -> bool:
	var key = buff.get_script()
	if buffs.get(key) != buff:
		return false   # 不是当前挂着的那件（已被换掉或从未挂上）
	buffs.erase(key)   # 必须 erase：留 false 占位会让字典只增不减，遍历时结算到已脱落的 buff
	return true

func has_buff(key) -> bool:
	return buffs.has(key)

func get_buff(key) -> Buff:
	return buffs.get(key)

# 供调度器收集：所有挂在身上的 buff（值即实例）
func all_buffs() -> Array:
	return buffs.values()

# ---------- 存档 ----------
# 角色共同的持久状态都收在这里，Hero / Mob 各 super() 一次再补自己的部分。
# 不存的：Actor.time（时间轴，读档一律归零，玩家先动）、sprite / game_scene（表现，场景重建）、
# FOV（每回合重算）、rest_anim / is_monster（按类固定，_init 里定）。
# alignment 存 int（枚举）：怪物是 ENEMY=0，动森等非敌对角色的阵营也靠它区分。
func serialize() -> Dictionary:
	return {
		# Vector2i 进不了 JSON：拆成 [x, y]，读回来再拼。
		"grid_pos": [grid_pos.x, grid_pos.y],
		"max_hp": max_hp,
		"hp": hp,
		"base_speed": base_speed,
		"paralysed": paralysed,
		"rooted": rooted,
		"flying": flying,
		"invisible": invisible,
		"alignment": alignment,
		"view_distance": view_distance,
		"buffs": _serialize_buffs(),
	}

func deserialize(data: Dictionary) -> void:
	var gp = data.get("grid_pos", null)
	if gp != null:
		grid_pos = Vector2i(int(gp[0]), int(gp[1]))
	# 逐项 int()/float() 归一：JSON 数字读回来一律是 float。带默认值退回当前值，防旧档缺字段。
	max_hp = int(data.get("max_hp", max_hp))
	hp = int(data.get("hp", hp))
	base_speed = float(data.get("base_speed", base_speed))
	paralysed = int(data.get("paralysed", 0))
	rooted = bool(data.get("rooted", false))
	flying = bool(data.get("flying", false))
	invisible = int(data.get("invisible", 0))
	# alignment 是未注解的枚举，可能是 null：只在存档里确有其值时才覆盖，别把 null 当 0 收成 ENEMY。
	var al = data.get("alignment", null)
	if al != null:
		alignment = int(al)
	view_distance = int(data.get("view_distance", view_distance))

	# buff 先清空再挂：复用实例时不至于把上一次的 buff 留着叠加。
	# 必须最后做——from_data 以当前 Actor.now 为锚（读档时时钟已由 GameState._reset_run 归零）。
	buffs.clear()
	for bd in data.get("buffs", []):
		Buff.from_data(self, bd)

func _serialize_buffs() -> Array:
	var out := []
	for b in all_buffs():
		out.append(b.serialize())
	return out

# 时间轴归零（换层等场合：让玩家先动）。
# buff 必须同步减去同一个量，而不是各自归零：buff 的 time 兼作到期时刻
# （attach 时锚定在宿主时间轴上再叠加时长），归零等于把剩余时长一并抹掉，灵视这类
# 限时 buff 会当场到期。减去 elapsed 只是平移坐标原点，剩余时长原样保留。
# 全局 now 也得跟着归零：cooldown 是 time - now，只把本 actor 搬到 0 而 now 留着旧值，
# 换层瞬间 buff 栏会显示成负的（原版换层时 Actor.clear() 正是把 now 置 0，这里照办；
# 顺带使"now == 0 表示刚载入新层"这个原版哨兵（Hero.java 里用来补处理搜索类 buff）重新成立）。
func reset_timeline() -> void:
	var elapsed: float = time
	time = 0.0
	Actor.now = 0.0
	for buff in all_buffs():
		buff.time -= elapsed

# 把本角色连同身上 buff 整体平移到以 now 为原点。直译 SPD Actor.clearTime：
#   spendConstant(-Actor.now()); for (Buff b : buffs()) b.spendConstant(-Actor.now());
# 与 reset_timeline 的区别只在平移量（原版按 now，本函数；换层那处按自身 time，为了落到 0）。
# 原版把它放在 Actor 上（那边用 instanceof Char 分支处理 buff），本工程下沉到 Char：
# Actor 若静态引用 Char，会与 Char extends Actor 构成解析环（同 Buff.gd 顶部那条注释）。
func clear_time() -> void:
	spend_constant(-Actor.now)
	for buff in all_buffs():
		buff.spend_constant(-Actor.now)

func spend(time: float) -> void:
	var time_scale: float = 1.0
	
	super.spend(time / time_scale)


# 打断当前动作的钩子（原版 Hero.interrupt）。空实现开在基类：Char.hit 要调它，
# 而那里不能把 defender 静态判成 Hero（成环）。非英雄没有"待办动作"可打断，空实现即正确。
# 真正的实现见 Hero.interrupt。
func interrupt() -> void:
	pass

# 物品动作收尾（InventoryUI 在 `await item.execute(...)` 之后调）。
# 原版对应物是"动画播完后 sprite 回调 actor.next()"：那边 readAnimation() 里
# curUser.spend(TIME_TO_READ); curUser.busy(); sprite.read(); 播完才由 sprite 放锁。
# 本工程没有 busy/sprite 回调这一层，spend 已由物品自己记（见 Item.gd 顶部注释），
# 故这里只剩两件事：放锁（next）+ 唤醒调度器（process）——等价于 sprite 播完那一下。
# 锁在 process() 停产时留在英雄身上（英雄空闲正是持锁态），故 next() 必然命中。

func on_attack_complete():
	next()
	
func on_operate_complete():
	next()

func resist(effect) -> float:
	var result: float = 1.0
	
	#元素之戒
	return result
	
