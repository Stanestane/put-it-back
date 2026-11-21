extends RefCounted
## November PNG packs, composed in their original 2500 by 5000 art space.
static func build(g, id: int) -> void:
	match id:
		17:
			g.prompt = "TURN THE LABELS FORWARD!"
			g.art("Top_Shelf_Level17",200,1100,2100,980)
			g.art("Middle_Shelf_Level17",200,2080,2100,700)
			g.art("Bottom_Shelf_Level17",200,2780,2100,950)
			var sizes = [Vector2(410,560),Vector2(310,560),Vector2(280,480),Vector2(250,490),Vector2(210,560)]
			var products: Array = []
			for row in 3:
				for i in 5:
					var size: Vector2 = sizes[i]*0.85
					var p = g.add_piece("Item%d_Front_Level17" % (i+1),Vector2(530+i*360,2030+row*700-size.y/2),size,"face")
					p.correct_name = p.name
					p.back_name = "Item%d_Back_Level17" % (i+1)
					p.alpha_hit = true
					products.append(p)
			products.shuffle()
			for i in randi_range(1,2):
				products[i].name = products[i].back_name
				products[i].faults = 1
		27:
			g.prompt = "STRAIGHTEN THE CHAIRS!"
			for seat in [[Vector2(1250,800),180], [Vector2(1250,4200),0],
				[Vector2(450,1980),90], [Vector2(2050,1980),-90],
				[Vector2(450,3020),90], [Vector2(2050,3020),-90]]:
				var p = g.add_piece("Chair_Level27",seat[0],Vector2(504,582),"rotate",seat[1])
				p.step = 15.0
			g.art("Table_Level27",600,950,1300,3100)
			for at in [Vector2(1250,1265),Vector2(1250,3735),Vector2(910,1980),
				Vector2(1590,1980),Vector2(910,3020),Vector2(1590,3020)]:
				g.add_piece("Plate_Level27",at,Vector2(450,450))
			g.add_piece("Plant_Level27",Vector2(1250,2500),Vector2(421.4,404.6))
			for p in g.pieces: p.alpha_hit = true
			g.disturb()
		28:
			g.prompt = "MATCH THE KNIFE TO ITS SHAPE!"
			# Each handle shares a baseline; blade lengths differ in the supplied art.
			var sizes = [Vector2(400,1100),Vector2(250,1110),Vector2(260,1130),
				Vector2(260,1100),Vector2(250,1110),Vector2(276,1280)]
			for i in 6:
				var bottom = 3280 if i < 3 else 4800
				var p = g.add_piece("Knife%d_Level28" % (i+1),Vector2(770+(i%3)*480,bottom-sizes[i].y/2),sizes[i],"fit")
				p.alpha_hit = true
			# One missing knife is enough for a five-second shape-matching round.
			var loose = g.pieces[randi_range(0,5)]
			loose.target = Vector2(randf_range(700,1800),1100)
			loose.pos = loose.target
			loose.faults = 1
		29:
			g.prompt = "CENTER THE ICE CREAM!"
			for x in [550,1250,1950]:
				g.add_piece("Stick_Level29",Vector2(x,2820),Vector2(137.5,852.5))
				g.add_piece("Ice_Cream_Level29",Vector2(x,2220),Vector2(550,935),"move")
			g.disturb(1)
			for p in g.pieces:
				if p.faults == 0: continue
				p.target = p.home+Vector2(120*[-1,1].pick_random(),0)
				p.pos = p.target
		30:
			g.prompt = "TIDY UP FOR BED!"
			# The cover ends at the mattress foot; pillows sit below its headboard.
			var cover = g.art("Covers3_Level30",470,1565,1560,1650,"face")
			cover.correct_name = cover.name
			for x in [875,1625]:
				var pillow = g.add_piece("Pillow_Level30",Vector2(x,1400),Vector2(726,406)*0.9,"rotate")
				pillow.step = 8.0
			for x in [240,2260]:
				var lamp = g.add_piece("Lamp_Off_Level30",Vector2(x,1190),Vector2(410,410),"face")
				lamp.correct_name = lamp.name
			for p in g.pieces: p.alpha_hit = true
			var candidates = range(g.pieces.size())
			candidates.shuffle()
			for i in randi_range(1,2):
				var p = g.pieces[candidates[i]]
				p.faults = 1
				if p == cover:
					p.name = "Covers%d_Level30" % randi_range(1,2)
				elif p.mode == "rotate":
					p.rotation_target = -p.step
					p.angle = p.rotation_target
				else:
					p.name = "Lamp_On_Level30"
