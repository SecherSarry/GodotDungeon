extends Node2D

@onready var bedrock_layer = $Layers/BedrockLayer
@onready var water_layer = $Layers/WaterLayer
@onready var wall_layer = $Layers/WallLayer
@onready var fog_layer = $Layers/FogLayer

var hero: Hero:
	get:
		return GameState.hero
	set(value):
		GameState.hero = value

@onready var camera = $Camera2D
@onready var inventory_ui = $CanvasLayer/InventoryUI  # 背包UI
@onready var zoom_in_button = $CanvasLayer/Button      # 缩放放大按钮
@onready var buff_list = $CanvasLayer/BuffList          # 身上 buff 一览

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

# ---------- 自动行走状态 ----------
var auto_walking: bool = false
var _walk_target: Vector2i = Vector2i(-1, -1)
var _walk_seen: Dictionary = {}   # 起步时已可见的怪（实例 id）→ 只对"新看到"的怪暂停
var _walk_monster: Char = null    # 敌人目标：非空则持续追击并攻击（目标格已探索时才设）

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

# 层序：地面瓦片=0 → 地面物品/飞行物品=0(树序靠后，压瓦片) → 角色=1。
# 故物品（含投掷飞行体）始终渲染在角色下方、瓦片上方。
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

	Scroll.new().init_nickname()
	init_layers()

	# 地格选取器：在 Layers 之后加入，才能盖住迷雾层绘制高亮（投掷/施法等复用）
	_selector = TileSelector.new()
	_selector.scene = self
	add_child(_selector)
	_selector.cursor_changed.connect(_on_selector_cursor_changed)
	_selector.confirmed.connect(_on_cell_confirmed)
	_selector.cancelled.connect(_on_selector_cancelled)

	render_hero()
	render_monsters()   # 按 MapManager 决策的怪物格渲染怪物节点
	render_items()   # 按 MapManager 决策的物品清单渲染地面物品

	# 初始背包：放在 hero 进树之后，使 refresh 读到已初始化的 hero（幂等：先清后灌）
	Bag.init_starting_inventory()

	camera.global_position = hero.global_position
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	
	update_fov()
	inventory_ui.refresh()

func _process(delta):
	camera.global_position = hero.global_position
	
	var text = "HP: " + str(hero.HP) + "/" + str(hero.maxHP) + "\n"
	text += "STR: " + str(hero.STR) + "\n"
	text += "lvl: " + str(hero.lvl) + "\n"
	text += "exp: " + str(hero.exp)+ "/" + str(hero.max_exp()) + "\n"
	text += "饥饿度: " + str(hero.get_buff(Hunger).hunger())+ "/450\n"
	if hero.weapon != null:
		text += "当前武器: " + hero.weapon.name() + "(" + str(hero.weapon.min()) + "-" + str(hero.weapon.max()) + ")\n"
	else:
		text += "当前武器: 无\n"
	if hero.armor != null:
		text += "当前护甲: " + hero.armor.name() + "(" + str(hero.armor.dr_min()) + "-" + str(hero.armor.dr_max()) + ")\n"
	else:
		text += "当前护甲: 无\n"
	text += "精准: " + str(hero.attack_skill) + " 闪避：" + str(hero.defense_skill) + "\n\n"
	text += "当前楼层: " + str(GameState.depth) + "\n"
	$CanvasLayer/StatusLabel.text = text

	_refresh_buff_list()

# ---------- 身上 buff 一览 ----------
var _buff_cache: Array = []

func _refresh_buff_list():
	var labels: Array = []
	if hero != null:
		for buff in hero.all_buffs():
			labels.append(_buff_label(buff))
	if labels == _buff_cache:
		return   # 无变化不重建：避免每帧 clear/add_item 的无谓分配与列表闪烁
	buff_list.clear()
	for l in labels:
		buff_list.add_item(l)
	_buff_cache = labels

