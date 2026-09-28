extends Node2D

@onready var terrain_layer = $Layers/TerrainTileMapLayer
@onready var water_layer = $Layers/WaterLayer
@onready var walls_layer = $Layers/WallsTileMapLayer
@onready var fog_layer = $Layers/FogLayer

var hero: Hero:
	get:
		return GameState.hero
	set(value):
		GameState.hero = value

@onready var camera = $Camera2D
@onready var inventory_ui = $CanvasLayer/InventoryUI  # 背包UI
@onready var zoom_in_button = $CanvasLayer/Button      # 缩放放大按钮
@onready var rest_button = $CanvasLayer/RestButton     # 休息一拍按钮
@onready var sleep_button = $CanvasLayer/SleepButton   # 长休息按钮（一直休息，再按退出）
@onready var buff_list = $CanvasLayer/BuffList          # 身上 buff 一览
@onready var talent_list = $CanvasLayer/TalentList

# ---------- 图块映射 ----------
const TILE_CHASM = Vector2i(8, 1)
const TILE_FLOOR = Vector2i(0, 0)
const TILE_GRASS = Vector2i(2, 0)
const TILE_ENTRENCE = Vector2i(0, 1)
const TILE_EXIT = Vector2i(1, 1)

const TILE_FOG_UNSEEN = Vector2i(1, 0)     # 纯黑
const TILE_FOG_EXPLORED = Vector2i(0, 0)   # 半透明黑

var is_animating: bool = false
var hero_dead: bool = false

# ---------- 地格选取 ----------
var _selector: TileSelector = null   # 通用选取器（投掷/施法等复用）
var _preview: Callable = Callable()  # 当前选格的预览回调（随 select_cell 传入，见该函数）

# select_cell 的结果通道：选格要点鼠标、跨帧，无法同步返回，故用一次性信号把
# "确认的格子"或"取消"（(-1,-1)）交回 await 方，由调用方自行决定拿到格子做什么。
signal _selection_resolved(cell: Vector2i)

# ---------- 背包选取 ----------
# select_item 的结果通道：同上，点选跨帧。交回"选中的物品"或取消（null）。
signal _item_selection_resolved(item: Item)

const ZOOM_MIN = 0.5
const ZOOM_MAX = 10.0

var items_on_floor: Array = []   # 地面物品节点（引用）

# 层序：地面瓦片=0 → 地面物品/飞行物品=0(树序靠后，压瓦片) → 角色=1 → 地格选取框=2。
# 故物品（含投掷飞行体）始终渲染在角色下方、瓦片上方；选取框再压在所有实体之上。
const ITEM_Z := 0
const CHAR_Z := 1

