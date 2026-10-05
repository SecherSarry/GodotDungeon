extends Blob
class_name ToxicGas

# 毒气：每拍先按 Blob 的规则扩散（super._evolve），再对仍留在毒气格里的角色造成毒伤。
# 直译 SPD ToxicGas.java 的 evolve()：
#   int damage = 1 + Dungeon.scalingDepth()/5;   // 本工程 scalingDepth 即 GameState.depth
#   遍历 area，格上有 cur>0 且有角色就 ch.damage(damage, this)。
# 注意 super._evolve 写的是 off、不动 cur，故下面读 cur[cell] 读到的是这一拍之前的浓度——
# 与原版同序（原版 evolve 里 super.evolve() 之后同样读 cur）。
func _evolve() -> void:
	super._evolve()

	var damage := 1 + GameState.depth / 5
	var w := LevelManager.MAP_WIDTH

	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var cell := y * w + x
			if cur[cell] > 0:
				var ch = TurnManager.find_char(Vector2i(x, y))
				if ch != null:
					ch.damage(damage, self)
