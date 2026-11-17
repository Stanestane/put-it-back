extends RefCounted
## November PNG packs, composed in their original 2500 by 5000 art space.
static func build(g, id: int) -> void:
	match id:
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