# Buff 没有名字字段，取脚本的全局类名（如 "Haste"）当显示名
func _buff_label(buff: Actor) -> String:
	var script = buff.get_script()
	var shown: String = script.get_global_name() if script != null else ""
	if shown == "":
		shown = "Buff"
	if buff is Hunger:
		return shown + "  " + str(buff.partical_damage)
	return shown + "  " + ("%.1f" % (buff.next_action_time - hero.next_action_time))

# ---------- 地图绘制 ----------
func init_layers():
	init_bedrock_layer()
	init_wall_layer()
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
	
func init_bedrock_layer():
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			var tile
			if pos == LevelManager.hero_spawn:
				tile = TILE_ENTRENCE   # 入口（上一层）
			elif pos == LevelManager.exit_cell:
				tile = TILE_EXIT       # 出口（下一层）
			else:
				match LevelManager.map_data[y][x]:
					Terrain.CHASM:	tile = TILE_CHASM
					Terrain.WATER:	tile = TILE_FLOOR
					Terrain.EMPTY:	tile = TILE_FLOOR
					Terrain.GRASS:	tile = TILE_GRASS
					_:					tile = TILE_CHASM
			bedrock_layer.set_cell(pos, 0, tile)

func init_wall_layer():
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			var tile = get_wall_tile(x, y)
			if tile != Vector2i(-1, -1): wall_layer.set_cell(pos, 0, tile)
	pass

func get_wall_tile(x: int, y: int) -> Vector2i:
	var mask = 0
	# 检测自己
	var c = LevelManager.map_data[y][x] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]
	
	# 检测左
	var l = x > 0 and LevelManager.map_data[y][x-1] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]

	# 检测左下
	var ld = x > 0 and y < LevelManager.MAP_HEIGHT - 1 and LevelManager.map_data[y+1][x-1] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]

	# 检测下
	var d = y < LevelManager.MAP_HEIGHT - 1 and LevelManager.map_data[y+1][x] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]

	# 检测右下
	var dr = x < LevelManager.MAP_WIDTH - 1 and y < LevelManager.MAP_HEIGHT - 1 and LevelManager.map_data[y+1][x+1] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]

	# 检测右
	var r = x < LevelManager.MAP_WIDTH - 1 and LevelManager.map_data[y][x+1] in [Terrain.WALL, Terrain.DOOR, Terrain.OPEN_DOOR, Terrain.LOCKED_DOOR, Terrain.CHASM]

	if  c and 				 !d:				return Vector2i(0, 5)
	if  c and  l and !ld and  d and !dr	:		return Vector2i(6, 9)
	if  c and !l and !ld and  d and !dr:		return Vector2i(14, 9)
	if  c and !l and  ld and  d and  dr and !r:	return Vector2i(9, 9)
	if  c and !l and  ld and  d and !dr:		return Vector2i(10, 9)
	if  c and !l and !ld and  d and  dr and !r:	return Vector2i(13, 9)
	if  c and  						 dr and !r:	return Vector2i(1, 9)
	if  c and !l and  ld:						return Vector2i(8, 9)
	if  c and  l and !ld:						return Vector2i(4, 9)
	if  c and !l and !ld:						return Vector2i(12, 9)
	if  c and 						!dr:		return Vector2i(2, 9)
	if !c and 		 !ld and  d and !dr:		return Vector2i(3, 12)
	if !c and 		 !ld and  d and  dr:		return Vector2i(2, 12)
	if !c and 		  ld and  d and !dr:		return Vector2i(1, 12)
	if !c and 		  ld and  d and  dr:		return Vector2i(0, 12)
	else: return Vector2i(-1, -1)
		
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
	hero.position = bedrock_layer.map_to_local(hero.grid_pos)
	hero.game_scene = self
	hero.z_index = CHAR_Z   # 角色压在地面物品之上
	add_child(hero)   # 触发 Hero._ready（init_hero 初始化属性）；摆位后才进树，无闪现
	hero.play_anim("idle")   # 生成即静止动画
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
		mob.position = bedrock_layer.map_to_local(cell)
		mob.game_scene = self
		mob.z_index = CHAR_Z   # 角色压在地面物品之上
		add_child(mob)
		TurnManager.register_actor(mob)

