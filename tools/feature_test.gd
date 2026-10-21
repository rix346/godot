extends SceneTree
# Headless check of every card and skill on a deep floor: applies all cards,
# fires each skill, and plays turns until death or a turn cap.
const Cards := preload("res://scripts/cards.gd")

func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.depth = 3
	main._new_floor()
	var pool := Cards.POOL.duplicate()
	pool.shuffle()
	for card in pool:
		if Cards.can_offer(main.player, card):
			Cards.apply(main.player, card)
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
		var ev = InputEventKey.new()
		ev.pressed = true
		ev.keycode = keys.pick_random()
		var before = main.turn
		main._unhandled_input(ev)
		if main.turn != before and ev.keycode in [KEY_1, KEY_2, KEY_3]:
			used[main.player.skills[ev.keycode - KEY_1].name] = true
	print("skills: ", main.player.skills.map(func(s): return s.name), " used: ", used.keys())
	print("depth ", main.depth, " turn ", main.turn, " hp ", main.player.hp, " kinds seen ok")
	quit()
