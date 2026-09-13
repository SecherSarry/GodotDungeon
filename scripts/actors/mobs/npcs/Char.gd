extends Actor
class_name Char

var maxHP: int = 10
var HP: int = 10

var base_speed: float = 1.0

var view_distance = 8

func hit_sound():
	AudioManager.play_sound(preload("res://assets/sounds/hit.mp3"), -5, randf_range(0.9, 1.1))

const MOVE_DURATION = 0.1   # 单格滑动时长（秒），由角色自驱逐帧插值推进

# ---------- 时间轴调度（抽象刻度，非真实秒）----------
# 每个 actor 有 speed 与 next_action_time；一次行动消耗"基础时长/speed"，
# 调度器永远让 next_action_time 最小者先动。刻度只定顺序与频次，不改变单次动画快慢。
const DUR_MOVE   := 1.0   # 移动基础时长
const DUR_ATTACK := 1.0   # 攻击基础时长（暂固定，不接武器 DLY）
const DUR_PICKUP := 1.0   # 拾取基础时长
const DUR_WAIT   := 1.0   # 无法行动时也消耗：保证调度器必然前进，杜绝死循环

var next_action_time: float = 0.0

func spend_time(base: float) -> void:
	next_action_time += base / max(base_speed, 0.001)

var grid_pos: Vector2i = Vector2i.ZERO

# 自滑状态：移动时逻辑即时提交 grid，视觉在此处用 _process 逐帧推进
var _sliding := false
var _from_pos := Vector2.ZERO
var _to_pos := Vector2.ZERO
var _slide_t := 0.0

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

# 角色"静止(站立)"动画：滑完/攻击结束后回到它。Hero 默认 idle；mob 覆写为 run（静止也一直跑）
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

# ---------- 寻路步进（英雄自动行走与怪物 AI 共用） ----------
# 朝 target 计算下一步（8 方向、避障）；无路可走返回 (-1,-1)。
# explored_only=true 只走己知格（玩家）；怪物 AI 传 false。
func next_step_to(target: Vector2i, explored_only: bool = true) -> Vector2i:
	var path = MapManager.find_path(grid_pos, target, self, explored_only)
	if path.is_empty():
		return Vector2i(-1, -1)
	return path[0]

# 朝 target 走一步（计算 + 移动）；成功返回 true
func step_toward(target: Vector2i, explored_only: bool = true) -> bool:
	var step = next_step_to(target, explored_only)
	if step == Vector2i(-1, -1):
		return false
	return walk_to(step)

# 战斗步骤一：给出攻击。自播攻击动画并结算——动画由角色自管，调用方只需 await 本函数
# （Hero 与 Mob 共用；不再由 Mob.act 在外层重复点播动画/音效）。
# 返回是否命中。敌人死亡由 take_damage → die → destory 自理，此处不重复触发。
func attack(enemy: Char, dmg_multi: float = 1.0, dmg_bonus: float = 0.0, acc_multi: float = 1.0) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return false

	spend_time(DUR_ATTACK)   # 攻击计时由本函数自负：英雄走场景直驱、怪物走调度器，都无需再记账

	# 朝向目标，自播攻击动画与音效；动画播完再结算
	set_facing(enemy.grid_pos - grid_pos)
	
	play_anim("attack")
	if anim_sprite and anim_sprite.sprite_frames.has_animation("attack"):
		await anim_sprite.animation_finished

	# 战斗步骤二：命中检定（含命中修正 acc_multi）
	
	if hit(self, enemy, acc_multi, false):
		var dr: int = enemy.dr_roll()
		var dmg: float = damage_roll() * dmg_multi + dmg_bonus
		
		var effective_damage: int = enemy.defenseProc(self, roundi(dmg))
		
		if effective_damage >= 0:
			effective_damage = attackProc(self, effective_damage)
			hit_sound()
			
		enemy.take_damage(effective_damage, self)
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

func damage_roll(actor: Char = self):
	return 1

# 战斗步骤六：攻方修正
func attackProc(enemy: Char, damage: int) -> int:
	return damage

# 战斗步骤四：守方修正
func defenseProc(enemy: Char, damage: int) -> int:
	return damage

# 战斗步骤七：承受伤害	
func take_damage(damage: int, src = null):
	if !is_alive() or damage<0:
		return
	
	HP = max(HP - damage, 0)
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
	
# 返回"本次行动的基础时长"；基类不自动行动，返回 DUR_WAIT 兜底
func act() -> float:
	return DUR_WAIT
