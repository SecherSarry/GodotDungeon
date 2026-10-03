extends DungeonTileMapLayer


func get_tile_visual(pos: Vector2i, tile: int, flat: bool) -> Vector2i:
	# 1. 直接映射
	var visual = DungeonTileSheet.DIRECT_VISUALS.get(tile, DungeonTileSheet.NULL_TILE)
	if visual != DungeonTileSheet.NULL_TILE:
		return DungeonTileSheet.get_visual_with_alts(visual, pos)

	# 2. 深渊拼接
	if tile == Terrain.CHASM:
		return DungeonTileSheet.stitch_chasm_tile(_terrain_at(pos + Vector2i.UP))

	# 3. 非平铺模式：凸起地形
	if not flat:
		if DungeonTileSheet.door_tile(tile):
			return DungeonTileSheet.get_raised_door_tile(
				tile,
				_terrain_at(pos + Vector2i.DOWN)
			)

		if DungeonTileSheet.wall_stitcheable(tile):
			return DungeonTileSheet.get_raised_wall_tile(
				tile,
				pos,
				_terrain_at(pos + Vector2i.RIGHT),
				_terrain_at(pos + Vector2i.DOWN),
				_terrain_at(pos + Vector2i.LEFT),
			)

		match tile:
			Terrain.STATUE:
				return DungeonTileSheet.RAISED_STATUE
			Terrain.STATUE_SP:
				return DungeonTileSheet.RAISED_STATUE_SP
			Terrain.REGION_DECO:
				return DungeonTileSheet.RAISED_REGION_DECO
			Terrain.REGION_DECO_ALT:
				return DungeonTileSheet.RAISED_REGION_DECO_ALT
			Terrain.MINE_CRYSTAL:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.RAISED_MINE_CRYSTAL, pos)
			Terrain.MINE_BOULDER:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.RAISED_MINE_BOULDER, pos)
			Terrain.ALCHEMY:
				return DungeonTileSheet.RAISED_ALCHEMY_POT
			Terrain.BARRICADE:
				return DungeonTileSheet.RAISED_BARRICADE
			Terrain.HIGH_GRASS:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.RAISED_HIGH_GRASS, pos)
			Terrain.FURROWED_GRASS:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.RAISED_FURROWED_GRASS, pos)
			_:
				return DungeonTileSheet.NULL_TILE

	# 4. flat 回退
	return DungeonTileSheet.get_visual_with_alts(
		DungeonTileSheet.DIRECT_FLAT_VISUALS.get(tile, DungeonTileSheet.NULL_TILE),
		pos
	)


func _terrain_at(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= LevelManager.MAP_WIDTH:
		return -1
	if pos.y < 0 or pos.y >= LevelManager.MAP_HEIGHT:
		return -1
	return LevelManager.level.map_data[pos.y][pos.x]
