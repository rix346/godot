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
var xp_mult := 1.0
var armor := 0
var berserk := 0.0  # bonus damage multiplier while below half HP
var kill_heal := 0
var revives := 0  # Phoenix Heart
var shield_turns := 0  # Stone Skin: enemy turns left with all damage blocked

var card_stacks := {}  # card id -> times picked
var skills: Array[Dictionary] = []  # {id, name, cooldown, ready_in}


func _init() -> void:
	display_name = "You"
	glyph = "@"
	color = Color(0.35, 0.65, 1.0)
	max_hp = 20
	hp = 20
	attack = 3
	load_art("player")


func gain_xp(amount: int) -> void:
	xp += ceili(amount * xp_mult)
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


func _draw() -> void:
	super()
	if shield_turns > 0:
		draw_arc(Vector2(TILE, TILE) / 2, TILE / 2 - 1, 0, TAU, 24, Color(0.6, 0.85, 1), 2)