func _ready():
	# 连接 TurnManager 信号（角色动画由角色自身自管，故不在此接攻击/死亡）
	TurnManager.before_monster_turn.connect(_on_before_monster_turn)
	TurnManager.after_monster_turn.connect(_on_after_monster_turn)
	# 连接全局输入意图（回合 gate 在此处的 handler 内判定）
	InputHub.move_requested.connect(_on_move_requested)
	InputHub.map_click_requested.connect(_on_map_click)
	InputHub.zoom_requested.connect(_on_zoom_requested)
	
	Bag.inventory_updated.connect(_on_inventory_updated)
	SaveManager.entity_provider = capture_entities   # 当前层的怪/物由本场景采集（SaveManager 不认节点）
	inventory_ui.game_scene = self   # 必须先于任何会触发 inventory_updated 的操作，否则 refresh 拿到空 game_scene
	inventory_ui.item_chosen.connect(_on_item_chosen)
	inventory_ui.selection_cancelled.connect(_on_item_selection_cancelled)
	zoom_in_button.pressed.connect(_on_zoom_in_button_pressed)   # 缩放放大按钮
	rest_button.pressed.connect(_on_rest_button_pressed)   # 休息按钮
	sleep_button.pressed.connect(_on_sleep_button_pressed)   # 长休息按钮
	# 天赋列表：点一下加一点。用 item_clicked 而非 item_selected——后者只在"选中项变了"时发，
	# 同一项连点第二次不会再触发（连升两级就卡住了）；item_clicked 每次都发。
	talent_list.item_clicked.connect(_on_talent_list_item_clicked)

	Scroll.init_nickname()
	init_layers()

	# 地格选取器：在 Layers 之后加入，才能盖住迷雾层绘制高亮（投掷/施法等复用）
	_selector = TileSelector.new()
	_selector.scene = self
	# 压在所有实体之上：地面物品与角色都是 add_child 到本场景的，z_index 分别为 ITEM_Z/CHAR_Z；
	# 光靠"后加入的树序靠后"不够——物品与角色是运行期才 add_child 的，会盖在选取框上面。
	# 故显式抬到最高一档，黄光标与绿落点框才不会被物品与角色挡住。
	_selector.z_index = CHAR_Z + 1
	add_child(_selector)
	_selector.cursor_changed.connect(_on_selector_cursor_changed)
	_selector.confirmed.connect(_on_cell_confirmed)
	_selector.cancelled.connect(_on_selector_cancelled)

	# 一局开始：全局时钟归零。原版开局在 Dungeon 里调 Actor.clear()，其中一半就是 now = 0；
	# 本工程的"新的一局"入口是本场景的 _ready（换层不重建场景，只在下面那个函数里就地重绘）。
	# 必须早于 render_hero：Hero._ready → init() 会给英雄挂 Hunger，而 buff 的锚点是 Actor.now
	# （见 Buff.attach_to）。static var 不随场景重载还原，同一进程里开第二局时它仍是上局的数——
	# 不归零，Hunger 就会锚在上局的时钟上，英雄迟迟不饿。
	Actor.now = 0.0
	# 世界锁同理归零：上局若停在英雄身上（正常局终态），第二局开局的锁会指向已释放的旧英雄。
	# process 每轮开头都会清锁，故这只是让"开局无主"这件事显式成立，不依赖它自愈。
	Actor.current = null

	# 清空背包必须早于 render_hero：开局的物品是 Hero._ready → heroClass.init_hero 发进包的，
	# 而下面的 add_child(hero) 会当场触发 Hero._ready。若仍把 clear 放在其后，刚发的一整套会被清光。
	# （refresh 不受影响：它在更下面，读到的是清过又灌满的包。）
	Bag.init_starting_inventory()

	render_hero()
	render_monsters()   # 按 MapManager 决策的怪物格渲染怪物节点
	render_items()   # 按 MapManager 决策的物品清单渲染地面物品

	camera.global_position = hero.global_position
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	
	update_fov()
	inventory_ui.refresh()

func _process(delta):
	camera.global_position = hero.global_position
	
	var text = "HP: " + str(hero.hp) + "/" + str(hero.max_hp) + "\n"
	text += "STR: " + str(hero.str) + "\n"
	text += "lvl: " + str(hero.lvl) + "\n"
	text += "exp: " + str(hero.exp)+ "/" + str(hero.max_exp()) + "\n"
	text += "饥饿度: " + str(hero.get_buff(Hunger).hunger())+ "/450\n"
	if hero.weapon != null:
		text += "当前武器: " + hero.weapon.title() + "(" + str(hero.weapon.min()) + "-" + str(hero.weapon.max()) + ")\n"
	else:
		text += "当前武器: 无\n"
	if hero.armor != null:
		text += "当前护甲: " + hero.armor.title() + "(" + str(hero.armor.dr_min()) + "-" + str(hero.armor.dr_max()) + ")\n"
	else:
		text += "当前护甲: 无\n"
	text += "剩余天赋点"
	for i in range(1, 5):
		text +=str(hero.talent_points_available(i)) + " "
	text += "\n"
	text += "精准: " + str(hero.attack_skill) + " 闪避：" + str(hero.defense_skill) + "\n\n"
	text += "当前楼层: " + str(GameState.depth) + "\n"
	$CanvasLayer/StatusLabel.text = text

	_refresh_buff_list()
	_refresh_talent_list()

# ---------- 身上 buff 一览 ----------
var _buff_cache: Array = []

func _refresh_buff_list():
	var labels: Array = []
	if hero != null:
		for buff: Buff in hero.all_buffs():
			labels.append(buff.name()+" "+buff.desc())
	if labels == _buff_cache:
		return   # 无变化不重建：避免每帧 clear/add_item 的无谓分配与列表闪烁
	buff_list.clear()
	for l in labels:
		buff_list.add_item(l)
	_buff_cache = labels

