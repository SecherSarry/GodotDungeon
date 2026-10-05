extends Ring
class_name RingOfAccuracy

func _init(lvl: int = 0) -> void:
	super(lvl)
	buff_class = Accuracy.new()
	item_name = "精准之戒"

func get_buff() -> RingBuff:
	return Accuracy.new()

static func accuracy_multiplier(target: Char) -> float:
	return pow(1.3, Ring.get_buffed_bonus(target, Accuracy))

class Accuracy extends RingBuff:
	pass