# 世界服务：格子 → 屏幕像素（格中心）。移动目标像素供 Char.walk_to 取用，
# 角色自身 _process 做并行自滑，这里不再包揽滑动动画。
func cell_to_world(cell: Vector2i) -> Vector2:
	return bedrock_layer.map_to_local(cell)

# 一格像素尺寸（严格取自图块资源，当前 16×16）；供高亮框按格绘制
func tile_pixel_size() -> Vector2:
	return Vector2(bedrock_layer.tile_set.tile_size)


# ---------- 是否轮到玩家行动 ----------
# 只有不在播放自身动画、不在怪物回合处理中、且未死亡时，玩家才可行动
func is_player_turn() -> bool:
	return not hero_dead and not is_animating and not TurnManager.is_processing

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
	print("英雄死亡，游戏结束")
	# TODO: 显示游戏结束界面

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

# ---------- 输入处理：由全局 InputHub 翻译意图为信号，此处接信号做回合 gate 与执行 ----------
func _on_move_requested(direction: Vector2i):
	if _selector.active:
		return   # 选取模式中不响应方向移动
	if inventory_ui.selecting:
		return   # 选物模式中同理
	if auto_walking:
		_stop_auto_walk()   # 手动移动打断自动行走，避免两条驱动同时推进
		return
	if not is_player_turn():
		return
	try_hero_action(hero.grid_pos + direction)

# 点击地图：脚下 / 相邻 / 射程内的怪 → 单次行动；更远处（无论有无怪）→ 自动寻路走过去。
# 行走中点击 = 打断自动行走（本回合消费掉这次点击）。
# 目标格必须是已探索的。
func _on_map_click():
	if _selector.active:
		return   # 选取模式自行消费点击
	if inventory_ui.selecting:
		return   # 选物模式中地图点击一律忽略，避免一边等选取一边把回合推走
	if hero_dead:
		return
	var cell = get_cell_from_mouse_pos()
	if cell == Vector2i(-1, -1):
		return

	if auto_walking:
		_stop_auto_walk()   # 行走中点击 = 打断
		return

	if not MapManager.is_walk_target(cell):
		return   # 只能点已探索的格，或紧邻已探索区域的未探明格

	if not is_player_turn():
		return

	var offset = cell - hero.grid_pos
	var chebyshev = max(abs(offset.x), abs(offset.y))
	if cell == hero.grid_pos:
		try_hero_action(cell)          # 脚下：拾取
	elif chebyshev == 1:
		try_hero_action(cell)          # 相邻：攻击或移动
	else:
		var enemy = TurnManager.get_monster_at(cell)
		if hero.can_attack(enemy):
			try_hero_action(cell)      # 射程内的怪：直接攻击
		else:
			_start_auto_walk(cell)     # 远处（无论有无怪）：寻路过去

func _on_zoom_requested(factor: float):
	zoom_map(factor)

# 缩放放大按钮：按下即放大 0.2
func _on_zoom_in_button_pressed():
	zoom_map(InputHub.ZOOM_STEP)

# ---------- 玩家动作：判定合法性后把行动交给 hero（角色自管动画），GameScene 只负责编排与回合推进 ----------
func try_hero_action(target_cell: Vector2i):
	if not is_player_turn():
		return
		
	var offset = target_cell - hero.grid_pos

	is_animating = true
	var acted = false
	if offset == Vector2i.ZERO:
		# 脚下：拾取优先；无物品时再看是否站在入口/出口上换层
		if try_collect(hero):
			acted = true
		elif hero.grid_pos == LevelManager.hero_spawn:
			is_animating = false
			_change_floor(GameState.depth - 1)   # 站在入口 → 上一层
			return
		elif hero.grid_pos == LevelManager.exit_cell:
			is_animating = false
			_change_floor(GameState.depth + 1)   # 站在出口 → 下一层
			return
	else:
		var enemy = TurnManager.get_monster_at(target_cell)
		if hero.can_attack(enemy):
			await hero.attack(enemy)
			acted = true
		elif max(abs(offset.x), abs(offset.y)) == 1:
			acted = hero.move_step(target_cell)   # 同步即时提交 + 启动自滑
			# 不在此单独等待：下方 next 末尾会等英雄与怪物一起滑完（并行、无停顿）
	is_animating = false

	if acted:
		update_fov()
		await TurnManager.next()

