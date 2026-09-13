extends Node
# 全局输入中枢：检测玩家键鼠并把意图翻译成离散信号，交给游戏层消费。
# 约束：
#  - 只用 _unhandled_input，确保 UI(背包按钮等 Control)优先消费点击，地图命令走兜底。
#  - 不做回合 gate、不直接驱动角色：是否"轮到玩家行动"由接收方(GameScene)判定。

signal move_requested(direction: Vector2i)   # 方向意图（↑↓←→/WASD）
signal map_click_requested                     # 点击地图（坐标由场景读取鼠标位置解析）
signal map_hover                               # 鼠标在地图上移动（坐标由场景读取；用于选取地格高亮）
signal cancel_requested                        # 取消意图（右键/Esc）
signal zoom_requested(factor: float)           # 滚轮缩放

const ZOOM_STEP = 0.2   # 每触发一次缩放放大/缩小的幅度

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		map_hover.emit()
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_requested.emit(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_requested.emit(-ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				map_click_requested.emit()
			MOUSE_BUTTON_RIGHT:
				cancel_requested.emit()
			_:
				return
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return
		var direction := _key_to_direction(event.keycode)
		if direction != Vector2i.ZERO:
			move_requested.emit(direction)
			get_viewport().set_input_as_handled()

func _key_to_direction(keycode: Key) -> Vector2i:
	match keycode:
		KEY_UP, KEY_W:    return Vector2i(0, -1)
		KEY_DOWN, KEY_S:  return Vector2i(0, 1)
		KEY_LEFT, KEY_A:  return Vector2i(-1, 0)
		KEY_RIGHT, KEY_D: return Vector2i(1, 0)
		_:
			return Vector2i.ZERO
