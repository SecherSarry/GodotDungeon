extends Control

@onready var button_list = $Panel/ButtonList
@onready var item_list = $Panel/ItemList

var game_scene: Node = null
var selected_index: int = -1

func _ready():
	item_list.item_selected.connect(_on_item_selected)
	# 初始不隐藏，常驻显示

func open_inventory():
	refresh()
	show()   # 确保可见

func refresh():
	item_list.clear()
	var items = Bag.get_inventory()
	for i in range(items.size()):
		var item = items[i]
		var text = item.item_name
		if item.stackable and item.quantity > 1:
			text += " x" + str(item.quantity)
		item_list.add_item(text)
	selected_index = -1
	clear_buttons()

# ---------- 动作按钮：选中物品 → 读 item.actions() 生成按钮 → 按下调 item.execute(action) ----------
func clear_buttons():
	for child in button_list.get_children():
		button_list.remove_child(child)
		child.queue_free()

func _on_item_selected(index: int):
	selected_index = index
	_build_buttons(index)

func _build_buttons(index: int):
	clear_buttons()
	var items = Bag.get_inventory()
	if index < 0 or index >= items.size():
		return
	if game_scene == null:
		return
	var hero = game_scene.get("hero")   # 动态取英雄（game_scene 是 Node，避免静态成员解析）
	if hero == null:
		return
	var item = items[index]
	for action in item.actions(hero):
		var btn = Button.new()
		btn.text = action
		btn.pressed.connect(_on_action_pressed.bind(index, action))
		button_list.add_child(btn)

func _on_action_pressed(index: int, action: String):
	var items = Bag.get_inventory()
	if index < 0 or index >= items.size():
		return
	if game_scene == null:
		return
	var hero = game_scene.get("hero")
	if hero == null:
		return
	await items[index].execute(hero, action)
	refresh()   # 动作可能改变背包（用量/移除/换装），重建列表与按钮
