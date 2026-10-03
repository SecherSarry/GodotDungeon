extends Char
class_name Hero

const MAX_LEVEL = 30
const STARTING_STR = 10

const TIME_TO_REST = 1
const TIME_TO_SEARCH = 2
const HUNGER_FOR_SEARCH = 6

var heroClass: HeroClass = HeroClass.WARRIOR

# 天赋树（原版 Hero.talents：ArrayList<LinkedHashMap<Talent, Integer>>）。
# 外层下标 = 层号 - 1，内层 {天赋ID: 已投点数}。结构由 Talent.init_class_talents 按职业建。
# 初值空数组：真正的树在 init() 里建（那儿才拿到 heroClass）。
var talents: Array = []


# ---------- 动作分派（直译 SPD Hero.java 的 curAction / ready / path 三件套） ----------
# 输入路径只负责造一个 HeroAction 塞进 cur_action 再放锁（hero.next()），动作本身由 act() 分派。
# 于是"英雄在忙什么"是角色自己的状态，GameScene 不再需要 _auto_walk_loop 那套外挂状态机。



# get_closer 的路径缓存（原版 Hero.path）。缓存的是"从当前位置起的剩余步"，故 path[0] 即下一步。
# 不缓存也能走，但每步都全图 BFS 一次；缓存后只在路径失效时重算（失效条件见 get_closer）。
var path: Array = []



var attack_skill: int = 10
var defense_skill: int = 5

# 输入门闩（原版 Hero.ready）。true = 空闲待输入；act() 分派动作前会置假。
# 门闩一关，GameScene 的 is_player_turn 就挡住点击与方向键——所以"行走途中改道"是没有的
# （原版 cellSelector.enable(Dungeon.hero.ready) 同理）。
#
# 名字偏离：原版字段就叫 ready，但 Node 自带 ready 信号，同名不敢赌（同 Node.name 那个坑，
# 见 Mob.gd:37 / Buff.gd 顶部），故加 is_ 前缀，方法相应叫 enter_ready / set_busy。
var is_ready: bool = false
# 受击是否打断当前动作（原版 Hero.damageInterrupt）。只有英雄用得上，但字段开在基类：
# Char.hit 要按它决定调不调 interrupt()，而 base 上得有这个名字才能静态编译通过——见 interrupt() 处。
var damage_interrupt: bool = true

# 当前待办动作（原版 Hero.curAction）。null = 无动作，即空闲或休息。
# 不注解 HeroAction：本类静态引用 HeroAction，而 HeroAction.Attack 又持有角色，注解会绕成环
# （同 Mob.gd:37）。本就是鸭子类型，无需静态类型。
var cur_action = null

var last_action = null

var attack_target: Char

var resting: bool = false

var belongings: Belongings

var str = 10

var lvl = 1
var exp = 0

var max_hp_boost = 0

# 随身物容器（SPD Belongings）：背包与六槽都归 belongings 管；weapon/armor/… 只是转发到对应槽，
# 各处仍读 hero.weapon，不必改写成 hero.belongings.weapon。
var backpack: Belongings.Backpack:
	get:
		return belongings.backpack
var weapon: KindOfWeapon:
	get:
		return belongings.weapon
	set(value):
		belongings.weapon = value

var armor: Armor:
	get:
		return belongings.armor
	set(value):
		belongings.armor = value

var artifact: Artifact:
	get:
		return belongings.artifact
	set(value):
		belongings.artifact = value

var misc: KindOfMisc:
	get:
		return belongings.misc
	set(value):
		belongings.misc = value

var ring: Ring:
	get:
		return belongings.ring
	set(value):
		belongings.ring = value
		
var second_wep: KindOfWeapon:
	get:
		return belongings.second_wep
	set(value):
		belongings.second_wep = value

# SPD Belongings 由 Hero 构造器持有（Belongings(Hero owner)）；本工程 Hero 是 Resource，对应地在 _init 里 new。
# 放 _init 而非 init()：读档路径不跑 init() 就直接 deserialize，GameState._reset_run 也会在 init() 前访问
# hero.backpack——belongings 必须从构造起就非空。super() 必调：Char._init 赋 act_priority（见 Char.gd:30）。
func _init() -> void:
	super()
	belongings = Belongings.new()

