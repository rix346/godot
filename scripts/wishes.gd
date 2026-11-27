extends RefCounted
## Wishes made at the wishing well (see main.gd). Each wish makes the rest of
## the run harder, and every wish also makes enemies give REWARD more XP.
## They stack: making the same wish again counts it twice. They last until
## the run ends. If you change a number here, change the desc text too.

const REWARD := 0.25  # +25% XP from every kill, per wish made
const STRENGTH := 0.25  # Challenge: +25% HP and attack for every enemy, per wish. Boss Madness: the same for bosses
const BOSS_CHANCE := 0.25  # Boss Madness: chance per wish that a normal floor gets a boss too (4 wishes: every floor)

## Shown as cards at the well. `rarity` only picks the card frame.
const POOL := [
	{id = "challenge", name = "Challenge", type = "wish", subtitle = "WISH", rarity = "rare",
		desc = "Every enemy gets +25% HP and attack."},
	{id = "boss_madness", name = "Boss Madness", type = "wish", subtitle = "WISH", rarity = "legendary",
		desc = "Bosses can show up on normal floors. Boss caves get bigger, with 1 more boss. Bosses get +25% HP and attack."},
	{id = "loud_steps", name = "Loud Steps", type = "wish", subtitle = "WISH", rarity = "epic",
		desc = "Enemies hear you coming from twice as far away (7 more tiles)."},
]


## The text on a wish's card, with how many times you've made it.
static func describe(wish: Dictionary, made: int) -> String:
	return wish.desc if made == 0 else "%s (made x%d)" % [wish.desc, made]
