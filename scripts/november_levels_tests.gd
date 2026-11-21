extends RefCounted
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func run(game) -> bool:
	test_bedtime(game)
	# Both switch layouts must be reachable and solvable through real input.
	for repetition in 20:
		for id in [7,107]:
			seed(71000+repetition*100+id)
			game.start_round(id)
			var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
			check(game.tex(game.background) != null,"Missing switch background")
			var levers = game.pieces.filter(func(p): return p.mode == "move")
			check(levers.size() == (8 if id == 107 else 3),"Wrong switch count")
			check(game.fault_count() in [1,2] if id == 107 else game.fault_count() == 1,"Wrong switch fault count")
			var faults: int = game.fault_count()
			for p in levers:
				if p.faults == 0: input.click(p.pos)
			check(game.fault_count() == faults,"Correct switch changes the puzzle")
			for p in levers:
				if p.faults > 0: input.click(p.pos)
			check(game.state == "win" and game.solved(),"Switch mouse/touch solve failed")
			check(input.failures == 0,"Switch input regression")
	var reversed_products = {}
	for repetition in 40:
		for id in [17,109]:
			seed(171090+repetition*100+id)
			game.start_round(id)
			var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
			check(game.tex(game.background) != null,"Missing feedback background")
			check(game.fault_count() in [1,2],"Expected one or two feedback faults")
			var faults: int = game.fault_count()
			input.click(Vector2(50,4700))
			check(game.fault_count() == faults,"Empty space changes feedback puzzle")
			var movable = game.pieces.filter(func(p): return p.mode != "static")
			check(movable.size() == (15 if id == 17 else 6),"Wrong feedback object count")
			for p in game.pieces:
				check(game.tex(p.name) != null,"Missing feedback sprite")
				check(Rect2(Vector2.ZERO,game.SIZE).encloses(Rect2(p.pos-p.size/2,p.size)),"Feedback sprite outside screen")
			if id == 17:
				for p in movable:
					if p.faults == 0: input.click(p.pos)
					else:
						reversed_products[p.name] = true
						check(p.name == p.back_name,"Faulty grocery shows its front")
				check(game.fault_count() == faults,"Correct grocery changes the puzzle")
			else:
				for i in range(1,movable.size()):
					check(movable[i].size.y > movable[i-1].size.y,"Tools do not increase in size")
			for p in movable:
				if p.faults > 0: input.click(p.pos)
			check(game.state == "win" and game.solved(),"Feedback mouse/touch solve failed")
			if id == 17:
				for p in movable: check(p.name == p.correct_name,"Solved grocery still faces backward")
			check(input.failures == 0,"Feedback input regression")
			game.start_round(id)
			game._process(5.01)
			check(game.state == "lose","Feedback level did not time out")
	check(reversed_products.size() == 5,"Not all five grocery backs were tested")
	var knives_seen = {}
	for repetition in 40:
		for id in [27,28,29]:
			seed(270000+repetition*100+id)
			game.start_round(id)
			var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
			check(game.tex(game.background) != null,"Missing November background")
			check(not game.solved(),"November round starts solved")
			for p in game.pieces:
				check(game.tex(p.name) != null,"Missing November sprite")
				check(Rect2(Vector2.ZERO,game.SIZE).encloses(Rect2(p.pos-p.size/2,p.size)),"November sprite outside screen")
			var before: int = game.fault_count()
			input.click(Vector2(50,4700))
			check(game.fault_count() == before,"Empty space changes the puzzle")
			if id == 28:
				check(before == 1,"Expected one loose knife")
				var loose = -1
				for i in game.pieces.size():
					if game.pieces[i].faults > 0: loose = i
				var p = game.pieces[loose]
				knives_seen[p.name] = true
				var origin: Vector2 = p.target
				input.exercise_cancel(loose)
				input.drag(loose,game.pieces[(loose+1)%6].home)
				check(p.faults == 1 and p.target == origin,"Wrong silhouette accepts the knife")
				input.drag(loose,Vector2(50,1800))
				check(p.faults == 1 and p.target == origin,"Off-tray drop changes the knife")
				input.drag(loose,p.home)
				check(game.state == "win" and p.target == p.home,"Correct silhouette rejected the knife")
				game.start_round(id)
				for fixed in game.pieces:
					if fixed.faults > 0: continue
					input.button(fixed.pos,true)
					check(game.interaction.held == -1,"Fitted knife can be removed")
					input.button(fixed.pos,false)
				for i in game.pieces.size():
					if game.pieces[i].faults == 0: continue
					input.button(game.pieces[i].pos,true)
					input.motion(game.pieces[i].home)
					game._process(5.01)
					input.button(game.pieces[i].home,false)
					check(game.state == "lose" and game.interaction.held == -1,"Timeout commits knife drag")
					break
			else:
				check(before in [1,2] if id == 27 else before == 1,"Wrong number of alignment faults")
				if id == 29:
					for a in [1,3,5]:
						for b in [1,3,5]:
							if a >= b: continue
							var first: Dictionary = game.pieces[a]
							var second: Dictionary = game.pieces[b]
							check(not Rect2(first.pos-first.size/2,first.size).intersects(Rect2(second.pos-second.size/2,second.size)),"Ice creams overlap")
				if id == 27:
					input.click(Vector2(1250,2500))
					check(game.fault_count() == before,"Table decoration changes a chair")
				for p in game.pieces:
					if p.faults > 0: input.click(p.pos)
				check(game.state == "win" and game.solved(),"Mouse/touch alignment solve failed")
				for p in game.pieces:
					check(p.target == p.home and p.rotation_target == p.goal,"Solved object is misaligned")
			check(input.failures == 0,"November input regression")
			game.start_round(id)
			game._process(5.01)
			check(game.state == "lose","November round did not time out")
	check(knives_seen.size() == 6,"Randomized tests did not cover every knife shape")
	for failure in failures: push_error("November levels: "+failure)
	if failures.is_empty(): print("NOVEMBER LEVEL TESTS PASSED: 320 mouse/touch rounds, bedtime faults, feedback layouts, six knife shapes, invalid drops, cancellation, timeouts")
	return failures.is_empty()