# 无 _ready：Hero 已是数据（Resource），不再有节点生命周期。
# init() 由 GameScene.render_hero 在摆好表现节点后显式调用；
# 入队注册改走 TurnManager.register_hero（原 add_to_group("hero")）。
func init():
	alignment = Alignment.ALLY
	max_hp = 20
	hp = 20
	str = STARTING_STR

	live()

	# 天赋树：按职业建结构，点数全 0（原版 HeroClass.initHero 里的 Talent.initClassTalents(this)）。
	# 曾经这里写的是 `talents[HEARTY_MEAL] = Talent.DATA.get(HEARTY_MEAL)`——那是把**元数据**
	# （{title, max_points, desc}）当成点数值塞进了平字典，既不是原版语义（原版存 0，
	# 点数由升级累加），也让 talents 的结构和 Talent.init_class_talents 对不上。
	talents = Talent.init_class_talents(heroClass)

	# 职业初始化交回职业对象自己（原版 Hero.initHero 里也是 hero.heroClass.initHero(hero)）。
	# 必须晚于上面那行开槽：init_hero 会往 belongings 里塞初始武器/护甲，早于开槽会被整片冲掉。
	heroClass.init_hero(self)

	print(talents)
	
func update_maxHP(boost_hp: bool):
	var cur_max_hp = max_hp
	max_hp = 20 + 5*(lvl-1)
	if boost_hp:
		hp += 	max(max_hp - cur_max_hp, 0)
	hp = min(hp, max_hp)

func get_str():
	var str_bouns: int = 0
	
	return str + str_bouns

func live():
	for b: Buff in buffs:
		if(!b.revive_persists): b.detach()
	Buff.affect(self, Regeneration)
	Buff.affect(self, Hunger)
	
# 移动到相邻格：同步即时提交 grid 并启动自滑，立即返回成功与否（动画由自身 _process 收尾）
func move_step(target: Vector2i) -> bool:
	var from = grid_pos
	var ok = walk_to(target)
	if ok:
		spend(1/speed())
		# 玩家走过门后随手带上。上锁门那一步只解锁、不挪窝（grid_pos 没变），那时不算"走过"，不关。
		if grid_pos != from:
			var gs = game_scene
			if gs != null:
				gs.close_door_behind(from)
	return ok

func dr_roll() -> int:
	if armor == null:
		return 0   # 无甲：不减伤
	return randi_range(armor.dr_min(), armor.dr_max())
	
func damage_roll() -> int:
	if weapon == null:
		return randi_range(1, 5)   # 空手：1-5
	return randi_range(weapon.min(), weapon.max())

# 攻击触及距离：空手为 1
func reach() -> int:
	return weapon.RCH if weapon != null else 1

func speed() -> float:
	var speed: float = super()
	if armor != null:
		speed = armor.speed_factor(self, speed)
	return speed

func can_attack(enemy: Char) -> bool:
	if(enemy == null or grid_pos == enemy.grid_pos):
		return false
	
	var diff = enemy.grid_pos - self.grid_pos
	var dis = max(absi(diff.x), absi(diff.y))
	if dis == 1:
		return true
	return dis <= reach()
	
func damage(dmg: int, src = null):

	# 直译 SPD Hero.damage 的打断入口（Hero.java:1591-1595）：
	#   `if (!(src instanceof Hunger || src instanceof Viscosity.DeferedDamage) && damageInterrupt)
	#        interrupt();`
	# 补这条之前，"被伤害打醒"只有怪物近战那条路（Char.hit，见 Char.gd:372）——
	# 陷阱/燃烧/中毒/法术这类不走命中检定的伤害唤不醒，休息照样进行到底。
	#
	# 为什么豁免 Hunger：挨饿是**按时间滴血**，而休息的全部意义就是花掉时间——
	# 越饿越该打坐，不豁免就是隔几拍被自己打断一次。原版把"跌进挨饿"那个事件单独处理：
	# Hunger.java:100 的 damage 传 src=this，正被这条放过；于是紧接 :102 手写了一句
	# interrupt()。本工程 Hunger 还没移植那段阈值判定（见 Hunger.gd 顶部注释），
	# 所以目前挨饿掉血完全不打断——这是待补的另一半，不是本条遗漏。
	# Viscosity 本工程没有对应物（全树 grep 无结果），故不写它那半个判断。
	if not (src is Hunger) and damage_interrupt:
		interrupt()

	if (self.has_buff(Drowsy)):
		self.get_buff(Drowsy).detach()

	var damage: float = dmg
	dmg = roundi(dmg)

	super.damage(dmg, src)
	