# ---------- 天赋一览 + 点击加点 ----------
# 数据源是 hero.talents（分层树：下标=层号-1，内层 {天赋ID: 点数}），
# **不是** Talent.DATA——DATA 是全部天赋的元数据，含别的职业的；树里才是"这个英雄有哪些"。
# 遍历顺序即树的插入顺序（T1 → T2 → T3），所以列表天然按层级排列，与原版 TalentsPane 同序。
#
# ItemList 的每一项只带一个 int 行号，升级却要反查"它在哪一层"（余额按层算，见
# Hero.talent_points_available），故刷新时同步重建一份行号 → (层, 天赋) 的对照表。
var _talent_rows: Array = []    # [{tier: int, id: int}, ...]，与列表项一一对应
var _talent_cache: Array = []

func _refresh_talent_list():
	var labels: Array = []
	var rows: Array = []
	if hero != null:
		for tier_idx in hero.talents.size():
			for id in hero.talents[tier_idx]:
				var points: int = hero.talents[tier_idx][id]
				# 带层号前缀：点不动时（余额为 0 / 该层没开）光看名字看不出为什么，层号是线索。
				labels.append("T%d %s %d/%d" % [tier_idx + 1, Talent.name(id), points, Talent.max_points(id)])
				rows.append({"tier": tier_idx + 1, "id": id})
	if labels == _talent_cache:
		return   # 无变化不重建：同 _refresh_buff_list，避免每帧 clear/add_item 的分配与闪烁
	talent_list.clear()
	for l in labels:
		talent_list.add_item(l)
	_talent_rows = rows
	_talent_cache = labels

# 点一下 = 加一点。两道门槛都直接问 Hero 的接口，不在这里自己算余额：
#   · 本层还有余额吗（含"等级够不够开这层"——那条判据就在 talent_points_available 里面）
#   · 这个天赋点满了吗
# 原版 UI 是把不可点的项灰掉；这里改成"点了没反应"，因为灰显要额外维护一份状态、
# 且 ItemList 对禁用项的 item_clicked 行为不值得赌（见上方连接的注释）。要灰显再加。
func _on_talent_list_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _talent_rows.size():
		return
	var row: Dictionary = _talent_rows[index]
	var tier: int = row["tier"]
	var id = row["id"]
	if hero.talent_points_available(tier) <= 0:
		return
	if hero.points_in_talent(id) >= Talent.max_points(id):
		return
	hero.upgrade_talent(id)
	# 不必就地重建列表：_process 每帧会调 _refresh_talent_list，点数变了标签就变，
	# 缓存自然失效。晚一帧（≤16ms）无感。

# ---------- 地图绘制 ----------
func init_layers():
	terrain_layer.update_all()
	walls_layer.update_all()
	init_water_layer()
	init_foglayer()

# ---------- 水体渲染：把 map_data 的 WATER 格画进 WaterLayer(TileMapDual)。
# 用 Godot 原生 terrain 把整片水连上、自动挑岸线瓦片(terrain_set 0 / terrain 1="FG水")，
# TileMapDual 再把世界格镜像到其半格偏移 display 层做交错表现。 ----------
func init_water_layer():
	water_layer.modulate.a = 0.9
	var water_cells: Array[Vector2i] = []
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			if LevelManager.map_data[y][x] == Terrain.WATER:
				water_layer.draw_cell(Vector2i(x, y), 0)
				water_cells.append(Vector2i(x, y))
	if water_cells.is_empty():
		return
	water_layer.set_cells_terrain_connect(water_cells, 0, 1)
	
		
func init_foglayer():
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			fog_layer.set_cell(Vector2i(x, y), 0, TILE_FOG_UNSEEN)

func refresh_foglayer():
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			if LevelManager.explored[y][x]:
				if hero.FOV[y][x]:
					fog_layer.set_cell(pos, -1)
				else:
					fog_layer.set_cell(pos, 0, TILE_FOG_EXPLORED)
			else:
				fog_layer.set_cell(pos, 0, TILE_FOG_UNSEEN)

func update_fov():
	hero.fieldofview()                  # 视野由英雄自己按 view_distance 算，写入 hero.FOV
	_reveal_by_mind_vision()            # 灵视在英雄 FOV 之上额外点亮（尚未落账）
	MapManager.record_sight(hero.FOV)   # 落账进已探索：唯一写入点，故须排在灵视之后
	refresh_foglayer()
	update_monsters_visibility()
	update_items_visibility()

# 灵视：把每个生物及其九宫格补进英雄视野（fieldofview 每次先清空 FOV 再重算，
# 故 buff 一掉，这些格自然恢复黑暗；explored 已记下，地形仍留在迷雾记忆中）。
func _reveal_by_mind_vision():
	if not hero.has_buff(MindVision):
		return
	var cells := []
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			cells.append(mob.grid_pos)
	hero.reveal_around(cells, MindVision.RADIUS)
	
