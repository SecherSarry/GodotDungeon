extends Node2D

@onready var bedrock_layer = $Layers/BedrockLayer
@onready var water_layer = $Layers/WaterLayer
@onready var wall_layer = $Layers/WallLayer
@onready var fog_layer = $Layers/FogLayer
@onready var hero: Hero = preload("res://tscns/Hero.tscn").instantiate()
@onready var camera = $Camera2D
@onready var inventory_ui = $CanvasLayer/InventoryUI  # 背包UI
@onready var zoom_in_button = $CanvasLayer/Button      # 缩放放大按钮

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

# ---------- 地格选取 / 投掷 ----------
var _selector: TileSelector = null   # 通用选取器（投掷/施法等复用）
var _throw_index: int = -1           # 待投掷的背包物品下标

# 投掷流程结束通知（已落地=true / 被取消=false）。投掷要点格子、跨帧，
# 无法同步返回，故用一次性信号让 Item.execute 的 await 一直等到真正结束，
# 再由 Item 统一收尾（记账 + 推进回合），保证"一次玩家动作恰好推进一次回合"。
signal throw_resolved(acted: bool)
var _throw_pending := false

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
	Bag.init_starting_inventory()   # 新游戏开局给初始背包（幂等：先清后灌）
	inventory_ui.game_scene = self
	zoom_in_button.pressed.connect(_on_zoom_in_button_pressed)   # 缩放放大按钮


	init_layers()

	# 地格选取器：在 Layers 之后加入，才能盖住迷雾层绘制高亮（投掷/施法等复用）
	_selector = TileSelector.new()
	_selector.scene = self
	add_child(_selector)
	_selector.cursor_changed.connect(_on_selector_cursor_changed)
	_selector.cancelled.connect(_on_selector_cancelled)

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
	
	var text = "HP: " + str(hero.HP) + "/" + str(hero.maxHP) + "\n"
	text += "STR: " + str(hero.STR) + "\n"
	text += "lvl: " + str(hero.lvl) + "\n"
	text += "exp: " + str(hero.exp)+ "/" + str(hero.max_exp()) + "\n"
	text += "当前武器: " + hero.weapon.item_name + "(" + str(hero.weapon.min()) + "-" + str(hero.weapon.max()) + ")\n"
	text += "精准: " + str(hero.attack_skill) + " 闪避：" + str(hero.defense_skill) + "\n"
	$CanvasLayer/Label.text = text

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
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			if MapManager.map_data[y][x] == MapManager.WATER:
				water_layer.draw_cell(Vector2i(x, y), 0)
				water_cells.append(Vector2i(x, y))
	if water_cells.is_empty():
		return
	water_layer.set_cells_terrain_connect(water_cells, 0, 1)
	
func init_bedrock_layer():
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			var tile
			if pos == MapManager.hero_spawn:
				tile = TILE_ENTRENCE   # 入口（上一层）
			elif pos == MapManager.exit_cell:
				tile = TILE_EXIT       # 出口（下一层）
			else:
				match MapManager.map_data[y][x]:
					MapManager.CHASM:	tile = TILE_CHASM
					MapManager.WATER:	tile = TILE_FLOOR
					MapManager.FLOOR:	tile = TILE_FLOOR
					MapManager.GRASS:	tile = TILE_GRASS
					_:					tile = TILE_CHASM
			bedrock_layer.set_cell(pos, 0, tile)

func init_wall_layer():
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			var tile = get_wall_tile(x, y)
			if tile != Vector2i(-1, -1): wall_layer.set_cell(pos, 0, tile)
	pass

func get_wall_tile(x: int, y: int) -> Vector2i:
	var mask = 0
	# 检测自己
	var c = MapManager.map_data[y][x] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]
	
	# 检测左
	var l = x > 0 and MapManager.map_data[y][x-1] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]

	# 检测左下
	var ld = x > 0 and y < MapManager.MAP_HEIGHT - 1 and MapManager.map_data[y+1][x-1] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]

	# 检测下
	var d = y < MapManager.MAP_HEIGHT - 1 and MapManager.map_data[y+1][x] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]

	# 检测右下
	var dr = x < MapManager.MAP_WIDTH - 1 and y < MapManager.MAP_HEIGHT - 1 and MapManager.map_data[y+1][x+1] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]

	# 检测右
	var r = x < MapManager.MAP_WIDTH - 1 and MapManager.map_data[y][x+1] in [MapManager.WALL, MapManager.DOOR, MapManager.OPEN_DOOR, MapManager.LOCKED_DOOR, MapManager.CHASM]

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
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			fog_layer.set_cell(Vector2i(x, y), 0, TILE_FOG_UNSEEN)

