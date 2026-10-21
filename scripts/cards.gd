extends RefCounted
## Card pool offered on level-up. To add a card: add an entry to POOL and a
## branch in apply() (passives) or in main.gd's _use_skill() (skills).

const POOL := [
	# Passives
	{id = "tough_hide", name = "Tough Hide", type = "passive", max_stacks = 5,
		desc = "+5 max HP and heal 5."},
	{id = "sharpened_blade", name = "Sharpened Blade", type = "passive", max_stacks = 5,
		desc = "+1 attack."},
	{id = "vampiric", name = "Vampiric Fangs", type = "passive", max_stacks = 3,
		desc = "Heal 1 HP every time you hit."},
	{id = "thorns", name = "Thorns", type = "passive", max_stacks = 3,
		desc = "Enemies that hit you take 1 damage."},
	{id = "second_wind", name = "Second Wind", type = "passive", max_stacks = 3,
		desc = "Regenerate 1 HP every few turns (faster per stack)."},
	{id = "keen_eye", name = "Keen Eye", type = "passive", max_stacks = 3,
		desc = "+15% chance to deal double damage."},
	# Skills (active, used with keys 1-3, cost a turn, have a cooldown)
	{id = "whirlwind", name = "Whirlwind", type = "skill", cooldown = 5, max_stacks = 3,
		desc = "Hit every enemy around you (8 directions)."},
	{id = "fireball", name = "Fireball", type = "skill", cooldown = 4, max_stacks = 3,
		desc = "Blast the nearest enemy within 6 tiles for attack +3."},
	{id = "mend", name = "Mend", type = "skill", cooldown = 10, max_stacks = 3,
		desc = "Restore 40% of max HP."},
]


static func roll_choices(player, count := 3) -> Array:
	var available := POOL.filter(func(c): return can_offer(player, c))
	available.shuffle()
	return available.slice(0, count)


static func can_offer(player, card: Dictionary) -> bool:
	var stacks: int = player.card_stacks.get(card.id, 0)
	if card.type == "skill" and stacks == 0 and player.skills.size() >= player.MAX_SKILLS:
		return false
	return stacks < card.max_stacks


## Text shown on the card; owned skills are offered as upgrades.
static func describe(player, card: Dictionary) -> String:
	var stacks: int = player.card_stacks.get(card.id, 0)
	if card.type == "skill":
		if stacks > 0:
			return "Upgrade: cooldown -1 and ready now."
		return "%s Cooldown %d." % [card.desc, card.cooldown]
	if stacks > 0:
		return "%s (owned x%d)" % [card.desc, stacks]
	return card.desc


static func apply(player, card: Dictionary) -> void:
	player.card_stacks[card.id] = player.card_stacks.get(card.id, 0) + 1
	match card.id:
		"tough_hide":
			player.max_hp += 5
			player.heal(5)
		"sharpened_blade":
			player.attack += 1
		"vampiric":
			player.lifesteal += 1
		"thorns":
			player.thorns += 1
		"second_wind":
			player.regen_every = 6 if player.regen_every == 0 else max(2, player.regen_every - 2)
		"keen_eye":
			player.crit_chance += 0.15
	if card.type == "skill":
		var owned: Dictionary = player.find_skill(card.id)
		if owned.is_empty():
			player.skills.append({id = card.id, name = card.name, cooldown = card.cooldown, ready_in = 0})
		else:
			owned.cooldown = max(1, owned.cooldown - 1)
			owned.ready_in = 0
