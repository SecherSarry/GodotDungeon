extends Resource
class_name SpawnTable

# 全部已知怪种。生成器按深度筛选后加权随机抽取。
# entries 故意不标类型（Array 而非 Array[MonsterData]）——手写 .tres 时泛型数组序列化易出错，
# 而这里只是人工维护的一份清单，运行时取用时按 MonsterData 使用。
@export var entries: Array = []

# 按深度筛选出可出没的怪，再按 weight 加权随机抽一种；无可用返回 null。
func pick(depth: int, rng: RandomNumberGenerator) -> MonsterData:
	var pool: Array = []
	var total := 0.0
	for e in entries:
		if e is MonsterData and depth >= e.min_depth and depth <= e.max_depth:
			var w := maxf(e.weight, 0.0)
			if w > 0.0:
				pool.append(e)
				total += w
	if pool.is_empty():
		return null
	var roll := rng.randf() * total
	for e in pool:
		roll -= maxf(e.weight, 0.0)
		if roll <= 0.0:
			return e
	return pool[pool.size() - 1]
