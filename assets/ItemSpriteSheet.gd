extends RefCounted
class_name ItemSpriteSheet

const ITEM_ATLAS := preload("res://assets/sprites/items.png")

static var WORN_SHORTSWORD = get_image(1, 7, 13, 13)
static var ARTIFACT_CHALICE1 = get_image(14, 16, 12, 15)
static var ARTIFACT_CHALICE2 = get_image(15, 16, 12, 15)
static var ARTIFACT_CHALICE3 = get_image(16, 16, 12, 15)

static func get_image(x, y, w, h) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = ITEM_ATLAS
	tex.region = Rect2((x-1) * 16, (y-1) * 16, w, h)
	return tex
