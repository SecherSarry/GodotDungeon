extends MeleeWeapon
class_name WornShortsword

func _init(lvl: int = 0):
	super(lvl)   # 必须透传：否则 EquipableItem 的 stackable=false 与 Item 的等级都不生效
	image = ItemSpriteSheet.WORN_SHORTSWORD
	item_name = "破旧的短剑"
	tier = 1
