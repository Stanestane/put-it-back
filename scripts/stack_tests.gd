extends RefCounted
const InputTests = preload("res://scripts/puzzle_tests.gd")
var game
var input

func _init(host, touch: bool) -> void:
	game = host
	input = InputTests.new(host,touch)

func visible_point(index: int) -> Vector2:
	var p = game.pieces[index]
	var front: Array = game.drawing_order()
	front.reverse()
	for y in [0.4,0.3,0.2,0.0,-0.2,-0.35]:
		for x in [0.0,0.2,-0.2,0.35,-0.35,0.45,-0.45]:
			var point: Vector2 = p.pos+p.size*Vector2(x,y)
			for other in front:
				if game.stack_hit(game.pieces[other],point):
					if other == index: return point
					break
	input.check(false,"Stack item has no accessible visible rim: %d" % index)
	return p.pos

func drag_to(index: int, center: Vector2) -> void:
	var point = visible_point(index)
	var delta: Vector2 = center-game.pieces[index].pos
	input.button(point,true)
	input.check(game.interaction.held == index,"Grab selected a hidden plate")
	input.motion(point+delta*0.5)
	input.motion(point+delta)
	input.button(point+delta,false)
	input.settle()

func rank_drop(index: int, rank: int) -> void:
	drag_to(index,Vector2(1250.5,2400+200*rank))

func insertion_solution(sequence: Array[int]) -> Array:
	var correct = sequence.duplicate()
	correct.sort()
	var candidates: Array = []
	for i in sequence.size():
		for j in sequence.size():
			if i == j: continue
			var candidate = sequence.duplicate()
			var item = candidate.pop_at(i)
			candidate.insert(j,item)
			if candidate == correct: return [[item,j]]
			candidates.append({"order":candidate,"move":[item,j]})
	for option in candidates:
		for i in sequence.size():
			for j in sequence.size():
				if i == j: continue
				var candidate: Array[int] = option.order.duplicate()
				var item = candidate.pop_at(i)
				candidate.insert(j,item)
				if candidate == correct: return [option.move,[item,j]]
	return []

func test_alignment(id: int) -> void:
	input.check(game.pieces.size() == 5,"Expected five stacked objects")
	var faults = input.fault_count()
	input.check(faults >= 1 and faults <= (3 if id == 3 else 2),"Wrong stack fault budget")
	for i in game.pieces.size():
		var p = game.pieces[i]
		input.check(p.home.x == 1250.5,"Solved stack is not centered")
		input.check(p.pos.y == p.home.y and p.target.y == p.home.y,"Horizontal puzzle changed vertical stacking")
		input.check(p.angle == 0 and p.rotation_target == 0,"Stack sprite rotated away from its artwork orientation")
		if i > 0:
			var below = game.pieces[i-1]
			input.check(p.home.y < below.home.y and below.home.y-p.home.y < p.size.y,"Objects do not overlap as a vertical stack")
		if id == 20:
			input.check(p.pos == p.home,"Facing puzzle moved a cookie")
			input.check(p.name == ("Bar2_Level20" if p.faults else "Bar1_Level20"),"Cookie sprite faces the wrong way")
		else:
			input.check(p.name == ("Plate_Level3" if id == 3 else "Bar1_Level20"),"Alignment puzzle changed artwork facing")
			input.check((p.pos.x != p.home.x) == (p.faults > 0),"Fault is not a horizontal offset")
			input.check(absf(p.pos.x-p.home.x) <= 280,"Offset moved the object off the stack")
		if p.faults == 0:
			input.click(visible_point(i))
			input.check(input.fault_count() == faults,"Tap passed through a correct visible stack surface")
	var taps = 0
	for i in game.pieces.size():
		if game.pieces[i].faults > 0:
			input.click(visible_point(i))
			input.settle()
			taps += 1
	input.check(taps == faults and game.state == "win","Stack did not solve with one tap per fault")
	for p in game.pieces:
		input.check(p.target == p.home,"Solved stack still has an offset")
		if id != 3: input.check(p.name == "Bar1_Level20","Solved cookie does not face left")

func test_sizes() -> void:
	var before: Array[int] = game.interaction.order.duplicate()
	var correct = before.duplicate()
	correct.sort()
	input.check(game.background == "Background_Level3","Size variant lost the plate background")
	input.check(before != correct and before.size() == 6,"Invalid size-ordering layout")
	input.check(before.front() == 0 and before.back() == 5,"Topmost or bottommost plate was scrambled")
	input.check(input.fault_count() == 2,"More than two plates start out of their slots")
	for anchor in [0,5]:
		input.button(visible_point(anchor),true)
		input.check(game.interaction.held == -1,"Reference plate should stay fixed")
		input.button(visible_point(anchor),false)
	for i in game.pieces.size():
		var p = game.pieces[i]
		input.check(p.pos.x == p.home.x,"Size puzzle horizontally disturbed plates")
		if i > 0:
			input.check(game.pieces[i-1].size.x > p.size.x and game.pieces[i-1].home.y < p.home.y,"Largest plate must be at the top")
	var solution = insertion_solution(before)
	input.check(solution.size() in [1,2],"Plate stack needs more than two insertion drags")
	if solution.is_empty(): return
	var item: int = solution[0][0]
	input.click(visible_point(item))
	input.check(game.interaction.order == before,"Tap auto-sorted the plates")
	drag_to(item,Vector2(2450,4700))
	input.check(game.interaction.order == before,"Off-stack drop changed size order")
	for rank in [0,5]:
		rank_drop(item,rank)
		input.check(game.interaction.order == before,"Drop displaced a top/bottom reference plate")
	# Cancel an in-flight preview and ensure its insertion is not committed.
	var point = visible_point(item)
	input.button(point,true)
	input.motion(point+Vector2(0,200))
	var key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	game._input(key)
	input.check(game.paused and game.interaction.held == -1 and game.interaction.order == before,"Pause committed a plate insertion")
	game._input(key)
	input.settle()
	# A valid incorrect insertion must change the stack rather than auto-solve.
	var old_rank = before.find(item)
	for rank in range(1,before.size()-1):
		var expected = before.duplicate()
		expected.erase(item)
		expected.insert(rank,item)
		if expected == correct or expected == before: continue
		rank_drop(item,rank)
		input.check(game.interaction.order == expected and game.state == "play","Wrong insertion was not honored")
		rank_drop(item,old_rank)
		input.check(game.interaction.order == before,"Could not undo wrong plate insertion")
		break
	for action in solution: rank_drop(action[0],action[1])
	input.check(game.state == "win" and game.interaction.order == correct,"Plate sizes did not solve largest to smallest")
	for p in game.pieces: input.check(p.target == p.home,"Sorted plate is not in its vertical slot")

func run_round(id: int) -> bool:
	if id == 103: test_sizes()
	else: test_alignment(id)
	game.start_round(id)
	if id == 103:
		var at = visible_point(1)
		input.button(at,true)
		input.motion(at+Vector2(0,200))
	game._process(5.01)
	input.check(game.state == "lose" and game.interaction.held == -1,"Timeout did not stop the stack puzzle")
	return input.failures == 0