func test_bedtime(game) -> void:
	var faults_seen = {}
	for repetition in 80:
		seed(300000+repetition)
		game.start_round(30)
		var input = preload("res://scripts/puzzle_tests.gd").new(game,repetition%2 == 0)
		check(game.tex(game.background) != null,"Missing bedroom background")
		check(game.pieces.size() == 5,"Bedroom needs a cover, two pillows and two lamps")
		var before: int = game.fault_count()
		check(before in [1,2],"Bedtime must start with one or two faults")
		input.click(Vector2(1250,4400))
		# The cover's bottom-left corner is transparent in every supplied state.
		input.click(Vector2(472,3213))
		check(game.fault_count() == before,"Empty bedroom space or transparent corner accepts a tap")
		for p in game.pieces:
			check(game.tex(p.name) != null,"Missing bedroom sprite")
			check(Rect2(Vector2.ZERO,game.SIZE).encloses(Rect2(p.pos-p.size/2,p.size)),"Bedroom sprite outside screen")
			if p.faults == 0: input.click(p.pos)
			else: faults_seen[p.name] = true
		check(game.fault_count() == before,"Correct bedroom object changes the puzzle")
		game.paused = true
		for p in game.pieces:
			if p.faults > 0: input.click(p.pos)
		check(game.fault_count() == before,"Paused bedroom accepts taps")
		game.paused = false
		for p in game.pieces:
			if p.faults > 0: input.click(p.pos)
		check(game.state == "win" and game.solved(),"Bedtime mouse/touch solve failed")
		for p in game.pieces:
			check(p.pos == p.home and p.rotation_target == p.goal,"Solved bedroom object is misaligned")
			if p.mode == "face": check(p.name == p.correct_name,"Solved bed is rumpled or lamp remains lit")
		check(input.failures == 0,"Bedtime input regression")
		game.start_round(30)
		var timed_out_faults: int = game.fault_count()
		game._process(5.01)
		for p in game.pieces:
			if p.faults > 0: input.click(p.pos)
		check(game.state == "lose" and game.fault_count() == timed_out_faults,"Timeout accepts bedtime repair")
	for name in ["Covers1_Level30","Covers2_Level30","Pillow_Level30","Lamp_On_Level30"]:
		check(faults_seen.has(name),"Missing bedtime fault coverage: "+name)
