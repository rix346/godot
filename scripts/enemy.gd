extends "res://scripts/unit.gd"
## A monster. Stats come from a KINDS entry, scaled by dungeon depth.
## Optional KINDS keys: actions (moves per turn), range (ranged attack along a
## straight line), slow (only acts every other turn).

const KINDS := [
	{name = "Rat", glyph = "r", hp = 4, atk = 1, xp = 1, color = Color(0.65, 0.55, 0.45), min_depth = 1},
	{name = "Bat", glyph = "b", hp = 3, atk = 1, xp = 2, color = Color(0.6, 0.6, 0.75), min_depth = 1, actions = 2},
	{name = "Goblin", glyph = "g", hp = 7, atk = 2, xp = 2, color = Color(0.35, 0.8, 0.35), min_depth = 1},
	{name = "Archer", glyph = "a", hp = 5, atk = 2, xp = 3, color = Color(0.9, 0.75, 0.4), min_depth = 2, range = 5},
	{name = "Orc", glyph = "o", hp = 12, atk = 3, xp = 4, color = Color(0.85, 0.35, 0.25), min_depth = 2},
	{name = "Brute", glyph = "B", hp = 20, atk = 6, xp = 8, color = Color(0.6, 0.4, 0.3), min_depth = 3, slow = true},
	{name = "Wraith", glyph = "W", hp = 9, atk = 5, xp = 6, color = Color(0.75, 0.5, 0.95), min_depth = 3},
	{name = "Knight", glyph = "K", hp = 15, atk = 7, xp = 10, color = Color(0.75, 0.15, 0.2), min_depth = 5},
]

const AGGRO_RANGE := 7

var xp_value := 1
var actions := 1
var attack_range := 1
var slow := false
var resting := false


func setup(kind: Dictionary, depth: int) -> void:
	display_name = kind.name
	glyph = kind.glyph
	color = kind.color
	max_hp = kind.hp + (depth - 1) * 2
	hp = max_hp
	attack = kind.atk + (depth - 1) / 2
	xp_value = kind.xp
	actions = kind.get("actions", 1)
	attack_range = kind.get("range", 1)
	slow = kind.get("slow", false)
	load_art(kind.name)


## Slow enemies alternate between acting and resting. Returns true if this
## enemy skips the current turn.
func tick_rest() -> bool:
	if not slow:
		return false
	resting = not resting
	queue_redraw()
	return resting


static func random_kind(depth: int) -> Dictionary:
	var options := KINDS.filter(func(k): return k.min_depth <= depth)
	return options.pick_random()


func _draw() -> void:
	super()
	if resting:
		draw_string(ThemeDB.fallback_font, Vector2(TILE - 10, 10), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
