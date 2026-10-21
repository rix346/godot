extends "res://scripts/unit.gd"
## A monster. Stats come from a KINDS entry, scaled by dungeon depth.

const KINDS := [
	{name = "Rat", glyph = "r", hp = 4, atk = 1, xp = 1, color = Color(0.65, 0.55, 0.45), min_depth = 1},
	{name = "Goblin", glyph = "g", hp = 7, atk = 2, xp = 2, color = Color(0.35, 0.8, 0.35), min_depth = 1},
	{name = "Orc", glyph = "o", hp = 12, atk = 3, xp = 4, color = Color(0.85, 0.35, 0.25), min_depth = 2},
	{name = "Wraith", glyph = "W", hp = 9, atk = 5, xp = 6, color = Color(0.75, 0.5, 0.95), min_depth = 3},
]

const AGGRO_RANGE := 7

var xp_value := 1


func setup(kind: Dictionary, depth: int) -> void:
	display_name = kind.name
	glyph = kind.glyph
	color = kind.color
	max_hp = kind.hp + (depth - 1) * 2
	hp = max_hp
	attack = kind.atk + (depth - 1) / 2
	xp_value = kind.xp


static func random_kind(depth: int) -> Dictionary:
	var options := KINDS.filter(func(k): return k.min_depth <= depth)
	return options.pick_random()
