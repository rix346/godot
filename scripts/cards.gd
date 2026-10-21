extends RefCounted
## Card pool offered on level-up. To add a card: add an entry to POOL and a
## branch in apply() (passives) or in main.gd's _use_skill() (skills).

const RARITY_WEIGHTS := {common = 60, rare = 30, epic = 10}
const RARITY_COLORS := {
	common = Color(0.8, 0.8, 0.8),
	rare = Color(0.4, 0.65, 1.0),
	epic = Color(0.8, 0.45, 1.0),
}

const POOL := [
	# Passives
	{id = "tough_hide", name = "Tough Hide", type = "passive", rarity = "common", max_stacks = 5,
		desc = "+5 max HP and heal 5."},
	{id = "sharpened_blade", name = "Sharpened Blade", type = "passive", rarity = "common", max_stacks = 5,
		desc = "+1 attack."},
	{id = "thorns", name = "Thorns", type = "passive", rarity = "common", max_stacks = 3,
		desc = "Enemies that hit you in melee take 1 damage."},
	{id = "keen_eye", name = "Keen Eye", type = "passive", rarity = "common", max_stacks = 3,
		desc = "+15% chance to deal double damage."},
	{id = "quick_study", name = "Quick Study", type = "passive", rarity = "common", max_stacks = 3,
		desc = "+25% XP from kills."},
	{id = "vampiric", name = "Vampiric Fangs", type = "passive", rarity = "rare", max_stacks = 3,
		desc = "Heal 1 HP every time you hit."},
	{id = "second_wind", name = "Second Wind", type = "passive", rarity = "rare", max_stacks = 3,
		desc = "Regenerate 1 HP every few turns (faster per stack)."},
	{id = "iron_skin", name = "Iron Skin", type = "passive", rarity = "rare", max_stacks = 3,
		desc = "Take 1 less damage from every hit (min 1)."},
	{id = "berserker", name = "Berserker", type = "passive", rarity = "rare", max_stacks = 2,
		desc = "+50% damage while below half HP."},
	{id = "bloodlust", name = "Bloodlust", type = "passive", rarity = "epic", max_stacks = 3,
		desc = "Heal 3 HP on every kill."},
	{id = "glass_cannon", name = "Glass Cannon", type = "passive", rarity = "epic", max_stacks = 2,
		desc = "+3 attack, but -5 max HP."},
	# Skills (active, used with keys 1-3, cost a turn, have a cooldown)
	{id = "fireball", name = "Fireball", type = "skill", rarity = "common", cooldown = 4, max_stacks = 3,
		desc = "Blast the nearest enemy within 6 tiles for attack +3."},
	{id = "whirlwind", name = "Whirlwind", type = "skill", rarity = "rare", cooldown = 5, max_stacks = 3,
		desc = "Hit every enemy around you (8 directions)."},
	{id = "mend", name = "Mend", type = "skill", rarity = "rare", cooldown = 10, max_stacks = 3,
		desc = "Restore 40% of max HP."},
	{id = "stone_skin", name = "Stone Skin", type = "skill", rarity = "rare", cooldown = 9, max_stacks = 3,
		desc = "Block all damage for the next 2 enemy turns."},
	{id = "chain_lightning", name = "Chain Lightning", type = "skill", rarity = "epic", cooldown = 6, max_stacks = 3,
		desc = "Zap the nearest enemy, then jump to 2 more nearby, for attack damage each."},
]


## Picks up to `count` different cards, weighted by rarity.
static func roll_choices(player, count := 3) -> Array:
	var available := POOL.filter(func(c): return can_offer(player, c))
	var picked := []
	while picked.size() < count and not available.is_empty():
		var total := 0
		for c in available:
			total += RARITY_WEIGHTS[c.rarity]
		var roll := randi() % total
		for c in available:
			roll -= RARITY_WEIGHTS[c.rarity]
			if roll < 0:
				picked.append(c)
				available.erase(c)
				break
	return picked


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
		"quick_study":
			player.xp_mult += 0.25
		"iron_skin":
			player.armor += 1
		"berserker":
			player.berserk += 0.5
		"bloodlust":
			player.kill_heal += 3
		"glass_cannon":
			player.attack += 3
			player.max_hp = max(5, player.max_hp - 5)
			player.hp = min(player.hp, player.max_hp)
			player.queue_redraw()
	if card.type == "skill":
		var owned: Dictionary = player.find_skill(card.id)
		if owned.is_empty():
			player.skills.append({id = card.id, name = card.name, cooldown = card.cooldown, ready_in = 0})
		else:
			owned.cooldown = max(1, owned.cooldown - 1)
			owned.ready_in = 0
