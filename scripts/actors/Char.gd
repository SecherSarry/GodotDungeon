extends Actor
class_name Char

var grid_pos: Vector2i = Vector2i.ZERO

var maxHP: int = 10
var HP: int = 10

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

func name() -> String:
	return " "

func can_interact(c: Char):
	return true

func hit_sound():
	AudioManager.play_sound(preload("res://assets/sounds/hit.mp3"), -5, randf_range(0.9, 1.1))

const MOVE_DURATION = 0.1   # 单格滑动时长（秒），由角色自驱逐帧插值推进

# base_speed / next_action_time / spend / act / DUR_* 已上移到 Actor：
# Buff 与角色共用同一套调度刻度，故这些必须落在共同基类上。


# 自滑状态：移动时逻辑即时提交 grid，视觉在此处用 _process 逐帧推进
var _sliding := false
var _from_pos := Vector2.ZERO
var _to_pos := Vector2.ZERO
var _slide_t := 0.0

# 正在播一次性动画（attack/die，非循环、有人 await 它的 animation_finished）。
# 置位期间 _process 的滑行收尾不得用静止动画覆盖：否则"移动中起手攻击"会被
# 滑完那一帧切走，被切走的非循环动画不再发 animation_finished，await 永挂 → 回合锁死。
var _busy := false

# 连续移动会话：为真时滑步结束不回静止动画。多步行走（自动寻路等）由驱动方开启，
# 使跑步动画跨步连贯播放，而非每步 idle→run 从头重播。
var keep_moving_anim: bool = false


var game_scene: Node = null

@onready var anim_sprite = get_sprite()

func get_sprite():
	for child in get_children():
		if child is AnimatedSprite2D:
			return child
	return null

func set_facing(direction: Vector2i):
	if anim_sprite:
		if direction.x < 0:
			anim_sprite.flip_h = true
		elif direction.x > 0:
			anim_sprite.flip_h = false

# 角色"静止(站立)"动画：滑完/攻击结束后回到它。Hero 与 Mob 都是 idle
var rest_anim := "idle"

# ---------- 统一动画入口：所有动画播放都走这里 ----------
# 规则：
#  1. 该动画正在播放 → 不重播（连续移动时跑步动画不会每步从第 0 帧重新开始）
#  2. 连续移动会话中（keep_moving_anim）→ 静止动画不打断当前行走动画
#  3. 该动画不存在 → 忽略
func play_anim(anim_name: String) -> void:
	if anim_sprite == null or not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if keep_moving_anim and anim_name == rest_anim:
		return
	if anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	anim_sprite.play(anim_name)

# 攻击结算信号：攻击方发出，携带受害者与伤害（供 UI/音效等消费者连接）
signal actor_attacked(attacker, target, damage)

# 受到攻击的简单表现（原地/闪白，当前以 idle 代替）
func on_hit() -> void:
	play_anim("idle")

# ---------- 自滑驱动：仅在滑动时逐帧推进插值；到点回本角色静止动画。多角色各自 _process → 天然并行 ----------
func _process(delta: float) -> void:
	if not _sliding:
		return
	_slide_t += delta
	var t = clamp(_slide_t / MOVE_DURATION, 0.0, 1.0)
	position = _from_pos.lerp(_to_pos, t)
	if t >= 1.0:
		_sliding = false
		if not _busy:
			play_anim(rest_anim)   # 滑完回静止动画；连续移动中的抑制由 play_anim 内部规则处理

# ---------- 移动：逻辑即时提交 grid + 启动自滑，立即返回，不等待动画（并行移动不阻塞回合） ----------
func walk_to(target: Vector2i) -> bool:
	var gs = game_scene
	if gs == null or not MapManager.is_walkable(target) or MapManager.is_occupied(target, self):
		return false
	var delta = target - grid_pos
	set_facing(delta)
	_from_pos = position
	_to_pos = gs.cell_to_world(target)
	grid_pos = target   # 逻辑权威：同帧生效，供占用/视野判定
	_sliding = true
	_slide_t = 0.0
	play_anim("run")
	return true

# 是否正在滑行（供回合编排等待所有并行滑动收尾）
func is_moving() -> bool:
	return _sliding

# 瞬移到某格（换层/传送等）：取消残留滑动并直接摆位，避免插值把角色拽回旧位置
func snap_to(cell: Vector2i) -> void:
	_sliding = false
	grid_pos = cell
	var gs = game_scene
	if gs != null:
		position = gs.cell_to_world(cell)