func update_monsters_visibility():
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			var cell = mob.grid_pos
			# 检查坐标是否在有效范围内
			if cell.x >= 0 and cell.x < LevelManager.MAP_WIDTH and cell.y >= 0 and cell.y < LevelManager.MAP_HEIGHT:
				mob.visible = hero.FOV[cell.y][cell.x]
			else:
				mob.visible = false
				
func update_items_visibility():
	for item_node in items_on_floor:
		if is_instance_valid(item_node):
			var cell = item_node.grid_pos
			if cell.x >= 0 and cell.x < LevelManager.MAP_WIDTH and cell.y >= 0 and cell.y < LevelManager.MAP_HEIGHT:
				item_node.visible = hero.FOV[cell.y][cell.x]
			else:
				item_node.visible = false
				
# ---------- 放置英雄：实例化 Hero.tscn 后摆到 MapManager 决策的出生点并加入场景树 ----------
func render_hero():
	hero.grid_pos = LevelManager.hero_spawn
	hero.position = terrain_layer.map_to_local(hero.grid_pos)
	hero.game_scene = self
	hero.z_index = CHAR_Z   # 角色压在地面物品之上
	add_child(hero)   # 触发 Hero._ready（init_hero 初始化属性）；摆位后才进树，无闪现
	hero.play_anim("idle")   # 生成即静止动画
	# 开局回到空闲态：输入门闩得打开（is_ready），否则 is_player_turn 恒为假、点击全被挡。
	# 必须留在这里而不是靠 Hero 的字段默认值：GameState.hero 是 autoload 里只 new 一次的常驻实例，
	# 同一进程开第二局不会重跑字段初值（同上面 Actor.now / Actor.current 归零那条）。
	hero.enter_ready()
	TurnManager.register_actor(hero)

# ---------- 渲染怪物：按 LevelManager.monster_cells 实例化怪物节点 ----------
func render_monsters():
	# 有本层快照（读档或回访）→ 按快照重建（含存下的血量）。
	var ents = LevelManager.get_floor_entities(LevelManager.current_depth)
	if not ents.is_empty():
		_render_monsters_from(ents.get("monsters", []))
		return
	for cell in LevelManager.monster_cells:
		var mob = preload("res://scripts/actors/mobs/rat/Rat.tscn").instantiate()
		mob.grid_pos = cell
		mob.position = terrain_layer.map_to_local(cell)
		mob.game_scene = self
		mob.z_index = CHAR_Z   # 角色压在地面物品之上
		add_child(mob)
		TurnManager.register_actor(mob)

