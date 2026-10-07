extends RefCounted
## Layouts matched to the September 29 before/after reference pictures.

static func build_arch(g) -> void:
	g.prompt = "CENTER THE ARCH!"
	# Two fixed pillars leave the path visible through the opening.
	for r in 5:
		for x in [235,1615]:
			g.art("Bricks_Level15",x,2220+r*280,650,280)
	for row in 3:
		var count = row+1
		for c in count:
			var p = g.art("Bricks_Level15",(2500-count*650)/2.0+c*650,1380+row*280,650,280,"move")
			p.arch_row = row
	var odd = randi_range(0,2)
	var shift = randf_range(120,210)*[-1,1].pick_random()
	for p in g.pieces:
		if p.get("arch_row",-1) != odd: continue
		p.target = p.home+Vector2(shift,0)
		p.pos = p.target
		p.faults = 1

static func hex_center(row: int, column: int) -> Vector2:
	return Vector2(125+column*450+(225 if posmod(row,2) == 0 else 0),row*390)

static func flower_color(row: int, column: int) -> int:
	var at = hex_center(row,column)
	for k in range(-3,6):
		for red in [hex_center(4*k,k+1),hex_center(4*k+3,k-1),hex_center(4*k+1,k+5)]:
			if at.distance_to(red) < 1: return 3
	# Every red center has a ring of six blue petals; the gaps are cream.
	for k in range(-3,6):
		for red in [hex_center(4*k,k+1),hex_center(4*k+3,k-1),hex_center(4*k+1,k+5)]:
			if at.distance_to(red) < 451: return 2
	return 1

static func build_flowers(g) -> void:
	g.prompt = "FIX THE FLOWERS!"
	for row in range(14):
		for column in range(-1,6):
			var p = g.add_piece("Tile%d_Level19" % flower_color(row,column),hex_center(row,column),Vector2(450,520),"swap")
			p.row = row
			p.column = column
	# Move one central red tile into the cream gap two rows below it.
	var row = [4,8].pick_random()
	var column = 2 if row == 4 else 3
	var a = row*7+column+1
	var b = (row+2)*7+column+1
	var first = g.pieces[a]
	var second = g.pieces[b]
	first.partner = b
	second.partner = a
	first.target = second.home
	second.target = first.home
	first.pos = first.target
	second.pos = second.target
	first.faults = 1
	second.faults = 1

static func build_dessert(g) -> void:
	g.background = ""
	g.prompt = "SWAP TO FIX THE PICTURE!"
	var size: Vector2 = g.SIZE/Vector2(4,8)
	for i in 32:
		var name = "DessertTile%d" % i
		var p = g.add_piece(name,Vector2((i%4+0.5)*size.x,(int(i/4)+0.5)*size.y),size,"exchange")
		p.correct_name = name
		p.slot = i
	var pairs = [[5,18],[6,25],[9,22],[13,29]]
	pairs.shuffle()
	for n in randi_range(1,2): g.interaction.exchange_bottles(pairs[n][0],pairs[n][1])
	for p in g.pieces: p.pos = p.target
