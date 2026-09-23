extends RefCounted
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func run(game) -> bool:
	check(103 not in game.LEVELS,"Removed plate-size level remains selectable")
	for repetition in 50:
		seed(91000+repetition)
		for id in [4,7,8,9]:
			game.start_round(id)
			var movable = 0
			var displaced = 0
			for p in game.pieces:
				if p.mode != "static": movable += 1
				if p.faults > 0: displaced += 1
			if movable == 3: check(displaced == 1,"Three-object scene has multiple imperfections")
		for id in [1,4,8,11,13]:
			game.start_round(id)
			for p in game.pieces:
				if p.mode != "move" or p.faults == 0: continue
				var shift = absf(p.pos.x-p.home.x)
				check(shift >= 85 and shift <= 245,"Horizontal fault is too faint or too large")
				check(p.pos.y == p.home.y,"Horizontal alignment fault moved vertically")
				check(Rect2(Vector2.ZERO,game.SIZE).encloses(Rect2(p.pos-p.size/2,p.size)),"Horizontal fault moved artwork off screen")
		game.start_round(5)
		for p in game.pieces:
			if p.faults > 0:
				check(p.pos.distance_to(p.home) >= 89 and p.pos.distance_to(p.home) <= 121,"Bush no longer sits beside its own baseplate")
		game.start_round(15)
		var flipped = 0
		var odd = -1
		for i in game.pieces.size():
			var p = game.pieces[i]
			check(p.pos == p.home and p.target == p.home and p.angle == 0,"Brick segment moved or rotated")
			if p.get("flip_h",false):
				flipped += 1
				odd = i
		check(flipped == 1,"Wall must have exactly one mirrored segment")
		if odd >= 0:
			var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
			input.click(game.pieces[odd].pos)
			check(game.state == "win" and not game.pieces[odd].flip_h,"Single tap did not restore brick pattern")
		game.start_round(21)
		var faults = 0
		var art_scale = game.SIZE/Vector2(2500,5000)
		for p in game.pieces:
			var center: Vector2 = p.home/art_scale
			var c = int(round((center.x-125)/250))
			var r = int(round((center.y-1375)/250))
			check(center.is_equal_approx(Vector2(c*250+125,r*250+1375)),"Bathroom tile does not match the floor grid")
			check((r+c)%2 == 0,"Bathroom checker pattern broken")
			check(not (r >= 6 and r <= 9 and c >= 7),"Tile overlaps sink")
			check(not (r >= 11 and r <= 13 and c >= 3 and c <= 5),"Tile overlaps toilet")
			check(not (r == 14 and c >= 2 and c <= 6),"Tile overlaps toilet base")
			if p.faults > 0:
				faults += 1
				check(p.pos.distance_to(p.home) >= 89 and p.pos.distance_to(p.home) <= 111,"Bathroom imperfection is too faint or too large")
			else: check(p.pos == p.home,"Correct bathroom tile is displaced")
		check(faults == 1,"Bathroom must have one displaced tile")
	for failure in failures: push_error("Aesthetic test: " + failure)
	if failures.is_empty(): print("AESTHETIC TESTS PASSED")
	return failures.is_empty()