func refresh_foglayer():
	for y in MapManager.MAP_HEIGHT:
		for x in MapManager.MAP_WIDTH:
			var pos = Vector2i(x, y)
			if MapManager.explored[y][x]:
				if MapManager.visiblity[y][x]:
					fog_layer.set_cell(pos, -1)
				else:
					fog_layer.set_cell(pos, 0, TILE_FOG_EXPLORED)
			else:
				fog_layer.set_cell(pos, 0, TILE_FOG_UNSEEN)

func update_fov():
	MapManager.update_fov(hero.grid_pos)
	refresh_foglayer()
	update_monsters_visibility()
	update_items_visibility()
	
func update_monsters_visibility():
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			var cell = mob.grid_pos
			# 检查坐标是否在有效范围内
			if cell.x >= 0 and cell.x < MapManager.MAP_WIDTH and cell.y >= 0 and cell.y < MapManager.MAP_HEIGHT:
				mob.visible = MapManager.visiblity[cell.y][cell.x]
			else:
				mob.visible = false
				
func update_items_visibility():
	for item_node in items_on_floor:
		if is_instance_valid(item_node):
			var cell = item_node.grid_pos
			if cell.x >= 0 and cell.x < MapManager.MAP_WIDTH and cell.y >= 0 and cell.y < MapManager.MAP_HEIGHT:
				item_node.visible = MapManager.visiblity[cell.y][cell.x]
			else:
				item_node.visible = false
				
# ---------- 放置英雄：实例化 Hero.tscn 后摆到 MapManager 决策的出生点并加入场景树 ----------
func render_hero():
	hero.grid_pos = MapManager.hero_spawn
	hero.position = bedrock_layer.map_to_local(hero.grid_pos)
	hero.game_scene = self
	hero.z_index = CHAR_Z   # 角色压在地面物品之上
	add_child(hero)   # 触发 Hero._ready（init_hero 初始化属性）；摆位后才进树，无闪现
	hero.play_anim("idle")   # 生成即静止动画
	TurnManager.register_actor(hero)

# ---------- 渲染怪物：按 MapManager.monster_placements 实例化怪物节点 ----------
func render_monsters():
	for placement in MapManager.monster_placements:
		var mob = preload("res://tscns/Mob.tscn").instantiate()
		mob.data = placement["data"]   # 数值/外观在 _ready 前注入
		mob.grid_pos = placement["cell"]
		mob.position = bedrock_layer.map_to_local(placement["cell"])
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
		var monster = TurnManager.get_monster_at(cell)
		if monster != null and chebyshev <= hero.weapon.RCH:
			try_hero_action(cell)      # 射程内的怪：直接攻击
		else:
			_start_auto_walk(cell)     # 远处（无论有无怪）：寻路过去

func _on_zoom_requested(factor: float):
	zoom_map(factor)

# 缩放放大按钮：按下即放大 0.2
func _on_zoom_in_button_pressed():
	zoom_map(InputHub.ZOOM_STEP)
	hero.weapon.do_unequip(hero)

# ---------- 玩家动作：判定合法性后把行动交给 hero（角色自管动画），GameScene 只负责编排与回合推进 ----------
func try_hero_action(target_cell: Vector2i):
	if not is_player_turn():
		return
	var offset = target_cell - hero.grid_pos

	is_animating = true
	var acted = false
	if offset == Vector2i.ZERO:
		# 脚下：拾取优先；无物品时再看是否站在入口/出口上换层
		acted = try_collect(hero)
		if acted:
			hero.spend_time(Char.DUR_PICKUP)
		elif hero.grid_pos == MapManager.hero_spawn:
			is_animating = false
			_change_floor(-1)   # 站在入口 → 上一层
			return
		elif hero.grid_pos == MapManager.exit_cell:
			is_animating = false
			_change_floor(1)    # 站在出口 → 下一层
			return
	else:
		var monster = TurnManager.get_monster_at(target_cell)
		if monster != null and max(abs(offset.x), abs(offset.y)) <= hero.weapon.RCH:
			await hero.attack(monster)
			acted = true
		elif max(abs(offset.x), abs(offset.y)) == 1:
			acted = hero.move_step(target_cell)   # 同步即时提交 + 启动自滑
			# 不在此单独等待：下方 advance 末尾会等英雄与怪物一起滑完（并行、无停顿）
	is_animating = false

	if acted:
		update_fov()
		await TurnManager.advance()

