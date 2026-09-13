extends Actor

var dialogue = "你好，冒险者！"   # 对话内容

func _ready():
	add_to_group("npc")

# NPC 可能不参与战斗，仅处理对话；当前不入调度队列，仍遵循统一接口返回基础时长
func act() -> float:
	# 如果玩家相邻，可以触发对话（由 GameScene 检测）
	# 我们可以在 GameScene 中检测到点击 NPC 时调用此函数
	return DUR_WAIT

# 交互函数
func interact():
	print(dialogue)
	# 可扩展弹窗显示对话