func attack_delay():
	var delay: float = 1.0
	
	return delay/speed()
	
func spend(time: float) -> void:
	super.spend(time)

func spend_and_next(time: float):
	spend(time)
	next()

# 角色类别取 HERO_PRIO（Actor 里的优先级表）：与怪物同刻到点时角色先动。
# 不在此赋 act_priority：Char._init 已经赋好，Hero 无需覆写 _init——覆写反而多一处漏 super() 的机会。

# ---------- 输入门（原版 Hero.ready / Hero.busy） ----------

# 放开输入、清掉待办动作。原版 Hero.ready() 就是这一串：空闲的标准态。
# 动作走不下去时（路径断了、目标没了、格子被占）都回到这里，于是世界停在英雄身上等下一次输入。
func enter_ready() -> void:
	is_ready = true
	cur_action = null
	damage_interrupt = true   # 原版 Hero.ready() 同置（那边只有 resume() 会置回 false，本工程没有 resume）
	path = []                 # 空闲即丢弃缓存路径：下次点别处不必先判失效
	if sprite: sprite.end_continuous_move()   # 会话结束：回静止动画（仍在滑则交 _process 收尾；见 ActorNode.end_continuous_move）

# 占用输入门：本轮有事要做，别收新指令。原版 Hero.busy()。
# 原版还会 sprite.busy()，本工程动画由表现层（ActorNode）自管，故只剩这一件事。
func set_busy() -> void:
	is_ready = false

# 打断当前动作（原版 Hero.interrupt）。由 Char.hit 在挨打时调（见 Char.hit 顶部）。
# 原版这里还把 Move / LvlTransition 存进 lastAction、供 resume() 用；本工程没有 resume 那套
# （界面上的 resumed 标签、GameScene.resetKeyHold 都没有），故不存——省一个没有消费者的字段。
func interrupt() -> void:
	cur_action = null
	path = []
	resting = false
	enter_ready()

# 休息（直译 SPD Hero.rest，Hero.java:1450-1470）。原版三步：
# spendAndNextConstant(TIME_TO_REST) + sprite 提示（本工程无此物，略）+ resting = fullRest，
# 其中 spendAndNextConstant = busy() + spendConstant(time) + next()。此处照抄同一次序。
#
# full_rest=false：点按一下 = **等一拍**。花 TIME_TO_REST、next() 放锁让怪动一轮，
#   回来后 act() 走空闲分支 → enter_ready()，操作交还玩家。不会持续。
# full_rest=true：**一直休息到被打断**。act() 的 resting 分支每拍 spendConstant + next()，
#   于是世界照走、怪照动，英雄原地不动。
#
# 退出休息的路径全在**本函数之外**（原版同样如此，没有 Hero 端的方法）：
#   · 输入层直接写 resting = false —— 原版 CellSelector.java:331（方向键）、
#     :344-345（其它任意键）、GameScene.java:1629-1632（取消键）。本工程在 GameScene 的
#     输入处理里照做；注意这些路径都绕开 is_player_turn，因为休息期间输入门是关的。
#   · 挨打 —— Char.hit 调 interrupt()（原版 Hero.java:956 同）。
#   · 回血 buff 收尾 —— Healing / WellFed 满血或到期时清 resting（原版 Healing.java:57,66 等）。
#
# 别把它和 MagicalSleep 混起来：那边也置 resting，但**强制**，清 resting 醒不过来
# （paralysed 分支排在 resting 之前，Hero.java:854 先于 :863）。本工程没给 MagicalSleep
# 做玩家入口，它只由 Drowsy 施放。
#
# 偏离原版一处，记着：原版用 spendConstant（不吃加速/减速）；本工程 Actor 上只有 spend，
# 而当前 speed() 恒为 1，两者等价，故先用现成的 spend_and_next，等真接上加速/减速再拆开。
func rest(full_rest: bool = false) -> void:
	cur_action = null
	set_busy()
	spend_and_next(TIME_TO_REST)
	resting = full_rest

