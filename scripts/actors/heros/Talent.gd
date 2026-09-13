extends Resource
class_name Talent

enum ID { HEARTY_MEAL, HOLD_FAST, STRONGMAN }

const DATA := {
	ID.HEARTY_MEAL: {"max_points": 3},
	ID.HOLD_FAST:   {"max_points": 3},
	ID.STRONGMAN:   {"max_points": 3},
}

static func max_points(id: ID) -> int:
	return DATA[id]["max_points"]