# 世界服务：格子 → 屏幕像素（格中心）。移动目标像素供 Char.walk_to 取用，
# 角色自身 _process 做并行自滑，这里不再包揽滑动动画。
func cell_to_world(cell: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(cell)

# 一格像素尺寸（严格取自图块资源，当前 16×16）；供高亮框按格绘制
func tile_pixel_size() -> Vector2:
	return Vector2(terrain_layer.tile_set.tile_size)


# ---------- 是否轮到玩家行动 ----------
# hero.is_ready 是主判据（原版 cellSelector.enable(hero.ready)）：英雄正忙一个动作
# （走位、追击、拾取、换层）时门闩是关的，此时点击/方向键一律不响应——行走途中不可改道。
# 另两条照旧：本场景自己的飞行/选格动画期间、以及调度器循环进行中，都不收输入。
func is_player_turn() -> bool:
	return hero.is_ready and not hero_dead and not is_animating and not TurnManager.is_processing

# ---------- 信号响应 ----------
func _on_before_monster_turn():
	pass

func _on_after_monster_turn():
	update_fov()

# ---------- 英雄死亡状态：由 Char.destory 在动画开始前调用；只改状态与 UI，不播动画 ----------
func set_hero_dead():
	if hero_dead:
		return
	hero_dead = true
	inventory_ui.clear_buttons()   # 死亡后清掉动作按钮（且动作本就被 is_player_turn 挡住）
	clear_map()                    # 清场：地图四层 + 怪 + 地面物（英雄留在原地）
	print("英雄死亡，游戏结束")
	# TODO: 显示游戏结束界面

# 死亡清场：四个瓦片层一律 clear，怪与地面物一并移除。
# 数据（map_data / explored）不动——死亡不是换层，没有下家要读它。
func clear_map():
	terrain_layer.clear()
	walls_layer.clear()
	water_layer.clear()
	fog_layer.clear()
	for item_node in items_on_floor:
		if is_instance_valid(item_node):
			item_node.queue_free()
	items_on_floor.clear()
	for mob in TurnManager.monsters.duplicate():
		if is_instance_valid(mob):
			mob.queue_free()
	TurnManager.monsters.clear()

# ---------- 缩放 ----------
func zoom_map(factor: float):
	var new_zoom = camera.zoom.x + factor
	new_zoom = clamp(new_zoom, ZOOM_MIN, ZOOM_MAX)
	if new_zoom == camera.zoom.x:
		return
	var mouse_global = get_global_mouse_position()
	var old_zoom = camera.zoom.x
	var offset = (mouse_global - camera.global_position) / old_zoom
	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.global_position = mouse_global - offset * new_zoom

# ---------- 退出休息 ----------
# 直译原版 CellSelector.java:331 / :344-345——任意输入把 resting 拨回 false。
# 必须排在 is_player_turn 之前：休息期间输入门是关的（Hero.rest 里 set_busy），
# gate 会先把这次输入挡掉，而"退出休息"恰恰要在门关着的时候也能进来。
# 只写这一个字段，不碰 is_ready：原版同样不碰 ready（那边由英雄下一次 act() 走
# else 分支时才 ready()）。也不必在这里唤醒调度器——休息循环正停在 Hero.wait_one_tick
# 处，下一拍读到新值就会走空闲分支收尾。清 resting 时顺带清 cur_action，同原版
# GameScene.cancel()（Hero.java 之外的唯一"取消"入口，Toolbar 的休息键走的正是它）。
# 返回 true 表示这次输入被休息消费掉了（原版 CellSelector 里两支都 return true）。
func _cancel_rest_if_any() -> bool:
	if not hero.resting:
		return false
	hero.cur_action = null
	hero.resting = false
	return true

# ---------- 输入处理：由全局 InputHub 翻译意图为信号，此处接信号做回合 gate 与执行 ----------
func _on_move_requested(direction: Vector2i):
	if _cancel_rest_if_any():
		return   # 休息中按方向键 = 退出休息，这一步不吃（再按一次才走），同原版 CellSelector
	if _selector.active:
		return   # 选取模式中不响应方向移动
	if inventory_ui.selecting:
		return   # 选物模式中同理
	if not is_player_turn():
		return
	_issue(hero.grid_pos + direction)

# 点击地图：脚下 / 相邻 / 射程内的怪 → 单次行动；更远处（无论有无怪）→ 寻路走过去。
# 走多远、途中遇到什么，全由 curAction 自己决定（见 Hero.act 分派）。
func _on_map_click():
	if _cancel_rest_if_any():
		return   # 休息中点地图 = 退出休息
	if _selector.active:
		return   # 选取模式自行消费点击
	if inventory_ui.selecting:
		return   # 选物模式中地图点击一律忽略，避免一边等选取一边把回合推走
	if hero_dead:
		return
	var cell = get_cell_from_mouse_pos()
	if cell == Vector2i(-1, -1):
		return
	if not MapManager.is_walk_target(cell):
		return   # 只能点已探索的格，或紧邻已探索区域的未探明格
	if not is_player_turn():
		return
	_issue(cell)

func _on_zoom_requested(factor: float):
	zoom_map(factor)

# 缩放放大按钮：按下即放大 0.2
func _on_zoom_in_button_pressed():
	zoom_map(InputHub.ZOOM_STEP)

# ---------- 玩家动作的入口 ----------
# 曾经的 try_hero_action 一拆三：这一格有什么 → Hero.handle（造 curAction）、
# 怎么执行 → Hero.act 分派、剩下的"放锁 + 醒调度器"留在这里。
# 后者不外迁的理由：世界锁与调度器是 TurnManager 的领域，让角色自己去驱动调度器
# 会把它同时变成"世界编排者"，而这两个身份正是这一轮重构要分开的。
func _issue(cell: Vector2i):
	if not is_player_turn():
		return
	if not hero.handle(cell):
		return   # 这一格无动作可造（不可走），不推回合
	hero.next()   # 放锁：英雄空闲时锁正留在它身上（停产等输入，见 Actor.next）
	await TurnManager.process()

# ---------- 换层 ----------
# 数据侧（存档 / 进层 / 落点）交给 LevelManager.switch_level；本场景负责节点侧：
# 开走前采集实体快照，回来后按落点重建视图。到顶则 switch_level 返回空字典，什么也不做。
# 公开：Hero.act_transition 走到出入口后从角色侧回调（原来只有本场景的 try_hero_action 调）。
func change_floor(depth: int) -> void:
	var result = LevelManager.switch_level(depth, capture_entities())
	if result.is_empty():
		return
	rebuild_level(result["landing"], result["restored"])

# ---------- 采集当前层活实体 → 快照（怪的位置与血量、地面物品） ----------
func capture_entities() -> Dictionary:
	var monsters := []
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			monsters.append({ "cell": mob.grid_pos, "hp": mob.hp, "max_hp": mob.max_hp })
	var items := []
	for node in items_on_floor:
		if is_instance_valid(node):
			items.append({ "cell": node.grid_pos, "item": node.item_data })
	return { "monsters": monsters, "items": items }

# 换层后重建视图：清旧实体、重绘地图层、摆好英雄、按快照或新生成渲染怪/物。
# 由 change_floor 在 LevelManager 完成数据侧后调用（唯一调用方是 Hero.act_transition，
# 而它之后会调 enter_ready 清掉 cur_action / path，故此处不必再清英雄的动作状态）。
func rebuild_level(landing: Vector2i, restored: bool) -> void:
	# 清掉旧层实体
	for item_node in items_on_floor:
		if is_instance_valid(item_node):
			item_node.queue_free()
	items_on_floor.clear()
	for mob in TurnManager.monsters.duplicate():
		if is_instance_valid(mob):
			mob.queue_free()
	TurnManager.monsters.clear()
	# 重绘地图层（先清后画，否则残留上一层瓦片）
	terrain_layer.clear()
	walls_layer.clear()
	water_layer.clear()
	fog_layer.clear()
	init_layers()
	# 英雄摆到落点，并清空时间轴（玩家先动）；buff 随宿主一同归零，否则换层后再也轮不到
	hero.snap_to(landing)
	hero.reset_timeline()
	if restored:
		var ents = LevelManager.get_floor_entities(LevelManager.current_depth)
		_render_monsters_from(ents.get("monsters", []))
		_render_items_from(ents.get("items", []))
	else:
		render_monsters()
		render_items()
	camera.global_position = hero.global_position
	update_fov()
	inventory_ui.refresh()

# 从快照重建怪（位置 + 血量）；HP 在 add_child 之后设，避免被 _ready 的初始值覆盖
func _render_monsters_from(snapshot: Array) -> void:
	for m in snapshot:
		var mob: Mob = preload("res://scripts/actors/mobs/rat/Rat.tscn").instantiate()
		mob.grid_pos = m["cell"]
		mob.position = terrain_layer.map_to_local(m["cell"])
		mob.game_scene = self
		add_child(mob)
		mob.max_hp = m["max_hp"]
		mob.hp = m["hp"]
		mob.z_index = CHAR_Z   # 角色压在地面物品之上
		TurnManager.register_actor(mob)

func _render_items_from(snapshot: Array) -> void:
	for e in snapshot:
		# 快照里的物品可能为空（Item.serialize 尚未实现，存下来的每件都是 {}）：
		# 空项一律跳过，不能喂给 create_floor_item——它会在合并循环里对 null 取 .name() 崩掉。
		if e.get("item", null) == null:
			continue
		create_floor_item(e["item"], e["cell"])

# ---------- 鼠标坐标 ----------
func get_cell_from_mouse_pos() -> Vector2i:
	var mouse_pos = get_global_mouse_position()
	var local_pos = terrain_layer.to_local(mouse_pos)
	var tile_pos = terrain_layer.local_to_map(local_pos)
	if tile_pos.x >= 0 and tile_pos.x < LevelManager.MAP_WIDTH and tile_pos.y >= 0 and tile_pos.y < LevelManager.MAP_HEIGHT:
		return tile_pos
	return Vector2i(-1, -1)

# ---------- 物品系统 ----------
# 渲染地面物品：按 LevelManager.item_placements 实例化 Item 节点（含同格合并逻辑沿用 create_floor_item）
func render_items():
	# 有本层快照（读档或回访）→ 按快照重建；物品内容仍缺序列化，空项由 _render_items_from 跳过。
	var ents = LevelManager.get_floor_entities(LevelManager.current_depth)
	if not ents.is_empty():
		_render_items_from(ents.get("items", []))
		return
	for placement in LevelManager.item_placements:
		create_floor_item(placement["item"], placement["cell"])

func create_floor_item(item_data: Item, cell: Vector2i):
	for item_node in items_on_floor:
		if item_node.grid_pos == cell and item_node.item_data.name() == item_data.name():
			item_node.item_data.item_quantity += item_data.item_quantity
			return
	var item_node = preload("res://tscns/Item.tscn").instantiate()
	item_node.grid_pos = cell
	item_node.position = terrain_layer.map_to_local(cell)
	item_node.item_data = item_data
	item_node.z_index = ITEM_Z   # 在角色之下、地面瓦片之上
	add_child(item_node)
	items_on_floor.append(item_node)

func is_item_on_cell(cell: Vector2i) -> bool:
	for item_node in items_on_floor:
		if item_node.grid_pos == cell:
			return true
	return false

# 走开某格时把该格上开着的门带上。门格里放着东西就永远敞着——关不上。
func close_door_behind(cell: Vector2i) -> void:
	if is_item_on_cell(cell):
		return
	MapManager.close_door(cell)

func try_collect(actor: Char) -> bool:
	for i in range(items_on_floor.size() - 1, -1, -1):
		var item_node = items_on_floor[i]
		if item_node.grid_pos == actor.grid_pos:
			if item_node.do_pickup(actor):
				items_on_floor.remove_at(i)
				item_node.queue_free()
				return true
	print("此处没有物品或背包已满")
	return false

# ---------- 通用选格 ----------
# 进入选取模式，等玩家左键确认或右键/Esc 取消，返回选中格；取消返回 (-1,-1)。
# 选格要点鼠标、跨帧，故本函数是协程，调用方必须 await。
# preview 是"预览种类"标识：按它挂上对应的预览函数，光标每次移动即重画预览。
# 调用方（如 Item.do_throw）只需传种类名，不必知道预览怎么实现；以后施法、指定目标
# 各加一个种类与对应的 _refresh_xxx_preview 即可复用，本函数主体不必再改。
func select_cell(origin: Vector2i = hero.grid_pos, preview: String = "") -> Vector2i:
	if _selector.active:
		_selector.cancel()   # 关掉可能开着的上一次选取
	match preview:
		"throw":
			_preview = _refresh_throw_preview
		_:
			_preview = Callable()   # 无预览：只有跟随鼠标的光标框
	_selector.begin(origin, Callable())   # 确认/取消统一走 confirmed/cancelled 信号
	if _preview.is_valid():
		_preview.call(_selector.cursor)   # 初始格先预览一次，免得要动一下鼠标才出框
	var cell: Vector2i = await _selection_resolved
	return cell

func _on_cell_confirmed(cell: Vector2i) -> void:
	_preview = Callable()
	_selection_resolved.emit(cell)

func _on_selector_cancelled() -> void:
	_preview = Callable()
	_selection_resolved.emit(Vector2i(-1, -1))   # 取消：交回 (-1,-1)，不记时、不推进回合

# 光标移动：转交给当前预览回调（无预览则只更新光标框本身）
func _on_selector_cursor_changed(cell: Vector2i) -> void:
	if _preview.is_valid():
		_preview.call(cell)

# 落点可达 = 沿直线无遮挡（= 实际落点即光标格）→ 光标绿；被墙挡 → 黄。
# 未探索格一律不显绿（看不见的暗格不冒充"已确定落点"）：落点在未探索处则不画绿框，
# 光标落在未探索格也不算"有效"。
func _refresh_throw_preview(cell: Vector2i) -> void:
	var landing = MapManager.throw_landing_cell(hero.grid_pos, cell)
	_selector.set_secondary(landing if MapManager.is_explored(landing) else Vector2i(-1, -1))
	_selector.set_cursor_valid(landing == cell and MapManager.is_explored(cell))

# ---------- 通用选物 ----------
# 进入选物模式，等玩家点选一件物品后返回；取消返回 null。
# 与 select_cell 同构：点选跨帧，无法同步返回，故本函数是协程，调用方必须 await。
# 背包与装备栏都可选（原版 WndBag 的格子里本就有 5 个装备槽；升级/驱邪卷轴要能作用到
# 已装备的武器护甲，故不能只认背包）。取消走全局 Esc/右键。
# 调用方（如将来"用药前先选一瓶"）不必知道背包 UI 怎么搭，只 await 拿结果。
func select_item() -> Item:
	if inventory_ui.selecting:
		inventory_ui.cancel_select()   # 关掉可能开着的上一次选取
	inventory_ui.begin_select()
	var item: Item = await _item_selection_resolved
	return item

func _on_item_chosen(item: Item) -> void:
	_item_selection_resolved.emit(item)

func _on_item_selection_cancelled() -> void:
	_item_selection_resolved.emit(null)

# 放下：把物品摆到指定格（放下与扔出共用）。飞行动画 + 落地 + 刷可见性。
# 目标格与英雄同格时（放下）_animate_throw 直接返回，不产生飞行。
# 只认"已取出的物品"——从背包取出归 Item.detach/detach_all；记账与推进回合由 Item 收尾。
func drop(item: Item, cell: Vector2i) -> bool:
	if not is_player_turn():
		return false
	if item == null:
		return false
	is_animating = true   # 飞行期间挡输入，避免半途再次行动
	await _animate_throw(item, cell)
	create_floor_item(item, cell)
	# 物品落在门上 → 门开。否则会剩下"关着的门 + 门格上有物品"，与"门格有物品就始终开着"冲突。
	# 不是门、或门本来就开着都是 no-op；上锁门不在此列（open_door 只认 DOOR）。
	MapManager.open_door(cell)
	update_items_visibility()   # 落点可能未探索：立即按视野决定可见性，避免闪现
	is_animating = false
	print("放置：", item.name(), " x", item.item_quantity, " 于 ", cell)
	return true

# 物品飞出动画：一份临时视觉从英雄格飞向落点，飞完自毁，随后才真正落地。
# 线性插值 + 时长正比于距离 = 匀速飞行（原来 QUAD/EASE_IN 会先慢后快，看着像越飞越快）。
const THROW_SECONDS_PER_CELL := 0.05   # 每格飞行耗时（恒定即匀速）
func _animate_throw(item_data: Item, landing: Vector2i) -> void:
	var cells = max(abs(landing.x - hero.grid_pos.x), abs(landing.y - hero.grid_pos.y))
	if cells <= 0:
		return   # 原地落下，无需飞行
	var fly = preload("res://tscns/Item.tscn").instantiate()
	fly.item_data = item_data
	fly.grid_pos = landing
	fly.position = cell_to_world(hero.grid_pos)
	fly.z_index = ITEM_Z   # 飞行体同样在角色之下、地面瓦片之上
	add_child(fly)
	var tween = fly.create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)   # 匀速
	tween.tween_property(fly, "position", cell_to_world(landing), cells * THROW_SECONDS_PER_CELL)
	await tween.finished
	if is_instance_valid(fly):
		fly.queue_free()

