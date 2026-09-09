extends RefCounted
## Integration checks run through game._input with mouse and touch events.
var game
var touch: bool
var failures = 0

func _init(host, use_touch: bool) -> void:
	game = host
	touch = use_touch

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Level %d: %s" % [game.level,message])

func button(at: Vector2, pressed: bool, secondary: bool = false) -> void:
	if touch or secondary:
		var event = InputEventScreenTouch.new()
		event.position = at*game.scale
		event.index = 1 if secondary else 0
		event.pressed = pressed
		game._input(event)
	else:
		var event = InputEventMouseButton.new()
		event.position = at*game.scale
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		game._input(event)

func motion(at: Vector2) -> void:
	if touch:
		var event = InputEventScreenDrag.new()
		event.index = 0
		event.position = at*game.scale
		game._input(event)
	else:
		var event = InputEventMouseMotion.new()
		event.position = at*game.scale
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		game._input(event)

func settle() -> void:
	for p in game.pieces: p.pos = p.target

func click(at: Vector2) -> void:
	button(at,true)
	button(at,false)

func drag(index: int, destination: Vector2) -> void:
	var origin: Vector2 = game.pieces[index].pos
	button(origin,true)
	check(game.interaction.held == index,"Drag grabbed wrong item")
	motion(origin.lerp(destination,0.5))
	motion(destination)
	button(destination,false)
	settle()

func rank_drop(index: int, rank: int) -> void:
	var target_item = game.interaction.order[rank]
	drag(index,Vector2(game.pieces[target_item].target.x,game.pieces[index].home.y))

func fault_count() -> int:
	var total = 0
	for p in game.pieces: total += p.faults
	return total

func exercise_cancel(index: int) -> void:
	var p = game.pieces[index]
	var before: Vector2 = p.target
	button(p.pos,true)
	motion(p.pos+Vector2(60,180))
	button(Vector2(1250,2500),true,true)
	button(Vector2(1250,2500),false,true)
	check(game.interaction.held == index,"Second finger stole drag")
	var key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	game._input(key)
	check(game.paused and game.interaction.held == -1,"Pause did not cancel drag")
	check(p.target == before,"Canceled drag changed destination")
	game._input(key)
	settle()
	if touch:
		button(p.pos,true)
		motion(p.pos+Vector2(60,180))
		var cancel_event = InputEventScreenTouch.new()
		cancel_event.index = 0
		cancel_event.canceled = true
		cancel_event.position = p.pos*game.scale
		game._input(cancel_event)
		check(game.interaction.held == -1 and p.target == before,"Canceled touch committed drag")
		settle()

func test_order() -> void:
	var before: Array[int] = game.interaction.order.duplicate()
	var correct: Array[int] = before.duplicate()
	correct.sort()
	check(before != correct,"Ordering puzzle was already sorted")
	var misplaced = -1
	for i in before.size():
		var candidate = before.duplicate()
		var item = candidate.pop_at(i)
		candidate.insert(item,item)
		if candidate == correct:
			misplaced = item
			break
	check(misplaced >= 0,"Ordering puzzle cannot be solved in one insertion")
	if misplaced < 0: return
	var p = game.pieces[misplaced]
	check(p.pos.y == p.home.y,"Item was vertically displaced instead of reordered")
	click(p.pos)
	check(game.interaction.order == before and not game.solved(),"Tap auto-fixed drag puzzle")
	drag(misplaced,Vector2(1250,4700))
	check(game.interaction.order == before,"Out-of-row drop changed order")
	exercise_cancel(misplaced)
	check(game.interaction.order == before,"Canceled insertion changed order")
	# A valid but wrong insertion must be honored, not silently auto-corrected.
	var old_rank = before.find(misplaced)
	var wrong_rank = -1
	for rank in before.size():
		if rank != old_rank and rank != misplaced:
			wrong_rank = rank
			break
	rank_drop(misplaced,wrong_rank)
	var expected = before.duplicate()
	expected.erase(misplaced)
	expected.insert(wrong_rank,misplaced)
	check(game.interaction.order == expected and not game.solved(),"Wrong insertion was not preserved")
	rank_drop(misplaced,old_rank)
	check(game.interaction.order == before,"Reverse insertion failed")
	rank_drop(misplaced,misplaced)
	check(game.interaction.order == correct and game.state == "win","Correct insertion did not win")
	for item in correct:
		check(game.pieces[item].target == game.pieces[item].home,"Sorted item is not in its artwork slot")

func test_garden() -> void:
	check(game.pieces.size() == 8,"Garden must have eight bushes")
	check(fault_count() >= 1 and fault_count() <= 3,"Garden must start with 1–3 loose bushes")
	var loose: Array[int] = []
	var occupied: Array[int] = []
	for i in game.pieces.size():
		var p = game.pieces[i]
		if p.slot < 0: loose.append(i)
		else:
			occupied.append(p.slot)
			check(p.target == game.interaction.planting_spots[p.slot],"Bush not centered over artwork baseplate")
	var index = loose[0]
	var origin: Vector2 = game.pieces[index].target
	click(origin)
	check(game.pieces[index].slot == -1,"Tap auto-planted bush")
	drag(index,Vector2(1250,700))
	check(game.pieces[index].slot == -1 and game.pieces[index].target == origin,"Off-baseplate drop was accepted")
	drag(index,game.interaction.planting_spots[occupied[0]])
	check(game.pieces[index].slot == -1,"Occupied baseplate accepted a second bush")
	exercise_cancel(index)
	# Identical bushes can fill any empty plate, including another bush's old spot.
	var empty: Array[int] = []
	for i in 8:
		if not i in occupied: empty.append(i)
	empty.reverse()
	for i in loose.size():
		drag(loose[i],game.interaction.planting_spots[empty[i]])
		check(game.pieces[loose[i]].slot == empty[i],"Valid empty circle rejected bush")
	check(game.solved() and game.state == "win","Planted garden did not win")
	var filled = {}
	for p in game.pieces: filled[p.slot] = true
	check(filled.size() == 8,"Garden has duplicate occupied circles")

func test_hex() -> void:
	check(game.pieces.size() == 35,"Hex grid size changed")
	var broken = fault_count()
	check(broken in [2,4,6],"Hex grid needs 1–3 neighboring swaps")
	for i in game.pieces.size():
		var p = game.pieces[i]
		check(p.name == game.pieces[int(i/5)*5].name,"Solved hex row is not a recognizable color stripe")
		if p.faults > 0:
			var partner = game.pieces[p.partner]
			check(partner.partner == i,"Hex swap is not reciprocal")
			check(p.target == partner.home and partner.target == p.home,"Hex tiles were offset instead of exchanged")
			check(p.home.distance_to(partner.home) < 451,"Swapped hexagons are not neighbors")
		else:
			click(p.pos)
			check(fault_count() == broken,"Correct hex tap altered pattern")
	var taps = 0
	for p in game.pieces:
		if p.faults > 0:
			click(p.pos)
			taps += 1
	check(taps == broken/2 and game.solved() and game.state == "win","Hex ordering did not solve within 1–3 taps")

func run_round(id: int) -> bool:
	match id:
		5: test_garden()
		10,22: test_order()
		19: test_hex()
	if id != 19:
		game.start_round(id)
		var index = 0
		button(game.pieces[index].pos,true)
		motion(game.pieces[index].pos+Vector2(60,100))
		game._process(5.01)
		check(game.state == "lose" and game.interaction.held == -1,"Timeout retained active drag")
	return failures == 0
