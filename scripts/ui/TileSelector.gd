extends Node2D
class_name TileSelector

# 通用地格选取模式（封装）：进入后跟随鼠标高亮当前格，左键确认、右键/Esc 取消。
# 不关心"选了做什么"——确认时把选中格交给 begin() 传入的回调，因此可复用于投掷、
# 施法、指定目标等任意需要"点一个格子"的场合。
# 可选的 secondary 高亮：调用方（如投掷预览）用 set_secondary 标示第二个格子（落点等）。
# 输入仍走 InputHub 信号，由本节点自行消费；宿主场景在 active 时应让开同信号。

signal confirmed(cell: Vector2i)
signal cancelled
signal cursor_changed(cell: Vector2i)

const BORDER_WIDTH := 2.0                              # 高亮框边框厚度（像素）

const COLOR_CURSOR := Color(1.0, 0.95, 0.2, 0.9)      # 光标格：黄（不可达）
const COLOR_CURSOR_OK := Color(0.3, 1.0, 0.4, 0.9)    # 光标格：绿（可达）
const COLOR_SECONDARY := Color(0.3, 1.0, 0.4, 0.9)    # 第二格（实际落点）：绿

var active: bool = false
var cursor: Vector2i = Vector2i.ZERO
var cursor_valid: bool = false   # 光标格是否为"有效目标"（如可扔到）→ 决定黄/绿
var secondary: Vector2i = Vector2i(-1, -1)
var scene: Node2D = null                    # 提供 cell_to_world / get_cell_from_mouse_pos
var _on_confirm: Callable = Callable()

func _ready() -> void:
	visible = false
	InputHub.map_hover.connect(_on_hover)
	InputHub.map_click_requested.connect(_on_click)
	InputHub.cancel_requested.connect(_on_cancel)

# 进入选择模式：origin 为初始光标格；on_confirm 在左键确认时被调用（参数=选中格）
func begin(origin: Vector2i, on_confirm: Callable) -> void:
	cursor = origin
	secondary = Vector2i(-1, -1)
	_on_confirm = on_confirm
	active = true
	visible = true
	_update_cursor_from_mouse()
	queue_redraw()

func cancel() -> void:
	if not active:
		return
	active = false
	visible = false
	queue_redraw()
	cancelled.emit()

# 设置第二高亮格（如投掷落点预览）；传 (-1,-1) 清除
func set_secondary(cell: Vector2i) -> void:
	if secondary == cell:
		return
	secondary = cell
	queue_redraw()

# 标记当前光标格是否"有效"（如可扔到）→ 绿色/黄色
func set_cursor_valid(valid: bool) -> void:
	if cursor_valid == valid:
		return
	cursor_valid = valid
	queue_redraw()

func _on_hover() -> void:
	if active:
		_update_cursor_from_mouse()

func _on_click() -> void:
	if not active:
		return
	var cell := Vector2i(-1, -1)
	if scene != null:
		cell = scene.get_cell_from_mouse_pos()
	if cell == Vector2i(-1, -1):
		return   # 点到地图外：忽略
	var cb = _on_confirm
	active = false
	visible = false
	queue_redraw()
	if cb.is_valid():
		cb.call(cell)
	confirmed.emit(cell)

func _on_cancel() -> void:
	if active:
		cancel()

func _update_cursor_from_mouse() -> void:
	if scene == null:
		return
	var c = scene.get_cell_from_mouse_pos()
	if c == Vector2i(-1, -1) or c == cursor:
		return
	cursor = c
	queue_redraw()
	cursor_changed.emit(cursor)

func _draw() -> void:
	if not active or scene == null:
		return
	_draw_cell(cursor, COLOR_CURSOR_OK if cursor_valid else COLOR_CURSOR)
	# 实际落点始终画绿（被墙挡住时它与光标不同格，两色并存：黄光标 + 绿落点）
	if secondary != Vector2i(-1, -1) and secondary != cursor:
		_draw_cell(secondary, COLOR_SECONDARY)

func _draw_cell(cell: Vector2i, color: Color) -> void:
	var center: Vector2 = scene.cell_to_world(cell)
	# 用图块自身像素尺寸（严格 = 一格 16×16），取不到时退回相邻格间距
	var size: Vector2
	if scene.has_method("tile_pixel_size"):
		size = scene.tile_pixel_size()
	else:
		size = Vector2(
			abs(scene.cell_to_world(cell + Vector2i(1, 0)).x - center.x),
			abs(scene.cell_to_world(cell + Vector2i(0, 1)).y - center.y))
	# 描边以线宽中线为基准，会向内外各溢出半个线宽；把矩形内缩半个线宽，
	# 使外沿恰好落在 16×16 上、边框厚 2px。
	var half := BORDER_WIDTH * 0.5
	draw_rect(Rect2(center - size * 0.5 + Vector2(half, half), size - Vector2(BORDER_WIDTH, BORDER_WIDTH)), color, false, BORDER_WIDTH)