func _on_inventory_updated():
	inventory_ui.refresh()

# 休息按钮：**等一拍**（原版点按 wait 键 → hero.rest(false)）。
# 和别的玩家动作同一条路：设好状态 → 放锁 → 醒调度器，让怪动一轮后把操作交回来。
func _on_rest_button_pressed():
	# 正长休息中按它 = 退出，不再叠一轮。见下面睡觉按钮的注释（同一个 cancel 结构）。
	if _cancel_rest_if_any():
		return
	if not is_player_turn():
		return
	hero.rest()
	hero.next()
	await TurnManager.process()

# 睡觉按钮：**一直休息到被打断**（原版长按 wait 键 / REST 键 → hero.rest(true)）。
# 本工程没有长按，故单开一个按钮。怪照常行动，英雄原地不动，直到：
#   · 任意输入（方向键 / 点地图 / 再按这两个按钮之一）→ 被上面的 _cancel_rest_if_any 拦下；
#   · 回血 buff 满血或到期 → Healing / WellFed 自行清 resting；
#   · 挨打 → Char.hit 调 interrupt() 清 resting。
# 这不是魔法睡眠：那个是 MagicalSleep，paralysed 挂上后输入一律无效，本按钮不走那条。
func _on_sleep_button_pressed():
	# 已在休息中就退出，不再起一轮。原版 Toolbar.java:201 的休息键正是这个结构：
	# 前置 `!GameScene.cancel()`，而 cancel() 在 resting 时会把 resting 清掉并返回 true。
	if _cancel_rest_if_any():
		return
	if not is_player_turn():
		return
	hero.rest(true)
	hero.next()
	await TurnManager.process()
