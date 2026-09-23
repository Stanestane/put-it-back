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
	if game.interaction.order_grid:
		drag(index,game.pieces[rank].home)
		return
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
	if game.interaction.order_grid:
		check(p.pos == game.pieces[before.find(misplaced)].home,"Tube is not in a tray slot")
	else:
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
	check(fault_count() == 1,"Garden must start with one slightly displaced bush")
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

func bottle_slots() -> Array:
	var slots = []
	for p in game.pieces: slots.append(p.slot)
	return slots

func test_bottles() -> void:
	check(game.pieces.size() == 24,"Expected 24 bottles")
	check(fault_count() == 2,"Exactly two bottles must start exchanged")
	var wrong: Array[int] = []
	var lemons = 0
	for i in game.pieces.size():
		var p = game.pieces[i]
		if p.name == "Juice1_Level24": lemons += 1
		if p.faults > 0: wrong.append(i)
		check(p.target == game.pieces[p.slot].home,"Bottle is not in a shelf slot")
	check(lemons == 12,"Swapping changed the number of each flavor")
	if wrong.size() != 2: return
	var first = wrong[0]
	var second = wrong[1]
	var p = game.pieces[first]
	check(p.slot == second and game.pieces[second].slot == first,"Initial bottles were not exchanged")
	var before = bottle_slots()
	# Grabbing a bottle during its slide must not turn the intermediate
	# animation position into a permanent shelf slot when released.
	var shelf: Vector2 = p.target
	p.pos += Vector2(50,0)
	click(p.pos)
	check(p.target == shelf,"Tap during animation moved the bottle's shelf slot")
	settle()
	check(bottle_slots() == before and not game.solved(),"Tap auto-fixed bottle puzzle")
	drag(first,Vector2(50,4700))
	check(bottle_slots() == before,"Off-shelf drop changed bottles")
	exercise_cancel(first)
	check(bottle_slots() == before,"Canceled drag exchanged bottles")
	# A wrong swap must move both bottles and remain playable.
	var other = -1
	for i in game.pieces.size():
		if i != second and game.pieces[i].name != p.name:
			other = i
			break
	var destination: Vector2 = game.pieces[other].target
	var origin: Vector2 = p.target
	drag(first,destination)
	check(p.target == destination and game.pieces[other].target == origin,"Drop did not exchange both positions")
	check(game.state == "play" and not game.solved(),"Wrong swap won the round")
	drag(first,game.pieces[other].target)
	check(bottle_slots() == before,"Reverse swap failed")
	# Identical bottles can trade slots without creating a false fault.
	var same: Array[int] = []
	for i in game.pieces.size():
		if game.pieces[i].faults == 0 and game.pieces[i].name == p.name: same.append(i)
	drag(same[0],game.pieces[same[1]].target)
	check(fault_count() == 2,"Exchanging identical flavors created a fault")
	drag(first,game.pieces[second].target)
	check(game.state == "win" and game.solved(),"Correct bottle swap did not win")
	var occupied = {}
	for bottle in game.pieces:
		occupied[bottle.slot] = true
		check(bottle.name == game.pieces[bottle.slot].correct_name,"Solved shelf has the wrong flavor")
	check(occupied.size() == 24,"Two bottles occupy the same slot")

func run_round(id: int) -> bool:
	match id:
		5: test_garden()
		10,22,23: test_order()
		19: test_hex()
		24: test_bottles()
	if id != 19:
		game.start_round(id)
		var index = 0
		button(game.pieces[index].pos,true)
		motion(game.pieces[index].pos+Vector2(60,100))
		game._process(5.01)
		check(game.state == "lose" and game.interaction.held == -1,"Timeout retained active drag")
	return failures == 0
