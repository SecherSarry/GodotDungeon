extends Artifact
class_name ChaliceOfBlood

func _init(lvl: int = 0) -> void:
	super()
	image = ItemSpriteSheet.ARTIFACT_CHALICE1
	level_cap = 10
	item_name = "蓄血圣杯"

func actions(hero: Hero):
	var actions: Array = super(hero)
	if is_equipped(hero) and level() < level_cap and !cursed:
		actions.append('血祭')
	return actions

var anonymous = false

func execute(hero: Hero, action: String = default_action) -> void:
	await super(hero, action)
	if action == "血祭":
		prick(hero)

func min_prick_dmg():
	var dmg: int = ceili(3 + 2.5*level()*level())
	return dmg
	
func max_prick_dmg():
	var dmg: int = floori(7 + 3.5*level()*level())
	return dmg

func prick(hero: Hero):
	var damage: int = randi_range(min_prick_dmg(), max_prick_dmg())
	
	damage -= hero.dr_roll()

	hero.spend(Actor.TICK)
	print("圣杯升级")
	
	if damage <= 0:
		damage = 1;
	else:
		pass
		
	#hero.damage(damage, self);
	
	if not hero.is_alive():
		print("死了")
	else:
		upgrade()

func upgrade() -> Item:
	if level() >= 6:
		image = ItemSpriteSheet.ARTIFACT_CHALICE3
	elif level() >= 2:
		image = ItemSpriteSheet.ARTIFACT_CHALICE2
	return super.upgrade()

func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if level() >= 7:
		image = ItemSpriteSheet.ARTIFACT_CHALICE3
	elif level() >= 3:
		image = ItemSpriteSheet.ARTIFACT_CHALICE2

func get_passive_buff() -> ArtifactBuff:
	return ChaliceRegen.new()

func charge(target: Hero, amount: float) -> void:
	if cursed:
		return
	
	if target.is_starving():
		return
	
	var heal_delay: float = 10 - (1.33 + level()*0.667)
	heal_delay /= amount
	var heal: float = 5/heal_delay
	
	if randf() < fmod(heal, 1):
		heal += 1
	
	if heal >= 1 and target.hp < target.max_hp:
		target.hp = mini(target.max_hp, target.hp + heal)
		
		if target.hp == target.max_hp and target is Hero:
			target.resting = false
		
class ChaliceRegen extends ArtifactBuff:
	pass
