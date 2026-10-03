extends EquipableItem
class_name KindOfMisc

func do_equip(hero: Hero) -> bool:
	var equip_full: bool = false
	if self is Artifact and hero.artifact != null and hero.misc != null:
		# 杂物栏为戒指而戒指栏空，则可以更换顺序
		if hero.misc is Ring and hero.ring != null:
			hero.ring = hero.misc
			hero.misc = null
		else:
			equip_full = true
	elif self is Ring and hero.misc != null and hero.ring != null:
		# 反过来也适用
		if hero.misc is Artifact and hero.artifact != null:
			hero.artifact = hero.misc
			hero.misc = null
		else:
			equip_full = true
	
	if equip_full:
		if self is Artifact:
			hero.artifact.do_unequip(hero, true, false)
			hero.artifact = self
		elif self is Ring:
			hero.ring = self;
		return false
	else:
		if self is Artifact:
			if hero.artifact == null:
				hero.artifact = self
			else:
				hero.misc = self;
		elif self is Ring:
			if hero.ring == null:
				hero.ring = self;
			else:
				hero.misc = self;

		detach(hero.backpack);

		Talent.on_item_equipped(hero, self)
		activate( hero );

		cursed_known = true;
		if cursed:
			equip_cursed( hero );
			print("你装备了诅咒" + self.name())
		hero.spend_and_next(time_to_equip(hero))
			
		return true;
	
func do_unequip(hero: Hero, collect: bool = true, single: bool = true) -> bool:
	if super.do_unequip(hero, collect, single):
		if hero.artifact == self:
			hero.artifact = null
		if hero.misc == self:
			hero.misc = null
		if hero.ring == self:
			hero.ring = null
		return true
	else:
		return false

func is_equipped(hero: Hero) -> bool:
	return hero != null and (hero.artifact == self or hero.misc == self or hero.ring == self) 
	