# ---------- 换层 ----------
# 数据侧（存档 / 进层 / 落点）交给 LevelManager.switch_level；本场景负责节点侧：
# 开走前采集实体快照，回来后按落点重建视图。到顶则 switch_level 返回空字典，什么也不做。
func _change_floor(depth: int) -> void:
	var result = LevelManager.switch_level(depth, capture_entities())
	if result.is_empty():
		return
	rebuild_level(result["landing"], result["restored"])

# ---------- 采集当前层活实体 → 快照（怪的位置与血量、地面物品） ----------
func capture_entities() -> Dictionary:
	var monsters := []
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			monsters.append({ "cell": mob.grid_pos, "hp": mob.HP, "max_hp": mob.maxHP })
	var items := []
	for node in items_on_floor:
		if is_instance_valid(node):
			items.append({ "cell": node.grid_pos, "item": node.item_data })
	return { "monsters": monsters, "items": items }

# 换层后重建视图：清旧实体、重绘地图层、摆好英雄、按快照或新生成渲染怪/物。
# 由 _change_floor 在 LevelManager 完成数据侧后调用。
func rebuild_level(landing: Vector2i, restored: bool) -> void:
	auto_walking = false
	_walk_target = Vector2i(-1, -1)
	_walk_monster = null
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
	bedrock_layer.clear()
	wall_layer.clear()
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
		var mob = preload("res://scripts/actors/mobs/rat/Rat.tscn").instantiate()
		mob.grid_pos = m["cell"]
		mob.position = bedrock_layer.map_to_local(m["cell"])
		mob.game_scene = self
		add_child(mob)
		mob.maxHP = m["max_hp"]
		mob.HP = m["hp"]
		mob.z_index = CHAR_Z   # 角色压在地面物品之上
		TurnManager.register_actor(mob)

func _render_items_from(snapshot: Array) -> void:
	for e in snapshot:
		# 快照里的物品可能为空（Item.serialize 尚未实现，存下来的每件都是 {}）：
		# 空项一律跳过，不能喂给 create_floor_item——它会在合并循环里对 null 取 .name() 崩掉。
		if e.get("item", null) == null:
			continue
		create_floor_item(e["item"], e["cell"])

# ---------- 自动行走：沿已探索最短路径逐格走近；途中看到新出现的怪立即暂停 ----------
# 单一驱动循环：每步重算路径（怪会移动，旧路径随时失效），经主角 move_step 与 TurnManager.next 走一回合。
# 到达目标格后按目标内容做动作：有物品→拾取、是出入口→换层；目标是敌人→持续追击并攻击至死。
# 以上"到达/追击"行为仅在目标格已探索时生效（看不见的暗格只走过去，不做任何动作）。
func _start_auto_walk(cell: Vector2i):
	auto_walking = true
	_walk_target = cell
	# 敌人目标仅在"已探索"时成立：看不见的暗格不追敌（到达动作同理）
	_walk_monster = TurnManager.get_monster_at(cell) if MapManager.is_explored(cell) else null
	_walk_seen = _visible_monster_ids()   # 起步已见的怪不计入"新看到"
	hero.begin_continuous_move()   # 会话内滑步结束不回 idle，跑步动画连贯
	_auto_walk_loop()

func _stop_auto_walk():
	auto_walking = false
	_walk_target = Vector2i(-1, -1)
	_walk_monster = null