# 让出一拍。原版这两处的节奏来自渲染线程：SPD 的调度线程每拍 wait()、由渲染线程 notify 唤醒，
# 而唤醒那侧有 notifyDelay = 1/60s 的上限，休息/麻痹因此天然被压到每秒最多 60 拍。
# **这条上限是按秒、不是按帧**：原版 notifyDelay 每帧只减 Game.elapsed（GameScene.java:857），
# 144Hz 屏上照样 60 拍/秒，与帧率无关。
# 本工程没有线程，process() 的循环体之间也不 await——不在这里主动让出，整段休息会在
# **一帧之内**算完：回血过程看不见，怪物还会在同一帧里连动好几拍（画面上像瞬移）。
# 曾用 await get_tree().process_frame 让出，那是"一帧一拍"：帧率多高就多少拍/秒，
# 在 144Hz 屏上休息跑成 2.4 倍速（当时的注释误以为它等价于原版那条 60Hz 上限，只在 60fps 下成立）。
# 现改成一个真时长，与帧率解耦。取 1/30 而非原版的 1/60：**故意比原版慢一倍**，
# 睡觉时看得清回血与怪物走位（原版 60 拍/秒偏快，正是加这一处的原因）。
# 这一让还是"休息可随时退出"的前提：只有在这里把控制权交回引擎，输入才有机会被处理；
# 否则休息循环在一帧内空转到底，玩家点什么都到不了处理函数，rest(true) 就成了死循环。
# 只加这两处：正常行走/攻击不能按拍让出，那会把"英雄与各怪同帧起滑"的并行拆成串行。
func wait_one_tick() -> void:
	# get_tree() 是节点 API、数据层拿不到，故计时转交表现层；时长与语义不变。
	await sprite.wait(1.0 / 30.0)

# ---------- 动作分派（原版 Hero.act 的裁剪版） ----------
# 三步同序：刷视野 → 特殊态（麻痹 / 空闲 / 休息）→ 有动作则分派。
# 分派各分支的收尾契约见其函数注释；总则是"推进了就 return true、推不动就 enter_ready + return false"。
func act() -> bool:
	# 原版 act 开头就是 `fieldOfView = Dungeon.level.heroFOV; Dungeon.observe();`
	# ——每回合开头把视野刷一遍。本工程视野绘制在场景侧，故经 game_scene 调。
	# 行走途中每步都走这里，于是边走边开图（原版同）。
	var gs = game_scene
	if gs != null:
		gs.observe()

	if (paralysed > 0):
		print("[HERO] 麻痹中 paralysed=", paralysed, " HP=", hp, "/", max_hp, " time=", time)
		cur_action = null
		set_busy()   # 原版是 spendAndNext(TICK) = busy() + spend() + next()，三步一个不少
		spend(TICK)
		next()
		await wait_one_tick()   # 一拍 1/30s（见上）
		return false

	if cur_action == null:
		if (resting):
			spend_constant(TIME_TO_REST)
			next()
			await wait_one_tick()   # 一拍 1/30s（见上）
		else:
			enter_ready()   # 空闲：放开输入、不 next() → 调度器见锁还在即停产，世界等玩家
		return false

	resting = false
	set_busy()
	if cur_action is HeroAction.Move:
		return act_move()
	elif cur_action is HeroAction.Attack:
		return await act_attack()
	elif cur_action is HeroAction.PickUp:
		return await act_pick_up()
	elif cur_action is HeroAction.LvlTransition:
		return act_transition()
	else:
		# 未识别的动作类型：当成推不动，交回输入（原版末尾也是 actResult = false）
		enter_ready()
		return false

# 直译 SPD Hero.actMove（Hero.java:979）：
#   能朝目标靠近一步 → true（时长已由 move_step 记好）；靠不动 → ready() + false。
# 原版还有个"站在草上原地踩一脚"的分支（canSelfTrample），本工程没有踩草机制，不移植。
# 注意 Move 成功后**不清 cur_action**：下一拍还走这条，于是一路走到终点（原版同）。
func act_move() -> bool:
	if sprite: sprite.begin_continuous_move()   # 走整段期间不回 idle，跑步动画才连得上
	if get_closer(cur_action.dst):
		return true
	enter_ready()
	return false