# ---------- 连续移动会话（供自动行走等驱动方使用） ----------
func begin_continuous_move() -> void:
	keep_moving_anim = true

func end_continuous_move() -> void:
	keep_moving_anim = false
	# 停在原地即刻回静止动画；仍在滑则交给 _process 收尾；正在死亡则不覆盖 die 动画
	if not _sliding and not _dying:
		play_anim(rest_anim)

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
	return Terrain.has_flag(LevelManager.map_data[cell_y][cell_x], Terrain.FLAG_LOS_BLOCKING)

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

	# 朝向目标，自播攻击动画与音效；动画播完再结算
	set_facing(enemy.grid_pos - grid_pos)
	
	_busy = true
	play_anim("attack")
	if anim_sprite and anim_sprite.sprite_frames.has_animation("attack"):
		await anim_sprite.animation_finished
	_busy = false

	# 战斗步骤二：命中检定（含命中修正 acc_multi）
	
	if hit(self, enemy, acc_multi, false):
		var dr: int = enemy.dr_roll()
		var dmg: float = damage_roll() * dmg_multi + dmg_bonus
		
		var effective_damage: int = enemy.defenseProc(self, roundi(dmg))
		
		if effective_damage >= 0:
			effective_damage = max(effective_damage-dr, 0)
			
			effective_damage = attackProc(self, effective_damage)
			hit_sound()
			
		enemy.damage(effective_damage, self)
		print(self.name, " 攻击 ", enemy.name, " 造成 ", effective_damage, " 点伤害")
		emit_signal("actor_attacked", self, enemy, effective_damage)
		play_anim(rest_anim)   # 攻完回到静止动画（Hero=idle，Mob=run）
		return true
			
	else:
		play_anim(rest_anim)   # 未命中也要收回动画
		return false



# 战斗步骤二：命中检定（acc_multi 缩放攻方命中值；magic 预留给法术命中）
func hit(attacker: Char, defender: Char, acc_multi: float, magic: bool) -> bool:
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

# 战斗步骤七：承受伤害	
func damage(dmg: int, src = null):
	if !is_alive() or dmg<0:
		return
	if (self.has_buff(MagicalSleep)):
		self.get_buff(MagicalSleep).detach()
	HP = max(HP - dmg, 0)
	# 受击自反应（非致死一击；致死那下交给 destory 播 die，避免动画重叠）
	if is_alive():
		on_hit()
	else:
		die( src )
	
# ---------- 死亡：自播 die 并自理清理 ----------
# 整合了原 start_dying/_on_death_started/_on_death_finished：
#   怪物 → 动画前移出行动列表，动画后移除自身；
#   英雄 → 动画前锁操作（游戏结束），动画后保留在原地。
var _dying := false

func destory():
	if _dying:
		return
	_dying = true
	HP = 0
	var is_monster := is_in_group("monster")
	if is_monster:
		TurnManager.monsters.erase(self)   # 立刻移出行动列表，避免死亡动画期间再被调度
	else:
		var gs = game_scene
		if gs and gs.has_method("set_hero_dead"):
			gs.set_hero_dead()
	if anim_sprite and anim_sprite.sprite_frames.has_animation("die"):
		_busy = true
		play_anim("die")
		await anim_sprite.animation_finished
	if is_monster:
		queue_free()   # 怪物移除；英雄保留在原地

func die( src = null ):
	destory()
	print(self.name, "因", src.name, "而死")
	
var death_marked: bool = false

func is_alive() -> bool:
	return HP>0 or death_marked
	
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

# 时间轴归零（换层等场合：让玩家先动）。
# buff 必须同步减去同一个量，而不是各自归零：buff 的 next_action_time 兼作到期时刻
# （attach 时锚定在宿主时间轴上再叠加时长），归零等于把剩余时长一并抹掉，灵视这类
# 限时 buff 会当场到期。减去 elapsed 只是平移坐标原点，剩余时长原样保留。
func reset_timeline() -> void:
	var elapsed: float = next_action_time
	next_action_time = 0.0
	for buff in all_buffs():
		buff.next_action_time -= elapsed

func spend(time: float) -> void:
	var time_scale: float = 1.0
	
	super.spend(time / time_scale)

func on_attack_complete():
	next()
	
func on_operate_complete():
	next()
