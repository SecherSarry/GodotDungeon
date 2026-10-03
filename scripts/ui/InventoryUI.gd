extends Control

@onready var button_list = $Panel/ButtonList
@onready var item_list = $Panel/ItemList
@onready var belongings_list = $Panel/BelongingsList

var game_scene: Node = null

# 当前选中项：来源 + 下标。两列表共享一套动作按钮，故选中互斥——
# 选背包项即清掉装备项的高亮，反之亦然。""=无选中。
var selected_source: String = ""
var selected_index: int = -1

# 选物模式：由 GameScene.select_item 开启。开着时点物品不再建动作按钮，
# 而是直接把物品交回（item_chosen）；Esc/右键取消（selection_cancelled）。
# 背包与装备栏两边都认（原版 WndBag 的格子本就含 5 个装备槽）。
var selecting: bool = false

# 选物模式的结果通道，与 TileSelector 的 confirmed/cancelled 同构，由 GameScene 桥接。
signal item_chosen(item: Item)
signal selection_cancelled

func _ready():
	item_list.item_selected.connect(_on_bag_selected)
	belongings_list.item_selected.connect(_on_equip_selected)
	InputHub.cancel_requested.connect(_on_cancel)
	# 初始不隐藏，常驻显示

func open_inventory():
	refresh()
	show()   # 确保可见

# 进入选物模式：refresh 内含 _reset_selection（清高亮与动作按钮并重列），先设标志再刷。
func begin_select():
	selecting = true
	refresh()
	show()

# 取消选物（Esc/右键，或调用方主动关掉上一次未完成的选取）
func cancel_select():
	if not selecting:
		return
	selecting = false
	_reset_selection()
	selection_cancelled.emit()

func _on_cancel():
	cancel_select()

func refresh():
	# 背包与装备槽都从 hero.belongings 取（SPD Belongings 全收）。game_scene/hero 尚未就绪时直接跳过。
	if game_scene == null or game_scene.hero == null:
		return
	item_list.clear()
	for item in game_scene.hero.backpack.items:
		item_list.add_item(_label(item))

	belongings_list.clear()
	var slots: Array = game_scene.hero.belongings.slots()
	for i in slots.size():
		belongings_list.add_item(_label(slots[i], i))

	_reset_selection()

func _label(item: Item, slot: int = -1) -> String:
	if item == null:
		return "无"
	var text = item.title()
	return text

# ---------- 选中：两列表互斥 ----------
func _deselect_all(list: ItemList):
	for i in list.item_count:
		list.deselect(i)

func _reset_selection():
	selected_source = ""
	selected_index = -1
	_deselect_all(item_list)
	_deselect_all(belongings_list)
	clear_buttons()

func _on_bag_selected(index: int):
	_deselect_all(belongings_list)
	selected_source = "bag"
	selected_index = index
	if selecting:
		selecting = false   # 选中即结束选取，交回物品；不建动作按钮
		item_chosen.emit(_current_item())
		return
	_build_buttons(_current_item())

func _on_equip_selected(index: int):
	_deselect_all(item_list)
	selected_source = "equip"
	selected_index = index
	var item = _current_item()
	if item == null:
		# 空槽（标签"无"）不是物品：正常模式下没有可执行的动作可建；
		# 选取模式下更不能往下走——item_chosen 递 null 会被 GameScene 解读成"取消"。
		# 清掉这次高亮即可。（原版对应物是 Placeholder，itemSelectable 一律判否，同样不可选。）
		_reset_selection()
		return
	if selecting:
		selecting = false   # 装备槽与背包同权：原版 WndBag 把 5 个装备槽摆在格子最前，照样可点选
		item_chosen.emit(item)
		return
	_build_buttons(item)

# 当前选中项的实际 Item（按来源取）；无效返回 null
func _current_item() -> Item:
	if game_scene == null:
		return null
	var hero = game_scene.get("hero")
	if hero == null or selected_index < 0:
		return null
	var items: Array = hero.backpack.items if selected_source == "bag" else hero.belongings.slots()
	if selected_index >= items.size():
		return null
	return items[selected_index]

# ---------- 动作按钮：读 item.actions() 生成按钮 → 按下调 item.execute(action) ----------
func clear_buttons():
	for child in button_list.get_children():
		button_list.remove_child(child)
		child.queue_free()

func _build_buttons(item: Item):
	clear_buttons()
	if item == null:
		return
	var hero = game_scene.get("hero")   # 动态取英雄（game_scene 是 Node，避免静态成员解析）
	if hero == null:
		return
	for action in item.actions(hero):
		var btn = Button.new()
		btn.text = action
		btn.pressed.connect(_on_action_pressed.bind(action))
		button_list.add_child(btn)

func _on_action_pressed(action: String):
	var item = _current_item()
	if item == null or game_scene == null:
		return
	var hero = game_scene.get("hero")
	if hero == null:
		return
	await item.execute(hero, action)
	await hero.on_operate_complete()   # 放锁 + 驱动调度器；等它走完再刷列表，否则列表会在怪行动中途重建
	refresh()   # 动作可能改变背包/装备（用量/移除/换装），重建列表与按钮
