extends SceneTree
# Headless smoke test: plays random turns and auto-picks cards.
func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var keys = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_1, KEY_2, KEY_3, KEY_SPACE]
	var picks = 0
	for i in 3000:
		if main.state == main.State.DEAD:
			print("DEAD at turn ", main.turn, " depth ", main.depth, " lvl ", main.player.level)
			break
		if main.state == main.State.LEVEL_UP:
			main._level_ui._pick(randi() % main._level_ui._cards.size()); picks += 1
			continue
		var ev = InputEventKey.new(); ev.pressed = true
		# bias toward nearest enemy / stairs
		ev.keycode = keys.pick_random()
		var tgt = main.stairs if main.stairs.x >= 0 else (main.enemies[0].grid_pos if main.enemies.size() else main.player.grid_pos)
		if randf() < 0.7:
			var p = main.astar.get_id_path(main.player.grid_pos, tgt)
			if p.size() > 1:
				var d = p[1] - main.player.grid_pos
				ev.keycode = {Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN, Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT}[d]
		main._unhandled_input(ev)
	print("turn ", main.turn, " depth ", main.depth, " lvl ", main.player.level, " picks ", picks, " hp ", main.player.hp, "/", main.player.max_hp, " stacks ", main.player.card_stacks)
	print(main._hud.text)
	quit()
