extends Scroll
class_name ScrollOfTerror

func _init():
	super()
	item_name = "恐惧卷轴"

func do_read(curUser: Char) -> void:
	detach(curUser.backpack)
	
	var count: int = 0
	var affected: Mob = null
	for mob: Mob in TurnManager.monsters:
		if not is_instance_valid(mob):
			continue
		if mob.alignment != Char.Alignment.ALLY and curUser.FOV[mob.grid_pos.y][mob.grid_pos.x]:
			Buff.affect(mob, Terror, Terror.DURATION)
			if(mob.has_buff(Terror)):
				count += 1
				affected = mob
	match count:
		0:
			print("无")
		1:
			print(affected.name() + "跑")
		_:
			print("跑")
				
	

	identify()
	read_animation()
	return


func value() -> int:
	return 40 * item_quantity
