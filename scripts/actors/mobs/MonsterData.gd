extends Resource
class_name MonsterData

# 一种怪 = 一个 MonsterData 资源（.tres）。加怪只需加数据文件，不必写代码、不必建场景。
# 需要独有 AI/技能时再另挂脚本（后续逃生口），纯数值差异的怪永远不进代码。

@export var id: String = ""
@export var display_name: String = "未知怪物"

@export_group("属性")
@export var max_hp: int = 8
@export var attack_skill: int = 8     # 命中检定攻方值
@export var defense_skill: int = 2    # 命中检定守方值
@export var damage_min: int = 1
@export var damage_max: int = 4
@export var dr: int = 0               # 固定减伤
@export var base_speed: float = 1.0   # 时间轴调度速度（越大单位时间行动越频繁）

@export_group("出没（供 SpawnTable 按深度抽取）")
@export var min_depth: int = 1
@export var max_depth: int = 999
@export var weight: float = 1.0

@export_group("表现")
@export var frames: SpriteFrames = null
@export var rest_anim: String = "run"   # 静止时播放的动画名