# ---------- 换层 ----------
# 站入口 → floor_delta=-1（上一层）；站出口 → +1（下一层）。到顶则拒绝。
# 离开前先把本层快照进 MapManager.floor_cache（含迷雾记忆与剩余怪/掉落物），
# 返回时原样载入，因此来回跑不会重掷地图。不消耗回合。
func _change_floor(floor_delta: int) -> void:
	var target_depth = MapManager.current_depth + floor_delta
	if target_depth < 1:
		print("已经是地牢顶层，无法再向上")
		return
	MapManager.save_floor(MapManager.current_depth, _capture_entities())
	var restored = MapManager.enter_floor(target_depth)
	# 落点：下楼/新层 → 该层入口；上楼回访 → 该层出口（即当初下来所走的台阶），进出对称。
	var landing = MapManager.exit_cell if floor_delta < 0 else MapManager.hero_spawn
	_rebuild_level(landing, restored)
	print("进入第 ", target_depth, " 层", "（返回）" if restored else "")

# 采集当前层活实体 → 快照（怪的位置与血量、地面物品）
func _capture_entities() -> Dictionary:
	var monsters := []
	for mob in TurnManager.monsters:
		if is_instance_valid(mob):
			monsters.append({ "cell": mob.grid_pos, "hp": mob.HP, "max_hp": mob.maxHP, "data": mob.data })
	var items := []
	for node in items_on_floor:
		if is_instance_valid(node):
			items.append({ "cell": node.grid_pos, "item": node.item_data })
	return { "monsters": monsters, "items": items }

func _rebuild_level(landing: Vector2i, restored: bool) -> void:
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
	# 英雄摆到落点，并清空时间轴（玩家先动）
	hero.snap_to(landing)
	hero.next_action_time = 0.0
	if restored:
		var ents = MapManager.get_floor_entities(MapManager.current_depth)
		_render_monsters_from(ents.get("monsters", []))
		_render_items_from(ents.get("items", []))
	else:
		render_monsters()
		render_items()
	camera.global_position = hero.global_position
	update_fov()
	inventory_ui.refresh()

# 从快照重建怪（位置 + 血量 + 怪种）；HP 在 add_child 之后设，避免被 _ready 的初始值覆盖
func _render_monsters_from(snapshot: Array) -> void:
	for m in snapshot:
		var mob = preload("res://tscns/Mob.tscn").instantiate()
		mob.data = m["data"]   # 先注入怪种，_ready 才知道配哪些数值/外观
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
		create_floor_item(e["item"], e["cell"])

# ---------- 自动行走：沿已探索最短路径逐格走近；途中看到新出现的怪立即暂停 ----------
# 单一驱动循环：每步重算路径（怪会移动，旧路径随时失效），经主角 move_step 与 TurnManager.advance 走一回合。
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
			if max(abs(hero.grid_pos.x - _walk_target.x), abs(hero.grid_pos.y - _walk_target.y)) <= hero.weapon.RCH:
				await hero.attack(_walk_monster)
				update_fov()
				await TurnManager.advance()
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
		# 英雄起滑后立刻推进回合：怪物同帧并行起滑，advance 末尾统一等一次滑动收尾
		await TurnManager.advance()
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
		if c.x >= 0 and c.x < MapManager.MAP_WIDTH and c.y >= 0 and c.y < MapManager.MAP_HEIGHT \
				and MapManager.visiblity[c.y][c.x]:
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
	if tile_pos.x >= 0 and tile_pos.x < MapManager.MAP_WIDTH and tile_pos.y >= 0 and tile_pos.y < MapManager.MAP_HEIGHT:
		return tile_pos
	return Vector2i(-1, -1)

