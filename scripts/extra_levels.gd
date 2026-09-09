extends RefCounted
const Stacks = preload("res://scripts/stack_puzzles.gd")
## Additional scenes composed from all fourteen Corel ZIP exports.
static func build(g, id: int) -> void:
	match id:
		2:
			g.prompt = "STRAIGHTEN!"
			for r in 5:
				for c in 2:
					g.add_piece("Button%d_Level2" % (r*2+c+1),Vector2(910+c*680,1110+r*510),Vector2(410,410),"rotate")
			for i in 3:
				g.add_piece(["Button_close_Level2","Button_open_Level2","Button_alarm_Level2"][i],Vector2(770+i*480,3870),Vector2(385,385),"rotate")
		3,20,120:
			Stacks.build(g,id)
			return
		5:
			g.prompt = "DRAG TO THE CIRCLES!"
			# Centres measured from the eight circular baseplates in the artwork.
			g.interaction.planting_spots = [Vector2(750,1500),Vector2(1750,1500),
				Vector2(250,2000),Vector2(2250,2000),Vector2(250,3000),
				Vector2(2250,3000),Vector2(750,3500),Vector2(1750,3500)]
			for i in g.interaction.planting_spots.size():
				var p = g.add_piece("Bush_Level5",g.interaction.planting_spots[i],Vector2(500,500),"place")
				p.slot = i
			g.interaction.scatter_bushes()
			return
		6:
			g.prompt = "JOIN THE LINES!"
			var p = g.add_piece("Manhole_Level6",Vector2(1250,2500),Vector2(1200,1200),"rotate")
			p.step = 90.0
		7:
			g.prompt = "SWITCH UP!"
			for i in 3:
				g.add_piece("Switch_Frame_Level7",Vector2(650+i*600,2500),Vector2(490,936))
				g.add_piece("Switch_Lever_Level7",Vector2(650+i*600,2440),Vector2(240,80),"move")
		9:
			g.prompt = "HANG STRAIGHT!"
			for i in 3:
				g.add_piece("Hanger_Level9",Vector2(650+i*600,950),Vector2(114,114))
				var p = g.art("Wrench_Level9",467+i*600,790,366,1940,"rotate")
				p.step = 6.0
		10:
			g.prompt = "DRAG INTO COLOR ORDER!"
			for i in 12: g.art("Pencil%d_Level10" % (i+1),415+i*140,280,90,2053,"reorder")
			g.interaction.setup_order(415.0,50.0)
			return
		12:
			g.prompt = "COMPLETE THE PATTERN!"
			for r in 8:
				for c in 4:
					var angle = [[0,90],[270,180]][r%2][c%2]
					g.add_piece("Tile_Level12",Vector2(312.5+c*625,312.5+r*625),Vector2(625,625),"rotate",angle)
		15:
			g.prompt = "FLIP THE ODD BRICK!"
			for r in 6:
				for c in 3:
					g.art("Bricks_Level15",275.5+c*650,1660+r*280,650,280,"mirror")
			# This sprite is 180-degree symmetric. Mirror one segment so the
			# running brick joints break, while every segment stays on its grid.
			var p = g.pieces[randi_range(1,4)*3+randi_range(0,2)]
			p.flip_h = true
			p.faults = 1
			return
		17:
			g.prompt = "FIT THE PARQUET!"
			for r in 5:
				for c in 3:
					var x = 50+c*800
					var y = 500+r*800
					if (r+c)%2 == 0:
						for j in 2: g.art("Tile1_Level17",x+j*400,y,400,800,"move")
					else:
						for j in 2: g.art("Tile2_Level17",x,y+j*400,800,400,"move")
		19:
			g.prompt = "TAP TO FIX THE STRIPES!"
			var colors = [1,2,3]
			colors.shuffle()
			for r in 7:
				for c in 5:
					var p = g.add_piece("Tile%d_Level19" % colors[r%3],Vector2(237.5+c*450+(r%2)*225,1100+r*390),Vector2(450,520),"swap")
					p.row = r
					p.column = c
			g.interaction.swap_neighbors()
			return
		21:
			g.prompt = "ALIGN THE ODD TILE!"
			# The source floor starts at y=1250 on a 250-pixel grid. The
			# exclusions follow the sink/toilet footprints in the original PNG.
			var scale_to_art = g.SIZE/Vector2(2500,5000)
			var candidates: Array[int] = []
			for r in 15:
				for c in 10:
					if (r+c)%2 != 0: continue
					if r >= 6 and r <= 9 and c >= 7: continue
					if r >= 11 and r <= 13 and c >= 3 and c <= 5: continue
					if r == 14 and c >= 2 and c <= 6: continue
					var center = Vector2(c*250+125,1250+r*250+125)*scale_to_art
					g.add_piece("Tile_Level21",center,Vector2(250,250)*scale_to_art,"move")
					if r >= 1 and r <= 8 and c >= 1 and c <= 5: candidates.append(g.pieces.size()-1)
			var p = g.pieces[candidates.pick_random()]
			p.target += Vector2(35,0)
			p.pos = p.target
			p.faults = 1
			return
		22:
			g.prompt = "DRAG INTO BOOK ORDER!"
			var widths = [200,250,150,220,300,170,270]
			var x = 220.0
			for i in 7:
				var h = (1230+i*50)*0.8
				g.art("Book%d_Level22" % (i+1),x,1660-h,widths[i]*0.8,h,"reorder")
				x += widths[i]*0.8+20
			g.art("Plant_Level22",1460,3800-1256,900,1256)
			g.interaction.setup_order(220.0,20.0)
			return
	g.disturb()
	# Tight repeated layouts move vertically to keep every hit target accessible.
	for p in g.pieces:
		if p.faults == 0: continue
		if id == 17:
			p.target = p.home + Vector2(0,-minf(40,p.size.y*0.08))
			p.pos = p.target
		elif id == 7:
			p.target = p.home+Vector2(0,170)
			p.pos = p.target