# 直译 SPD Hero.actAttack（Hero.java:1409）。
# 打得着 → 交给 Char.attack（它自己 await 完动画、记好 DUR_ATTACK），完事清动作交回输入；
# 够不着 → 先走近（原版同：`getCloser(attackTarget.pos)`），够不着又走不动才 ready()。
# 于是"点远处的怪"= 一路追击的攻击动作，GameScene 那套 _walk_monster 追击循环不必存在。
func act_attack() -> bool:
	var target = cur_action.target
	if not is_instance_valid(target) or not target.is_alive():
		enter_ready()
		return false
	if not can_attack(target):
		if MapManager.is_explored(target.grid_pos) and get_closer(target.grid_pos):
			return true   # 走上一步，下一拍再判
		enter_ready()
		return false
	await attack(target)
	cur_action = null   # 原版在 onAttackComplete 里清（那边是动画回调，本工程 attack 返回即已播完）
	return true

# 直译 SPD Hero.actPickUp（Hero.java:1105）。
# 站到目标格上 → 交给场景拾取（GameScene.try_collect 内部走 Item.do_pickup，时长已由物品记账）；
# 还没到 → 走近；走不动 → ready()。
func act_pick_up() -> bool:
	if grid_pos == cur_action.dst:
		var gs = game_scene
		if gs != null and gs.try_collect(self):
			cur_action = null
			return true   # spend 已由 Item.do_pickup 记好（见 Item.gd 顶部注释）
		enter_ready()
		return false
	if MapManager.is_explored(cur_action.dst) and get_closer(cur_action.dst):
		return true
	enter_ready()
	return false

# 直译 SPD Hero.actTransition（Hero.java:1380）。
# 站到出入口上 → 取该格的 transition，交场景激活换层并交回输入（原版 activateTransition 之后也是
# curAction = null + false）；还没到 → 走近。于是"点远处的楼梯"一次点击就能走到并下楼，不必点到格子上再点一次。
func act_transition() -> bool:
	var transition = LevelManager.level.get_transition_at(grid_pos)
	if grid_pos == cur_action.dst and transition != null:
		cur_action = null
		var gs = game_scene
		if gs != null:
			gs.activate_transition(transition)
		# 换成功、以及"已在地牢顶层没得换"两种情形都回到空闲，等下一次输入。
		# 不能省：分派前 set_busy() 关掉了输入门，不在这里开回来，新层就再也点不动了。
		enter_ready()
		return false   # 换层后世界停产（锁留在身上），等新层里的第一次输入
	if MapManager.is_explored(cur_action.dst) and get_closer(cur_action.dst):
		return true
	enter_ready()
	return false

# ---------- 点击 → 待办动作（原版 Hero.handle 的裁剪版） ----------
# 只看这一格里有什么，造出对应的 HeroAction；动作怎么执行不关这里的事。
# 原版还有一堆分支（Alchemy / Mine / Buy / OpenChest / Interact / Unlock、以及"怪附近不自动拾取"），
# 本工程没有对应机制，略；上锁门由 Char.walk_to 内联解锁，故也走 Move。
# 返回 false 表示这一格无动作可造（调用方据此不推回合）。
func handle(cell: Vector2i) -> bool:
	if not MapManager.is_walk_target(cell):
		return false

	var ch = TurnManager.get_monster_at(cell)
	if ch != null and ch.is_alive() and MapManager.is_explored(cell):
		# 原版这里用 fieldOfView（此刻可见）判怪；本工程用已探索——与现有输入门一致，
		# 免得记忆中的怪因一时离开视野就点不动。
		var a = HeroAction.Attack.new()
		a.target = ch
		cur_action = a
		return true

	var gs = game_scene
	if gs != null and gs.is_item_on_cell(cell):
		var a = HeroAction.PickUp.new()
		a.dst = cell
		cur_action = a
		return true

	if LevelManager.level.get_transition_at(cell) != null:
		var a = HeroAction.LvlTransition.new()
		a.dst = cell
		cur_action = a
		return true

	var a = HeroAction.Move.new()
	a.dst = cell
	cur_action = a
	return true

