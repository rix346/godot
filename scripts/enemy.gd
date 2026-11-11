extends "res://scripts/unit.gd"
## A monster. Stats come from a KINDS entry, scaled by dungeon depth.
## Optional KINDS keys: actions (moves per turn), range (ranged attack along a
## straight line), slow (only acts every other turn), poison (melee hits poison
## the player for that many turns).
## Bosses extend this script (see cow.gd) and take their turn in boss_turn().

const KINDS := [
	{name = "Rat", glyph = "r", hp = 4, atk = 1, xp = 1, color = Color(0.65, 0.55, 0.45), min_depth = 1},
	{name = "Bat", glyph = "b", hp = 3, atk = 1, xp = 2, color = Color(0.6, 0.6, 0.75), min_depth = 1, actions = 2},
	{name = "Goblin", glyph = "g", hp = 7, atk = 2, xp = 2, color = Color(0.35, 0.8, 0.35), min_depth = 1},
	{name = "Archer", glyph = "a", hp = 5, atk = 2, xp = 3, color = Color(0.9, 0.75, 0.4), min_depth = 2, range = 5},
	{name = "Orc", glyph = "o", hp = 12, atk = 3, xp = 4, color = Color(0.85, 0.35, 0.25), min_depth = 2},
	{name = "Brute", glyph = "B", hp = 20, atk = 6, xp = 8, color = Color(0.6, 0.4, 0.3), min_depth = 3, slow = true},
	{name = "Wraith", glyph = "W", hp = 9, atk = 5, xp = 6, color = Color(0.75, 0.5, 0.95), min_depth = 3},
	{name = "Spider", glyph = "s", hp = 6, atk = 2, xp = 4, color = Color(0.45, 0.3, 0.55), min_depth = 3, poison = 3},
	{name = "Knight", glyph = "K", hp = 15, atk = 7, xp = 10, color = Color(0.75, 0.15, 0.2), min_depth = 5},
]

const AGGRO_RANGE := 7
const ELITE_FROM := 9  # first depth with elites: where main.gd's MAX_ENEMIES cap is reached
const ELITE_STEP := 0.05  # elite chance added per depth from ELITE_FROM on
const ELITE_MAX := 0.75
const ELITE_HP := 2.0  # elites get these times the HP, attack and XP
const ELITE_ATK := 1.5
const ELITE_XP := 2
const GOLD := Color(1.0, 0.84, 0.3)

var xp_value := 1
var actions := 1
var attack_range := 1
var slow := false
var poison := 0
var resting := false
var elite := false
var danger: Array[Vector2i] = []  # tiles a boss attack is about to hit, drawn by main.gd
var danger_color := Color(1, 0.2, 0.15)


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
	poison = kind.get("poison", 0)
	load_art(kind.name)


## Elite version: double HP, more attack, double XP, a gold outline and a
## coin every time.
func make_elite() -> void:
	elite = true
	display_name = "Elite " + display_name
	max_hp = ceili(max_hp * ELITE_HP)
	hp = max_hp
	attack = ceili(attack * ELITE_ATK)
	xp_value *= ELITE_XP


## Share of enemies that spawn as elites: none before depth 9, then 5% more
## per depth (5% at depth 9, 50% at depth 18) up to 75%.
static func elite_chance(depth: int) -> float:
	return clampf((depth - ELITE_FROM + 1) * ELITE_STEP, 0.0, ELITE_MAX)


## Tougher enemies (more XP) are more likely to drop a coin: a Rat 18%, a
## Goblin 26%, an Orc 42%, a Brute 74%, a Knight 90%.
func coin_chance() -> float:
	return minf(0.9, 0.1 + 0.08 * xp_value)


## Coins dropped on death: elites always drop one, others roll coin_chance().
func coin_drop() -> int:
	if elite:
		return 1
	return 1 if randf() < coin_chance() else 0


## Slow enemies alternate between acting and resting. Returns true if this
## enemy skips the current turn.
func tick_rest() -> bool:
	if not slow:
		return false
	resting = not resting
	queue_redraw()
	return resting


## Picks an enemy type for a new floor. Tougher types get more common the
## deeper you go: each type's weight is its XP to the power depth / 10, so on
## depth 1 they're all about equal, on depth 10 a Knight (10 XP) is 10 times as
## likely as a Rat (1 XP), and on depth 20 it's 100 times.
static func random_kind(depth: int) -> Dictionary:
	var options := KINDS.filter(func(k): return k.min_depth <= depth)
	var total := 0.0
	for k in options:
		total += pow(k.xp, depth / 10.0)
	var roll := randf() * total
	for k in options:
		roll -= pow(k.xp, depth / 10.0)
		if roll < 0:
			return k
	return options.back()


func _draw() -> void:
	super()
	if elite:
		# Gold frame with corner studs, so it doesn't look like the bow's target box.
		draw_rect(Rect2(Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), GOLD, false, 2)
		for corner in [Vector2(0, 0), Vector2(TILE - 5, 0), Vector2(0, TILE - 5), Vector2(TILE - 5, TILE - 5)]:
			draw_rect(Rect2(corner, Vector2(5, 5)), GOLD)
		_draw_hp_bar()  # back on top of the frame
	if resting:
		draw_string(ThemeDB.fallback_font, Vector2(TILE - 10, 10), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
