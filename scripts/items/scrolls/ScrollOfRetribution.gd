extends Scroll
class_name ScrollOfRetribution

func _init():
	super()   # 必须调：Scroll._init 里设的 stackable 才会生效
	item_name = "复仇卷轴"

# 催眠：读者视野内的怪全部陷入困倦，读者自己也困倦。
# 过滤用 curUser.FOV 而非写死英雄的——卷轴按"读者自己的视野"生效，将来怪读卷轴也自动成立。
# FOV 无需在此重算：它由 GameScene.update_fov() 在每次行动后刷新，而读者此刻尚未移动。
func do_read(curUser: Char) -> bool:
	detach()
	var hp_percent: float = (curUser.hp - curUser.max_hp) / float(curUser.max_hp)
	var power: float = min(4.0, 4.45*hp_percent)
	
	for mob: Mob in TurnManager.monsters:
		if not is_instance_valid(mob):
			continue
		if mob.alignment != Char.Alignment.ALLY and curUser.FOV[mob.grid_pos.y][mob.grid_pos.x]:
			mob.damage(roundi(mob.max_hp/10.0 + mob.hp * power * 0.225), self)
			Buff.affect(mob, Blindness, Blindness.DURATION)

	Buff.affect(curUser, Blindness, Blindness.DURATION)
	Buff.affect(curUser, Weakness, Weakness.DURATION)
	identify()
	read_animation()
	return true

func value() -> int:
	return 40 * item_quantity
