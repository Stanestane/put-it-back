extends RefCounted
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func run(game) -> bool:
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
	if failures.is_empty(): print("NOVEMBER LEVEL TESTS PASSED: 120 mouse/touch rounds, six knife shapes, invalid drops, cancellation, timeouts")
	return failures.is_empty()
