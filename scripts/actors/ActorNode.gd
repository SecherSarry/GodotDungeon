extends Node2D

# 角色表现层：Hero.tscn / Mob.tscn 的根脚本。
# 与 Item 那条线同构：Item(Resource) + ItemNode(Node2D) ↔ Actor(Resource) + ActorNode(Node2D)。
# 数据（hp / time / grid_pos）在 actor_data 那份 Resource 上，本节点只管画面——
# 精灵、朝向、自滑插值、血条、一次性动画的播放与收尾。
#
# 不加 class_name：本类静态引用 Actor（actor_data 的类型），数据侧 Actor.sprite 则不写类型，
# 只保留"节点引用数据"这一个方向，避免 class_name 互相引用导致解析失败。
#
# 数据侧经 actor_data.sprite 调用本类：slide_to / snap_to / set_facing / play_anim /
# play_once / play_die / begin_continuous_move / end_continuous_move / is_moving / wait。
var actor_data: Char = null

# 自滑状态：移动时逻辑即时提交 grid（数据侧），视觉在此处用 _process 逐帧推进插值。
var _sliding := false
var _from_pos := Vector2.ZERO
var _to_pos := Vector2.ZERO
var _slide_t := 0.0

# 正在播一次性动画（attack/die，非循环、有人 await 它的 animation_finished）。
# 置位期间 _process 的滑行收尾不得用静止动画覆盖：否则"移动中起手攻击"会被
# 滑完那一帧切走，被切走的非循环动画不再发 animation_finished，await 永挂 → 回合锁死。
var _busy := false

# 连续移动会话：为真时滑步结束不回静止动画。多步行走（自动寻路等）由驱动方开启，
# 使跑步动画跨步连贯播放，而非每步 idle→run 从头重播。
var keep_moving_anim: bool = false

# 正在死亡演出：end_continuous_move 不得覆盖 die 动画。
var _dying := false

var anim_sprite: AnimatedSprite2D = null
var _hp_bar: ProgressBar = null

const MOVE_DURATION := 0.1   # 单格滑动时长（秒），逐帧插值推进

# 怪类 → 帧集。Mob.tscn 是通用场景、不自带帧集，用哪套由 actor_data 的实际类决定；
# 以后加新怪：写一份 assets/xxx_frames.tres，在这里加一行即可。
# 英雄不走这张表——Hero.tscn 自带 warrior 帧集，查不到就保留场景里那套。
const MONSTER_FRAMES := {
	"Rat": preload("res://assets/rat_frames.tres"),
}

func _ready() -> void:
	anim_sprite = get_sprite()
	_apply_frames()
	_hp_bar = get_node_or_null("ProgressBar")   # 英雄没有血条，可空
	if _hp_bar != null and actor_data != null:
		_hp_bar.max_value = actor_data.max_hp
	# 起播静止动画。.tscn 里没开 autoplay，故必须自己播一次；
	# 否则 AnimatedSprite2D 只显示默认动画的第 0 帧然后定格。
	play_anim(_rest_anim())

func get_sprite() -> AnimatedSprite2D:
	for child in get_children():
		if child is AnimatedSprite2D:
			return child
	return null

# 按 actor_data 的实际类套帧集（见 MONSTER_FRAMES）。
func _apply_frames() -> void:
	if anim_sprite == null:
		return
	var frames: SpriteFrames = MONSTER_FRAMES.get(_data_class_name(), null)
	if frames != null:
		anim_sprite.sprite_frames = frames

func _data_class_name() -> String:
	if actor_data == null or actor_data.get_script() == null:
		return ""
	return actor_data.get_script().get_global_name()

# ---------- 自滑驱动：仅在滑动时逐帧推进插值；到点回静止动画。多角色各自 _process → 天然并行 ----------
func _process(delta: float) -> void:
	if _hp_bar != null and actor_data != null:
		_hp_bar.value = actor_data.hp
		_hp_bar.visible = not (actor_data.hp == actor_data.max_hp or actor_data.hp == 0)
	if not _sliding:
		return
	_slide_t += delta
	var t := clampf(_slide_t / MOVE_DURATION, 0.0, 1.0)
	position = _from_pos.lerp(_to_pos, t)
	if t >= 1.0:
		_sliding = false
		if not _busy:
			play_anim(_rest_anim())   # 滑完回静止动画；连续移动中的抑制由 play_anim 内部规则处理

# 朝目标格开滑。起点取当前位置（可能正在滑，于是从半格处接续，不会回跳），
# 与旧 Char.walk_to 里 `_from_pos = position` 同义。
func slide_to(to_cell: Vector2i) -> void:
	_from_pos = position
	_to_pos = _cell_to_world(to_cell)
	_slide_t = 0.0
	_sliding = true
	play_anim("run")

# 瞬移到某格（换层/传送等）：取消残留滑动并直接摆位，避免插值把角色拽回旧位置。
func snap_to(cell: Vector2i) -> void:
	_sliding = false
	position = _cell_to_world(cell)

func is_moving() -> bool:
	return _sliding

# 格 → 世界像素。取位靠场景（map_to_local 认 tile_size 与层偏移），数据侧经 game_scene 转达。
func _cell_to_world(cell: Vector2i) -> Vector2:
	if actor_data != null and actor_data.game_scene != null:
		return actor_data.game_scene.cell_to_world(cell)
	return position

func set_facing(direction: Vector2i) -> void:
	if anim_sprite == null:
		return
	if direction.x < 0:
		anim_sprite.flip_h = true
	elif direction.x > 0:
		anim_sprite.flip_h = false

# ---------- 统一动画入口：所有动画播放都走这里 ----------
# 规则：
#  1. 该动画正在播放 → 不重播（连续移动时跑步动画不会每步从第 0 帧重新开始）
#  2. 连续移动会话中（keep_moving_anim）→ 静止动画不打断当前行走动画
#  3. 该动画不存在 → 忽略
func play_anim(anim_name: String) -> void:
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return
	if keep_moving_anim and anim_name == _rest_anim():
		return
	if anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	anim_sprite.play(anim_name)

# 播放一个一次性非循环动画（attack 等）并等它播完；期间置忙，防自滑收尾把它切走。
# 没有该动画则立即返回（不等待）。
func play_once(anim_name: String) -> void:
	if anim_sprite == null:
		return
	_busy = true
	play_anim(anim_name)
	if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation(anim_name):
		await anim_sprite.animation_finished
	_busy = false

# 死亡演出：置忙播 die 并等播完。是否释放节点由调用方决定（怪物自由、英雄留原地）。
func play_die() -> void:
	_dying = true
	if anim_sprite != null and anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("die"):
		_busy = true
		play_anim("die")
		await anim_sprite.animation_finished

func _rest_anim() -> String:
	return actor_data.rest_anim if actor_data != null else "idle"

# ---------- 连续移动会话（供自动行走等驱动方使用） ----------
func begin_continuous_move() -> void:
	keep_moving_anim = true

func end_continuous_move() -> void:
	keep_moving_anim = false
	# 停在原地即刻回静止动画；仍在滑则交给 _process 收尾；正在死亡则不覆盖 die 动画
	if not _sliding and not _dying:
		play_anim(_rest_anim())

# 等待一段真实时间。get_tree() 是节点 API、数据层拿不到，故计时统一走这里
# （供 Hero.wait_one_tick 用，语义与时长与旧的 get_tree().create_timer 完全一致）。
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
