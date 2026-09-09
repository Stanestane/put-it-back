extends RefCounted
## Pointer ownership, insertion reordering, baseplate placement, and neighbor swaps.
var game
var planting_spots: Array = []
var order: Array[int] = []
var order_left = 0.0
var order_gap = 0.0
var order_vertical = false
var order_top = 0.0
var order_pitch = 0.0
var held = -1
var owner = -2
var grab_offset = Vector2.ZERO
var press_point = Vector2.ZERO
var moved = false
var hover = -1
var held_position = Vector2.ZERO
var slot_centers: Array[float] = []

func _init(host) -> void:
	game = host

func reset() -> void:
	held = -1
	owner = -2
	hover = -1
	moved = false
	order.clear()
	planting_spots.clear()
	slot_centers.clear()
	order_vertical = false

func scatter_bushes() -> void:
	var indices = range(game.pieces.size())
	indices.shuffle()
	var loose_positions = [Vector2(420,800),Vector2(2080,800),Vector2(1250,4250)]
	loose_positions.shuffle()
	for i in randi_range(1,3):
		var p = game.pieces[indices[i]]
		p.slot = -1
		p.faults = 1
		p.pos = loose_positions[i]
		p.target = p.pos

func setup_order(left: float, gap: float) -> void:
	order_left = left
	order_gap = gap
	for i in game.pieces.size():
		if game.pieces[i].mode == "reorder": order.append(i)
	# One item is removed from its correct position and inserted elsewhere.
	# The intervening items shift, so one well-placed drag restores the order.
	var source = randi_range(0,order.size()-1)
	var destinations: Array[int] = []
	for i in order.size():
		if absi(i-source) >= 2 and absi(i-source) <= 5: destinations.append(i)
	var destination: int = destinations.pick_random()
	var displaced = order.pop_at(source)
	order.insert(destination,displaced)
	layout_order(order)
	refresh_order_faults()
	for i in order: game.pieces[i].pos = game.pieces[i].target

func layout_order(sequence: Array[int]) -> void:
	if order_vertical:
		for rank in sequence.size():
			var p = game.pieces[sequence[rank]]
			p.target = Vector2(p.home.x,order_top+rank*order_pitch)
		return
	var x = order_left
	for i in sequence:
		var p = game.pieces[i]
		p.target = Vector2(x+p.size.x/2,p.home.y)
		x += p.size.x+order_gap

func setup_vertical_order(top: float, pitch: float) -> void:
	order_vertical = true
	order_top = top
	order_pitch = pitch
	for i in game.pieces.size():
		if game.pieces[i].mode == "reorder": order.append(i)
	# Exchange exactly two interior plates. Every other plate keeps its slot,
	# including the largest/topmost and smallest/bottommost reference plates.
	var interior = range(1,order.size()-1)
	interior.shuffle()
	var a: int = interior[0]
	var b: int = interior[1]
	var item = order[a]
	order[a] = order[b]
	order[b] = item
	layout_order(order)
	refresh_order_faults()
	for i in order: game.pieces[i].pos = game.pieces[i].target

func refresh_order_faults() -> void:
	for i in order.size(): game.pieces[order[i]].faults = int(order[i] != i)

func swap_neighbors() -> void:
	# Disjoint row pairs preserve four intact cells per row as a pattern cue.
	var rows = [0,2,4]
	rows.shuffle()
	for n in randi_range(1,3):
		var a: int = rows[n]*5+randi_range(0,4)
		var b = a+5
		var first = game.pieces[a]
		var second = game.pieces[b]
		first.partner = b
		second.partner = a
		first.target = second.home
		second.target = first.home
		first.pos = first.target
		second.pos = second.target
		first.faults = 1
		second.faults = 1

func hit(p: Dictionary, point: Vector2) -> bool:
	if p.get("stack",false): return game.stack_hit(p,point)
	var local: Vector2 = (point-p.pos).rotated(-deg_to_rad(p.angle))
	if p.mode == "swap":
		return absf(local.x) <= p.size.x/2 and absf(local.y) <= p.size.y/2-absf(local.x)*p.size.y/(2*p.size.x)
	if p.mode == "place": return local.length() <= p.size.x/2
	return Rect2(-p.size/2,p.size).grow(15).has_point(local)

