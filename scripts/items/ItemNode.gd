extends Node2D

var item_data: Item = null   # 存储 Item 资源
var grid_pos: Vector2i = Vector2i.ZERO

# 节点层薄壳：把 actor 递给 Item 数据层按类型分发各物品的拾取事件
func do_pickup(hero: Hero) -> bool:
	if item_data == null:
		return false
	return item_data.do_pickup(hero)