# ---------- 朝目标走一步（原版 Hero.getCloser） ----------
# 返回是否真的挪了窝/花了这一拍。调用方（act_move / act_attack / act_pick_up / act_transition）
# 见 true 就继续跑，见 false 就 ready() 交回输入。
#
# 正交相邻：直接走那格。放行上锁门——本工程把解锁内联在 Char.walk_to 里（原版是单独的
# HeroAction.Unlock，那边 passable[locked]=false 所以会停住等玩家再点一次）。
# 不相邻：查缓存 path，失效则用 Pathfinding.find 重建。
func get_closer(target: Vector2i) -> bool:
	if target == grid_pos:
		return false

	# 终点自挡：本工程的 Pathfinding 会把终点无条件种入距离图（见 Char.next_step_to 的注释），
	# 墙也算得出路来——不挡的话"点远处那面墙"会变成"走过去贴着站"。原版靠
	# Dungeon.findPath 对不可走终点返回 null 达到同样效果，这里得自己挡。
	# 放行上锁门：那一步在 walk_to 里内联解锁（见下）。
	if not MapManager.is_walkable(target) and not MapManager.is_locked_door(target):
		return false

	var step := Vector2i(-1, -1)
	var diff = target - grid_pos
	if max(absi(diff.x), absi(diff.y)) == 1:
		path = []
		if not MapManager.is_occupied(target, self) \
				and (MapManager.is_walkable(target) or MapManager.is_locked_door(target)):
			step = target
	else:
		# 缓存失效的四条（原版同序）：
		#   1. 空；2. 首步已不再与当前位置相邻（走岔了）；3. 末步不是目标（目标换了）；
		#   4. 首步已不可走或被占（路被堵/被怪占）。
		var new_path := false
		if path.is_empty():
			new_path = true
		else:
			var head: Vector2i = path[0]
			var d = head - grid_pos
			if max(absi(d.x), absi(d.y)) != 1:
				new_path = true
			elif path[-1] != target:
				new_path = true
			elif not MapManager.is_walkable(head) or MapManager.is_occupied(head, self):
				new_path = true
		if new_path:
			# 只走已探索格（玩家自动行走）。
			var passable := MapManager.build_passable(self, true)
			var fresh := _path_cells(target, passable)
			# 原版的迂回判据：新路比旧路长一倍以上，说明局面变复杂了，宁可停下重来
			# （丢弃缓存后下面 path 为空 → 返回 false → ready()，等玩家重新发令）。
			if not fresh.is_empty() and not path.is_empty() and fresh.size() > 2 * path.size():
				path = []
			else:
				path = fresh
		if path.is_empty():
			return false
		step = path.pop_front()

	if step == Vector2i(-1, -1):
		return false
	return move_step(step)

# 求到 target 的路，返回**格**序列（第一步在最前、终点在最后）→ path[0] 即下一步。
# 只做索引→格这一道转换：Pathfinding 全线走格索引（find 收索引、返回 Array[int]），这里要 Vector2i。
# 一格都不能丢：find 的返回**不含起点、含终点**——Pathfinding.gd:68-80 是先 `s = mins`（挪到邻居）
# 再 `result.append(s)`，所以 result[0] 已经是第一步，from 根本不在里面。
# 原版 PathFinder.find 同样如此（PathFinder.java:102-103），那边的 path.removeFirst() 取到的也正是第一步。
# 曾经在这里多丢了一格（按"含起点"写 range(1,...)），于是每次重建路径后的第一跳都跨两格，
# 看着就是"一次走两格、开头偏快"——那一跳走的是同一个 MOVE_DURATION。
func _path_cells(target: Vector2i, passable: PackedByteArray) -> Array:
	var idx_path := Pathfinding.find(MapManager.to_index(grid_pos), MapManager.to_index(target), passable)
	var cells: Array = []
	for idx in idx_path:
		cells.append(MapManager.to_cell(idx))
	return cells


func max_exp(lvl: int = self.lvl):
	return 5 + lvl * 5
	
func is_starving():
	return Buff.affect(self, Hunger).is_starving()
	
func earn_exp(exp: int, source):
	self.exp += exp
	while (self.exp >= max_exp()):
		self.exp -= max_exp();
		var levelUp = up_level();
	pass

func up_level(level: int = 1):
	self.lvl += level
	
	update_maxHP(true)
	attack_skill += level
	defense_skill += level
	pass
	

