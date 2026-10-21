extends "res://scripts/unit.gd"
## The player: XP/levels plus the stats that cards modify.

const MAX_SKILLS := 3

var level := 1
var xp := 0
var xp_to_next := 5
var pending_levels := 0

# Passive stats, changed by cards (see cards.gd).
var lifesteal := 0
var thorns := 0
var crit_chance := 0.0
var regen_every := 0  # 0 = no regen
var regen_counter := 0

var card_stacks := {}  # card id -> times picked
var skills: Array[Dictionary] = []  # {id, name, cooldown, ready_in}


func _init() -> void:
	display_name = "You"
	glyph = "@"
	color = Color(0.35, 0.65, 1.0)
	max_hp = 20
	hp = 20
	attack = 3


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.5) + 1
		pending_levels += 1


func find_skill(id: String) -> Dictionary:
	for s in skills:
		if s.id == id:
			return s
	return {}


## Called once at the end of each of the player's turns.
func end_turn() -> void:
	for s in skills:
		if s.ready_in > 0:
			s.ready_in -= 1
	if regen_every > 0:
		regen_counter += 1
		if regen_counter >= regen_every:
			regen_counter = 0
			heal(1)