func _auto_walk_loop() -> void:
	while auto_walking and not hero_dead:
		if _walk_target == Vector2i(-1, -1):
			break   # 目标被取消

		if _walk_monster != null:
			# 敌人目标：持续追击，进入射程即攻击，直至击杀/消失
			if not is_instance_valid(_walk_monster) or not _walk_monster.is_alive():
				break
			_walk_target = _walk_monster.grid_pos   # 怪会移动：每步重定位
			if max(abs(hero.grid_pos.x - _walk_target.x), abs(hero.grid_pos.y - _walk_target.y)) <= hero.reach():
				await hero.attack(_walk_monster)
				update_fov()
				await TurnManager.next()
				continue
		elif hero.grid_pos == _walk_target:
			# 到达目标格：物品→拾取、出入口→换层。目标未探索则不生效（看不见的格子不做到达动作）
			if MapManager.is_explored(_walk_target):
				await try_hero_action(_walk_target)
			break

		# 途中出现"新看到"的怪 → 停下（追击目标时跳过：正在主动接近它）
		if _walk_monster == null and _has_new_visible_monster():
			print("前方发现怪物，停下")
			break
		var next_step = hero.next_step_to(_walk_target)   # 8 方向、只走已探索格
		if next_step == Vector2i(-1, -1):
			break   # 无可走路径
		if _walk_monster == null and TurnManager.get_monster_at(next_step) != null:
			break   # 去路被怪占据：不硬撞，停下等玩家决策
		if not hero.move_step(next_step):
			break
		update_fov()
		# 英雄起滑后立刻推进回合：怪物同帧并行起滑，next 末尾统一等一次滑动收尾
		await TurnManager.next()
	auto_walking = false
	_walk_target = Vector2i(-1, -1)
	_walk_monster = null
	hero.end_continuous_move()   # 会话结束：回静止动画（仍在滑则交 _process 收尾）

# 当前可见怪（实例 id 集合）
func _visible_monster_ids() -> Dictionary:
	var ids := {}
	for mob in TurnManager.monsters:
		if not is_instance_valid(mob):
			continue
		var c = mob.grid_pos
		if c.x >= 0 and c.x < LevelManager.MAP_WIDTH and c.y >= 0 and c.y < LevelManager.MAP_HEIGHT \
				and hero.FOV[c.y][c.x]:
			ids[mob.get_instance_id()] = true
	return ids

func _has_new_visible_monster() -> bool:
	for id in _visible_monster_ids():
		if not _walk_seen.has(id):
			return true
	return false

# ---------- 鼠标坐标 ----------
func get_cell_from_mouse_pos() -> Vector2i:
	var mouse_pos = get_global_mouse_position()
	var local_pos = bedrock_layer.to_local(mouse_pos)
	var tile_pos = bedrock_layer.local_to_map(local_pos)
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
	item_node.position = bedrock_layer.map_to_local(cell)
	item_node.item_data = item_data
	item_node.z_index = ITEM_Z   # 在角色之下、地面瓦片之上
	add_child(item_node)
	items_on_floor.append(item_node)

func is_item_on_cell(cell: Vector2i) -> bool:
	for item_node in items_on_floor:
		if item_node.grid_pos == cell:
			return true
	return false

func try_collect(actor: Char) -> bool:
	for i in range(items_on_floor.size() - 1, -1, -1):
		var item_node = items_on_floor[i]
		if item_node.grid_pos == actor.grid_pos:
			if item_node.interact(actor):
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
# 进入背包选取模式，等玩家点选一件物品后返回；取消返回 null。
# 与 select_cell 同构：点选跨帧，无法同步返回，故本函数是协程，调用方必须 await。
# 只认背包（belongings 是装备槽，不属于"背包内的一件物品"）。取消走全局 Esc/右键。
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
	if auto_walking:
		_stop_auto_walk()
	if not is_player_turn():
		return false
	if item == null:
		return false
	is_animating = true   # 飞行期间挡输入，避免半途再次行动
	await _animate_throw(item, cell)
	create_floor_item(item, cell)
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
