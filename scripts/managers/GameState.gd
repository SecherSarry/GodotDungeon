extends Node

# 一局的编排者，也是存档的真相源。hero 是数据（Resource），表现节点由 GameScene.render_hero 另建。
# 本类只碰数据：清场、建英雄、读档、生成/载入楼层，节点一概不碰（manager 只做纯数据）。
#
# 两个开局入口互斥，由 TitleScene 二选一调用：
#   new_game()      —— 新档：清 → 新英雄 → init → 生成第 1 层
#   load_game(slot) —— 读取：清 → 新英雄 → 读档 → 载入该层
# 两者共用 _reset_run 的清场与建英雄，差别只在之后走 init 还是走 deserialize 还原。
var hero: Hero = Hero.new()
var depth: int = 1
var branch: int = 0
var gold: int = 0
var energy: int = 0

# 开一局前的共同清场：背包 / 调度队列 / 层数据 / 上一局的残留计数，然后换一个新英雄。
# 次序要点：清背包必须早于建英雄——init_hero 会把初始物品 collect 进包（HeroClass.gd:22-41），反了会被清光。
func _reset_run() -> void:
	hero.backpack.reset()
	TurnManager.clear_actors()
	LevelManager.reset()
	depth = 1
	branch = 0
	gold = 0
	energy = 0
	hero = Hero.new()
	# 时间轴归零：Actor.now 是 static，跨局不清会把新挂的 buff 锚点带偏（见 Char.reset_timeline）。
	hero.reset_timeline()

# 新档：初始化的全部都在这里。
# 新英雄的属性 / 初始装备 / 初始背包 / 全 0 天赋树 / Regeneration·Hunger 全由 hero.init() 建。
func new_game() -> void:
	_reset_run()
	GameState.init_anonymous_names()
	hero.init()
	LevelManager.generate_level(depth)
	hero.grid_pos = LevelManager.level.entrance()

# 读取。与 new_game 的分野：**不跑 init()**——init 会重置属性、重发初始物品、把天赋树重建为全 0，
# 正好把要恢复的东西冲掉；读档一律走 deserialize 全量还原。无档返回 false（什么都没读进来）。
func load_game(slot: int) -> bool:
	_reset_run()
	var data := SaveManager.read_game(slot)
	if data.is_empty():
		print("[GameState]->[load_game(slot:%d)]:存档不存在" % slot)
		return false
	deserialize(data)
	# 楼层：先把磁盘上所有层读进缓存，再载入当前深度那层（缓存里已有则原样载入，不动 hero.grid_pos）。
	for d in SaveManager.list_floors(slot):
		var fd := SaveManager.read_floor(slot, d)
		if not fd.is_empty():
			LevelManager.deserialize_floor(d, fd)
	LevelManager.enter_floor(depth)
	return true

# 存档：先把当前层收进 floor_cache，再写自身与每一层。
# entities 由场景采集（怪的位置与血量、地面物品），本类只认数据（manager 只做纯数据）。
func save_game(slot: int, entities: Dictionary = {}) -> bool:
	LevelManager.save_floor(depth, entities)
	# 先清掉旧楼层文件再写这一套：否则上一局残留的 floor_N.json 会在下次 load_game 里被读进来。
	SaveManager.clear_floors(slot)
	var ok := SaveManager.write_game(slot, serialize())
	for d in LevelManager.floor_cache.keys():
		if not SaveManager.write_floor(slot, d, LevelManager.serialize_floor(d)):
			ok = false
	return ok

static var anonymous_names: Dictionary = {}
# 已鉴定的物品**类型**集合（键同 anonymous_names，即 item_name）。
# 取代 SPD 的 ItemStatusHandler：那边按"类"记已知，本工程用 item_name 记。
# 是"鉴定"玩法的全部状态——鉴定一张升级卷轴后，同类全部一起变真名。
static var known: Dictionary = {}
static var identified_scrolls = ["升级卷轴", "鉴定卷轴", "驱邪卷轴", "镜像卷轴", "充能卷轴", "传送卷轴", "催眠卷轴", "探地卷轴", "盛怒卷轴", "复仇卷轴", "恐惧卷轴", "嬗变卷轴"]
static var anonymous_scrolls = ["KAUNAN卷轴", "SOWILO卷轴", "LAGUZ卷轴", "YNGVI卷轴", "GYFU卷轴", "RAIDO卷轴", "ISAZ卷轴", "MANNAZ卷轴", "NAUDIZ卷轴", "BERKANAN卷轴", "ODAL卷轴", "TIWAZ卷轴"]
static var identified_potions = []
static var anonymous_potions = []
static func init_anonymous_names():
	# 重洗假名必须同时清空已知集合，否则上一局的鉴定进度会漏进新局（同 SPD clearLabels+initLabels）。
	known.clear()
	anonymous_scrolls.shuffle()
	for i in range(0, identified_scrolls.size()):
		anonymous_names[identified_scrolls[i]] = anonymous_scrolls[i]
	anonymous_potions.shuffle()
	for i in range(0, identified_potions.size()):
		anonymous_names[identified_potions[i]] = anonymous_potions[i]

func serialize() -> Dictionary:
	var data = {
		"hero": hero.serialize(),
		"depth": depth,
		"branch": branch,
		"gold": gold,
		"energy": energy,
		"anonymous_names": anonymous_names,
		"known": known
	}
	return data

func deserialize(data: Dictionary):
	if(data.get("hero") != null):
		hero.deserialize(data.get("hero"))
	# JSON 数字读回来是 float，下列字段全线按 int 用，故 int() 归一。
	depth = int(data.get("depth", 1))
	branch = int(data.get("branch", 0))
	gold = int(data.get("gold", 0))
	energy = int(data.get("energy", 0))
	# 卷轴假名映射整份存/取，真相源是 GameState.anonymous_names（Scroll.name() 读它）。
	# 旧档没这个键时退回重洗一份——不能直接收 null，
	# 否则 Scroll.name() 里 anonymous_names[item_name] 会因无效键报错。
	var names = data.get("anonymous_names", null)
	if names is Dictionary:
		anonymous_names = names
	else:
		init_anonymous_names()
	# 已鉴定类型集合。旧档/过渡档没这个键就置空（不能留上一局的残留）。
	var k = data.get("known", null)
	known = k if k is Dictionary else {}
	print(depth)
	pass