# ---------- 天赋（直译 SPD Hero.java:357-409） ----------
# 设计要点：**没有"获得天赋点"这一步**。点数不存储，由 talent_points_available 按当前 lvl
# 现算，再减去已投点数即为余额。于是升级不必发点（up_level 一个字都不用改），
# 洗点 / 读档也不会错账。这是原版的设计，别改成"升级时 talents[x] += 1"那种记账式。

# 原版 Hero.hasTalent：投过点就算拥有。
func has_talent(talent) -> bool:
	return points_in_talent(talent) > 0

# 原版 Hero.pointsInTalent：逐层扫。找不到返回 0 而不是报错——原版正是靠这个 0
# 兜住"该职业树里没有这个天赋"的情况（比如将来读档读到别的职业的天赋），别改成 assert。
func points_in_talent(talent) -> int:
	for tier in talents:
		if tier.has(talent):
			return tier[talent]
	return 0

# 原版 Hero.upgradeTalent：给该天赋 +1。
# 原版随后还调 Talent.onTalentUpgraded(hero, talent)——那是"升级瞬间的副作用"的落点
# （老兵直觉到 +2 时立刻鉴定手上的武器之类，Talent.java:497-580）。本工程一个天赋效果都还没接，
# 故先不调；等接效果时一并补上，那个钩子是所有特例的唯一落点，别忘。
func upgrade_talent(talent) -> void:
	for tier in talents:
		if tier.has(talent):
			tier[talent] += 1

# 原版 Hero.talentPointsSpent(tier)：该层已投点数之和。tier 是 **1 起**的层号。
func talent_points_spent(tier: int) -> int:
	var total: int = 0
	for points in talents[tier - 1].values():
		total += points
	return total

# 原版 Hero.talentPointsAvailable(tier)：本层还能投几点。
# **这是唯一的准入闸门**——够不够级、有没有资格，全由这一个返回值表达；升级与 UI 都只问它，
# 不要另写"能不能投"的判断散在别处。
#
# 原版这个 return 0 里还压着两条资格判据：
#     (tier == 3 && subClass == HeroSubClass.NONE) || (tier == 4 && armorAbility == null)
# 本工程 subClass 与 armorAbility 都还不存在，语义等价于"永远未选"，故用下面这条替身守住
# 同样的行为：T3/T4 暂不可投。等子职业 / 护甲技能落地，把它换回原版那两句即可
# （注意换回来时是两条并列，不是现在这一条 tier >= 3）。
func talent_points_available(tier: int) -> int:
	if tier >= 3:
		return 0
	if lvl < (Talent.TIER_LEVEL_THRESHOLDS[tier] - 1):
		return 0
	elif lvl >= Talent.TIER_LEVEL_THRESHOLDS[tier + 1]:
		# 已到本层封顶：本层预算 = 下一层门槛 - 本层门槛
		return Talent.TIER_LEVEL_THRESHOLDS[tier + 1] - Talent.TIER_LEVEL_THRESHOLDS[tier] - talent_points_spent(tier) + bonus_talent_points(tier)
	else:
		# 还在爬：每升一级给一点 = 1 + (lvl - 本层门槛) - 已投
		return 1 + lvl - Talent.TIER_LEVEL_THRESHOLDS[tier] - talent_points_spent(tier) + bonus_talent_points(tier)

# 原版 Hero.bonusTalentPoints(tier)：神圣启示药水给的额外点（原版 :399-410）。
# 本工程没有那瓶药水，也没有 T3/T4 的资格判据，故恒为 0。
# 留着是因为 talent_points_available 的两条分支都加它——删掉这层就等于把原版的结构改了，
# 以后加药水时还得再拆一次。这是原版的方法，不是本工程新造的抽象。
func bonus_talent_points(tier: int) -> int:
	return 0

func get_attack_skill(target: Char) -> int:
	return attack_skill

func get_defense_skill(target: Char) -> int:
	var evasion = defense_skill
	if paralysed > 0:
		evasion /= 2
	return max(1, roundi(evasion))

