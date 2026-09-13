extends Char
class_name Mob

# 怪物数值与外观全部来自 MonsterData 资源；生成/重建方在 add_child 之前注入 data。
# 加一种怪 = 加一个 .tres，不必写代码、不必建场景。
var data: MonsterData = null

func _ready():
	add_to_group("monster")
	if data != null:
		maxHP = data.max_hp
		base_speed = data.base_speed
		rest_anim = data.rest_anim
		if anim_sprite != null and data.frames != null:
			anim_sprite.sprite_frames = data.frames
	else:
		maxHP = 8   # 无数据时的兜底，供 Mob.tscn 在编辑器里单独预览
	HP = maxHP
	play_anim(rest_anim)

	$ProgressBar.max_value = maxHP

func _process(delta: float) -> void:
	super._process(delta)   # 继承基类滑动推进（移动自滑由 Char._process 驱动）

	$ProgressBar.value = HP
	if HP == maxHP or HP == 0:
		$ProgressBar.visible = false
	else:
		$ProgressBar.visible = true

# ---------- 战斗数值：读 data（无数据时退回基类默认） ----------
func get_attack_skill(target: Char) -> int:
	return data.attack_skill if data != null else 0

func get_defense_skill(target: Char) -> int:
	return data.defense_skill if data != null else 0

func damage_roll(actor: Char = self):
	return randi_range(data.damage_min, data.damage_max) if data != null else 1

func dr_roll() -> int:
	return data.dr if data != null else 0

# 返回本次行动的基础时长（>0 交调度器记账；攻击返回 0 因已在 attack 内自记账）
func act() -> float:
	if game_scene == null:
		return DUR_WAIT
	var hero = game_scene.get("hero")
	if hero == null:
		return DUR_WAIT

	var diff = hero.grid_pos - grid_pos
	if abs(diff.x) + abs(diff.y) == 1:
		await attack(hero)   # 动画/音效/结算/计时都在 attack 内自管
		return 0.0           # 已自行记账，返回 0 告知调度器不要再记一次

	var directions = []
	if diff.x != 0:
		directions.append(Vector2i(sign(diff.x), 0))
	if diff.y != 0:
		directions.append(Vector2i(0, sign(diff.y)))
	directions.shuffle()
	for d in directions:
		if walk_to(grid_pos + d):   # walk_to 即时提交 grid + 启动自滑；多怪各自 _process 并行滑
			return DUR_MOVE

	var random_dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	random_dirs.shuffle()
	for d in random_dirs:
		if walk_to(grid_pos + d):
			return DUR_MOVE
	return DUR_WAIT   # 全方向不通：也消耗时间，避免死循环