func tap_hex(point: Vector2) -> bool:
	for i in range(game.pieces.size()-1,-1,-1):
		var p = game.pieces[i]
		if p.mode != "swap" or not hit(p,point): continue
		if p.faults > 0:
			var neighbor = game.pieces[p.partner]
			p.target = p.home
			neighbor.target = neighbor.home
			p.faults = 0
			neighbor.faults = 0
			if game.solved(): game.finish(true)
		return true
	return false

func pointer_down(point: Vector2, pointer: int) -> void:
	if held >= 0: return
	if game.state != "play" or game.paused or (point.y < 210 and point.x > 2090):
		game.tap(point)
		return
	var front_to_back: Array = game.drawing_order()
	front_to_back.reverse()
	for i in front_to_back:
		var p = game.pieces[i]
		if not p.mode in ["reorder","place"] or not hit(p,point): continue
		if order_vertical and (i == 0 or i == order.size()-1): return
		held = i
		owner = pointer
		grab_offset = point-p.pos
		press_point = point
		held_position = p.pos
		moved = false
		hover = -1
		slot_centers.clear()
		for index in order:
			slot_centers.append(game.pieces[index].target.y if order_vertical else game.pieces[index].target.x)
		return
	game.tap(point)

func pointer_move(point: Vector2, pointer: int) -> void:
	if held < 0 or pointer != owner or game.paused or game.state != "play": return
	if point.distance_to(press_point) >= 40: moved = true
	if not moved: return
	var p = game.pieces[held]
	p.pos = point-grab_offset
	if p.mode == "reorder":
		hover = insertion_at(p.pos)
		if hover >= 0:
			var preview = order.duplicate()
			preview.erase(held)
			preview.insert(hover,held)
			layout_order(preview)
		else: layout_order(order)
	else:
		hover = planting_at(p.pos)
	game.queue_redraw()

func insertion_at(center: Vector2) -> int:
	var p = game.pieces[held]
	if order_vertical:
		if absf(center.x-p.home.x) > 550 or center.y < order_top-order_pitch*0.6 or center.y > slot_centers.back()+order_pitch*0.6:
			return -1
	elif absf(center.y-p.home.y) > 420 or center.x < order_left-100 or center.x > slot_centers.back()+p.size.x/2+100:
		return -1
	var result = 0
	var distance = INF
	for i in slot_centers.size():
		var d = absf((center.y if order_vertical else center.x)-slot_centers[i])
		if d < distance:
			distance = d
			result = i
	if order_vertical and (result == 0 or result == order.size()-1): return -1
	return result

func planting_at(center: Vector2) -> int:
	var result = -1
	var distance = 220.0
	for i in planting_spots.size():
		var occupied = false
		for j in game.pieces.size():
			if j != held and game.pieces[j].get("slot",-1) == i: occupied = true
		if occupied: continue
		var d = center.distance_to(planting_spots[i])
		if d < distance:
			distance = d
			result = i
	return result

func pointer_up(point: Vector2, pointer: int) -> void:
	if held < 0 or pointer != owner: return
	pointer_move(point,pointer)
	var p = game.pieces[held]
	if moved and hover >= 0 and game.state == "play" and not game.paused:
		if p.mode == "reorder":
			order.erase(held)
			order.insert(hover,held)
			layout_order(order)
			refresh_order_faults()
		else:
			p.slot = hover
			p.target = planting_spots[hover]
			p.faults = 0
	else:
		if p.mode == "reorder": layout_order(order)
		else: p.target = held_position
	held = -1
	owner = -2
	hover = -1
	if game.solved() and game.state == "play": game.finish(true)

func cancel() -> void:
	if held >= 0:
		if game.pieces[held].mode == "reorder": layout_order(order)
		else: game.pieces[held].target = held_position
	held = -1
	owner = -2
	hover = -1

func draw_drag() -> void:
	if held < 0: return
	var p = game.pieces[held]
	if moved and hover >= 0:
		if p.mode == "place":
			game.draw_arc(planting_spots[hover],260,0,TAU,48,game.YELLOW,15,true)
		else:
			game.draw_rect(Rect2(p.target-p.size/2,p.size).grow(20),Color(1,0.97,0.4,0.6),false,12)
	game.draw_set_transform(p.pos,deg_to_rad(p.angle))
	game.draw_texture_rect(game.tex(p.name),Rect2(-p.size/2+Vector2(22,28),p.size),false,Color(0,0,0,0.22))
	game.picture(p.name,Rect2(-p.size/2,p.size))
	game.draw_set_transform(Vector2.ZERO)
