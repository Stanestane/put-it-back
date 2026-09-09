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

func run_round(id: int) -> bool:
	test_alignment(id)
	game.start_round(id)
	game._process(5.01)
	input.check(game.state == "lose" and game.interaction.held == -1,"Timeout did not stop the stack puzzle")
	return input.failures == 0