# ---------- 物品系统 ----------
# 渲染地面物品：按 MapManager.item_placements 实例化 Item 节点（含同格合并逻辑沿用 create_floor_item）
func render_items():
	for placement in MapManager.item_placements:
		create_floor_item(placement["item"], placement["cell"])

func create_floor_item(item_data: Item, cell: Vector2i):
	for item_node in items_on_floor:
		if item_node.grid_pos == cell and item_node.item_data.item_name == item_data.item_name:
			item_node.item_data.quantity += item_data.quantity
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
			if item_node.collect(actor):
				items_on_floor.remove_at(i)
				item_node.queue_free()
				return true
	print("此处没有物品或背包已满")
	return false

# 丢弃 = 投掷：进入地格选取，选一个格子丢过去（可投向未探索区域；撞墙则落在墙前）。
# 纯摆位服务：只取出→飞行→落地→刷可见性；扣背包的"消耗"与记账/推进回合由 Item 收尾。
# 因选格跨帧，本函数 await 到 throw_resolved 才返回；返回是否真的扔出去了（取消=false）。
func drop_item_from_inventory(index: int) -> bool:
	if auto_walking:
		_stop_auto_walk()
	if not is_player_turn():
		return false
	if index < 0 or index >= Bag.get_inventory().size():
		return false
	_throw_index = index
	_throw_pending = true
	_selector.begin(hero.grid_pos, _on_throw_target_chosen)
	_refresh_throw_preview(_selector.cursor)
	var acted: bool = await throw_resolved
	return acted

# 光标移动：更新落点预览与"可否扔到"（可扔到 → 光标变绿）
func _on_selector_cursor_changed(cell: Vector2i) -> void:
	_refresh_throw_preview(cell)

# 落点可达 = 沿直线无遮挡（= 实际落点即光标格）→ 光标绿；被墙挡 → 黄。
# 未探索格一律不显绿（看不见的暗格不冒充"已确定落点"）：落点在未探索处则不画绿框，
# 光标落在未探索格也不算"有效"。
func _refresh_throw_preview(cell: Vector2i) -> void:
	var landing = MapManager.throw_landing_cell(hero.grid_pos, cell)
	_selector.set_secondary(landing if MapManager.is_explored(landing) else Vector2i(-1, -1))
	_selector.set_cursor_valid(landing == cell and MapManager.is_explored(cell))

func _on_selector_cancelled() -> void:
	_throw_index = -1
	if _throw_pending:
		_throw_pending = false
		throw_resolved.emit(false)   # 取消：通知等待方"没扔成"，不记时、不推进回合

func _on_throw_target_chosen(cell: Vector2i) -> void:
	var index = _throw_index
	_throw_index = -1
	_do_throw(index, cell)

func _do_throw(index: int, target_cell: Vector2i) -> void:
	if index < 0 or index >= Bag.get_inventory().size():
		_throw_pending = false
		throw_resolved.emit(false)
		return
	var item = Bag.remove_one(index)   # 每次只扔一个
	if item == null:
		_throw_pending = false
		throw_resolved.emit(false)
		return
	var landing = MapManager.throw_landing_cell(hero.grid_pos, target_cell)
	is_animating = true   # 飞行期间挡输入，避免半途再次行动
	await _animate_throw(item, landing)
	create_floor_item(item, landing)
	update_items_visibility()   # 落点可能未探索：立即按视野决定可见性，避免闪现
	is_animating = false
	print("投掷：", item.item_name, " 落于 ", landing)
	_throw_pending = false
	throw_resolved.emit(true)

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

# 放下：把选中物品整摞放在英雄本格（无需选格，不消耗投掷距离）。纯摆位服务，
# 记账/推进回合由 Item 收尾。返回是否真的放下了。
func drop_all_from_inventory(index: int) -> bool:
	if _selector.active:
		_selector.cancel()   # 关掉可能开着的投掷选取
	if auto_walking:
		_stop_auto_walk()
	if not is_player_turn():
		return false
	if index < 0 or index >= Bag.get_inventory().size():
		return false
	var item = Bag.remove_item(index)   # 整摞取出
	if item == null:
		return false
	create_floor_item(item, hero.grid_pos)
	update_items_visibility()
	print("放下：", item.item_name, " x", item.quantity)
	return true

func _on_inventory_updated():
	inventory_ui.refresh()
