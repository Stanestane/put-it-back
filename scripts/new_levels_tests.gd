extends RefCounted
## Exercise the September art packs through mouse and touch input.
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func run(game) -> bool:
	check(game.LEVELS.size() == 28,"Expected 28 playable variants")
	for i in game.LEVELS.size():
		var rect: Rect2 = game.level_button_rect(i)
		check(rect.end.y < 4750,"Level picker overlaps its footer")
		game.state = "select"
		var input = preload("res://scripts/puzzle_tests.gd").new(game,i%2 == 0)
		input.click(rect.get_center())
		check(game.level == game.LEVELS[i] and game.state == "play" and game.practice,"Level picker selected the wrong puzzle")
	for point in [Vector2(1230,700),Vector2(2400,4900),Vector2(1800,4700)]:
		game.state = "select"
		game.tap(point)
		check(game.state == "select","Empty menu space selected a level")
	for touch in [false,true]:
		game.start_round(25)
		for p in game.pieces:
			if p.mode == "close": game.set_drawer_depth(p,0)
		game.set_drawer_depth(game.pieces[3],2)
		game.set_drawer_depth(game.pieces[5],1)
		var input = preload("res://scripts/puzzle_tests.gd").new(game,touch)
		# The upper drawer's front covers the first 40 pixels of the next row.
		input.click(Vector2(725,2420))
		check(game.pieces[3].depth == 1 and game.pieces[5].depth == 1,"Tap passed through the front drawer into the drawer below")
		input.click(game.pieces[3].pos)
		input.click(game.pieces[5].pos)
		check(game.state == "win","Overlapping drawers cannot both be closed")
	for repetition in 30:
		for id in [11,23,24,25]:
			seed(230000+repetition*100+id)
			game.start_round(id)
			var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
			check(game.tex(game.background) != null,"Missing background")
			check(not game.solved(),"New round starts solved")
			if id == 24:
				check(input.run_round(id),"Bottle exchange failed")
				continue
			if id == 23:
				for p in game.pieces:
					check(game.tex(p.name) != null,"Missing paint tube")
					check(p.angle == 0,"Paint tubes must be reordered, not rotated")
				# Guarantee coverage of an insertion crossing the tray rows.
				game.interaction.order.assign([0,1,2,3,5,6,7,8,4,9,10,11])
				game.interaction.layout_order(game.interaction.order)
				game.interaction.refresh_order_faults()
				input.settle()
				check(input.run_round(id),"Paint color insertion failed")
				continue
			var faults = 0
			for p in game.pieces:
				check(game.tex(p.name) != null,"Missing piece texture")
				check(Rect2(Vector2.ZERO,game.SIZE).encloses(Rect2(p.pos-p.size/2,p.size)),"New piece is outside the screen")
				if p.faults > 0: faults += 1
				if id == 11 and p.mode == "move":
					check(p.pos.distance_to(p.home) <= 135.1,"Cake is too far from its plate")
			if id == 11: check(faults == 1,"Expected one odd cake")
			else: check(faults in [1,2],"Expected one or two open drawers")
			input.click(Vector2(50,4700))
			check(game.state == "play","Empty scene tap solved the puzzle")
			for p in game.pieces:
				var attempts = 0
				while p.faults > 0 and attempts < 4:
					var before: int = p.faults
					input.click(p.pos)
					if id == 25:
						check(p.depth == before-1,"Drawer tap skipped or failed an opening depth")
						check(p.name == "Drawer%d_Level25" % (p.depth+1),"Drawer uses the wrong depth sprite")
					attempts += 1
			check(game.state == "win" and game.solved(),"Mouse/touch could not solve a new level")
			for p in game.pieces:
				check(p.target == p.home and p.rotation_target == p.goal,"Solved piece did not return home")
				if id == 25 and p.mode == "close": check(p.size == Vector2(950,550),"Closed drawer has the wrong dimensions")
			game.start_round(id)
			game._process(5.01)
			check(game.state == "lose","New level did not time out")
	for failure in failures: push_error("New levels: " + failure)
	if failures.is_empty(): print("NEW LEVEL TESTS PASSED: menu reachability, artwork, mouse/touch solves, drawer depths, timeouts")
	return failures.is_empty()
