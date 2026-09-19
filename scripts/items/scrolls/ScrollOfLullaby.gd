extends Scroll
class_name ScrollOfLullaby

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "催眠卷轴"

# 催眠：读者视野内的怪全部陷入困倦，读者自己也困倦。
# 过滤用 curUser.FOV 而非写死英雄的——卷轴按"读者自己的视野"生效，将来怪读卷轴也自动成立。
# FOV 无需在此重算：它由 GameScene.update_fov() 在每次行动后刷新，而读者此刻尚未移动。
func do_read(curUser: Char) -> bool:
	detach()
	for mob in TurnManager.monsters:
		if not is_instance_valid(mob):
			continue
		var c: Vector2i = mob.grid_pos
		if c.x < 0 or c.x >= MapManager.MAP_WIDTH or c.y < 0 or c.y >= MapManager.MAP_HEIGHT:
			continue
		if curUser.FOV[c.y][c.x]:
			Drowsy.new().attach_to(mob, Drowsy.DURATION)
	Drowsy.new().attach_to(curUser, Drowsy.DURATION)

	identify()
	read_animation()
	return true

func value() -> int:
	return 40 * item_quantity
