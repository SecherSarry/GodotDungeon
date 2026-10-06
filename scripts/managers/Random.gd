class_name Random
extends RefCounted

# ============================================================================
# 生成器栈 —— 直译 SPD com.watabou.utils.Random 的"随机流栈"。
#
# 为什么不直接用 Godot 的全局 randi()/randf()：全局那条流是进程级的、不受种子管。
# 原版整张图只用**一条受控流**：进一层时把"本层种子"压栈，该层所有随机取材都从
# 栈顶这条流取 —— 同一个种子 → 同一张图，可复现。
#
# push/pop 让某一段逻辑临时换一条**子流**：它消耗多少随机数都不影响上层主流，
# 主流的下一个值仍是它"本该"是的那一个。原版 RegularLevel.create 里那些
# pushGenerator(Random.Long())…popGenerator() 就是拿它把"身上的物品/元进度/天赋"
# 这类不该干扰地图的东西隔离出去。
#
# 与 SPD 的差别：栈底是 Godot 的 RandomNumberGenerator（PCG），不是 java.util.Random，
# 故"与官方逐值相同"做不到；本工程只要求"同种子 → 同世界"。用的时候把生成代码里的
# 全局 randf()/randi()/randi_range() 换成下面同名的 Random 版本即可（名字刻意对齐全局，
# 改起来是逐处替换）。
# ============================================================================

# 栈顶 = 当前在用的流。第 0 层是基底流，永不弹出（保证栈非空、任何时刻都有一条流可用）。
static var _generators: Array = []

# 取栈；空则先垫一条随机种子的基底流。
static func _gens() -> Array:
	if _generators.is_empty():
		var base := RandomNumberGenerator.new()
		base.randomize()
		_generators.push_back(base)
	return _generators

# 清空并重置回只有基底流。开新局、或生成中途出错栈被带歪时用。
static func reset() -> void:
	_generators.clear()
	_gens()

# 压入一条以 seed_value 为种的新流。进层时用：Random.push_generator(本层种子)。
static func push_generator(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scramble_seed(seed_value)
	_gens().push_back(rng)

# 压入一条随机种子的子流：隔离"不该干扰主流"的一段。用完记得 pop_generator()。
static func push_random_generator() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_gens().push_back(rng)

# 弹掉栈顶、回到上一层。基底流不可弹（否则栈空，后续无流可用）。
static func pop_generator() -> void:
	if _gens().size() <= 1:
		push_error("Random.pop_generator：基底生成器不可弹出")
		return
	_generators.pop_back()

static func top() -> RandomNumberGenerator:
	return _gens().back()

# ---------- 取材：一律从栈顶那条流取，名字对齐 Godot 全局函数，便于逐处替换 ----------
static func randi() -> int:
	return top().randi()

static func randi_range(from: int, to: int) -> int:
	return top().randi_range(from, to)

static func randf() -> float:
	return top().randf()

static func randf_range(from: float, to: float) -> float:
	return top().randf_range(from, to)

# ---------- 种子打散 ----------
# MX3 混淆（Jon Maiga, CC0），直译 SPD Random.scrambleSeed。相近的种子（如 depth 1 与 2
# 各自派生的）直接拿来当 RNG 种子，开头几个输出会高度相关；先打散一遍再喂进去。
static func scramble_seed(s: int) -> int:
	s ^= _ushr(s, 32)
	s *= -4710160504952957587   # = 0xbea225f9eb34556d，超出 int64 的十六进制字面量只能写成补码有符号值
	s ^= _ushr(s, 29)
	s *= -4710160504952957587   # = 0xbea225f9eb34556d，超出 int64 的十六进制字面量只能写成补码有符号值
	s ^= _ushr(s, 32)
	s *= -4710160504952957587   # = 0xbea225f9eb34556d，超出 int64 的十六进制字面量只能写成补码有符号值
	s ^= _ushr(s, 29)
	return s

# 逻辑右移（无符号）。GDScript 的 >> 对负数补符号位，这里把高 n 位抹成 0 补回。
static func _ushr(v: int, n: int) -> int:
	if v >= 0:
		return v >> n
	return (v >> n) & ((1 << (64 - n)) - 1)
