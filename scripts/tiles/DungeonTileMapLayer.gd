extends TileMapLayer
class_name DungeonTileMapLayer

func update_all() -> void:
	for y in LevelManager.MAP_HEIGHT:
		for x in LevelManager.MAP_WIDTH:
			var pos := Vector2i(x, y)
			var tile := get_tile_visual(pos, LevelManager.level.map_data[y][x], false)
			if tile != Vector2i(-1, -1):
				set_cell(pos, 0, tile)

func get_tile_visual(pos: Vector2i, tile: int, flat: bool) -> Vector2i:
	return Vector2i(-1, -1)

func _terrain_at(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= LevelManager.MAP_WIDTH:
		return -1
	if pos.y < 0 or pos.y >= LevelManager.MAP_HEIGHT:
		return -1
	return LevelManager.level.map_data[pos.y][pos.x]
