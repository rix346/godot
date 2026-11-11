extends SceneTree
# Headless check of every card and skill on a deep floor: applies all cards,
# fires each skill, and plays turns until death or a turn cap. Before that it
# checks the rules for weapon offers, the stairs heal, coins, the shop, Night
# Vision and Break Wall, and prints FAIL for anything that's broken.
const Cards := preload("res://scripts/cards.gd")
const Enemy := preload("res://scripts/enemy.gd")

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
	main._shop_ui._close()
	check(main.state == main.State.PLAYER_TURN, "leaving the shop")

	# Break Wall smashes a wall next to you, but not the outer wall or room corners.
	var bw := card("break_wall")
	player.skills.clear()
	player.card_stacks.erase("break_wall")
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
