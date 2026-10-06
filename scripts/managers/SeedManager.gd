extends Node

const TOTAL_SEEDS := 1_000_000_000
# LevelManager.gd


## 新一局的主种子（GameState.seed 的来源）。对应 SPD 的 DungeonSeed.randomSeed()：
## 那边是在 [0, TOTAL_SEEDS) 里掷到"不含元音字母"的 code 为止；本工程还没有 base26 的
## 种子码展示，只求"每局不同"，故直接掷一个 64 位量。Godot 的 randi() 是 32 位，拼两条凑宽。
func new_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return (rng.randi() << 32) | rng.randi()


## 从主种子派生指定深度的子种子
func seed_for_depth(master_seed: int, depth: int, branch: int = 0) -> int:
	var look_ahead := depth + 30 * branch
	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed
	for i in look_ahead:
		rng.randi()
	return rng.randi()


## 当前深度的种子
func seed_cur_depth() -> int:
	return seed_for_depth(GameState.seed, GameState.depth, GameState.branch)


## 系统隔离：不同系统用不同偏移
func level_seed(depth: int) -> int:
	return seed_for_depth(GameState.seed, depth)

func loot_seed(depth: int) -> int:
	return seed_for_depth(GameState.seed + 1000, depth)

func mob_seed(depth: int) -> int:
	return seed_for_depth(GameState.seed + 2000, depth)

func shop_seed(depth: int) -> int:
	return seed_for_depth(GameState.seed + 3000, depth)
