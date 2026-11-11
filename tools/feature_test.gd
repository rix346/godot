extends SceneTree
# Headless check of every card and skill on a deep floor: applies all cards,
# fires each skill, and plays turns until death or a turn cap. Before that it
# checks the rules for weapon offers, the stairs heal, coins, the shop and its
# reroll, Night Vision, Break Wall, the enemy cap, mix and elites, boss floors
# and each of the Cow's attacks, and prints FAIL for anything that's broken.
const Cards := preload("res://scripts/cards.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Cow := preload("res://scripts/cow.gd")
const ShopUI := preload("res://scripts/shop_ui.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func card(id: String) -> Dictionary:
	for c in Cards.POOL:
		if c.id == id:
			return c
	return {}


func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check_rules(main)
	check_depth_rules(main)

	main.depth = 3
	main._new_floor()
	main.state = main.State.PLAYER_TURN
	var pool := Cards.POOL.duplicate()
	pool.shuffle()
	for c in pool:
		if Cards.can_offer(main.player, c):
			Cards.apply(main.player, c)
	main.player.max_hp = 200
	main.player.hp = 200
	var keys = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_1, KEY_2, KEY_3, KEY_SPACE]
	var used := {}
	for i in 400:
		if main.state == main.State.DEAD:
			break
		if main.state == main.State.LEVEL_UP:
			main._level_ui._pick(0)
			continue
		if main.state == main.State.SHOP:
			main._shop_ui._close()
			continue
		var ev = InputEventKey.new()
		ev.pressed = true
		ev.keycode = keys.pick_random()
		main._unhandled_input(ev)
		for s in main.player.skills:
			if s.ready_in > 0:
				used[s.name] = true
	print("skills: ", main.player.skills.map(func(s): return s.name), " used: ", used.keys())
	print("depth ", main.depth, " turn ", main.turn, " hp ", main.player.hp, " coins ", main.player.coins)
	print("all rule checks passed" if failures == 0 else "%d rule checks FAILED" % failures)
	quit()


func check_rules(main) -> void:
	var player = main.player

	# Level-ups never offer 3 weapons once you hold one, but can with fists.
	var all_weapons := 0
	for i in 3000:
		if Cards.roll_choices(player).all(func(c): return c.type == "weapon"):
			all_weapons += 1
	check(all_weapons > 0, "with fists, 3 weapon cards should be possible")
	player.equip(card("sword"))
	for i in 3000:
		if Cards.roll_choices(player).all(func(c): return c.type == "weapon"):
			check(false, "offered 3 weapons while holding a sword")
			break

	# Going down the stairs heals 30% of max HP.
	player.hp = 5
	main._descend()
	check(main.depth == 2 and player.hp == 5 + ceili(player.max_hp * main.DESCEND_HEAL), "stairs heal (hp %d)" % player.hp)

	# Coins: tougher enemies drop more often, you pick them up by walking on them.
	var rat := Enemy.new()
	rat.setup(Enemy.KINDS[0], 1)
	var knight := Enemy.new()
	knight.setup(Enemy.KINDS[Enemy.KINDS.size() - 1], 5)
	check(rat.coin_chance() < knight.coin_chance(), "knights should drop coins more often than rats")
	var dir := Vector2i.ZERO
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if main.floor_cells.has(player.grid_pos + d) and main._enemy_at(player.grid_pos + d) == null:
			dir = d
	knight.grid_pos = player.grid_pos + dir
	for i in 50:
		main._drop_coin(knight)
	var dropped: int = main.coins.get(knight.grid_pos, 0)
	check(dropped > 30, "knight drops (%d of 50)" % dropped)
	main._player_step(dir)
	check(player.coins == dropped and main.coins.is_empty(), "picking up coins")

	# Coin Magnet pulls in coins on the floor and catches new drops.
	main.coins[Vector2i(1, 1)] = 3
	main._gain_card(card("coin_magnet"))
	check(player.coins == dropped + 3 and main.coins.is_empty(), "coin magnet pull")
	for i in 20:
		main._drop_coin(knight)
	check(main.coins.is_empty() and player.coins > dropped + 3, "coin magnet catches drops")

	# Night Vision shows the whole floor and every enemy.
	main._gain_card(card("night_vision"))
	check(main.floor_cells.keys().all(func(c): return main.visible_cells.has(c)), "night vision floor")
	check(main.enemies.all(func(e): return e.visible), "night vision enemies")

	# Clearing a floor brings the stairs and (forced here) a shop.
	main.floors_without_shop = 2
	for e in main.enemies.duplicate():
		e.take_damage(e.hp)
	check(main.stairs.x >= 0, "stairs after clearing")
	check(main.shop.x >= 0 and main.astar.is_point_solid(main.shop), "shop spawned (%s)" % main.shop)
	for x in range(main.shop.x - 1, main.shop.x + 2):
		for y in range(main.shop.y - 1, main.shop.y + 2):
			check(main.floor_cells.has(Vector2i(x, y)), "shop needs floor all around")
	player.place(main.shop + Vector2i.LEFT)
	var turn_before: int = main.turn
	main._player_step(Vector2i.RIGHT)
	check(main.state == main.State.SHOP and main._shop_ui.visible, "walking into the shop opens it")
	check(main.turn == turn_before and player.grid_pos == main.shop + Vector2i.LEFT, "the shopkeeper isn't attacked")
	player.coins = 0
	main._shop_ui._pick(0)
	check(not main.shop_stock[0].sold, "can't buy without coins")
	player.coins = 100
	var price: int = main._shop_ui.price_of(main.shop_stock[0].card)
	main._shop_ui._pick(0)
	check(main.shop_stock[0].sold and player.coins == 100 - price, "buying a card")
	main._shop_ui._pick(0)
	check(player.coins == 100 - price, "a sold card can't be bought twice")
	main._shop_ui._try_reroll()
	check(player.coins == 100 - price - ShopUI.REROLL_PRICE, "reroll costs %d coins" % ShopUI.REROLL_PRICE)
	check(main.shop_stock.size() == 3 and main.shop_stock.all(func(it): return not it.sold), "reroll gives 3 new cards")
	check(is_same(main._shop_ui._stock, main.shop_stock), "the shop screen shows the rerolled cards")
	player.coins = ShopUI.REROLL_PRICE - 1
	var before_reroll: Array = main.shop_stock.duplicate()
	main._shop_ui._try_reroll()
	check(player.coins == ShopUI.REROLL_PRICE - 1 and main.shop_stock == before_reroll, "can't reroll without the coins")
	main._shop_ui._close()
	check(main.state == main.State.PLAYER_TURN, "leaving the shop")

	# Break Wall smashes a wall next to you, but not the outer wall or room corners.
	var bw := card("break_wall")
	player.skills.clear()
	for c in Cards.POOL:
		if c.type == "skill":
			player.card_stacks.erase(c.id)
	main._gain_card(bw)
	check(not main._can_break(Vector2i(0, 5)), "outer wall is unbreakable")
	check(not main._can_break(main.rooms[0].grow(1).position), "room corner is unbreakable")
	var target := Vector2i(-1, -1)
	for c in main.floor_cells.keys():
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if target.x < 0 and not main.floor_cells.has(c + d) and main._can_break(c + d) and c != main.shop:
				player.place(c)
				dir = d
				target = c + d
	check(target.x >= 0, "found a breakable wall")
	main._use_skill(0)
	check(main.breaking and main.turn == turn_before, "break wall waits for a direction")
	main._aim_break_wall(KEY_ESCAPE)
	check(not main.breaking and not main.floor_cells.has(target), "break wall cancel")
	main._use_skill(0)
	var key: int = {Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN, Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT}[dir]
	check(main._aim_break_wall(key), "break wall used a turn")
	check(main.floor_cells.has(target) and not main.astar.is_point_solid(target), "wall became floor")
	check(player.skills[0].ready_in > 0, "break wall cooldown")
	rat.free()
	knight.free()

	# Dying loses your coins.
	player.revives = 0
	player.coins = 9
	player.take_damage(player.hp)
	check(main.state == main.State.DEAD and player.coins == 0, "coins lost on death")


func check_depth_rules(main) -> void:
	var player = main.player
	main.state = main.State.PLAYER_TURN
	player.hp = player.max_hp

	# Tough Hide and Sharpened Blade can be picked forever.
	for id in ["tough_hide", "sharpened_blade"]:
		for i in 12:
			Cards.apply(player, card(id))
		check(Cards.can_offer(player, card(id)), "%s should have no limit" % id)

	# 3 + 2 enemies per depth, capped at 20 (reached on depth 9).
	main.depth = 8
	main._new_floor()
	check(main.enemies.size() == 19, "depth 8 has 19 enemies (%d)" % main.enemies.size())
	check(main.enemies.all(func(e): return not e.elite), "no elites before depth 9")
	main.depth = 29
	main._new_floor()
	check(main.enemies.size() == main.MAX_ENEMIES, "depth 29 is capped at %d enemies (%d)" % [main.MAX_ENEMIES, main.enemies.size()])
	check(main.enemies.any(func(e): return e.elite), "depth 29 has elites")

	# The mix: even on depth 1, mostly tough enemies deep down.
	for d in [1, 30]:
		var counts := {}
		for i in 3000:
			var kind: String = Enemy.random_kind(d).name
			counts[kind] = counts.get(kind, 0) + 1
		if d == 1:
			check(counts.values().all(func(n): return n > 800), "depth 1 mix should be even (%s)" % counts)
		else:
			check(counts.get("Knight", 0) > 10 * counts.get("Rat", 0) + 10, "knights should be far more common than rats on depth 30 (%s)" % counts)

	# Elites: a growing share from depth 9, double HP, more attack, double XP, always a coin.
	check(Enemy.elite_chance(8) == 0.0 and Enemy.elite_chance(9) > 0.0 and Enemy.elite_chance(100) == Enemy.ELITE_MAX, "elite chance")
	var plain := Enemy.new()
	plain.setup(Enemy.KINDS[0], 12)
	var elite := Enemy.new()
	elite.setup(Enemy.KINDS[0], 12)
	elite.make_elite()
	check(elite.max_hp == plain.max_hp * 2 and elite.hp == elite.max_hp, "elite HP")
	check(elite.attack > plain.attack and elite.xp_value == plain.xp_value * 2, "elite attack and XP")
	check(range(50).all(func(i): return elite.coin_drop() == 1), "elites always drop a coin")
	plain.free()
	elite.free()

	# Every 5th depth is a cave with only the Cow, drawn with the depth 1 tiles.
	main.depth = 4
	main._descend()
	check(main.depth == 5 and main.is_boss_floor(), "depth 5 is a boss floor")
	check(main.enemies.size() == 1 and main.enemies[0] is Cow, "the boss floor has only the Cow")
	check(main.rooms.is_empty() and player.grid_pos == Vector2i(main.W / 2, main.H / 2), "the boss floor is a cave")
	check(main._floor_tex == main._depth_art("floor", 1) and main._wall_tex == main._depth_art("wall", 1), "the boss floor uses the depth 1 tiles")
	check(main._dist(main.enemies[0].grid_pos, player.grid_pos) >= main.BOSS_SPAWN_DIST, "the Cow starts away from you")
	main._carve_map()
	check(not main.rooms.is_empty(), "normal floors still have rooms")

	# The Cow's attacks, in an open arena so walls don't get in the way.
	var cow = main.enemies[0]
	main.floor_cells.clear()
	for x in range(1, main.W - 1):
		for y in range(1, main.H - 1):
			main.floor_cells[Vector2i(x, y)] = true
	main._build_astar()
	player.max_hp = 500
	player.hp = 500
	player.armor = 0
	player.thorns = 0
	player.shield_turns = 0

	# Line blast: you're hit if you stay in the red line, not if you step out.
	cow.place(Vector2i(5, 8))
	player.place(Vector2i(10, 8))
	cow.plan_line(main)
	check(cow.danger.has(player.grid_pos) and cow.plan_turns == 1, "the line blast marks your row or column")
	var row: bool = cow.danger.has(Vector2i(11, 8))
	check(row or cow.danger.has(Vector2i(10, 9)), "the line runs out to the walls")
	var hp: int = player.hp
	player.place(Vector2i(10, 9) if row else Vector2i(11, 8))
	cow.boss_turn(main)
	check(player.hp == hp and cow.plan == Cow.Plan.NONE and cow.danger.is_empty(), "stepping out of the line dodges it")
	cow.plan_line(main)
	cow.boss_turn(main)
	check(player.hp == hp - ceili(cow.attack * Cow.LINE_MULT), "standing in the line gets you blasted (%d -> %d)" % [hp, player.hp])

	# Charge: it aims one step ahead of the way you're walking.
	hp = player.hp
	cow.place(Vector2i(4, 8))
	player.place(Vector2i(9, 8))
	main.last_step = Vector2i.RIGHT
	cow.plan_dash(main)
	check(cow.plan == Cow.Plan.DASH and cow.danger.back() == Vector2i(10, 8), "the charge aims where you're heading (%s)" % [cow.danger])
	player.place(Vector2i(10, 8))  # you kept walking right
	cow.boss_turn(main)
	check(cow.grid_pos == Vector2i(9, 8) and player.hp == hp - ceili(cow.attack * Cow.DASH_MULT), "walking into the charge gets you rammed")
	hp = player.hp
	cow.place(Vector2i(4, 8))
	player.place(Vector2i(9, 8))
	main.last_step = Vector2i.ZERO
	cow.plan_dash(main)
	player.place(Vector2i(9, 9))  # you stepped aside
	cow.boss_turn(main)
	check(cow.grid_pos == Vector2i(9, 8) and player.hp == hp, "stepping aside dodges the charge")
	var line := Cow.walk_line(Vector2i(0, 0), Vector2i(3, 2))
	var steps_ok: bool = line.size() == 5 and line.back() == Vector2i(3, 2)
	var prev := Vector2i.ZERO
	for c in line:
		steps_ok = steps_ok and main._dist(prev, c) == 1
		prev = c
	check(steps_ok, "a charge moves one tile up, down, left or right at a time (%s)" % [line])

	# Stomp: 3 turns of warning, then the 5x5 around the Cow explodes.
	hp = player.hp
	cow.place(Vector2i(10, 8))
	player.place(Vector2i(11, 8))
	cow.plan_stomp(main)
	check(cow.danger.size() == 25 and cow.danger.has(player.grid_pos), "the stomp marks the 5x5 area")
	cow.boss_turn(main)
	cow.boss_turn(main)
	check(player.hp == hp and cow.plan == Cow.Plan.STOMP and cow.plan_turns == 1 and cow.grid_pos == Vector2i(10, 8), "the stomp waits 3 turns and the Cow stays still")
	cow.boss_turn(main)
	check(player.hp == hp - ceili(cow.attack * Cow.STOMP_MULT) and cow.plan == Cow.Plan.NONE, "staying close to the stomp hurts")
	hp = player.hp
	cow.plan_stomp(main)
	player.place(Vector2i(13, 8))
	for i in 3:
		cow.boss_turn(main)
	check(player.hp == hp, "getting 3 tiles away dodges the stomp")

	# Between big attacks it hits you up close, and only walks every other turn.
	cow.special_in = 99
	hp = player.hp
	player.place(Vector2i(11, 8))
	cow.boss_turn(main)
	check(player.hp == hp - cow.attack, "the Cow hits you up close")
	player.place(Vector2i(16, 8))
	var moves := 0
	for i in 4:
		var before: Vector2i = cow.grid_pos
		cow.boss_turn(main)
		if cow.grid_pos != before:
			moves += 1
	check(moves == 2, "the Cow walks every other turn (%d of 4)" % moves)

	# Big attacks come back after a few turns, but only when it can see you.
	cow.special_in = 1
	cow.place(Vector2i(10, 8))
	player.place(Vector2i(14, 8))
	main.floor_cells.erase(Vector2i(12, 8))
	cow.boss_turn(main)
	check(cow.plan == Cow.Plan.NONE, "no big attack through a wall")
	main.floor_cells[Vector2i(12, 8)] = true
	cow.special_in = 1
	cow.place(Vector2i(10, 8))
	cow.boss_turn(main)
	check(cow.plan != Cow.Plan.NONE and not cow.danger.is_empty(), "a big attack when it sees you")
	cow.plan = Cow.Plan.NONE
	cow.danger.clear()

	# Killing it drops a pile of coins and brings the stairs.
	player.coin_magnet = false
	main.coins.clear()
	cow.take_damage(cow.hp)
	check(main.enemies.is_empty() and main.stairs.x >= 0, "killing the Cow brings the stairs")
	check(main.coins.get(cow.grid_pos, 0) == Cow.COINS, "the Cow drops %d coins" % Cow.COINS)
	main.state = main.State.PLAYER_TURN