# 直译 SPD Hero.onAttackComplete（Hero.java:2310-2340）。
# 原版这是攻击的**第二段**：actAttack 只把目标存进 attackTarget、起播动画就 return false 停产，
# 动画播完由 sprite 回调到本函数，这里才真正 attack() + spend + 放锁。
#
# 注意本函数**目前没有调用点**，也先别急着接。本工程的 Char.attack 把原版那两段压成了一条
# await（Char.gd:330-335 的 animation_finished 就是原版 sprite 回调的位置），动画、伤害、计时
# 全在里面办完；调用方（Hero.act_attack / Mob.Hunting）拿到的已经是结果，直接 return true 走
# act() 契约的重挑分支。所以这里的活儿在原版是必需的，在这里是空的——
# 与 Char.on_attack_complete 一样先留着占位，等攻击拆回两段时再用（那时 act_attack 要改成
# "存 attack_target + 起播动画 + return false"，本函数才活）。
#
# 逐句对照，被略去的都在原版有对应物、本工程无：
#   AttackIndicator.target —— 本工程无攻击指示器。
#   wasEnemy —— 只喂下面两个职业分支，本工程无子职业，故连带不取。
#   spend(attackDelay()) —— **不是遗漏**：本工程 Char.attack 内部已 spend(DUR_ATTACK)
#     （Char.gd:326），这里再记一次会把一次攻击算成两回合。
#   Combo / Sai.ComboStrikeTracker —— 角斗士连击、决斗家 Sai 计次，本工程两个职业都没有。
# 因此原版那句 `boolean hit = attack(attackTarget)` 的返回值本工程无人消费，不绑定。
# Invisibility.dispel() 本工程有（Invisibility.gd:23），保留；原版是无参版（内部取 Dungeon.hero），
# 这里显式传 self —— 同一个对象，且绕开该函数那个空参判据写反的 bug（见该文件）。
func on_attack_complete() -> void:
	if attack_target == null:
		cur_action = null
		super.on_attack_complete()
		return

	await attack(attack_target)

	Invisibility.dispel(self)

	cur_action = null
	attack_target = null

	super.on_attack_complete()

func on_operate_complete():
	await super.on_operate_complete()

func next():
	if (is_alive()):
		super.next()

# 只在英雄自己的字段上工作：Char 层的（血量/位置/状态/buff…）由 super.serialize 带上。
func serialize() -> Dictionary:
	var data = super.serialize()
	data["max_hp_boost"] = max_hp_boost
	data["str"] = str
	data["lvl"] = lvl
	data["exp"] = exp
	data["attack_skill"] = attack_skill
	data["defense_skill"] = defense_skill
	# 职业只存名字，读档查回单例（HeroClass.save_key / from_key）——不存整个对象。
	data["hero_class"] = heroClass.save_key()
	data["belongings"] = belongings.serialize()
	data["talents"] = talents
	return data

func deserialize(data: Dictionary):
	super.deserialize(data)   # Char 层：血量 / 位置 / 状态 / 阵营 / buff
	# JSON 数字读回来一律是 float，而下列字段全线按 int 用（等级、技能、点数…），故逐项 int() 归一。
	# 都带默认值：读到缺字段的旧档时退回字段的初始值，而不是被 int(null)=0 清零。
	max_hp_boost = int(data.get("max_hp_boost", 0))
	str = int(data.get("str", STARTING_STR))
	lvl = int(data.get("lvl", 1))
	exp = int(data.get("exp", 0))
	attack_skill = int(data.get("attack_skill", 10))
	defense_skill = int(data.get("defense_skill", 5))

	heroClass = HeroClass.from_key(data.get("hero_class", "WARRIOR"))

	# 背包与六槽整份还原（Hero._init 已保证 belongings 非空）。
	belongings.deserialize(data.get("belongings", {}))

	# JSON 的对象键只能是字符串，写出去时内层 int 键（Talent.ID）全变成了 "0" "1"…
	# 读回来必须转回 int，否则 has_talent / points_in_talent / upgrade_talent 用 int 查恒落空。
	# 值同理：JSON 数字读回来是 float，而点数全线按 int 用（talent_points_spent 累加、
	# upgrade_talent 自增、format "%d" 显示），故一并 int() 归一。
	talents = []
	for tier in data.get("talents", []):
		var t := {}
		for k in tier:
			t[int(k)] = int(tier[k])
		talents.append(t)
