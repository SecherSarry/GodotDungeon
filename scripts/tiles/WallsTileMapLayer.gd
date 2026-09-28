extends DungeonTileMapLayer

static var skip_cells: Dictionary = {}


func get_tile_visual(pos: Vector2i, tile: int, flat: bool) -> Vector2i:
	if flat:
		return DungeonTileSheet.NULL_TILE

	if DungeonTileSheet.wall_stitcheable(tile):
		var below := _terrain_at(pos + Vector2i.DOWN)

		if below != -1 and not DungeonTileSheet.wall_stitcheable(below):
			match below:
				Terrain.DOOR:         return DungeonTileSheet.DOOR_SIDEWAYS
				Terrain.LOCKED_DOOR:  return DungeonTileSheet.DOOR_SIDEWAYS_LOCKED
				Terrain.HERO_LKD_DR:  return DungeonTileSheet.DOOR_SIDEWAYS_LOCKED
				Terrain.CRYSTAL_DOOR: return DungeonTileSheet.DOOR_SIDEWAYS_CRYSTAL
				Terrain.OPEN_DOOR:    return DungeonTileSheet.NULL_TILE
		else:
			return DungeonTileSheet.stitch_internal_wall_tile(
				tile,
				_terrain_at(pos + Vector2i.RIGHT),
				_terrain_at(pos + Vector2i.RIGHT + Vector2i.DOWN),
				below,
				_terrain_at(pos + Vector2i.LEFT + Vector2i.DOWN),
				_terrain_at(pos + Vector2i.LEFT),
			)

	if skip_cells.has(pos):
		return DungeonTileSheet.NULL_TILE

	if tile == Terrain.LOCKED_EXIT or tile == Terrain.UNLOCKED_EXIT:
		return DungeonTileSheet.EXIT_UNDERHANG

	var below := _terrain_at(pos + Vector2i.DOWN)

	if below != -1 and DungeonTileSheet.wall_stitcheable(below):
		return DungeonTileSheet.stitch_wall_overhang_tile(
			tile,
			_terrain_at(pos + Vector2i.RIGHT + Vector2i.DOWN),
			below,
			_terrain_at(pos + Vector2i.LEFT + Vector2i.DOWN),
		)

	if below != -1:
		match below:
			Terrain.DOOR:
				return DungeonTileSheet.DOOR_OVERHANG
			Terrain.LOCKED_DOOR:
				return DungeonTileSheet.DOOR_OVERHANG
			Terrain.HERO_LKD_DR:
				return DungeonTileSheet.DOOR_OVERHANG
			Terrain.OPEN_DOOR:
				return DungeonTileSheet.DOOR_OVERHANG_OPEN
			Terrain.CRYSTAL_DOOR:
				return DungeonTileSheet.DOOR_OVERHANG_CRYSTAL
			Terrain.STATUE:
				return DungeonTileSheet.STATUE_OVERHANG
			Terrain.STATUE_SP:
				return DungeonTileSheet.STATUE_SP_OVERHANG
			Terrain.REGION_DECO:
				return DungeonTileSheet.REGION_DECO_OVERHANG
			Terrain.REGION_DECO_ALT:
				return DungeonTileSheet.REGION_DECO_ALT_OVERHANG
			Terrain.MINE_CRYSTAL:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.MINE_CRYSTAL_OVERHANG,
					pos + Vector2i.DOWN
				)
			Terrain.MINE_BOULDER:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.MINE_BOULDER_OVERHANG,
					pos + Vector2i.DOWN
				)
			Terrain.ALCHEMY:
				return DungeonTileSheet.ALCHEMY_POT_OVERHANG
			Terrain.BARRICADE:
				return DungeonTileSheet.BARRICADE_OVERHANG
			Terrain.HIGH_GRASS:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.HIGH_GRASS_OVERHANG,
					pos + Vector2i.DOWN
				)
			Terrain.FURROWED_GRASS:
				return DungeonTileSheet.get_visual_with_alts(
					DungeonTileSheet.FURROWED_OVERHANG,
					pos + Vector2i.DOWN
				)

	return DungeonTileSheet.NULL_TILE


func _terrain_at(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= LevelManager.MAP_WIDTH:
		return -1
	if pos.y < 0 or pos.y >= LevelManager.MAP_HEIGHT:
		return -1
	return LevelManager.map_data[pos.y][pos.x]
